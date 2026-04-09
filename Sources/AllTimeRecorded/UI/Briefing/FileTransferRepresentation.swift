import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// A `Transferable` wrapper for multiple file URLs, enabling drag-and-drop
/// of aggregated file results from CatchMeUp's Agent Chat to other apps.
///
/// When dragged, this presents the file URLs on the pasteboard so receiving
/// apps (Finder, Gemini web UI, ChatGPT, etc.) can accept them as file drops.
struct FileTransferRepresentation: Transferable {
    let urls: [URL]

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .fileURL) { item in
            // For single file, return directly
            guard let first = item.urls.first else {
                throw CocoaError(.fileNoSuchFile)
            }
            return SentTransferredFile(first)
        }
    }
}

/// NSView-based drag source for multi-file drag-and-drop.
/// SwiftUI's `.draggable` only handles single Transferable items well,
/// so for multi-file we use an AppKit overlay.
struct MultiFileDragView: NSViewRepresentable {
    let fileURLs: [URL]

    func makeNSView(context: Context) -> DragSourceView {
        let view = DragSourceView()
        view.fileURLs = fileURLs
        return view
    }

    func updateNSView(_ nsView: DragSourceView, context: Context) {
        nsView.fileURLs = fileURLs
    }

    final class DragSourceView: NSView {
        var fileURLs: [URL] = []

        override func mouseDown(with event: NSEvent) {
            guard !fileURLs.isEmpty else { return }

            let items = fileURLs.map { url -> NSDraggingItem in
                let item = NSDraggingItem(pasteboardWriter: url as NSURL)
                let iconSize = NSSize(width: 32, height: 32)
                let icon = NSWorkspace.shared.icon(forFile: url.path)
                icon.size = iconSize
                item.setDraggingFrame(
                    NSRect(origin: .zero, size: iconSize),
                    contents: icon
                )
                return item
            }

            beginDraggingSession(with: items, event: event, source: self)
        }
    }
}

extension MultiFileDragView.DragSourceView: NSDraggingSource {
    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }
}
