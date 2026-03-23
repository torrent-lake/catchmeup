import AppKit

enum StatusIconStyle: String, CaseIterable {
    case longStrip
    case clockBars12
    case radialNeedle12

    var next: StatusIconStyle {
        switch self {
        case .longStrip:
            return .clockBars12
        case .clockBars12:
            return .radialNeedle12
        case .radialNeedle12:
            return .longStrip
        }
    }

    var menuLabel: String {
        switch self {
        case .longStrip:
            return "长条"
        case .clockBars12:
            return "时钟条"
        case .radialNeedle12:
            return "径向细条"
        }
    }

    var statusItemLength: CGFloat {
        switch self {
        case .longStrip:
            return 116
        case .clockBars12, .radialNeedle12:
            return NSStatusItem.squareLength
        }
    }
}

