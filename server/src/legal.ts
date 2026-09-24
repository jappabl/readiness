/**
 * Terms and privacy, served from the same Worker the app already talks to.
 *
 * App Review requires both to be reachable from inside the app, and the paywall pointed
 * at example.com. Hosting them here rather than on a marketing site means they cannot be
 * broken by a deploy of something else, and they are on the origin the app is already
 * allowed to reach.
 *
 * Everything below is drawn from what the app actually does: the HealthKit usage strings
 * in Info.plist, the consent gate on CoachSharing, the context object audited by the
 * "What leaves the device" suite, and the on-device stores. It is not legal advice and
 * has not been reviewed by anybody qualified.
 */

const UPDATED = "24 September 2026"

function page(title: string, body: string): Response {
  return new Response(
    `<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${title} · Coach Jett</title>
<style>
  :root { color-scheme: light dark; }
  body { font: 17px/1.6 -apple-system, BlinkMacSystemFont, system-ui, sans-serif;
         max-width: 40rem; margin: 0 auto; padding: 2.5rem 1.25rem 4rem; }
  h1 { font-size: 1.8rem; letter-spacing: -0.02em; margin-bottom: 0.25rem; }
  h2 { font-size: 1.1rem; margin-top: 2.25rem; }
  .updated { opacity: 0.6; font-size: 0.9rem; margin-top: 0; }
  li { margin: 0.4rem 0; }
</style></head><body>
<h1>${title}</h1><p class="updated">Last updated ${UPDATED}</p>
${body}</body></html>`,
    { headers: { "content-type": "text/html; charset=utf-8", "cache-control": "public, max-age=3600" } },
  )
}

const PRIVACY = `
<p>Coach Jett is a training app. This describes what it collects, where it goes, and what
it never does.</p>

<h2>What stays on your iPhone</h2>
<ul>
  <li>Every raw Health record it reads: heart rate samples, sleep periods, workouts,
      steps, weight, nutrition. These are read on the device and are never uploaded.</li>
  <li>Your date of birth. It is turned into an age on the device, and only the age is
      ever sent anywhere.</li>
  <li>Anything to do with where you are. Gym detection compares your location against
      gyms you named yourself, entirely on the device. No location leaves it, ever.</li>
  <li>Your logged sets and sessions, your check-ins, your conversations with Jett and the
      short list of things he remembers. These are stored only on your iPhone. Parts of
      them travel with a question to Jett, as the next section describes, but our server
      does not keep them.</li>
</ul>

<h2>What is sent, and only if you allow it</h2>
<p>AI coaching is off until you turn it on. While it is on, asking Jett a question sends a
summary to our server, which forwards it to the AI provider that writes the reply. That
summary can contain:</p>
<ul>
  <li>today's scores and the readings behind them, their 7 and 28 day averages, and your
      daily scores for the last 14 days;</li>
  <li>daily totals you record, such as activity, food, caffeine, alcohol and mindful
      minutes;</li>
  <li>your age, height and biological sex, if Health has them;</li>
  <li>your goal, training experience, equipment, and any injury or limitation you told
      the app about;</li>
  <li>today's session, with its exercises, sets, reps and loads;</li>
  <li>your check-in answers, the things Jett remembers, and the conversation itself.</li>
</ul>
<p>It never contains a raw Health sample; an automated test fails if one ever appears.</p>
<p>A meal photo goes the same way, and only when you take one and approve it. Taking the
photo is the choice, so the AI coaching switch does not cover it.</p>
<p>Turning AI coaching off in Profile stops any future coaching request. It cannot recall
something already sent.</p>

<h2>What our server keeps</h2>
<p>Our server does not store your summaries, your conversations or your photos. It passes
them to the AI provider and keeps nothing of them. For each install it keeps only:</p>
<ul>
  <li>a key that proves requests come from a genuine copy of the app, and a counter that
      stops an old request being replayed;</li>
  <li>your member number;</li>
  <li>counts used for rate limits and the free message and meal photo allowances;</li>
  <li>if Apple refunds a purchase, that purchase's transaction ID, so the refund ends it.</li>
</ul>
<p>The app has no accounts, so none of this is linked to your name, your email or your
Apple Account.</p>

<h2>How the app is used</h2>
<p>So we can see where the app loses people, it sends PostHog, an analytics service, a
short note when you reach certain steps: starting and finishing setup, connecting Health,
saving a check-in or a workout, sending Jett a message, seeing the subscription screen,
and subscribing, with which plan. It also notes when the app is installed, updated or
opened, with the app's version and your iPhone's model and iOS version.</p>
<p>Each note says only that the step happened. It never contains a Health reading, a
score, a message, a photo or anything you typed. It carries a random ID the app makes, so
one install's steps can be counted together. That ID is not linked to your name, your
email, your Apple Account or your member number, and PostHog is set to discard your IP
address.</p>

<h2>Who else sees it</h2>
<p>The AI provider processes each request to produce the reply, under its own terms for
what it keeps. Our server runs on Cloudflare, which carries requests to and from it. Apple
checks that the app is genuine and handles subscriptions. PostHog receives the notes
described above. There are no advertising networks and no data brokers. Nothing is sold,
and Health data is never used for advertising.</p>

<h2>Dictation</h2>
<p>Logging a set by voice uses Apple's speech recognition. On iPhones that support it, the
words are recognised on the device. On others, Apple processes the audio under its own
privacy policy. The app never sends audio to our server.</p>

<h2>Texting Hao</h2>
<p>Text Hao opens a message from your own Messages app to Hao, who built Coach Jett. It
fills in the app version, your iPhone model, the iOS version and the screen you were on.
When you tap it under an error, it also adds the error and a picture of that screen. You
see all of it before you send, and nothing goes unless you press send. It goes by text message, not through our
server, and none of your health data is added to it.</p>

<h2>Payments</h2>
<p>Subscriptions are handled by Apple. We never see your payment details. With each
question to Jett, the app sends Apple's signed record of your subscription, so our server
can check that it is real and current. It is checked and discarded, unless Apple later
tells us that purchase was refunded.</p>

<h2>Deleting it</h2>
<p>Deleting the app removes everything stored on the device, which is almost all of it.
You can clear the conversation and forget anything Jett remembers from Profile at any
time. The server records above belong to the install, not to you, so once the app is
deleted nothing uses them again.</p>

<h2>Children</h2>
<p>Coach Jett is not intended for children under 13. The app does not set calorie or
weight targets itself, and Jett is instructed not to give adult calorie or weight-loss
targets to anybody whose age shows they are under 18.</p>

<h2>Contact</h2>
<p>Questions about any of this: <a href="mailto:hlincontacts@gmail.com">hlincontacts@gmail.com</a>.</p>
`

