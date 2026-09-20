import Foundation
import Testing
@testable import ReadinessCore

/// What the balance accrues against has to be as steady as the balance itself.
///
/// Round 9 took the cliff out of the *window*; it came back through the *reference*. The
/// reference is a median, and it was taken over a fixed run of calendar nights — so for
/// somebody wearing the watch twice a week it rested on eight recorded nights and stepped
/// by whole hours as single nights rolled out of range. Measured on a four-nights-a-week
/// wearer whose habit had dropped to six hours: three consecutive mornings, every night an
/// identical 6.0 h, and the card read 7.0 h behind, then 5.5, then 4.1 — falling 2.9 hours
/// while the arrow said "up after last night" each morning and the ring gained 7 points on
/// behaviour that had not changed.
@Suite("What the balance is measured against")
struct DebtReferenceTests {

    /// `everyNth` calendar nights carry a reading; the rest are nil.
    private func worn(_ hours: [Double], everyNth: Int) -> [Double?] {
        hours.enumerated().map { index, value in index % everyNth == 0 ? value : nil }
    }

    /// A settled record with ordinary night-to-night variation. A fixture of only two
    /// distinct values would make the median step between them by construction, which
    /// overstates the case: real records move it smoothly.
    private func habit(_ hours: Double, _ count: Int, from seed: Int = 0) -> [Double] {
        (0..<count).map { hours + (Double(($0 + seed) % 7) - 3) * 0.12 }
    }

    /// A habit that changed a while back, recorded sparsely, then the same night again and
    /// again. Nothing about the sleeper is moving, so nothing on the card should.
    @Test("the level does not re-level overnight", arguments: [2, 3, 4])
    func referenceIsSteady(everyNth: Int) {
        let settled = habit(9.0, 45) + habit(6.0, 40, from: 3)
        let balances = (0..<4).map { extra -> Double in
            let hours = settled + Array(repeating: 6.0, count: extra)
            return SleepDebt.of(nights: worn(hours, everyNth: everyNth)).hours
        }
        let steps = zip(balances, balances.dropFirst()).map { abs($1 - $0) }
        #expect(steps.max()! < 1.0,
                "every \\(everyNth) nights: moved \\(steps.max()!) on an unchanged night: \\(balances)")
    }

    /// And the arrow has to agree with the number it sits beside.
    @Test("the arrow agrees with the number", arguments: [2, 3, 4])
    func arrowMatchesTheMove(everyNth: Int) {
        let settled = habit(9.0, 45) + habit(6.0, 40, from: 3)
        for extra in 1..<4 {
            let before = SleepDebt.of(nights: worn(settled + Array(repeating: 6.0, count: extra - 1),
                                                   everyNth: everyNth))
            let after = SleepDebt.of(nights: worn(settled + Array(repeating: 6.0, count: extra),
                                                  everyNth: everyNth))
            let moved = after.hours - before.hours
            guard abs(moved) > 0.05, abs(after.change) > 0.05 else { continue }
            #expect((moved < 0) == (after.change < 0),
                    "card moved \\(moved) while the arrow said \\(after.change)")
        }
    }
}
