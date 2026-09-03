import Foundation
import CodexUsageCore

enum UsageConnectionIssue: Equatable {
    case codexMissing
    case signInRequired
    case chatGPTAccountRequired
    case unsupportedAccount
    case generic(String)

    init(error: Error) {
        switch error as? CodexUsageClientError {
        case .executableNotFound:
            self = .codexMissing
        case .notLoggedIn:
            self = .signInRequired
        case .chatGPTAccountRequired:
            self = .chatGPTAccountRequired
        case .unsupportedAccount:
            self = .unsupportedAccount
        default:
            self = .generic(error.localizedDescription)
        }
    }

}

enum UsageResetNotice: Equatable {
    case reset
    case alreadyRedeemed
    case nothingToReset
    case noCredit
    case unknown(String)
    case failure(String)
}

@MainActor
final class UsageModel: ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var isLoading = false
    @Published private(set) var isConsumingReset = false
    @Published private(set) var connectionIssue: UsageConnectionIssue?
    @Published var resetNotice: UsageResetNotice?

    private let client = CodexUsageClient()
    private var refreshTimer: Timer?
    private var pendingResetAttempt: (creditId: String?, idempotencyKey: UUID)?

    var isBusy: Bool {
        isLoading || isConsumingReset
    }

    var menuBarText: String {
        if let snapshot {
            return "\(snapshot.remainingPercent)%"
        }
        return isLoading ? "…" : "!"
    }

    func start() {
        guard refreshTimer == nil else { return }
        refresh()

        let timer = Timer(timeInterval: 5 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    func refresh() {
        guard !isBusy else { return }
        isLoading = true
        connectionIssue = nil
        resetNotice = nil

        Task {
            do {
                snapshot = try await client.fetch()
            } catch {
                connectionIssue = UsageConnectionIssue(error: error)
            }
            isLoading = false
        }
    }

    func consumeReset(creditId: String?) {
        guard !isBusy else { return }

        let attempt: (creditId: String?, idempotencyKey: UUID)
        if let pendingResetAttempt, pendingResetAttempt.creditId == creditId {
            attempt = pendingResetAttempt
        } else {
            attempt = (creditId, UUID())
            pendingResetAttempt = attempt
        }

        isConsumingReset = true
        connectionIssue = nil
        resetNotice = nil

        Task {
            do {
                let outcome = try await client.consumeReset(
                    creditId: attempt.creditId,
                    idempotencyKey: attempt.idempotencyKey
                )
                pendingResetAttempt = nil

                switch outcome {
                case .reset:
                    resetNotice = .reset
                case .alreadyRedeemed:
                    resetNotice = .alreadyRedeemed
                case .nothingToReset:
                    resetNotice = .nothingToReset
                case .noCredit:
                    resetNotice = .noCredit
                case .unknown(let value):
                    resetNotice = .unknown(value)
                }

                do {
                    snapshot = try await client.fetch()
                } catch {
                    connectionIssue = UsageConnectionIssue(error: error)
                }
            } catch {
                resetNotice = .failure(error.localizedDescription)
            }

            isConsumingReset = false
        }
    }
}
