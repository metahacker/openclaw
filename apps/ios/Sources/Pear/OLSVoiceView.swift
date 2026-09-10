import AVFoundation
import Observation
import Speech
import SwiftUI

struct OLSVoiceView: View {
    @Bindable var model: OLSModel
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
        self.model.messages.last(where: \.isAssistant)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Button {
                    self.stop()
                    self.onReturn()
                } label: {
                    Label { Text("Back").font(OLSTheme.label) } icon: { Image(systemName: "chevron.left") }
                        .frame(minHeight: 44)
                }
                Text("Same conversation.").font(OLSTheme.title)
                Text(self.model.activeContext?.hashtag ?? "Here with you")
                    .font(OLSTheme.chip).foregroundStyle(OLSTheme.secondary)

                VStack(spacing: 16) {
                    Button {
                        if self.voice.isListening || self.voice.isAuthorizing {
                            self.permissionTask?.cancel()
                            self.voice.stop()
                        } else {
                            self.listen()
                        }
                    } label: {
                        Image(systemName: self.voice.isListening ? "stop.fill" : "mic.fill")
                            .font(.system(size: 36, weight: .light))
                            .foregroundStyle(OLSTheme.ink)
                            .frame(width: 112, height: 112)
                            .background(OLSTheme.human, in: Circle())
                    }
                    .accessibilityLabel(self.voice.isListening ? "Stop listening" : "Start listening")
                    .accessibilityIdentifier("ols.voice.listen")
                    Text(self.voice.status).font(OLSTheme.label).foregroundStyle(OLSTheme.secondary)
                }
                .frame(maxWidth: .infinity)

                if let error = self.voice.error {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(error).font(OLSTheme.body).foregroundStyle(OLSTheme.warning)
                        if self.voice.needsSettings {
                            Button {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            } label: {
                                Text("Open Settings").font(OLSTheme.label).frame(minHeight: 44)
                            }
                        }
                    }
                    .accessibilityElement(children: .contain)
                }

                OLSCard {
                    VStack(alignment: .leading, spacing: 16) {
                        ZStack(alignment: .topLeading) {
                            if self.model.draft.isEmpty {
                                Text("Your words appear here…")
                                    .font(OLSTheme.body)
                                    .foregroundStyle(OLSTheme.secondary)
                                    .allowsHitTesting(false)
                                    .accessibilityHidden(true)
                            }
                            OLSTextView(
                                text: self.$model.draft,
                                minLines: 3,
                                maxLines: 12,
                                isEnabled: !self.voice.isListening,
                                accessibilityLabel: "Your message",
                                accessibilityIdentifier: "ols.voice.draft")
                        }
                        Button {
                            guard !self.screenshotMode else { return }
                            self.voice.stop()
                            self.sendTask = Task { await self.model.send() }
                        } label: {
                            Text(self.model.isSending ? "Sending…" : "Send")
                                .font(OLSTheme.label).padding(.horizontal, 20).frame(minHeight: 46)
                                .background(OLSTheme.human, in: Capsule())
                        }
                        .disabled(self.voice.isListening || self.voice.isAuthorizing || self.model.isSending
                            || self.model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if let status = self.model.sendStatus {
                            Text(status).font(OLSTheme.caption).foregroundStyle(OLSTheme.secondary)
                        }
                    }
                }

                if let reply = self.latestReply {
                    OLSCard {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Latest reply").font(OLSTheme.heading)
                            if let context = reply.context {
                                Text(context.hashtag).font(OLSTheme.chip).foregroundStyle(OLSTheme.secondary)
                            }
                            Text(Self.readingText(reply.text))
                                .font(OLSTheme.body).textSelection(.enabled)
                            Button {
                                guard !self.screenshotMode else { return }
                                if self.voice.isSpeaking {
                                    self.voice.stop()
                                } else if self.audioIsAvailable() {
                                    self.voice.speak(Self.readingText(reply.text))
                                }
                            } label: {
                                Label {
                                    Text(self.voice.isSpeaking ? "Stop reading" : "Read this reply")
                                        .font(OLSTheme.label)
                                } icon: {
                                    Image(systemName: self.voice.isSpeaking ? "stop.fill" : "speaker.wave.2")
                                }
                                .frame(minHeight: 44)
                            }
                            .disabled(self.voice.isListening || self.voice.isAuthorizing)
                        }
                    }
                }
            }
            .padding(24).frame(maxWidth: 720).frame(maxWidth: .infinity)
        }
        .background(OLSTheme.background)
        .foregroundStyle(OLSTheme.ink)
        .scrollDismissesKeyboard(.interactively)
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
                with: request, resultHandler: self.resultHandler(generation: generation, prefix: prefix))
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
        generation: Int, prefix: String) -> @Sendable (SFSpeechRecognitionResult?, Error?) -> Void
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
