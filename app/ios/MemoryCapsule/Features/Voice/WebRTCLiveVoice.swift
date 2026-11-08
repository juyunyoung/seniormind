import Foundation
import AVFoundation
import WebRTC

/// gpt-live-1 실제 연결(PoC voice.mjs 이식). API 키는 서버만 가진다: 앱은 SDP offer를 `/api/session`에 보내고 answer를 받는다.
/// 주의: 이 파일은 WebRTC iOS 프레임워크 API를 기준으로 작성했고 실제 빌드 확인이 필요하다.
@MainActor
final class WebRTCLiveVoice: NSObject, LiveVoice {
    var onEvent: (LiveEvent) -> Void = { _ in }
    var onState: (LiveState) -> Void = { _ in }
    private(set) var sessionId: String?
    private(set) var maxSeconds = 600

    private static let factory: RTCPeerConnectionFactory = {
        RTCInitializeSSL()
        return RTCPeerConnectionFactory()
    }()
    private var pc: RTCPeerConnection?
    private var dc: RTCDataChannel?
    private var active = false
    private var stopping = false
    private var timers: [Task<Void, Never>] = []
    private var iceComplete: CheckedContinuation<Void, Never>?
    /// 기억이 출력 자막이 들어온 최근 시각 → 입 움직임 근사(원격 트랙 RMS는 2차 과제)
    private var speakingUntil = Date.distantPast

    func mouthLevel() -> Double {
        let now = Date.now
        guard active, now < speakingUntil else { return 0 }
        return max(0, sin(now.timeIntervalSinceReferenceDate * 1000 / 95)) * 0.6
    }

    func start(api: APIClient) async {
        cleanup()
        onState(.connecting)
        do {
            guard await AVAudioApplication.requestRecordPermission() else {
                throw LiveError.message("마이크 권한을 허용한 뒤 다시 연결해 주세요.")
            }
            try configureAudioSession()

            let config = RTCConfiguration()
            config.sdpSemantics = .unifiedPlan
            let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
            guard let pc = Self.factory.peerConnection(with: config, constraints: constraints, delegate: self) else {
                throw LiveError.message("음성 연결을 준비하지 못했어요.")
            }
            self.pc = pc
            let source = Self.factory.audioSource(with: constraints)
            let track = Self.factory.audioTrack(with: source, trackId: "mic")
            pc.add(track, streamIds: ["mc"])

            let dcConfig = RTCDataChannelConfiguration()
            let dc = pc.dataChannel(forLabel: "oai-events", configuration: dcConfig)
            dc?.delegate = self
            self.dc = dc

            let offer = try await createOffer(pc, constraints)
            try await setLocal(pc, offer)
            await waitIce(timeout: 10)

            guard let sdp = pc.localDescription?.sdp else { throw LiveError.message("마이크 연결 준비 시간이 초과됐어요.") }
            let request = SessionCreateRequest(sdp: sdp, client: .init(platform: "ios", appVersion: AppInfo.version))
            let created: SessionCreateResponse
            do { created = try await api.createSession(request) }
            catch let e as APIError where e.code == "consent_required" {
                // 기기에는 동의가 있는데 서버에 기록이 없을 때(동의 저장 실패) 한 번 다시 보내고 재시도
                guard await AppState.shared.resyncSeniorConsents() else { throw e }
                created = try await api.createSession(request)
            }
            sessionId = created.session.id
            maxSeconds = created.session.maxSeconds
            try await setRemote(pc, RTCSessionDescription(type: .answer, sdp: created.transport.sdp))
            timers.append(Task { [weak self] in
                try? await Task.sleep(for: .seconds(25))
                guard let self, !self.active, !Task.isCancelled else { return }
                self.cleanup(); self.onState(.error("세션 시작 응답을 받지 못했어요."))
            })
        } catch {
            cleanup()
            var text = (error as? LiveError)?.text ?? (error as? APIError)?.errorDescription ?? "지금은 연결이 어려워요. 잠시 후 다시 해 주세요."
            #if DEBUG
            print("[MC] 음성 연결 실패: \(error)")
            if case .server(let status, let code, _)? = error as? APIError { text += " (\(status) \(code))" }
            else if !(error is LiveError) { text += " (\(error.localizedDescription))" }
            #endif
            onState(.error(text))
        }
    }

