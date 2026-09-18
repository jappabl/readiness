import Testing
@testable import ReadinessCore

@Suite("Percentile against your own history")
struct PercentileTests {

    @Test("a day exactly on baseline is the middle of your own distribution")
    func baselineIsFifty() {
        #expect(Percentile.percent(fromZ: 0) == 50)
    }

    @Test("one standard deviation up is about the 84th percentile")
    func oneSDUp() {
        #expect(abs(Percentile.fromZ(1) - 0.8413) < 0.001)
    }

    @Test("one standard deviation down is about the 16th percentile")
    func oneSDDown() {
        #expect(abs(Percentile.fromZ(-1) - 0.1587) < 0.001)
    }

    @Test("the scale is symmetric about baseline")
    func symmetric() {
        for z in [0.5, 1.0, 1.7, 2.4] {
            #expect(abs((Percentile.fromZ(z) + Percentile.fromZ(-z)) - 1.0) < 1e-9)
        }
    }

    @Test("it stays inside 0 and 100 however extreme the day")
    func bounded() {
        for z in [-50.0, -3.0, 0.0, 3.0, 50.0] {
            let percent = Percentile.percent(fromZ: z)
            #expect(percent >= 0 && percent <= 100, "z \(z) gave \(percent)")
        }
    }

    @Test("a non-finite z does not produce a non-finite ring")
    func nonFiniteIsSafe() {
        #expect(Percentile.fromZ(.nan).isFinite)
        #expect(Percentile.percent(fromZ: .infinity) == 100)
        #expect(Percentile.percent(fromZ: -.infinity) == 0)
    }

    @Test("a bad morning reads low rather than merely below average")
    func badDayReadsLow() {
        #expect(Percentile.percent(fromZ: -2.69) <= 5)
    }
}
