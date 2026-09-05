import Foundation

/// Pure geometry, no AppKit. Every rectangle uses the Accessibility coordinate space: origin at the
/// top-left corner of the primary display, y growing downwards. `visible` is the usable area of the
/// screen the window sits on, without menu bar and Dock.
enum Layout {
    static let resizeStep: CGFloat = 30
    static let minimumSize = CGSize(width: 200, height: 150)
    static let almostMaximizeRatio: CGFloat = 0.9

    /// Target frame for `action`, or nil for actions that need more than one screen's geometry
    /// (restore, next/previous display).
    static func frame(for action: WindowAction, window: CGRect, visible v: CGRect, customSize: CGSize) -> CGRect? {
        let halfWidth = (v.width / 2).rounded(.down)
        let halfHeight = (v.height / 2).rounded(.down)
        let thirdWidth = (v.width / 3).rounded(.down)

        switch action {
        case .leftHalf:
            return CGRect(x: v.minX, y: v.minY, width: halfWidth, height: v.height)
        case .rightHalf:
            return CGRect(x: v.minX + halfWidth, y: v.minY, width: v.width - halfWidth, height: v.height)
        case .topHalf:
            return CGRect(x: v.minX, y: v.minY, width: v.width, height: halfHeight)
        case .bottomHalf:
            return CGRect(x: v.minX, y: v.minY + halfHeight, width: v.width, height: v.height - halfHeight)
        case .topLeft:
            return CGRect(x: v.minX, y: v.minY, width: halfWidth, height: halfHeight)
        case .topRight:
            return CGRect(x: v.minX + halfWidth, y: v.minY, width: v.width - halfWidth, height: halfHeight)
        case .bottomLeft:
            return CGRect(x: v.minX, y: v.minY + halfHeight, width: halfWidth, height: v.height - halfHeight)
        case .bottomRight:
            return CGRect(x: v.minX + halfWidth, y: v.minY + halfHeight,
                          width: v.width - halfWidth, height: v.height - halfHeight)
        case .firstThird:
            return CGRect(x: v.minX, y: v.minY, width: thirdWidth, height: v.height)
        case .centerThird:
            return CGRect(x: v.minX + thirdWidth, y: v.minY, width: thirdWidth, height: v.height)
        case .lastThird:
            return CGRect(x: v.minX + 2 * thirdWidth, y: v.minY, width: v.width - 2 * thirdWidth, height: v.height)
        case .firstTwoThirds:
            return CGRect(x: v.minX, y: v.minY, width: 2 * thirdWidth, height: v.height)
        case .lastTwoThirds:
            return CGRect(x: v.minX + thirdWidth, y: v.minY, width: v.width - thirdWidth, height: v.height)
        case .maximize:
            return v
        case .almostMaximize:
            let size = CGSize(width: (v.width * almostMaximizeRatio).rounded(),
                              height: (v.height * almostMaximizeRatio).rounded())
            return centered(size, in: v)
        case .center:
            return clamp(centered(window.size, in: v), to: v)
        case .customSize:
            return clamp(centered(customSize, in: v), to: v)
        case .smaller:
            return resized(window, by: -resizeStep, in: v)
        case .larger:
            return resized(window, by: resizeStep, in: v)
        case .restore, .nextDisplay, .previousDisplay:
            return nil
        }
    }

    static func centered(_ size: CGSize, in v: CGRect) -> CGRect {
        CGRect(x: (v.midX - size.width / 2).rounded(), y: (v.midY - size.height / 2).rounded(),
               width: size.width, height: size.height)
    }

    /// Shrinks `rect` until it fits inside `v` and pulls it back in if it overhangs an edge.
    static func clamp(_ rect: CGRect, to v: CGRect) -> CGRect {
        var result = rect
        result.size.width = min(result.width, v.width)
        result.size.height = min(result.height, v.height)
        result.origin.x = min(max(result.minX, v.minX), v.maxX - result.width)
        result.origin.y = min(max(result.minY, v.minY), v.maxY - result.height)
        return result
    }

    /// Grows or shrinks around the window's centre, never below `minimumSize` and never beyond `v`.
    static func resized(_ window: CGRect, by delta: CGFloat, in v: CGRect) -> CGRect {
        let width = min(max(window.width + delta, minimumSize.width), v.width)
        let height = min(max(window.height + delta, minimumSize.height), v.height)
        let result = CGRect(x: (window.midX - width / 2).rounded(), y: (window.midY - height / 2).rounded(),
                            width: width, height: height)
        return clamp(result, to: v)
    }

    /// Moves `window` from `source` to `target`, keeping its relative position and relative size.
    static func translated(_ window: CGRect, from source: CGRect, to target: CGRect) -> CGRect {
        let scaleX = target.width / source.width
        let scaleY = target.height / source.height
        let result = CGRect(x: target.minX + (window.minX - source.minX) * scaleX,
                            y: target.minY + (window.minY - source.minY) * scaleY,
                            width: window.width * scaleX,
                            height: window.height * scaleY)
        return clamp(rounded(result), to: target)
    }

    static func rounded(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX.rounded(), y: rect.minY.rounded(), width: rect.width.rounded(), height: rect.height.rounded())
    }

    /// Index of the screen sharing the most area with `frame`; if the window is entirely off-screen, the
    /// screen whose centre is nearest.
    static func screenIndex(containing frame: CGRect, in screens: [CGRect]) -> Int? {
        guard !screens.isEmpty else { return nil }
        var best: (index: Int, area: CGFloat)?
        for (index, screen) in screens.enumerated() {
            let overlap = screen.intersection(frame)
            let area = overlap.isNull ? 0 : overlap.width * overlap.height
            if area > 0, area > (best?.area ?? 0) { best = (index, area) }
        }
        if let best { return best.index }
        let centre = CGPoint(x: frame.midX, y: frame.midY)
        func distance(_ index: Int) -> CGFloat {
            hypot(screens[index].midX - centre.x, screens[index].midY - centre.y)
        }
        return screens.indices.min { distance($0) < distance($1) }
    }
}
