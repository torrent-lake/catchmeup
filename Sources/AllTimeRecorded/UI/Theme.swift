import AppKit
import SwiftUI

enum Theme {
    static let neonCyan = Color(red: 0.28, green: 0.9, blue: 0.95)
    static let neonCyanNS = NSColor(srgbRed: 0.28, green: 0.9, blue: 0.95, alpha: 1)

    static let gapAmber = Color(red: 1.0, green: 0.56, blue: 0.2)
    static let gapAmberNS = NSColor(srgbRed: 1.0, green: 0.56, blue: 0.2, alpha: 1)

    static let lowDiskRed = Color(red: 1.0, green: 0.27, blue: 0.25)
    static let lowDiskRedNS = NSColor(srgbRed: 1.0, green: 0.27, blue: 0.25, alpha: 1)

    static let idleGray = Color.white.opacity(0.12)
    static let idleGrayNS = NSColor.white.withAlphaComponent(0.12)

    // Recall terminal
    static let terminalPrompt = neonCyan
    static let terminalText = Color.white.opacity(0.7)
    static let terminalDim = Color.white.opacity(0.4)
    static let terminalCardBg = Color.black.opacity(0.14)
    static let terminalCardBorder = neonCyan.opacity(0.12)
    static let highlightPulse = neonCyan.opacity(0.35)
}

