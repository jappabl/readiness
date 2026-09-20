import Foundation
import Testing
@testable import ReadinessCore

/// The app is light, because a coach that looks like a terminal reads as a tool for
/// nerds rather than a person. It goes dark at night, because a recovery app is opened
/// in a dark bedroom at six in the morning and a white screen then is cruelty.
@Suite("When the app goes dark")
struct NightfallTests {

    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = 2026; components.month = 9; components.day = 19
        components.hour = hour; components.minute = minute
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    @Test("daytime is light")
    func daytimeIsLight() {
        for hour in [7, 9, 12, 15, 18, 20] {
            #expect(Nightfall.isNight(at: at(hour)) == false, "\(hour):00 should be light")
        }
    }

    @Test("night is dark, across midnight")
    func nightIsDark() {
        for hour in [21, 22, 23, 0, 1, 4, 5] {
            #expect(Nightfall.isNight(at: at(hour)) == true, "\(hour):00 should be dark")
        }
    }

    @Test("the boundaries belong to the side that starts there")
    func boundaries() {
        // Dark begins exactly at the start hour and ends exactly at the end hour.
        #expect(Nightfall.isNight(at: at(Nightfall.darkFromHour, 0)) == true)
        #expect(Nightfall.isNight(at: at(Nightfall.darkFromHour - 1, 59)) == false)
        #expect(Nightfall.isNight(at: at(Nightfall.lightFromHour, 0)) == false)
        #expect(Nightfall.isNight(at: at(Nightfall.lightFromHour - 1, 59)) == true)
    }

    @Test("it knows when it next needs to change")
    func nextChange() throws {
        let evening = at(19, 30)
        let next = try #require(Nightfall.nextChange(after: evening))
        #expect(next > evening)
        // Crossing that moment flips the answer, which is the only property that
        // matters: the app must not sit in the wrong scheme because nobody asked again.
        #expect(Nightfall.isNight(at: next) != Nightfall.isNight(at: evening))
    }

    @Test("the next change from inside the night is the morning")
    func nextChangeOvernight() throws {
        let lateNight = at(23, 10)
        let next = try #require(Nightfall.nextChange(after: lateNight))
        #expect(Nightfall.isNight(at: lateNight) == true)
        #expect(Nightfall.isNight(at: next) == false)
    }
}

@Suite("Choosing an appearance")
struct AppearancePreferenceTests {

    private func at(_ hour: Int) -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = 9; c.day = 19; c.hour = hour
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    @Test("an explicit choice ignores the clock entirely")
    func explicitWins() {
        #expect(AppearancePreference.light.wantsDark(at: at(23)) == false)
        #expect(AppearancePreference.dark.wantsDark(at: at(11)) == true)
    }

    @Test("automatic follows the clock")
    func automaticFollowsTheClock() {
        #expect(AppearancePreference.automatic.wantsDark(at: at(11)) == false)
        #expect(AppearancePreference.automatic.wantsDark(at: at(23)) == true)
    }

    @Test("automatic is the one that needs explaining, so only it carries a detail")
    func onlyAutomaticExplainsItself() {
        #expect(AppearancePreference.automatic.detail != nil)
        #expect(AppearancePreference.light.detail == nil)
        #expect(AppearancePreference.dark.detail == nil)
    }
}
