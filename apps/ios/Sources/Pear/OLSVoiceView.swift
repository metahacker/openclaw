import AVFoundation
import Observation
import Speech
import SwiftUI

/// `.voice-surface`, light cascade: return pill, `VOICE` label, the orb, a truthful state
/// line, the spoken words, the project context row, and `Return to <origin>`.
struct OLSVoiceView: View {
    @Bindable var model: OLSModel
    let originLabel: String
    let projectName: String?
    let onReturn: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @Environment(NodeAppModel.self) private var appModel
    @State private var voice = OLSVoiceCapture()
    @State private var permissionTask: Task<Void, Never>?
    @State private var sendTask: Task<Void, Never>?

    private var screenshotMode: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--pear-ols-screenshot")
        #else
        false
        #endif
    }

    private var latestReply: OLSMessage? {
        self.model.latestFinalReply
    }

    /// `.voice-center small` ink (#63705d).
    private static let stateInk = Color(red: 99 / 255, green: 112 / 255, blue: 93 / 255)

    /// `.voice-orb`, light cascade.
    private static let orbGradient = RadialGradient(
        colors: [
            .white,
            Color(red: 232 / 255, green: 245 / 255, blue: 189 / 255),
            Color(red: 169 / 255, green: 204 / 255, blue: 96 / 255),
            Color(red: 111 / 255, green: 141 / 255, blue: 62 / 255),
            Color(red: 218 / 255, green: 229 / 255, blue: 189 / 255),
        ],
        center: UnitPoint(x: 0.42, y: 0.38),
        startRadius: 2,
        endRadius: 105)

    /// `.voice-surface` field: #f8f5ed down to #e8ecdc.
    private static let fieldGradient = LinearGradient(
        colors: [
            Color(red: 248 / 255, green: 245 / 255, blue: 237 / 255),
            Color(red: 232 / 255, green: 236 / 255, blue: 220 / 255),
        ],
        startPoint: .top,
        endPoint: .bottom)

    /// Never a fake "listening": the label follows the capture's real state.
    private var stateLabel: String {
        if self.voice.isAuthorizing { return "Voice mode · waiting for permission" }
        if self.voice.isListening { return "Voice mode · listening" }
        if self.voice.isSpeaking { return "PEAR · reading the reply" }
        if self.model.isSending { return "Voice mode · sending" }
        return "Voice mode · tap the orb to speak"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    self.stop()
                    self.onReturn()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.left").font(.system(size: 15, weight: .semibold))
                        VStack(alignment: .leading, spacing: 2) {
                            OLSKicker(text: "Return to", tracking: 1.4)
                            Text(self.originLabel).font(OLSTheme.serif(14, weight: .medium, relativeTo: .subheadline))
                        }
                    }
                    .foregroundStyle(OLSTheme.ink)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 48)
                    .background(OLSTheme.paper.opacity(0.72), in: Capsule())
                    .overlay { Capsule().strokeBorder(OLSTheme.spineLine) }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("ols.voice.return")
                .accessibilityLabel("Return to \(self.originLabel)")
                Spacer()
                HStack(spacing: 6) {
                    Image("PearMark").resizable().scaledToFit().frame(width: 13, height: 20).accessibilityHidden(true)
                    OLSKicker(text: "Voice", color: OLSTheme.ink, tracking: 1.2)
                }
            }
            .padding(.horizontal, 18)
            .frame(minHeight: 82)

            ScrollView {
                VStack(spacing: 18) {
                    Button {
                        if self.voice.isListening || self.voice.isAuthorizing {
                            self.permissionTask?.cancel()
                            self.voice.stop()
                        } else {
                            self.listen()
                        }
                    } label: {
                        ZStack {
                            ForEach(0..<3, id: \.self) { ring in
                                Circle().strokeBorder(OLSTheme.accent.opacity(0.18), lineWidth: 1)
                                    .frame(width: 180 + CGFloat(ring) * 38, height: 180 + CGFloat(ring) * 38)
                            }
                            Circle()
                                .fill(Self.orbGradient)
                                .frame(width: 150, height: 150)
                                .shadow(color: OLSTheme.accent.opacity(0.22), radius: 35)
                            if self.voice.isListening {
                                Image(systemName: "stop.fill").font(.system(size: 26, weight: .light))
                                    .foregroundStyle(OLSTheme.ink.opacity(0.7))
                            }
                        }
                        .frame(width: 260, height: 260)
                        .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(self.voice.isListening ? "Stop listening" : "Start listening")
                    .accessibilityIdentifier("ols.voice.listen")
                    .padding(.top, 20)
                    OLSKicker(text: self.stateLabel, color: Self.stateInk, tracking: 2.4)
                        .multilineTextAlignment(.center)
                    if let error = self.voice.error {
                        VStack(spacing: 10) {
                            Text(error).font(OLSTheme.label).foregroundStyle(OLSTheme.warning)
                                .multilineTextAlignment(.center)
                            if self.voice.needsSettings {
                                OLSPillAction(title: "Open Settings", filled: false) {
                                    if let url = URL(string: UIApplication.openSettingsURLString) {
                                        UIApplication.shared.open(url)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 22)
                    }
                    ZStack(alignment: .top) {
                        if self.model.draft.isEmpty {
                            Text("“Your words appear here.”")
                                .font(OLSTheme.quote)
                                .foregroundStyle(OLSTheme.secondary)
                                .multilineTextAlignment(.center)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                        OLSTextView(
                            text: self.$model.draft,
                            minLines: 2,
                            maxLines: 8,
                            isEnabled: !self.voice.isListening,
                            accessibilityLabel: "Your message",
                            accessibilityIdentifier: "ols.voice.draft")
                    }
                    .padding(.horizontal, 22)
                    .frame(maxWidth: 330)
                    HStack(spacing: 10) {
                        Button {
                            guard !self.screenshotMode else { return }
                            self.voice.stop()
                            self.sendTask = Task { await self.model.send() }
                        } label: {
                            HStack(spacing: 6) {
                                Text(self.model.isSending ? "Working" : "Send").font(OLSTheme.labelStrong)
                                Image(systemName: "paperplane.fill").font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundStyle(OLSTheme.sendInk)
                            .padding(.horizontal, 16).frame(minWidth: 80, minHeight: 44)
                            .background(OLSTheme.send, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(self.voice.isListening || self.voice.isAuthorizing || self.model.isSending
                            || self.model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("ols.voice.send")
                        if let reply = self.latestReply {
                            OLSPillAction(
                                title: self.voice.isSpeaking ? "Stop reading" : "Read the last reply",
                                filled: false,
                                symbol: self.voice.isSpeaking ? "stop.fill" : "speaker.wave.2")
                            {
                                guard !self.screenshotMode else { return }
                                if self.voice.isSpeaking {
                                    self.voice.stop()
                                } else if self.audioIsAvailable() {
                                    self.voice.speak(Self.readingText(reply.text))
                                }
                            }
                            .disabled(self.voice.isListening || self.voice.isAuthorizing)
                        }
                    }
                    if let status = self.model.sendStatus {
                        Text(status).font(OLSTheme.caption).foregroundStyle(OLSTheme.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)

            HStack(spacing: 10) {
                Image(systemName: "sparkles").font(.system(size: 16)).foregroundStyle(OLSTheme.ink)
                VStack(alignment: .leading, spacing: 3) {
                    Text(self.projectName ?? "Here with you")
                        .font(OLSTheme.serif(16, weight: .medium, relativeTo: .subheadline))
                        .foregroundStyle(OLSTheme.ink)
                    Text("Same project context · spoken instead of typed")
                        .font(OLSTheme.caption).foregroundStyle(OLSTheme.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 15)
            .overlay(alignment: .top) { OLSTheme.spineLine.frame(height: 1) }
            .overlay(alignment: .bottom) { OLSTheme.spineLine.frame(height: 1) }
            .padding(.horizontal, 18)
            Button {
                self.stop()
                self.onReturn()
            } label: {
                Text("Return to \(self.originLabel)")
                    .font(OLSTheme.labelStrong)
                    .foregroundStyle(Color(red: 35 / 255, green: 48 / 255, blue: 31 / 255))
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(OLSTheme.voiceDone, in: RoundedRectangle(cornerRadius: 4))
                    .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(OLSTheme.voiceDoneLine) }
            }
            .buttonStyle(.plain)
            .padding(EdgeInsets(top: 18, leading: 18, bottom: 22, trailing: 18))
        }
        .frame(maxWidth: .infinity)
        .background(Self.fieldGradient)
        .foregroundStyle(OLSTheme.ink)
        .simultaneousGesture(DragGesture(minimumDistance: 35).onEnded { value in
            if value.translation.width < -90, abs(value.translation.width) > abs(value.translation.height) * 2 {
                self.stop()
                self.onReturn()
            }
        })
        .onChange(of: self.voice.transcript) { _, text in self.model.draft = text }
        .onChange(of: self.scenePhase) { _, phase in
            // The system permission sheet may make the scene inactive. Let that
            // explicitly requested sheet finish, but never record in background.
            if phase == .background || (phase == .inactive && !self.voice.isAuthorizing) { self.stop() }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { _ in
            self.stop()
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.mediaServicesWereResetNotification)) { _ in
            self.stop()
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { notification in
            if let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
               reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { self.stop() }
        }
        .onDisappear { self.stop() }
    }

    private func audioIsAvailable() -> Bool {
        guard !self.appModel.talkMode.isEnabled, !self.appModel.talkMode.hasActivePushToTalkSession,
              !self.appModel.voiceWake.isListening
        else {
            self.voice.error = "Another voice session is using audio. Finish it in Device & connection, then try here."
            return false
        }
        return true
    }

    private func listen() {
        guard !self.screenshotMode, self.audioIsAvailable() else { return }
        let prefix = self.model.draft
        self.permissionTask = Task { await self.voice.start(prefix: prefix) }
    }

    private func stop() {
        self.permissionTask?.cancel()
        self.sendTask?.cancel()
        self.voice.stop()
    }

    private static func readingText(_ text: String) -> String {
        (try? AttributedString(markdown: text)).map { String($0.characters) } ?? text
    }
}

@MainActor
@Observable
private final class OLSVoiceCapture: NSObject, AVSpeechSynthesizerDelegate {
    private(set) var isListening = false
    private(set) var isAuthorizing = false
    private(set) var isSpeaking = false
    private(set) var transcript = ""
    var error: String?
    private(set) var needsSettings = false
    @ObservationIgnored private var engine = AVAudioEngine()
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var recognition: SFSpeechRecognitionTask?
    @ObservationIgnored private var recognizer: SFSpeechRecognizer?
    @ObservationIgnored private var synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private var tapInstalled = false
    @ObservationIgnored private var ownsAudio = false
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var speakingID: ObjectIdentifier?

    var status: String {
        if self.isAuthorizing { return "Waiting for permission…" }
        if self.isListening { return "Listening · tap to stop" }
        if self.isSpeaking { return "Reading your selected reply" }
        if self.needsFirstPermission {
            return "Tap to speak. iOS will ask once to use the microphone and speech recognition."
        }
        return "Tap to speak. Send when you’re ready."
    }

    /// Just-in-time permissions: explain before the first system prompt, which only
    /// happens after an explicit tap on the microphone button. These reads never prompt.
    private var needsFirstPermission: Bool {
        AVAudioApplication.shared.recordPermission != .granted
            || SFSpeechRecognizer.authorizationStatus() != .authorized
    }

    func start(prefix: String) async {
        self.stop()
        let generation = self.generation
        self.error = nil
        self.needsSettings = false
        self.transcript = prefix
        self.isAuthorizing = true
        let microphone = await VoicePermissionSupport.requestMicrophonePermission(timeoutErrorDomain: "OLSVoice")
        guard !Task.isCancelled, generation == self.generation else { return }
        guard microphone else {
            self.permissionFailed("Microphone access is needed to listen.")
            return
        }
        let speech = await VoicePermissionSupport.requestSpeechPermission(timeoutErrorDomain: "OLSVoice")
        guard !Task.isCancelled, generation == self.generation else { return }
        guard speech else {
            self.permissionFailed("Speech recognition access is needed to turn your words into text.")
            return
        }
        self.isAuthorizing = false
        let resolved = TalkSpeechLocale.makeRecognizer(gatewaySelection: nil)
        guard let recognizer = resolved.recognizer, recognizer.isAvailable else {
            self.error = "Speech recognition isn’t available just now. You can still type your message."
            return
        }
        do {
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try audio.setActive(true)
            self.ownsAudio = true
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.taskHint = .dictation
            self.request = request
            self.recognizer = recognizer
            let input = self.engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                throw OLSError.rejected("The microphone isn’t available.")
            }
            input.installTap(onBus: 0, bufferSize: 2048, format: format, block: Self.audioTap(request))
            self.tapInstalled = true
            self.engine.prepare()
            try self.engine.start()
            self.isListening = true
            self.recognition = recognizer.recognitionTask(
                with: request,
                resultHandler: self.resultHandler(generation: generation, prefix: prefix))
        } catch {
            self.stop()
            self.error = "I couldn’t start the microphone. Your message is still here; try again or type it."
        }
    }

    func stop() {
        self.generation += 1
        self.isAuthorizing = false
        self.isListening = false
        self.speakingID = nil
        self.isSpeaking = false
        self.synthesizer.stopSpeaking(at: .immediate)
        if self.engine.isRunning { self.engine.stop() }
        if self.tapInstalled {
            self.engine.inputNode.removeTap(onBus: 0)
            self.tapInstalled = false
        }
        self.request?.endAudio()
        self.recognition?.cancel()
        self.recognition = nil
        self.request = nil
        self.recognizer = nil
        self.releaseAudio()
    }

    func speak(_ text: String) {
        guard !text.isEmpty else { return }
        self.stop()
        self.error = nil
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)
            self.ownsAudio = true
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = AVSpeechSynthesisVoice(language: Locale.autoupdatingCurrent.identifier)
            self.speakingID = ObjectIdentifier(utterance)
            self.synthesizer.delegate = self
            self.synthesizer.speak(utterance)
        } catch {
            self.stop()
            self.error = "Audio couldn’t start. The reply is still available to read."
        }
    }

    private func permissionFailed(_ message: String) {
        self.isAuthorizing = false
        self.error = message
        self.needsSettings = true
    }

    private func releaseAudio() {
        guard self.ownsAudio else { return }
        self.ownsAudio = false
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    /// Match upstream TalkMode's nonisolated tap factory: the realtime audio
    /// callback appends buffers directly and never enters a main-actor closure.
    private nonisolated static func audioTap(_ request: SFSpeechAudioBufferRecognitionRequest) -> AVAudioNodeTapBlock {
        { buffer, _ in request.append(buffer) }
    }

    private nonisolated func resultHandler(
        generation: Int,
        prefix: String) -> @Sendable (SFSpeechRecognitionResult?, Error?) -> Void
    {
        { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let finished = result?.isFinal ?? false
            let failed = error != nil
            Task { @MainActor in
                guard let self, self.generation == generation, self.isListening else { return }
                if let text { self.transcript = prefix.isEmpty ? text : prefix + " " + text }
                if finished || failed {
                    self.stop()
                    if failed { self.error = "Listening ended. Review your words before sending, or tap to try again." }
                }
            }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in
            if self.speakingID == id { self.isSpeaking = true }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        self.finishedSpeech(ObjectIdentifier(utterance))
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        self.finishedSpeech(ObjectIdentifier(utterance))
    }

    private nonisolated func finishedSpeech(_ id: ObjectIdentifier) {
        Task { @MainActor in
            guard self.speakingID == id else { return }
            self.speakingID = nil
            self.isSpeaking = false
            self.releaseAudio()
        }
    }
}
