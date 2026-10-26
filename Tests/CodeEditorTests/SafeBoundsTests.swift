import AppKit
import Testing
@testable import CodeEditorUI

@Suite("NSBezierPath SafeBounds Workaround")
struct SafeBoundsTests {
    @Test("empty NSBezierPath returns zero bounds without throwing an exception")
    func emptyBezierPathBoundsDoesNotCrash() {
        NSBezierPath.installSafeBoundsWorkaround()

        let emptyPath = NSBezierPath()
        #expect(emptyPath.isEmpty)
        #expect(emptyPath.bounds == .zero)
        #expect(emptyPath.controlPointBounds == .zero)
    }

    @Test("non-empty NSBezierPath correctly reports geometric bounds")
    func nonEmptyBezierPathBounds() {
        NSBezierPath.installSafeBoundsWorkaround()

        let rect = NSRect(x: 15, y: 25, width: 100, height: 50)
        let rectPath = NSBezierPath(rect: rect)
        #expect(!rectPath.isEmpty)
        #expect(rectPath.bounds == rect)
        #expect(rectPath.controlPointBounds == rect)

        let linePath = NSBezierPath()
        linePath.move(to: NSPoint(x: 10, y: 20))
        linePath.line(to: NSPoint(x: 40, y: 20))
        #expect(!linePath.isEmpty)
        #expect(linePath.bounds == NSRect(x: 10, y: 20, width: 30, height: 0))
    }

    @Test("installSafeBoundsWorkaround is idempotent")
    func installationIdempotency() {
        NSBezierPath.installSafeBoundsWorkaround()
        NSBezierPath.installSafeBoundsWorkaround()

        let emptyPath = NSBezierPath()
        #expect(emptyPath.bounds == .zero)
    }
}
