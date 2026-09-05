import CoreGraphics
import Testing
@testable import Frameworker

@Suite struct LayoutTests {
    /// A 1440×900 display with a 25 pt menu bar, in top-left-origin coordinates.
    let visible = CGRect(x: 0, y: 25, width: 1440, height: 875)
    let window = CGRect(x: 100, y: 100, width: 800, height: 600)
    let customSize = CGSize(width: 1280, height: 800)

    func frame(_ action: WindowAction, window: CGRect? = nil, visible: CGRect? = nil) -> CGRect {
        Layout.frame(for: action, window: window ?? self.window, visible: visible ?? self.visible, customSize: customSize)!
    }

    @Test func halvesTileTheScreenExactly() {
        let left = frame(.leftHalf), right = frame(.rightHalf)
        #expect(left.minX == visible.minX)
        #expect(left.maxX == right.minX)
        #expect(right.maxX == visible.maxX)
        #expect(left.height == visible.height && right.height == visible.height)

        let top = frame(.topHalf), bottom = frame(.bottomHalf)
        #expect(top.minY == visible.minY)
        #expect(top.maxY == bottom.minY)
        #expect(bottom.maxY == visible.maxY)
    }

    @Test func quartersCoverTheScreenWithoutOverlap() {
        let quarters = [frame(.topLeft), frame(.topRight), frame(.bottomLeft), frame(.bottomRight)]
        let union = quarters.reduce(CGRect.null) { $0.union($1) }
        #expect(union == visible)
        let totalArea = quarters.reduce(0) { $0 + $1.width * $1.height }
        #expect(totalArea == visible.width * visible.height)
    }

    @Test func thirdsAddUpAndTwoThirdsComplementThem() {
        let first = frame(.firstThird), centre = frame(.centerThird), last = frame(.lastThird)
        #expect(first.maxX == centre.minX)
        #expect(centre.maxX == last.minX)
        #expect(first.width + centre.width + last.width == visible.width)
        #expect(frame(.firstTwoThirds).maxX == last.minX)
        #expect(frame(.lastTwoThirds).minX == first.maxX)
    }

    @Test func centerKeepsTheWindowSize() {
        let centred = frame(.center)
        #expect(centred.size == window.size)
        #expect(abs(centred.midX - visible.midX) <= 1)
        #expect(abs(centred.midY - visible.midY) <= 1)
    }

    @Test func customSizeIsClampedToTheScreen() {
        let small = CGRect(x: 0, y: 0, width: 1000, height: 600)
        let result = frame(.customSize, visible: small)
        #expect(result.size == small.size)
        #expect(small.contains(result))
        #expect(frame(.customSize).size == customSize)
    }

    @Test func smallerRespectsTheMinimumAndLargerStaysOnScreen() {
        let tiny = CGRect(x: 300, y: 300, width: 210, height: 160)
        #expect(frame(.smaller, window: tiny).size == Layout.minimumSize)
        let huge = frame(.larger, window: visible)
        #expect(huge == visible)
        #expect(frame(.smaller).width == window.width - Layout.resizeStep)
    }

    @Test func maximizeAndAlmostMaximize() {
        #expect(frame(.maximize) == visible)
        let almost = frame(.almostMaximize)
        #expect(visible.contains(almost))
        #expect(almost.width < visible.width && almost.height < visible.height)
    }

    @Test func translatedKeepsRelativePlacement() {
        let source = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        let target = CGRect(x: 1000, y: 0, width: 2000, height: 2000)
        let moved = Layout.translated(CGRect(x: 100, y: 100, width: 500, height: 500), from: source, to: target)
        #expect(moved == CGRect(x: 1200, y: 200, width: 1000, height: 1000))
    }

    @Test func screenIndexPrefersLargestOverlapThenNearest() {
        let left = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        let right = CGRect(x: 1000, y: 0, width: 1000, height: 1000)
        #expect(Layout.screenIndex(containing: CGRect(x: 800, y: 0, width: 600, height: 500), in: [left, right]) == 1)
        #expect(Layout.screenIndex(containing: CGRect(x: 2500, y: 0, width: 100, height: 100), in: [left, right]) == 1)
        #expect(Layout.screenIndex(containing: .zero, in: []) == nil)
    }

    @Test func repeatedFirstThirdWalksRightAndWraps() {
        func next(from current: WindowAction, pressing action: WindowAction) -> WindowAction {
            Layout.nextStep(for: action, window: frame(current), visible: visible, customSize: customSize)
        }
        #expect(Layout.nextStep(for: .firstThird, window: window, visible: visible, customSize: customSize) == .firstThird)
        #expect(next(from: .firstThird, pressing: .firstThird) == .centerThird)
        #expect(next(from: .centerThird, pressing: .firstThird) == .lastThird)
        #expect(next(from: .lastThird, pressing: .firstThird) == .firstThird)
        #expect(next(from: .lastThird, pressing: .lastThird) == .centerThird)
        #expect(next(from: .centerThird, pressing: .lastThird) == .firstThird)
        #expect(next(from: .firstTwoThirds, pressing: .firstTwoThirds) == .lastTwoThirds)
        #expect(next(from: .leftHalf, pressing: .leftHalf) == .firstTwoThirds)
        #expect(next(from: .firstTwoThirds, pressing: .leftHalf) == .firstThird)
        #expect(next(from: .firstThird, pressing: .leftHalf) == .leftHalf)
        #expect(next(from: .topLeft, pressing: .topLeft) == .topLeft)
        #expect(next(from: .maximize, pressing: .maximize) == .maximize)
    }

    @Test func matchingToleratesTinyDifferences() {
        let a = CGRect(x: 0, y: 25, width: 480, height: 875)
        #expect(Layout.matches(a, a.offsetBy(dx: 1, dy: -1)))
        #expect(!Layout.matches(a, a.offsetBy(dx: 3, dy: 0)))
    }

    @Test func actionsThatNeedOtherScreensHaveNoStaticFrame() {
        for action in [WindowAction.restore, .nextDisplay, .previousDisplay, .openSettings] {
            #expect(Layout.frame(for: action, window: window, visible: visible, customSize: customSize) == nil)
        }
    }
}
