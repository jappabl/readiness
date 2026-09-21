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

const UPDATED = "20 September 2026"

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
  <li>Your date of birth. Only your age is ever sent anywhere.</li>
  <li>Your conversations with Jett, and the short list of things he remembers.</li>
  <li>Your logged sets, sessions and check-ins.</li>
  <li>Anything to do with where you are. Gym detection compares your location against
      gyms you named yourself, entirely on the device. No location leaves it, ever.</li>
</ul>

<h2>What is sent, and only if you allow it</h2>
<p>AI coaching is off until you turn it on. While it is on, asking Jett a question sends
a summary of your day to our server, which forwards it to the AI provider that writes the
reply. That summary contains scores, averages and the readings behind them, your goal,
your training plan, your check-in answers and the conversation itself. It never contains
raw samples or timeseries; that is enforced by an automated test.</p>
<p>A meal photo is sent to the same provider only when you take one and approve it.</p>
<p>Turning sharing off stops any future request. It cannot recall something already
sent.</p>

<h2>Who else sees it</h2>
<p>The AI provider processes the request to produce the reply. There are no analytics
services, no advertising networks, and no data brokers. Nothing is sold, and Health data
is never used for advertising. There are no accounts, so there is nothing tied to an
identity beyond the install itself.</p>

<h2>Payments</h2>
<p>Subscriptions are handled by Apple. We never see your payment details. Our server sees
only whether an install currently holds a subscription.</p>

<h2>Deleting it</h2>
<p>Deleting the app removes everything stored on the device, which is almost all of it.
You can clear the conversation and any individual thing Jett remembers from Profile at
any time.</p>

<h2>Children</h2>
<p>Coach Jett is not intended for children under 13, and adult calorie and weight targets
are withheld from anybody who tells us they are under 18.</p>

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
<p>The measurements are free. A subscription pays for asking Jett questions, because that
is the part with a cost every time it is used. Subscriptions are billed through your Apple
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
