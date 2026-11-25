import Foundation

enum APIError: Error, LocalizedError {
    case server(status: Int, code: String, message: String)
    case invalidResponse
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .server(_, _, let message): message
        case .invalidResponse, .notConfigured: "지금은 연결이 어려워요. 잠시 후 다시 해 주세요."
        }
    }
    var code: String? { if case .server(_, let code, _) = self { code } else { nil } }
    var status: Int? { if case .server(let status, _, _) = self { status } else { nil } }
}

/// 팀 문서 backend_spec v0.4.3의 API. Android 앱과 같은 계약.
protocol APIClient: Sendable {
    func upsertMe(_ body: UserUpsert) async throws -> UserProfile
    func registerDevice(_ body: DeviceRegister) async throws
    func postConsent(_ body: ConsentRequest) async throws
    func config() async throws -> ConfigResponse

    func createSession(_ body: SessionCreateRequest) async throws -> SessionCreateResponse
    func decision(_ body: DecisionRequest) async throws -> DecisionResponse
    func endSession(id: String, _ body: SessionEndRequest) async throws
    func memoryControl(_ body: MemoryControlRequest) async throws

    func pairingCode() async throws -> PairingCode
    func link(code: String, relation: String) async throws -> GuardianLink
    func links() async throws -> [GuardianLink]
    func unlink(linkId: String) async throws
    func board(seniorId: String) async throws -> Board
    /// N21 제안: QR·번호로 대상 어르신 확인(코드 소비 없음)
    func resolvePairing(code: String) async throws -> PairingTarget
    func alerts(seniorId: String) async throws -> [Board.AlertItem]
    func markAlertRead(id: String) async throws
    func alertFollowUp(id: String, status: String) async throws

    func schedules(seniorId: String) async throws -> [ScheduleItem]
    func saveSchedule(_ item: ScheduleItem) async throws -> ScheduleItem
    func deleteSchedule(id: String) async throws
    func ack(scheduleId: String, _ body: ScheduleAck) async throws
}

/// 실제 서버 호출. JSON은 snake_case, 날짜는 ISO-8601 UTC.
/// 서버 시각 문자열(ISO-8601, 소수 초 있음/없음 모두) 해석.
/// 서버 응답의 snake_case 키를 Swift 이름으로 바꿀 때 쓰는 키
struct SnakeKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

enum ServerDate {
    static func parse(_ text: String) -> Date? {
        if let d = try? Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) { return d }
        if let d = try? Date(text, strategy: Date.ISO8601FormatStyle()) { return d }
        // 소수 자리가 6~9자리(마이크로·나노초)면 밀리초까지만 남기고 다시 읽는다
        if let dot = text.firstIndex(of: "."), let end = text[dot...].firstIndex(where: { $0 == "Z" || $0 == "+" || $0 == "-" }) {
            let fraction = String(text[text.index(after: dot)..<end].prefix(3)).padding(toLength: 3, withPad: "0", startingAt: 0)
            let trimmed = String(text[..<dot]) + "." + fraction + String(text[end...])
            return try? Date(trimmed, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true))
        }
        return nil
    }
}

