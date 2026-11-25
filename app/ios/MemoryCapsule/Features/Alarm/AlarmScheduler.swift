import Foundation
import AlarmKit
import AppIntents
import SwiftUI

/// 어르신 알람(iOS 26 AlarmKit). 팀 문서 iOS 대응표 2장 방식 B, 앱 계획서 2.4.
/// - 서버 일정(rrule 공통 부분집합)을 앞으로 alarmHorizonHours(48h) 동안의 고정 시각으로 펼쳐 예약한다.
///   반복 규칙을 기기 OS 기능에 맡기지 않으므로 Android와 같은 결과가 나온다(backend_spec v0.4 6.4).
/// - 재알림(reminder_after_min × maxReminders)은 미리 예약하고, "했어요" 누르면 남은 재알림을 취소한다.
/// - AlarmKit API는 iOS 26 SDK 기준으로 작성. 실제 빌드에서 시그니처 확인 필요.
@MainActor
final class AlarmScheduler {
    static let shared = AlarmScheduler()
    private let store = UserDefaults.standard
    private let mapKey = "mc.alarm.map"           // "scheduleId|dueEpoch|n" -> alarm UUID
    private let pendingAckKey = "mc.alarm.pendingAcks"
    private let cacheKey = "mc.schedules.cache"   // 마지막으로 받은 일정(앱 안 알람 화면용)
    private let handledKey = "mc.alarm.handled"   // 확인했거나 보여 준 "scheduleId|dueEpoch"

    var permissionString: String {
        switch AlarmManager.shared.authorizationState {
        case .authorized: "granted"
        case .denied: "denied"
        default: "unknown"
        }
    }

    func requestPermission() async -> Bool {
        (try? await AlarmManager.shared.requestAuthorization()) == .authorized
    }

    /// 서버 일정 전체를 받아 알람을 다시 채운다(앱 시작·포그라운드·무음 푸시).
    func sync(api: APIClient, seniorId: String) async {
        await flushPendingAcks(api: api)
        let items: [ScheduleItem]
        do { items = try await api.schedules(seniorId: seniorId) }
        catch {
            // 일정 공유 동의를 거두었거나 볼 권한이 없어지면(403) 예약해 둔 알람도 지운다. 통신 오류일 때는 그대로 둔다.
            if (error as? APIError)?.status == 403 { cancelAll(); store.removeObject(forKey: cacheKey); store.removeObject(forKey: mapKey) }
            return
        }
        if let data = try? JSONEncoder().encode(items) { store.set(data, forKey: cacheKey) }
        var allowed = permissionString == "granted"
        if !allowed { allowed = await requestPermission() }
        guard allowed else { return }
        cancelAll()
        let cfg = ConfigStore.shared.current.schedule
        let horizon = Date.now.addingTimeInterval(Double(cfg.alarmHorizonHours) * 3600)
        var map: [String: String] = [:]
        for item in items where item.active {
            for due in RRule.occurrences(item, from: .now, to: horizon) {
                let reminders = item.needsAck ? cfg.maxReminders : 0
                for n in 0...reminders {
                    let fire = due.addingTimeInterval(Double(n * item.reminderAfterMin) * 60)
                    guard fire > .now else { continue }
                    if let id = try? await schedule(item: item, dueAt: due, fireAt: fire, reminder: n) {
                        map["\(item.scheduleId)|\(Int(due.timeIntervalSince1970))|\(n)"] = id.uuidString
                    }
                }
            }
        }
        store.set(map, forKey: mapKey)
    }

    private func schedule(item: ScheduleItem, dueAt: Date, fireAt: Date, reminder: Int) async throws -> UUID {
        let id = UUID()
        // 확인 필요 일정만 "했어요"(ack 전송). 확인 불필요 일정은 "확인"으로 끄기만 한다(앱 계획서 2.4).
        let done = item.needsAck
            ? AlarmButton(text: "했어요", textColor: .white, systemImageName: "checkmark.circle.fill")
            : AlarmButton(text: "확인", textColor: .white, systemImageName: "xmark.circle.fill")
        let alert = AlarmPresentation.Alert(title: LocalizedStringResource(stringLiteral: item.title), stopButton: done)
        let meta = ScheduleAlarmMetadata(scheduleId: item.scheduleId, dueEpoch: Int(dueAt.timeIntervalSince1970), message: item.message)
        let attributes = AlarmAttributes<ScheduleAlarmMetadata>(presentation: AlarmPresentation(alert: alert), metadata: meta, tintColor: Theme.green)
        let intent = AckScheduleIntent(scheduleId: item.scheduleId, dueEpoch: meta.dueEpoch)
        let config = AlarmManager.AlarmConfiguration<ScheduleAlarmMetadata>.alarm(
            schedule: .fixed(fireAt), attributes: attributes, stopIntent: item.needsAck ? intent : nil)
        _ = try await AlarmManager.shared.schedule(id: id, configuration: config)
        return id
    }

