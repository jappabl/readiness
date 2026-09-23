import Testing
@testable import ReadinessCore

/// The founding hundred.
///
/// "First 100" is a countable promise, which is the whole reason the number comes from
/// the server rather than being guessed at by the app: founder 101 has to be able to see
/// why they are not one, and founder 99 has to be able to prove they are.
@Suite("The founding hundred")
struct FoundingMemberTests {

    @Test func theFirstHundredAreFoundersAndTheHundredAndFirstIsNot() {
        #expect(FoundingMember.isFounder(1))
        #expect(FoundingMember.isFounder(100))
        #expect(!FoundingMember.isFounder(101))
    }

    /// A number the server has not issued is no number at all. Reading a missing one as
    /// zero, or as a default, would put a stranger in the founding hundred.
    @Test func anUnissuedNumberIsNobody() {
        #expect(!FoundingMember.isFounder(0))
        #expect(!FoundingMember.isFounder(-1))
        #expect(FoundingMember.badge(nil) == nil)
        #expect(FoundingMember.badge(0) == nil)
    }

    @Test func abadgeIsTheirNumber() {
        #expect(FoundingMember.badge(1) == "Member #1")
        #expect(FoundingMember.badge(4382) == "Member #4382")
    }

    /// "0 places left" is an advert. A fact stops being one when it runs out.
    @Test func placesLeftStopsBeingSaidOnceThereAreNone() {
        #expect(FoundingMember.placesLeft(issued: 0) == 100)
        #expect(FoundingMember.placesLeft(issued: 99) == 1)
        #expect(FoundingMember.placesLeft(issued: 100) == nil)
        #expect(FoundingMember.placesLeft(issued: 5000) == nil)
    }

    // The yearly plan somebody is sold. The paywall used to take the founding product
    // whenever it merely existed, which it always does, so member 101 onwards had the
    // founder price selected and one tap bought it.
    @Test("only the first hundred are sold the founding yearly plan")
    func yearlyPlanFollowsTheNumber() {
        let standard = "com.coachjett.ios.pro.yearly"
        let founding = "com.coachjett.ios.pro.yearly.founding"
        for member in [1, 7, 100] {
            #expect(FoundingMember.yearlyProductID(member: member, standard: standard, founding: founding) == founding)
        }
        for member in [101, 150, 100_000, 0, -3] {
            #expect(FoundingMember.yearlyProductID(member: member, standard: standard, founding: founding) == standard)
        }
        // No number yet is not a founder: the server issues numbers, and the app does not
        // get to assume one it has not been given.
        #expect(FoundingMember.yearlyProductID(member: nil, standard: standard, founding: founding) == standard)
    }
}