struct HTTPAPIClient: APIClient {
    let baseURL: URL
    let auth: AuthService
    /// Firebase App Check 토큰(진짜 앱에서 온 요청인지 서버가 확인). 없으면 헤더 생략.
    var appCheck: AppCheckService = NoAppCheck()

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.keyEncodingStrategy = .convertToSnakeCase; e.dateEncodingStrategy = .iso8601; return e
    }()
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        // 기본 .convertFromSnakeCase는 숫자로 시작하는 마디를 "7D"로 바꿔서(emotion_7d → emotion7D)
        // emotion7d 같은 이름과 맞지 않는다. 같은 규칙에 숫자 마디만 그대로 두는 변환을 쓴다.
        d.keyDecodingStrategy = .custom { path in
            let key = path.last?.stringValue ?? ""
            let parts = key.split(separator: "_")
            guard key.contains("_"), let first = parts.first else { return SnakeKey(key) }
            let rest = parts.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            return SnakeKey(first.lowercased() + rest.joined())
        }
        // 서버(이현님 구현)는 시각을 "2026-11-12T08:33:42.123456Z"처럼 소수 초까지 보낸다. 기본 .iso8601은 소수 초를 읽지 못한다.
        d.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            if let date = ServerDate.parse(text) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "날짜 형식 오류"))
        }
        return d
    }()
    private struct Empty: Codable {}

    private func send<Body: Encodable, Out: Decodable>(_ method: String, _ path: String, _ body: Body?, timeout: TimeInterval = 15) async throws -> Out {
        let base = baseURL.absoluteString.hasSuffix("/") ? String(baseURL.absoluteString.dropLast()) : baseURL.absoluteString
        guard let url = URL(string: base + "/" + path) else { throw APIError.invalidResponse }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = method
        request.setValue("Bearer \(try await auth.idToken())", forHTTPHeaderField: "Authorization")
        request.setValue(ConfigStore.shared.current.configVersion, forHTTPHeaderField: "X-Config-Version")
        request.setValue("ios", forHTTPHeaderField: "X-Client-Platform")
        request.setValue(AppInfo.version, forHTTPHeaderField: "X-App-Version")
        if let token = await appCheck.token() { request.setValue(token, forHTTPHeaderField: "X-Firebase-AppCheck") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try Self.encoder.encode(body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            if let err = try? Self.decoder.decode(APIErrorBody.self, from: data) {
                throw APIError.server(status: http.statusCode, code: err.error.code, message: err.error.message)
            }
            throw APIError.server(status: http.statusCode, code: "http_\(http.statusCode)", message: "지금은 연결이 어려워요. 잠시 후 다시 해 주세요.")
        }
        if Out.self == Empty.self || data.isEmpty { return try Self.decoder.decode(Out.self, from: Data("{}".utf8)) }
        return try Self.decoder.decode(Out.self, from: data)
    }
    private func send<Body: Encodable>(_ method: String, _ path: String, _ body: Body?, timeout: TimeInterval = 15) async throws {
        let _: Empty = try await send(method, path, body, timeout: timeout)
    }
    private func get<Out: Decodable>(_ path: String) async throws -> Out { try await send("GET", path, Optional<Empty>.none) }

    func upsertMe(_ body: UserUpsert) async throws -> UserProfile { try await send("POST", "users/me", body) }
    func registerDevice(_ body: DeviceRegister) async throws { try await send("POST", "devices", body) }
    func postConsent(_ body: ConsentRequest) async throws { try await send("POST", "consents", body) }
    func config() async throws -> ConfigResponse { try await get("config/latest") }

    func createSession(_ body: SessionCreateRequest) async throws -> SessionCreateResponse { try await send("POST", "api/session", body, timeout: 25) }
    func decision(_ body: DecisionRequest) async throws -> DecisionResponse { try await send("POST", "api/decision", body, timeout: 10) }
    /// 서버가 카드 추출에 최대 60초를 쓰므로 넉넉히 기다린다(모바일 가이드 4장).
    func endSession(id: String, _ body: SessionEndRequest) async throws { try await send("POST", "sessions/\(id)/end", body, timeout: 75) }
    func memoryControl(_ body: MemoryControlRequest) async throws { try await send("POST", "memories/control", body) }

    func pairingCode() async throws -> PairingCode { try await send("POST", "pairing/code", Optional<Empty>.none) }
    func link(code: String, relation: String) async throws -> GuardianLink {
        struct B: Codable { var code: String; var relation: String }
        return try await send("POST", "guardian/link", B(code: code, relation: relation))
    }
    func links() async throws -> [GuardianLink] { try await get("guardian/links") }
    func unlink(linkId: String) async throws { try await send("DELETE", "guardian/link/\(linkId)", Optional<Empty>.none) }
    func board(seniorId: String) async throws -> Board { try await get("guardian/board/\(seniorId)") }
    func resolvePairing(code: String) async throws -> PairingTarget {
        struct B: Codable { var code: String }
        return try await send("POST", "pairing/resolve", B(code: code))
    }
    func alerts(seniorId: String) async throws -> [Board.AlertItem] {
        let id = seniorId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? seniorId
        return try await get("guardian/alerts?senior_id=\(id)")
    }
    func markAlertRead(id: String) async throws { try await send("PATCH", "guardian/alerts/\(id)/read", Optional<Empty>.none) }
    func alertFollowUp(id: String, status: String) async throws {
        struct B: Codable { var status: String }
        try await send("PATCH", "guardian/alerts/\(id)/follow-up", B(status: status))
    }

    func schedules(seniorId: String) async throws -> [ScheduleItem] {
        let id = seniorId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? seniorId
        return try await get("schedules?senior_id=\(id)")
    }
    func saveSchedule(_ item: ScheduleItem) async throws -> ScheduleItem {
        if item.scheduleId.isEmpty { return try await send("POST", "schedules", item) }
        return try await send("PUT", "schedules/\(item.scheduleId)", item)
    }
    func deleteSchedule(id: String) async throws { try await send("DELETE", "schedules/\(id)", Optional<Empty>.none) }
    func ack(scheduleId: String, _ body: ScheduleAck) async throws { try await send("POST", "schedules/\(scheduleId)/ack", body) }
}
