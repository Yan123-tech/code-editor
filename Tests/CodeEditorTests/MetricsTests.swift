import CodeEditorCore
import Testing

@Suite("Metrics")
struct MetricsTests {
    @Test("Every spacing step sits on the 4-point grid")
    func spacingIsOnGrid() {
        let steps = [
            Metrics.Space.compact,
            Metrics.Space.regular,
            Metrics.Space.relaxed,
            Metrics.Space.loose,
            Metrics.Space.spacious,
        ]
        for step in steps {
            #expect(step.truncatingRemainder(dividingBy: 4) == 0, "spacing \(step) is off the 4pt grid")
        }
    }

    @Test("Spacing steps are strictly increasing")
    func spacingAscends() {
        #expect(Metrics.Space.compact < Metrics.Space.regular)
        #expect(Metrics.Space.regular < Metrics.Space.relaxed)
        #expect(Metrics.Space.relaxed < Metrics.Space.loose)
        #expect(Metrics.Space.loose < Metrics.Space.spacious)
    }

    @Test("Radii grow with the surface they round")
    func radiiAscendBySurface() {
        #expect(Metrics.Radius.row < Metrics.Radius.control)
        #expect(Metrics.Radius.control < Metrics.Radius.panel)
    }

    @Test("Chrome heights clear the smallest hit target")
    func chromeHeightsFitContent() {
        #expect(Metrics.Height.tabStrip >= Metrics.minimumHitTarget)
        #expect(Metrics.Height.statusBar >= Metrics.minimumHitTarget - 2)
        #expect(Metrics.Height.dividerIndicator < Metrics.Height.divider)
    }

    @Test("Tree indentation sits on the grid")
    func treeIndentIsOnGrid() {
        #expect(Metrics.treeIndentPerLevel.truncatingRemainder(dividingBy: 4) == 0)
    }
}
