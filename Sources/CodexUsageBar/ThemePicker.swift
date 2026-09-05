import AppKit
import SwiftUI

/// A native button accepts clicks in a status menu's non-key window.
struct ThemePicker: NSViewRepresentable {
    var label: String
    var onOpen: (NSView) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onOpen: onOpen) }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: "paintpalette", accessibilityDescription: label)!,
                              target: context.coordinator, action: #selector(Coordinator.openThemes(_:)))
        button.isBordered = false
        button.setAccessibilityIdentifier("theme-picker")
        button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.onOpen = onOpen
        button.toolTip = label
        button.setAccessibilityLabel(label)
    }

    final class Coordinator: NSObject {
        var onOpen: (NSView) -> Void
        init(onOpen: @escaping (NSView) -> Void) { self.onOpen = onOpen }
        @objc func openThemes(_ sender: NSButton) { onOpen(sender) }
    }
}
