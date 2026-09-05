import AppKit
import Combine
import SwiftUI
import CodexUsageCore

/// AppKit owns the anchor and window shape; SwiftUI only supplies the panel content.
@MainActor
final class StatusBarController: NSObject, NSApplicationDelegate {
    private let model = UsageModel()
    private let updater = AppUpdateModel()
    private let language = CodexUsageLanguage.preferred()
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var subscriptions = Set<AnyCancellable>()
    private var appearanceObservation: NSKeyValueObservation?
    private var usesMonster = true

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        item.button?.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        updateStatusTitle()

        let panel = UsagePanel(model: model, updater: updater, language: language,
                               onSizeChange: { [weak self] in self?.resizePopover(to: $0) },
                               onThemeChange: { [weak self] in self?.updateAppearance(monster: $0) })
        let hosting = NSHostingController(rootView: panel)
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
        popover.behavior = .transient
        popover.animates = false
        popover.contentSize = NSSize(width: UsagePanel.width, height: 200)
        updateAppearance(monster: UserDefaults.standard.object(forKey: "snackTheme") as? Bool ?? true)
        appearanceObservation = NSApplication.shared.observe(\.effectiveAppearance) { [weak self] _, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.updateAppearance(monster: self.usesMonster)
            }
        }

        model.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateStatusTitle() }
            .store(in: &subscriptions)
        model.start()
        updater.start()
    }

    private func updateStatusTitle() {
        statusItem?.button?.title = model.menuBarText
        statusItem?.button?.toolTip = "Codex · \(model.menuBarText)"
        statusItem?.button?.setAccessibilityLabel("Codex · \(model.menuBarText)")
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            if let view = popover.contentViewController?.view {
                resizePopover(to: view.fittingSize)
            }
            NSApplication.shared.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func resizePopover(to size: CGSize) {
        guard size.height > 0 else { return }
        let size = NSSize(width: UsagePanel.width, height: ceil(size.height))
        guard popover.contentSize != size else { return }
        popover.contentSize = size
        if popover.isShown, let button = statusItem?.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func updateAppearance(monster: Bool) {
        usesMonster = monster
        popover.appearance = monster ? NSAppearance(named: .darkAqua) : NSApplication.shared.effectiveAppearance
    }
}
