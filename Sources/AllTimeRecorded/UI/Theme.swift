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

    // Context-density source colors
    static let emailViolet = Color(hex: "#9B7AFF")
    static let emailVioletNS = NSColor.from(hex: "#9B7AFF")
    static let chatGreen = Color(hex: "#89FFBE")
    static let chatGreenNS = NSColor.from(hex: "#89FFBE")
    static let calendarAmber = Color(hex: "#FFD77A")
    static let calendarAmberNS = NSColor.from(hex: "#FFD77A")
    static let filePink = Color(hex: "#FF9EC8")
    static let filePinkNS = NSColor.from(hex: "#FF9EC8")
    static let reminderBlue = Color(hex: "#8ED0FF")
    static let reminderBlueNS = NSColor.from(hex: "#8ED0FF")

    // Recall terminal
    static let terminalPrompt = neonCyan
    static let terminalText = Color.white.opacity(0.7)
    static let terminalDim = Color.white.opacity(0.4)
    static let terminalCardBg = Color.black.opacity(0.14)
    static let terminalCardBorder = neonCyan.opacity(0.12)
    static let highlightPulse = neonCyan.opacity(0.35)
}

