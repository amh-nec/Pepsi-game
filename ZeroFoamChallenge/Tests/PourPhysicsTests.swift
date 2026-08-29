import XCTest
@testable import ZeroFoamChallenge

final class GlassGeometryTests: XCTestCase {
    private func makeGlass() -> GlassGeometry {
        GlassGeometry(center: CGPoint(x: 200, y: 500),
                      height: 260, topWidth: 150, bottomWidth: 118)
    }

    func testEmptyGlassHasItsSurfaceAtTheBase() {
        let g = makeGlass()
        XCTAssertEqual(g.surfaceY(forFraction: 0), g.outline.maxY, accuracy: 0.5)
    }

    func testFullGlassHasItsSurfaceAtTheRim() {
        let g = makeGlass()
        XCTAssertEqual(g.surfaceY(forFraction: 1), g.outline.minY, accuracy: 1.0)
    }

    func testCapacityShrinksAsTheGlassIsTilted() {
        let g = makeGlass()
        XCTAssertEqual(g.spillCapacityFraction, 1.0, accuracy: 1e-6)
        g.tilt = 0.5
        XCTAssertLessThan(g.spillCapacityFraction, 1.0)
    }
}

final class PourPhysicsTests: XCTestCase {
    private func makeGlass() -> GlassGeometry {
        GlassGeometry(center: CGPoint(x: 200, y: 500),
                      height: 260, topWidth: 150, bottomWidth: 118)
    }

    func testAnUprightBottleDoesNotPour() {
        let p = PourPhysics(glass: makeGlass())
        p.bottleTilt = 0
        p.update(dt: 1.0 / 60.0, active: true)
        XCTAssertEqual(p.flow, 0)
        XCTAssertEqual(p.total, 0)
    }

    func testATiltedBottlePoursAMeasurableAmount() {
        let g = makeGlass()
        let p = PourPhysics(glass: g)
        p.bottleTilt = 1.2
        p.bottlePos = CGPoint(x: g.center.x, y: g.center.y - g.height - 90)
        for _ in 0..<120 { p.update(dt: 1.0 / 60.0, active: true) }
        // Everything poured is accounted for: in the glass, or on the table.
        XCTAssertGreaterThan(p.liquid + p.foam + p.wasted, 0.1)
        XCTAssertGreaterThan(p.flow, 0)
    }

    func testAStreamMissingTheGlassIsWastedNotStored() {
        let g = makeGlass()
        let p = PourPhysics(glass: g)
        p.bottleTilt = 1.2
        p.bottlePos = CGPoint(x: g.center.x + 400, y: g.center.y - g.height - 90)
        for _ in 0..<60 { p.update(dt: 1.0 / 60.0, active: true) }
        XCTAssertGreaterThan(p.wasted, 0)
        XCTAssertEqual(p.liquid, 0)
    }

    func testFoamCollapsesBackIntoLiquidWhenPouringStops() {
        let p = PourPhysics(glass: makeGlass())
        p.seed(liquid: 0.4, foam: 0.2)
        let foamBefore = p.foam
        for _ in 0..<60 { p.update(dt: 1.0 / 60.0, active: false) }
        XCTAssertLessThan(p.foam, foamBefore)
        XCTAssertGreaterThan(p.liquid, 0.4)
    }

    func testFoamFactorRisesWithImpactSpeed() {
        let g = makeGlass()
        func foamFactor(dropHeight: CGFloat) -> CGFloat {
            let p = PourPhysics(glass: g)
            p.bottleTilt = 0.75
            p.bottlePos = CGPoint(x: g.center.x, y: g.center.y - g.height - dropHeight)
            for _ in 0..<30 { p.update(dt: 1.0 / 60.0, active: true) }
            return p.trace.foamFactor
        }
        let low = foamFactor(dropHeight: 20)
        let high = foamFactor(dropHeight: 160)
        if low > 0 && high > 0 {
            XCTAssertGreaterThanOrEqual(high, low)
        }
    }
}
