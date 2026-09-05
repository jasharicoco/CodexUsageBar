import AppKit
import CodexUsageCore
import Foundation

@MainActor
final class AppUpdateModel: ObservableObject {
    @Published private(set) var release: AppRelease?
    @Published private(set) var isChecking = false
    @Published private(set) var isInstalling = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var installationError: String?
    @Published var automaticChecks: Bool {
        didSet {
            UserDefaults.standard.set(automaticChecks, forKey: "automaticAppUpdateChecks")
            if automaticChecks { check() }
        }
    }

    let currentVersion: String
    private let client: AppUpdateClient
    private var timer: Timer?

    init(client: AppUpdateClient = AppUpdateClient(),
         currentVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0") {
        self.client = client
        self.currentVersion = currentVersion
        automaticChecks = UserDefaults.standard.object(forKey: "automaticAppUpdateChecks") as? Bool ?? true
    }

    func start() {
        guard timer == nil else { return }
        if automaticChecks { check() }
        let timer = Timer(timeInterval: 6 * 60 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.automaticChecks else { return }
                self.check()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func check() {
        guard !isChecking, !isInstalling else { return }
        isChecking = true
        errorMessage = nil
        Task {
            defer { isChecking = false }
            do {
                guard let version = AppVersion(currentVersion) else { throw AppUpdateError.invalidBundle }
                release = try await client.latest(after: version)
            } catch {
                // Preserve an already discovered update when offline or rate limited.
                errorMessage = error.localizedDescription
            }
        }
    }

    func install() {
        guard let release, !isInstalling, !isChecking else { return }
        isInstalling = true
        errorMessage = nil
        installationError = nil
        let installedApp = Bundle.main.bundleURL.resolvingSymlinksInPath()
        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/UpdateInstaller")
        Task {
            do {
                let transaction = try await Task.detached(priority: .userInitiated) { [client] in
                    let manager = FileManager.default
                    let parent = installedApp.deletingLastPathComponent()
                    guard installedApp.pathExtension == "app",
                          !installedApp.path.contains("/AppTranslocation/"),
                          manager.isWritableFile(atPath: installedApp.path),
                          manager.isWritableFile(atPath: parent.path),
                          manager.isExecutableFile(atPath: helper.path) else {
                        throw AppUpdateError.installLocation
                    }
                    // A sibling staging directory guarantees the final atomic swap stays on one volume.
                    let transaction = parent.appendingPathComponent(".CodexUsageBar-update-\(UUID().uuidString)", isDirectory: true)
                    try manager.createDirectory(at: transaction, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
                    do {
                        let archive = try await client.download(release, to: transaction)
                        try AppInstallation.stage(archive: archive, version: release.version, installedApp: installedApp,
                                                  helper: helper, in: transaction)
                        try manager.removeItem(at: archive)
                        return transaction
                    } catch {
                        try? manager.removeItem(at: transaction)
                        throw error
                    }
                }.value

                let installer = Process()
                installer.executableURL = transaction.appendingPathComponent("UpdateInstaller")
                installer.arguments = [installedApp.path, String(ProcessInfo.processInfo.processIdentifier)]
                do {
                    try installer.run()
                    let deadline = Date().addingTimeInterval(10)
                    let ready = transaction.appendingPathComponent("ready")
                    while !FileManager.default.fileExists(atPath: ready.path) {
                        guard installer.isRunning, Date() < deadline else { throw AppUpdateError.invalidBundle }
                        try await Task.sleep(nanoseconds: 50_000_000)
                    }
                } catch {
                    if installer.isRunning { installer.terminate() }
                    try? FileManager.default.removeItem(at: transaction)
                    throw error
                }
                NSApplication.shared.terminate(nil)
            } catch {
                installationError = error.localizedDescription
                isInstalling = false
            }
        }
    }

    func dismissInstallationError() {
        installationError = nil
    }
}