const TERMS = `
<h2>What this is</h2>
<p>Coach Jett gives training, sleep and recovery guidance based on data your iPhone
already records. Using it means accepting what follows.</p>

<h2>It is not medical advice</h2>
<p>Coach Jett is not a doctor, a physiotherapist or a dietitian, and nothing it says is a
diagnosis or a treatment. Its sleep and recovery scores are estimates built on consumer
sensors, not clinical measurements. If something hurts, if you feel unwell, or if you are
managing a condition, talk to a qualified professional and follow them rather than the
app. Training carries risk of injury, and what you choose to do is your decision.</p>

<h2>Subscriptions</h2>
<p>The measurements are free, and so is typing a meal in. A subscription pays for asking
Jett questions and for meal photo estimates beyond the free ones, because those are the
parts with a cost every time they are used. Subscriptions are billed through your Apple
ID, renew automatically unless cancelled at least 24 hours before the period ends, and are
managed and cancelled in your Apple account settings rather than here. A free trial, where
offered, becomes a paid subscription unless cancelled before it ends. Refunds are Apple's
to give.</p>

<h2>Fair use</h2>
<p>There is no monthly cap for subscribers, but there is a rate limit to stop runaway
usage. Do not attempt to access the service other than through the app.</p>

<h2>Availability</h2>
<p>The app depends on Apple Health and on an AI provider, either of which can change or be
unavailable. Features may change. We may end the service, and would give notice through
the app before doing so.</p>

<h2>Liability</h2>
<p>Coach Jett is provided as it is, without warranty. To the extent the law allows, we are
not liable for injury, loss or damage arising from following its guidance or from any
inaccuracy in what it reports.</p>

<h2>Contact</h2>
<p>Questions: <a href="mailto:hlincontacts@gmail.com">hlincontacts@gmail.com</a>.</p>
`

export function legalPage(pathname: string): Response | null {
  if (pathname === "/legal/privacy") return page("Privacy", PRIVACY)
  if (pathname === "/legal/terms") return page("Terms of Use", TERMS)
  return null
}
