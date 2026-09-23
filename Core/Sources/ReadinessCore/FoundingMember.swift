import Foundation

/// The member number every install is given the first time it registers, and what the
/// first hundred of them get.
///
/// Deliberately a number for everybody rather than a flag for a few. A discount is a
/// price somebody stops noticing the day after they pay it; being member fourteen is
/// something they screenshot, and it keeps meaning something long after the price stops
/// mattering. The hundred is the offer, the number is the reason anybody cares about it.
public enum FoundingMember {

    /// How many are founders. A promise that has to be countable, which is the whole
    /// reason the number is issued by the server and not guessed at by the app.
    public static let limit = 100

    public static func isFounder(_ member: Int) -> Bool {
        member >= 1 && member <= limit
    }

    /// The yearly plan this member is sold: the founding one for the first hundred, the
    /// standard one for everybody else, never both. No number yet is not a founder.
    ///
    /// The one place that decides it, because the paywall used to decide it twice. The
    /// list of plans asked the member number; the default selection only asked whether
    /// the founding product existed, which it always does. So from member 101 onwards the
    /// founder price was selected and one tap bought it.
    public static func yearlyProductID(member: Int?, standard: String, founding: String) -> String {
        member.map(isFounder) == true ? founding : standard
    }

    /// What to call somebody, given their number.
    ///
    /// Never "Member #0" and never a negative: a number the server has not issued yet is
    /// no number at all, and inventing one would put a stranger in the founding hundred.
    public static func badge(_ member: Int?) -> String? {
        guard let member, member >= 1 else { return nil }
        return "Member #\(member)"
    }

    /// How many founding places are left, for the one place it is honest to say so.
    ///
    /// Nil once they are gone, because "0 places left" is an advert rather than a fact,
    /// and nil for somebody who already holds one: telling a founder how many are left
    /// is telling them about a queue they are not in.
    public static func placesLeft(issued: Int) -> Int? {
        let left = limit - max(0, issued)
        return left > 0 ? left : nil
    }
}
