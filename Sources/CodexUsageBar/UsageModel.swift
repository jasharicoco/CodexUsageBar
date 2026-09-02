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

@MainActor
final class UsageModel: ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var isLoading = false
    @Published private(set) var connectionIssue: UsageConnectionIssue?

    private let client = CodexUsageClient()
    private var refreshTimer: Timer?

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
        guard !isLoading else { return }
        isLoading = true
        connectionIssue = nil

        Task {
            do {
                snapshot = try await client.fetch()
            } catch {
                connectionIssue = UsageConnectionIssue(error: error)
            }
            isLoading = false
        }
    }
}
