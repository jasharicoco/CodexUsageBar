import AppKit
import SwiftUI

/// Keep theme choices inside the status menu instead of starting another menu session.
struct ThemePicker: NSViewRepresentable {
    var monster: Bool
    var label: String
    var onSelection: (Bool) -> Void

    func makeNSView(context: Context) -> ThemeSelectionView { ThemeSelectionView() }

    func updateNSView(_ view: ThemeSelectionView, context: Context) {
        view.onSelection = onSelection
        view.choices.selectedSegment = monster ? 1 : 0
        view.palette.toolTip = label
        view.palette.setAccessibilityLabel(label)
        view.choices.setAccessibilityLabel(label)
    }
}

final class ThemeSelectionView: NSView {
    let palette = NSButton()
    let choices = StatusMenuSegments(labels: ["Classic", "Monster"], trackingMode: .selectOne, target: nil, action: nil)
    var onSelection: (Bool) -> Void = { _ in }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 162, height: 26))
        palette.frame = NSRect(x: 136, y: 0, width: 26, height: 26)
        palette.image = NSImage(systemSymbolName: "paintpalette", accessibilityDescription: nil)
        palette.imagePosition = .imageOnly
        palette.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        palette.isBordered = false
        palette.target = self
        palette.action = #selector(toggleChoices)
        palette.setAccessibilityIdentifier("theme-picker")
        addSubview(palette)

        choices.frame = NSRect(x: 0, y: 2, width: 132, height: 22)
        choices.controlSize = .small
        choices.segmentStyle = .rounded
        choices.target = self
        choices.action = #selector(selectTheme)
        choices.setAccessibilityIdentifier("theme-choices")
        choices.isHidden = true
        addSubview(choices)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    @objc private func toggleChoices() {
        choices.isHidden.toggle()
        palette.setAccessibilityValue(NSNumber(value: !choices.isHidden))
    }

    @objc private func selectTheme() {
        choices.isHidden = true
        palette.setAccessibilityValue(NSNumber(value: false))
        onSelection(choices.selectedSegment == 1)
    }
}

final class StatusMenuSegments: NSSegmentedControl {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
