import Foundation
import PostHog

/// Which steps people reach, and nothing about who they are or what their body did.
///
/// A short list of named events, chosen by hand, so the first installs can say where the
/// app loses people: before Health, at the paywall, or after the first week. Everything
/// else the SDK can do is switched off. No screen tracking, no tap capture, no replay, no
/// surveys, no person profiles, and never a health value: an event says that something
/// happened, not what it measured.
///
/// The privacy manifest, the App Store answers and the policy page all describe exactly
/// this. Adding an event here is a change to what the app collects, and those three have
/// to move with it.
enum Analytics {

    enum Event: String {
        case onboardingStarted = "onboarding_started"
        case onboardingFinished = "onboarding_finished"
        /// With `has_data`: authorisation alone does not prove Health handed anything over.
        case healthConnected = "health_connected"
        case checkInSaved = "check_in_saved"
        case workoutSaved = "workout_saved"
        case coachMessageSent = "coach_message_sent"
        case paywallViewed = "paywall_viewed"
        /// With `product`: which of the plans, not who bought it.
        case subscriptionStarted = "subscription_started"
    }

    /// The Coach Jett project's public token. It is meant to ship inside the app, which is
    /// why it can live here. Empty sends nothing at all.
    private static let projectToken = ""
    private static let host = "https://us.i.posthog.com"

    static func start() {
        guard !projectToken.isEmpty else { return }
        #if DEBUG
        // A simulator session is not a founder. Debug builds stay out of the numbers
        // unless asked, so checking that events arrive is still possible.
        guard ProcessInfo.processInfo.arguments.contains("--analytics") else { return }
        #endif
        let config = PostHogConfig(projectToken: projectToken, host: host)
        // Lifecycle events stay on: "Application Opened" is what retention is read from.
        config.captureScreenViews = false
        config.personProfiles = .never
        config.setDefaultPersonProperties = false
        config.preloadFeatureFlags = false
        config.surveys = false
        #if DEBUG
        config.flushAt = 1
        #endif
        PostHogSDK.shared.setup(config)
    }

    static func record(_ event: Event, _ properties: [String: Any] = [:]) {
        PostHogSDK.shared.capture(event.rawValue, properties: properties)
    }
}
