import AppKit
import CodexUsageCore
import Darwin

// Copied out of the bundle before launch, so replacing the app cannot remove the running helper.
let manager = FileManager.default
let arguments = CommandLine.arguments
guard arguments.count == 3, let parentPID = Int32(arguments[2]), parentPID > 1 else { exit(1) }
let transaction = URL(fileURLWithPath: arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()
let installed = URL(fileURLWithPath: arguments[1]).standardizedFileURL
let staged = transaction.appendingPathComponent("CodexUsageBar.app")
guard transaction.lastPathComponent.hasPrefix(".CodexUsageBar-update-"),
      transaction.deletingLastPathComponent() == installed.deletingLastPathComponent(),
      Bundle(url: installed)?.bundleIdentifier == AppInstallation.bundleIdentifier,
      Bundle(url: staged)?.bundleIdentifier == AppInstallation.bundleIdentifier else { exit(1) }
do {
    try Data().write(to: transaction.appendingPathComponent("ready"), options: .atomic)
} catch { exit(1) }

func launch(_ app: URL) throws {
    var result: Result<Void, Error>?
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.createsNewApplicationInstance = true
    NSWorkspace.shared.openApplication(at: app, configuration: configuration) { application, error in
        DispatchQueue.main.async {
            if let error { result = .failure(error) }
            else if application != nil { result = .success(()) }
            else { result = .failure(AppUpdateError.invalidBundle) }
        }
    }
    // Wait for the actual result; timing out could roll back while a delayed launch succeeds.
    while result == nil {
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }
    try (result ?? .failure(AppUpdateError.invalidBundle)).get()
}

// Do not replace a live app or forcibly terminate it if quitting was cancelled.
let deadline = Date().addingTimeInterval(60)
while kill(parentPID, 0) == 0 && Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
guard kill(parentPID, 0) != 0 else {
    try? manager.removeItem(at: transaction)
    exit(1)
}

do {
    try AppInstallation.activate(installed: installed, staged: staged, launch: launch)
    try? manager.removeItem(at: transaction)
} catch {
    // Keep the transaction directory on failure so even a failed rollback preserves both copies.
    try? launch(installed)
    let language = CodexUsageLanguage.preferred()
    let alert = NSAlert()
    alert.messageText = language.text(swedish: "Appuppdateringen misslyckades", english: "App update failed")
    alert.informativeText = language.text(
        swedish: "Du kan försöka igen eller hämta releasen från GitHub. Säkerhetskopian finns i \(transaction.path).",
        english: "You can try again or download the release from GitHub. The backup is in \(transaction.path).")
    alert.addButton(withTitle: "OK")
    NSApplication.shared.setActivationPolicy(.accessory)
    NSApplication.shared.activate(ignoringOtherApps: true)
    alert.runModal()
    exit(1)
}
