import Foundation
import Testing
@testable import ReadinessCore

@Suite("Read-first Health details")
struct HealthProfileTests {
    private let today = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 9, day: 18))!

    @Test func ageUsesBirthdayRatherThanSubtractingYears() {
        let birthday = HealthProfile(dateOfBirth: DateComponents(year: 1995, month: 9, day: 19))
        #expect(birthday.ageYears(on: today) == 30)
        let onBirthday = HealthProfile(dateOfBirth: DateComponents(year: 1995, month: 9, day: 18))
        #expect(onBirthday.ageYears(on: today) == 31)
    }

    @Test func invalidAndIncompleteCharacteristicsRemainMissing() {
        for components in [DateComponents(year: 2030, month: 1, day: 1),
                           DateComponents(year: 1995), DateComponents(year: 1995, month: 2, day: 31)] {
            #expect(HealthProfile(dateOfBirth: components).ageYears(on: today) == nil)
        }
        #expect(HealthProfile(heightCM: .nan).missingFields(on: today).contains(.height))
        #expect(HealthProfile(heightCM: 0).missingFields(on: today).contains(.height))
        #expect(!HealthProfile(biologicalSex: .other).missingFields(on: today).contains(.biologicalSex))
    }

    @Test func healthWinsAndManualValuesFillOnlyGaps() {
        let health = HealthProfile(heightCM: 181, biologicalSex: .other)
        let manual = HealthProfile(heightCM: 170, dateOfBirth: DateComponents(year: 1995, month: 9, day: 19), biologicalSex: .male)
        let result = health.fillingMissing(from: manual, today: today)
        #expect(result.heightCM == 181 && result.biologicalSex == .other)
        #expect(result.ageYears(on: today) == 30)
    }

    @Test func coachPayloadContainsAgeButNeverBirthDateOrManualAnswers() throws {
        let profile = HealthProfile(heightCM: 175, dateOfBirth: DateComponents(year: 1995, month: 9, day: 19), biologicalSex: .female)
        var answers = OnboardingAnswers(); answers.experience = .experienced; answers.equipment = .bodyweight
        var context = CoachContextBuilder.withoutHealth(today: today, goal: "buildMuscle")
        context.profile = CoachProfileSummary(health: profile, answers: answers, today: today)
        #expect(context.profile?.ageYears == 30)
        #expect(context.brief.contains("175"))
        #expect(context.brief.contains("experienced"))
        #expect(!context.json.contains("dateOfBirth") && !context.json.contains("1995"))
        #expect(!context.json.contains("healthDetails"))
        #expect(try JSONDecoder().decode(CoachContext.self, from: Data(context.json.utf8)) == context)
    }
}