    func cancelAll() {
        let map = store.dictionary(forKey: mapKey) as? [String: String] ?? [:]
        for value in map.values { if let id = UUID(uuidString: value) { try? AlarmManager.shared.cancel(id: id) } }
        store.removeObject(forKey: mapKey)
    }

    // MARK: - 앱 안 알람 화면

    /// 15분 안에 울린 알람 중 아직 확인·표시하지 않은 것.
    func pendingRing(now: Date) -> RingingAlarm? {
        guard let data = store.data(forKey: cacheKey),
              let items = try? JSONDecoder().decode([ScheduleItem].self, from: data) else { return nil }
        let handled = Set(store.stringArray(forKey: handledKey) ?? [])
        for item in items where item.active {
            let windowStart = now.addingTimeInterval(-15 * 60)
            for due in RRule.occurrences(item, from: windowStart, to: now) where due >= windowStart && due <= now {
                let epoch = Int(due.timeIntervalSince1970)
                if !handled.contains("\(item.scheduleId)|\(epoch)") {
                    return RingingAlarm(scheduleId: item.scheduleId, dueEpoch: epoch, title: item.title,
                                        message: item.message, needsAck: item.needsAck)
                }
            }
        }
        return nil
    }

    func markHandled(scheduleId: String, dueEpoch: Int) {
        var list = store.stringArray(forKey: handledKey) ?? []
        list.append("\(scheduleId)|\(dueEpoch)")
        store.set(Array(list.suffix(200)), forKey: handledKey)
    }

    /// "했어요" → 같은 due의 남은 재알림 취소 + 서버 ack(실패 시 보관 후 재전송).
    /// method: 앱 화면 버튼은 button, 시스템 알람 버튼은 alarm_stop.
    func acknowledge(scheduleId: String, dueEpoch: Int, api: APIClient, method: String = "alarm_stop") async {
        markHandled(scheduleId: scheduleId, dueEpoch: dueEpoch)
        var map = store.dictionary(forKey: mapKey) as? [String: String] ?? [:]
        for (key, value) in map where key.hasPrefix("\(scheduleId)|\(dueEpoch)|") {
            if let id = UUID(uuidString: value) { try? AlarmManager.shared.cancel(id: id) }
            map.removeValue(forKey: key)
        }
        store.set(map, forKey: mapKey)
        let ack = Self.makeAck(due: Double(dueEpoch), acked: Date.now.timeIntervalSince1970, method: method, offline: false)
        do { try await api.ack(scheduleId: scheduleId, ack) }
        catch { if Self.shouldRetryAck(error) { savePending(scheduleId, ack) } }
    }

    /// 서버 규칙: due_at은 분 단위, due_at ≤ fired_at ≤ acked_at. 알람이 울린 시각을 따로 받지 못하므로 예정 시각을 fired_at으로 쓴다.
    private static func makeAck(due: Double, acked: Double, method: String, offline: Bool) -> ScheduleAck {
        let dueAt = Date(timeIntervalSince1970: (due / 60).rounded(.down) * 60)
        let ackedAt = max(Date(timeIntervalSince1970: acked), dueAt)
        return ScheduleAck(dueAt: dueAt, firedAt: dueAt, ackedAt: ackedAt, ackMethod: method, syncedFromOffline: offline)
    }

    /// 400·403·404(형식 오류, 동의·권한 없음, 지워진 일정, 확인이 필요 없는 일정)는 다시 보내도 같은 결과라 버린다. 그 밖(네트워크, 401, 5xx)은 보관 후 재전송.
    private static func shouldRetryAck(_ error: Error) -> Bool {
        if case APIError.server(let status, _, _) = error { return !(status == 400 || status == 403 || status == 404) }
        return true
    }

    private func savePending(_ scheduleId: String, _ ack: ScheduleAck) {
        var list = store.array(forKey: pendingAckKey) as? [[String: Any]] ?? []
        list.append(["id": scheduleId, "due": ack.dueAt.timeIntervalSince1970, "acked": ack.ackedAt.timeIntervalSince1970,
                     "method": ack.ackMethod])
        store.set(Array(list.suffix(200)), forKey: pendingAckKey)
    }

