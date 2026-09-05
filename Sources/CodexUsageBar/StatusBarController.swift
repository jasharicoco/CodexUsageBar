import AppKit
import Combine
import SwiftUI
import CodexUsageCore

/// A real status menu owns its background, corners, shadow, and position.
@MainActor
final class StatusBarController: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let model = UsageModel()
    private let updater = AppUpdateModel()
    private let language = CodexUsageLanguage.preferred()
    private var statusItem: NSStatusItem?
    private let menu = NSMenu()
    private let contentItem = NSMenuItem()
    private var hosting: NSHostingView<UsagePanel>?
    private var subscriptions = Set<AnyCancellable>()
    private var appearanceObservation: NSKeyValueObservation?
    private var isTracking = false
    private var pendingSize: NSSize?
    private var reopenAfterResize = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        item.button?.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        menu.autoenablesItems = false
        menu.delegate = self
        menu.appearance = NSApplication.shared.effectiveAppearance
        menu.addItem(contentItem)
        item.menu = menu
        updateStatusTitle()

        let hosting = NSHostingView(rootView: makePanel())
        hosting.sizingOptions = [.intrinsicContentSize]
        self.hosting = hosting
        hosting.setFrameSize(NSSize(width: UsagePanel.width, height: hosting.fittingSize.height))
        contentItem.view = hosting

        appearanceObservation = NSApplication.shared.observe(\.effectiveAppearance) { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.menu.appearance = NSApplication.shared.effectiveAppearance
            }
        }
        model.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateStatusTitle() }
            .store(in: &subscriptions)
        updater.$installationError
            .compactMap { $0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] error in self?.showInstallationError(error) }
            .store(in: &subscriptions)
        model.start()
        updater.start()
    }

    private func updateStatusTitle() {
        statusItem?.button?.title = model.menuBarText
        statusItem?.button?.toolTip = "Codex · \(model.menuBarText)"
        statusItem?.button?.setAccessibilityLabel("Codex · \(model.menuBarText)")
    }

    private func makePanel() -> UsagePanel {
        UsagePanel(model: model, updater: updater, language: language,
                   snackTheme: UserDefaults.standard.object(forKey: "snackTheme") as? Bool ?? true,
                   onSizeChange: { [weak self] in self?.resizeMenu(to: $0) },
                   onThemeSelection: { [weak self] in self?.selectTheme($0) },
                   onReset: { [weak self] in self?.confirmReset(creditID: $0) },
                   onInstall: { [weak self] in self?.performAfterClosingMenu { [weak self] in self?.updater.install() } })
    }

    private func selectTheme(_ monster: Bool) {
        UserDefaults.standard.set(monster, forKey: "snackTheme")
        if isTracking {
            reopenAfterResize = true
            menu.cancelTrackingWithoutAnimation()
        } else {
            hosting?.rootView = makePanel()
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard !isTracking, let hosting else { return }
        hosting.setFrameSize(NSSize(width: UsagePanel.width, height: ceil(hosting.fittingSize.height)))
    }

    func menuWillOpen(_ menu: NSMenu) {
        isTracking = true
    }

    func menuDidClose(_ menu: NSMenu) {
        isTracking = false
        if let size = pendingSize {
            pendingSize = nil
            hosting?.setFrameSize(size)
        }
        if reopenAfterResize {
            reopenAfterResize = false
            hosting?.rootView = makePanel()
            RunLoop.main.perform(inModes: [.default]) { [weak self] in
                MainActor.assumeIsolated { self?.statusItem?.button?.performClick(nil) }
            }
        }
    }

    private func resizeMenu(to size: CGSize) {
        guard size.height > 0, let hosting else { return }
        let size = NSSize(width: UsagePanel.width, height: ceil(size.height))
        guard hosting.frame.size != size else { return }
        if isTracking {
            // AppKit does not support resizing a custom menu view during tracking.
            // Reopen through the status item so AppKit preserves its native positioning.
            pendingSize = size
            reopenAfterResize = true
            menu.cancelTrackingWithoutAnimation()
        } else {
            hosting.setFrameSize(size)
        }
    }

    private func performAfterClosingMenu(_ action: @escaping @MainActor () -> Void) {
        reopenAfterResize = false
        menu.cancelTrackingWithoutAnimation()
        RunLoop.main.perform(inModes: [.default]) {
            MainActor.assumeIsolated { action() }
        }
    }

    private func confirmReset(creditID: String?) {
        performAfterClosingMenu { [weak self] in
            guard let self else { return }
            let strings = AppStrings(language: self.language)
            let alert = NSAlert()
            alert.messageText = strings.confirmResetTitle
            alert.informativeText = strings.confirmResetMessage
            alert.alertStyle = .warning
            alert.addButton(withTitle: strings.cancel)
            alert.addButton(withTitle: strings.useReset)
            NSApplication.shared.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertSecondButtonReturn {
                self.model.consumeReset(creditId: creditID)
            }
        }
    }

    private func showInstallationError(_ message: String) {
        performAfterClosingMenu { [weak self] in
            guard let self else { return }
            let alert = NSAlert()
            alert.messageText = self.language.text(swedish: "Uppdateringen kunde inte installeras", english: "The update could not be installed")
            alert.informativeText = message
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: self.language.text(swedish: "Försök igen", english: "Try again"))
            alert.addButton(withTitle: self.language.text(swedish: "Öppna releasen", english: "Open release"))
            NSApplication.shared.activate(ignoringOtherApps: true)
            let response = alert.runModal()
            self.updater.dismissInstallationError()
            if response == .alertSecondButtonReturn { self.updater.install() }
            if response == .alertThirdButtonReturn {
                NSWorkspace.shared.open(self.updater.release?.pageURL ?? AppRelease.releasesURL)
            }
        }
    }
}
