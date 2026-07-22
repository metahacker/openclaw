import Foundation
import Observation

/// State for the intimate PEAR conversation over the pear-mobile chat lane.
/// The truth line always reflects the real send/queue state — it is the queue UX.
@MainActor
@Observable
final class PearChatModel {
    enum SendState: Equatable {
        case idle
        case sending
        case delivered(Date)
        case failed(String)
    }

    private(set) var messages: [PearChatHistory.Message] = []
    private(set) var sendState: SendState = .idle
    private(set) var isLoadingHistory = false
    private(set) var historyError: String?
    var draft: String = ""

    private let page: String
    private var pollTask: Task<Void, Never>?

    init(page: String = "/apps/pear-mobile") {
        self.page = page
    }

    var truthLine: String {
        switch self.sendState {
        case .idle:
            self.historyError == nil ? "nothing queued · I'm all yours" : "offline · I'll catch up when we reconnect"
        case .sending:
            "sending…"
        case .delivered:
            "delivered · with PEAR now"
        case let .failed(reason):
            "couldn't send · \(reason)"
        }
    }

    private var api: PearAPI {
        PearAPI.current
    }

    // MARK: - History

    func startPolling() {
        guard self.pollTask == nil else { return }
        self.pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshHistory()
                try? await Task.sleep(nanoseconds: 4_000_000_000)
            }
        }
    }

    func stopPolling() {
        self.pollTask?.cancel()
        self.pollTask = nil
    }

    func refreshHistory() async {
        if self.isLoadingHistory { return }
        self.isLoadingHistory = true
        defer { self.isLoadingHistory = false }
        do {
            let fetched = try await self.api.chatHistory(page: self.page)
            if fetched != self.messages {
                self.messages = fetched
            }
            self.historyError = nil
            // A delivered marker only matters until PEAR's reply lands.
            if case let .delivered(at) = self.sendState, Date().timeIntervalSince(at) > 8 {
                self.sendState = .idle
            }
        } catch {
            self.historyError = error.localizedDescription
        }
    }

    // MARK: - Send

    func send() async {
        let text = self.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if case .sending = self.sendState { return }

        self.sendState = .sending
        self.draft = ""
        do {
            let response = try await self.api.sendChat(message: text, page: self.page)
            if response.ok == true {
                self.sendState = .delivered(Date())
            } else {
                // The message is on the ledger but PEAR's channel didn't take it.
                self.sendState = .failed(response.error ?? "PEAR is unreachable right now")
            }
        } catch {
            self.draft = text // give the words back — never lose a draft
            self.sendState = .failed(error.localizedDescription)
        }
        await self.refreshHistory()
    }
}
