import AppKit
import SwiftUI

struct GlassMaterialView: NSViewRepresentable {
    private let darkGlassTint = NSColor(srgbRed: 0.07, green: 0.09, blue: 0.12, alpha: 0.24)

    func makeNSView(context: Context) -> NSView {
        if #available(macOS 26.0, *) {
            let view = NSGlassEffectView()
            view.style = .clear
            view.cornerRadius = 18
            view.tintColor = darkGlassTint
            return view
        }

        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .withinWindow
        view.state = .active
        view.isEmphasized = false
        view.wantsLayer = true
        view.layer?.cornerRadius = 18
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if #available(macOS 26.0, *), let glassView = nsView as? NSGlassEffectView {
            glassView.style = .clear
            glassView.cornerRadius = 18
            glassView.tintColor = darkGlassTint
            return
        }

        guard let visualEffectView = nsView as? NSVisualEffectView else { return }
        visualEffectView.material = .underWindowBackground
        visualEffectView.blendingMode = .withinWindow
        visualEffectView.state = .active
    }
}