    func stop() {
        guard !stopping else { return }
        guard active, dc?.readyState == .open else { cleanup(); onState(.ended("대화를 마쳤어요.")); return }
        stopping = true
        onState(.closing)
        // 마이크는 즉시 끄고, 사용량 확정을 위해 이벤트 채널은 잠시 유지(PoC와 동일)
        pc?.senders.forEach { $0.track?.isEnabled = false }
        send(json: ["type": "session.close"])
        timers.append(Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard let self, !Task.isCancelled else { return }
            self.cleanup(); self.onState(.ended("연결을 닫았어요."))
        })
    }

    func send(json: [String: Any]) {
        guard let dc, dc.readyState == .open, let data = try? JSONSerialization.data(withJSONObject: json) else { return }
        dc.sendData(RTCDataBuffer(data: data, isBinary: false))
    }

    // MARK: - 이벤트 처리

    private func handle(_ e: [String: Any]) {
        let type = e["type"] as? String ?? ""
        switch type {
        case "session.started":
            active = true
            onEvent(.started); onState(.active)
            let limit = maxSeconds
            timers.append(Task { [weak self] in
                try? await Task.sleep(for: .seconds(limit))
                if !Task.isCancelled { self?.stop() }
            })
        case "session.closed":
            if let s = (e["usage"] as? [String: Any])?["seconds"] as? Double { onEvent(.usage(seconds: s, final: true)) }
            onEvent(.closed); cleanup(); onState(.ended("대화를 마쳤어요."))
        case "session.input_transcript.delta":
            if let d = e["delta"] as? String, let s = e["start_ms"] as? Int {
                onEvent(.inputDelta(id: e["event_id"] as? String ?? UUID().uuidString, text: d, startMs: s))
            }
        case "session.input_transcript.done":
            let s = e["start_ms"] as? Int ?? 0
            onEvent(.inputDone(startMs: s, endMs: e["end_ms"] as? Int ?? s))
        case "session.output_transcript.delta":
            if let d = e["delta"] as? String, let s = e["start_ms"] as? Int {
                speakingUntil = .now.addingTimeInterval(1.2)
                onEvent(.outputDelta(id: e["event_id"] as? String ?? UUID().uuidString, text: d, startMs: s))
            }
        case "session.delegation.created":
            if let id = (e["delegation"] as? [String: Any])?["id"] as? String { onEvent(.delegation(id: id)) }
        case "session.usage.updated":
            if let s = (e["usage"] as? [String: Any])?["seconds"] as? Double { onEvent(.usage(seconds: s, final: false)) }
        case "error", "session.error":
            // 복구 가능한 경고. 연결은 유지(PoC와 동일)
            onEvent(.warning((e["error"] as? [String: Any])?["message"] as? String ?? ""))
        default: break
        }
    }

    // MARK: - 정리

    private func cleanup() {
        timers.forEach { $0.cancel() }; timers.removeAll()
        active = false; stopping = false
        dc?.delegate = nil; dc?.close(); dc = nil
        pc?.close(); pc = nil
        iceComplete?.resume(); iceComplete = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func configureAudioSession() throws {
        let session = RTCAudioSession.sharedInstance()
        session.lockForConfiguration()
        defer { session.unlockForConfiguration() }
        // .voiceChat 모드가 에코 제거·노이즈 억제를 켠다(iOS 대응표 1.2)
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true)
    }

    // MARK: - 콜백 → async

    private func createOffer(_ pc: RTCPeerConnection, _ c: RTCMediaConstraints) async throws -> RTCSessionDescription {
        try await withCheckedThrowingContinuation { cont in
            pc.offer(for: c) { sdp, error in
                if let sdp { cont.resume(returning: sdp) } else { cont.resume(throwing: error ?? LiveError.message("연결 준비 실패")) }
            }
        }
    }
    private func setLocal(_ pc: RTCPeerConnection, _ sdp: RTCSessionDescription) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            pc.setLocalDescription(sdp) { error in error.map { cont.resume(throwing: $0) } ?? cont.resume() }
        }
    }
    private func setRemote(_ pc: RTCPeerConnection, _ sdp: RTCSessionDescription) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            pc.setRemoteDescription(sdp) { error in error.map { cont.resume(throwing: $0) } ?? cont.resume() }
        }
    }
    private func waitIce(timeout: Int) async {
        if pc?.iceGatheringState == .complete { return }
        await withCheckedContinuation { cont in
            iceComplete = cont
            timers.append(Task { [weak self] in
                try? await Task.sleep(for: .seconds(timeout))
                self?.iceComplete?.resume(); self?.iceComplete = nil
            })
        }
    }

    enum LiveError: Error { case message(String); var text: String { if case .message(let m) = self { m } else { "" } } }
}

extension WebRTCLiveVoice: RTCPeerConnectionDelegate, RTCDataChannelDelegate {
    nonisolated func peerConnection(_ pc: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        guard newState == .complete else { return }
        Task { @MainActor in self.iceComplete?.resume(); self.iceComplete = nil }
    }
    nonisolated func peerConnection(_ pc: RTCPeerConnection, didChange newState: RTCPeerConnectionState) {
        guard newState == .failed else { return }
        Task { @MainActor in self.cleanup(); self.onState(.error("음성 연결이 끊겼어요. 다시 연결해 주세요.")) }
    }
    nonisolated func dataChannel(_ dc: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        guard let json = try? JSONSerialization.jsonObject(with: buffer.data) as? [String: Any] else { return }
        let box = UncheckedBox(json)
        Task { @MainActor in self.handle(box.value) }
    }
    nonisolated func dataChannelDidChangeState(_ dc: RTCDataChannel) {
        guard dc.readyState == .closed else { return }
        Task { @MainActor in
            guard self.active else { return }
            self.cleanup(); self.onState(.ended("연결이 종료됐어요."))
        }
    }
    // 사용하지 않는 필수 콜백
    nonisolated func peerConnection(_ pc: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    nonisolated func peerConnection(_ pc: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
    nonisolated func peerConnection(_ pc: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    nonisolated func peerConnectionShouldNegotiate(_ pc: RTCPeerConnection) {}
    nonisolated func peerConnection(_ pc: RTCPeerConnection, didChange newState: RTCIceConnectionState) {}
    nonisolated func peerConnection(_ pc: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {}
    nonisolated func peerConnection(_ pc: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    nonisolated func peerConnection(_ pc: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
}

struct UncheckedBox<T>: @unchecked Sendable { let value: T; init(_ v: T) { value = v } }