    private func flushPendingAcks(api: APIClient) async {
        let list = store.array(forKey: pendingAckKey) as? [[String: Any]] ?? []
        var remaining: [[String: Any]] = []
        for e in list {
            guard let id = e["id"] as? String, let due = e["due"] as? Double, let acked = e["acked"] as? Double else { continue }
            let ack = Self.makeAck(due: due, acked: acked, method: e["method"] as? String ?? "alarm_stop", offline: true)
            do { try await api.ack(scheduleId: id, ack) } catch { if Self.shouldRetryAck(error) { remaining.append(e) } }
        }
        store.set(remaining, forKey: pendingAckKey)
    }
}

/// 앱 안 알람 화면에 띄울 알람 1건.
struct RingingAlarm: Identifiable, Equatable, Sendable {
    var scheduleId: String
    var dueEpoch: Int
    var title: String
    var message: String
    var needsAck: Bool
    var id: String { "\(scheduleId)|\(dueEpoch)" }
}

struct ScheduleAlarmMetadata: AlarmMetadata {
    var scheduleId: String
    var dueEpoch: Int
    var message: String
}

/// 알람의 "했어요" 버튼. 앱이 꺼져 있어도 시스템이 이 인텐트를 실행한다.
struct AckScheduleIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "일정 확인"
    static let openAppWhenRun = false

    @Parameter(title: "일정 ID") var scheduleId: String
    @Parameter(title: "예정 시각") var dueEpoch: Int

    init() {}
    init(scheduleId: String, dueEpoch: Int) { self.scheduleId = scheduleId; self.dueEpoch = dueEpoch }

    func perform() async throws -> some IntentResult {
        let api = await MainActor.run { AppState.shared.api }
        await AlarmScheduler.shared.acknowledge(scheduleId: scheduleId, dueEpoch: dueEpoch, api: api)
        return .result()
    }
}

/// 일정 반복 규칙. 두 OS 공통 부분집합만 지원(backend_spec v0.4 6.4): FREQ=DAILY, FREQ=WEEKLY;BYDAY=MO,TU,...
enum RRule {
    static func occurrences(_ item: ScheduleItem, from: Date, to: Date) -> [Date] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: item.timezone) ?? .current   // 어르신 시간대 기준
        let hm = item.timeLocal.split(separator: ":").compactMap { Int($0) }
        guard hm.count == 2 else { return [] }
        // 시작 날짜(G13, 목 전용 확장): 그 전 날짜는 건너뛴다. 반복 없음("NONE")이면 그날 한 번만.
        let fmt = DateFormatter(); fmt.calendar = cal; fmt.timeZone = cal.timeZone; fmt.dateFormat = "yyyy-MM-dd"
        let startDay = item.startDate.flatMap { fmt.date(from: $0) }
        if item.rrule == "NONE" {
            guard let startDay, let d = cal.date(bySettingHour: hm[0], minute: hm[1], second: 0, of: startDay),
                  d >= from.addingTimeInterval(-3600 * 3), d <= to else { return [] }
            return [d]
        }
        let parts = Dictionary(uniqueKeysWithValues: item.rrule.split(separator: ";").compactMap { p -> (String, String)? in
            let kv = p.split(separator: "=", maxSplits: 1); return kv.count == 2 ? (String(kv[0]), String(kv[1])) : nil })
        let days: Set<Int>? = parts["BYDAY"].map { Set($0.split(separator: ",").compactMap { weekday(String($0)) }) }
        guard parts["FREQ"] == "DAILY" || (parts["FREQ"] == "WEEKLY" && days != nil) else { return [] }

        var result: [Date] = []
        var day = cal.startOfDay(for: from)
        while day <= to {
            if (startDay == nil || day >= startDay!), days == nil || days!.contains(cal.component(.weekday, from: day)),
               let d = cal.date(bySettingHour: hm[0], minute: hm[1], second: 0, of: day), d >= from.addingTimeInterval(-3600 * 3), d <= to {
                result.append(d)   // 초 0 = due_at 분 단위 정규화
            }
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }

    static func weekday(_ s: String) -> Int? {
        ["SU": 1, "MO": 2, "TU": 3, "WE": 4, "TH": 5, "FR": 6, "SA": 7][s]
    }
    static func make(weekdays: Set<Int>) -> String {
        if weekdays.isEmpty || weekdays.count == 7 { return "FREQ=DAILY" }
        let names = [1: "SU", 2: "MO", 3: "TU", 4: "WE", 5: "TH", 6: "FR", 7: "SA"]
        return "FREQ=WEEKLY;BYDAY=" + weekdays.sorted { ($0 + 5) % 7 < ($1 + 5) % 7 }.compactMap { names[$0] }.joined(separator: ",")
    }
}
