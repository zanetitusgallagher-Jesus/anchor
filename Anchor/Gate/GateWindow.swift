import AppKit

/// Borderless window that covers one display above everything, including
/// full-screen apps, on every Space.
final class GateWindow: NSWindow {
    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = true
        hasShadow = false
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        hidesOnDeactivate = false
        setFrame(screen.frame, display: true)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    // Swallow Cmd-W / Cmd-M style actions while the gate is up.
    override func performClose(_ sender: Any?) {}
    override func performMiniaturize(_ sender: Any?) {}
}
