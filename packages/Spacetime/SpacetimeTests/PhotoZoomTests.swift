import CoreGraphics
import Testing
@testable import Spacetime

@MainActor
struct PhotoZoomTests {
    private let screen = CGSize(width: 400, height: 800)
    private let photo = CGSize(width: 400, height: 300)

    @Test func keepsThePointUnderTheFingersInPlace() {
        // The finger is 100 points right of center; the photo point there is at 100 before and after.
        let zoom = PhotoZoom().magnified(by: 2, around: CGPoint(x: 100, y: 0))
        #expect(zoom.scale == 2)
        #expect(zoom.scale * 100 + zoom.offset.width == 100)
        let again = zoom.magnified(by: 1.5, around: CGPoint(x: 100, y: 0))
        // The photo point under the finger: (100 - offset) / scale, unchanged.
        #expect(abs((100 - again.offset.width) / again.scale - 100) < 1e-9)
    }

    @Test func settlesBackWithinTheLimits() {
        #expect(PhotoZoom(scale: 0.7, offset: CGSize(width: 30, height: 0)).settled(content: photo, viewport: screen)
            == PhotoZoom())
        let tooFar = PhotoZoom(scale: 6, offset: .zero).settled(content: photo, viewport: screen)
        #expect(tooFar.scale == PhotoZoom.maxScale)
    }

    @Test func pansNoFurtherThanThePhotosEdges() {
        // At 2x the 400×300 photo is 800×600: 200 points to pan each way across, and none down, since
        // it's still shorter than the screen.
        let zoom = PhotoZoom(scale: 2, offset: CGSize(width: 500, height: 120)).settled(content: photo, viewport: screen)
        #expect(zoom.offset == CGSize(width: 200, height: 0))
        let left = PhotoZoom(scale: 2, offset: CGSize(width: -350, height: -50)).settled(content: photo, viewport: screen)
        #expect(left.offset == CGSize(width: -200, height: 0))
    }
}
