import AppKit
import CoachCore

/// A small floating window for the coach's message. It never takes the
/// keyboard focus away from the app the person is working in.
final class HintPanel: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var onClose: (() -> Void)?
    private let width: CGFloat = 360

    func show(_ message: CoachMessage, near fieldFrame: CGRect?, onClose: (() -> Void)? = nil) {
        close()
        self.onClose = onClose

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.widthAnchor.constraint(equalToConstant: width).isActive = true

        for section in message.sections {
            if let heading = section.heading {
                let label = NSTextField(labelWithString: heading)
                label.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
                stack.addArrangedSubview(label)
            }
            let body = NSTextField(wrappingLabelWithString: section.text)
            body.preferredMaxLayoutWidth = width - 32
            if section.heading == nil && message.sections.count > 1 {
                body.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
                body.textColor = .secondaryLabelColor
            }
            stack.addArrangedSubview(body)
        }
        let button = NSButton(title: message.buttonTitle, target: self, action: #selector(buttonPressed))
        button.bezelStyle = .rounded
        stack.addArrangedSubview(button)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 100),
            styleMask: [.titled, .closable, .nonactivatingPanel, .utilityWindow],
            backing: .buffered, defer: false
        )
        panel.title = message.title
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        panel.contentView = container
        panel.setContentSize(container.fittingSize)
        panel.setFrameOrigin(origin(for: panel.frame.size, near: fieldFrame))
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func close() {
        guard let panel else { return }
        panel.delegate = nil
        panel.close()
        self.panel = nil
        finish()
    }

    @objc private func buttonPressed() { close() }

    func windowWillClose(_ notification: Notification) {
        panel = nil
        finish()
    }

    private func finish() {
        let callback = onClose
        onClose = nil
        callback?()
    }

    /// Just below the field when its position is known, otherwise the top right of the screen.
    private func origin(for size: CGSize, near fieldFrame: CGRect?) -> CGPoint {
        guard let primary = NSScreen.screens.first else { return .zero }
        if let field = fieldFrame {
            // Accessibility uses a top-left origin; AppKit uses bottom-left.
            let flippedBottom = primary.frame.height - field.maxY
            var origin = CGPoint(x: field.minX, y: flippedBottom - size.height - 8)
            let screen = NSScreen.screens.first { $0.frame.contains(CGPoint(x: field.midX, y: flippedBottom)) } ?? primary
            let visible = screen.visibleFrame
            origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
            if origin.y < visible.minY + 8 {
                // No room below the field: show it above instead.
                origin.y = min(flippedBottom + field.height + 8, visible.maxY - size.height - 8)
            }
            return origin
        }
        let visible = (NSScreen.main ?? primary).visibleFrame
        return CGPoint(x: visible.maxX - size.width - 16, y: visible.maxY - size.height - 16)
    }
}
