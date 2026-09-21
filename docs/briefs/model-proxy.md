# Brief: put a proxy between the app and the model providers

You are working in an existing iOS app plus a new, small backend you will create. Read
this whole brief before writing anything.

## Why this exists

**Coach Jett** currently calls model providers directly from the device, using keys kept
in the Keychain on that device. That works for development and cannot ship:

- A distributable IPA is a zip. Any key that reaches it is extracted in minutes.
- A key on a device cannot be rotated without an App Store release and review.
- The free tier and the burst limit are enforced on the client, which makes them a
  courtesy rather than a control. The product sells "unlimited" to subscribers, so the
  meter is the margin.
- The system prompt is compiled into the app, so changing how Jett writes needs a
  release.

The fix is a thin server that holds the keys, proves the caller is a real install of this
app with a real entitlement, meters it, and forwards.

## The single most important design decision

**The server builds the request body. The client never sends one.**

It is tempting to make the proxy a dumb forwarder: same JSON, different URL. Do not. A
proxy that forwards a client-supplied body to a provider using your key is an open
relay: anybody who gets past attestation once can send it arbitrary prompts against your
account, with any model and any `max_tokens`. Whatever you spend on attestation is wasted
if the body is attacker-controlled.

So the client sends **structured, validated inputs** (the context object and the
conversation turns), and the Worker composes the provider request: model, system prompt,
tools, token limits, all server-side. This is also what buys you prompt changes without a
release.

## Current state on the client

### Coach. `App/Coach/ClaudeCoachProvider.swift`
```swift
static let model = "claude-sonnet-5"
static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
static let maximumToolRounds = 3       // tool loop rounds before giving up
static let maximumHistoryMessages = 16 // turns sent per request
var apiKey: String? { Keychain.apiKey }
```
- Streams with `URLSession.bytes(for:)`, parsing SSE into `CoachEvent`s.
- Headers: `x-api-key`, `anthropic-version: 2023-06-01`, `Content-Type: application/json`.
- Body comes from `CoachRequest.body(model:rules:data:messages:offersTools:)` in
  `Core/Sources/ReadinessCore/CoachRequest.swift`, with prompt text from `CoachPrompt`.
- Gated on `CoachSharing.isAllowed` (`App/Coach/CoachProvider.swift:157`), a UserDefaults
  consent flag. Keep that gate; it is the user's consent to send anything at all.

### Meal photos. `App/Coach/MealPhotoEstimator.swift`
```swift
POST https://api.deepseek.com/anthropic/v1/messages
model: "deepseek-flash", max_tokens 500, thinking disabled
x-api-key: <MealPhotoKey.read()>, anthropic-version: 2023-06-01
content: [ {type:image, base64 jpeg ≤1280px, q0.8}, {type:text, portion notes} ]
```
- Not streaming. Single request, JSON object back, decoded by `MealEstimate.decode`.
- Key lives in the Keychain under service `com.coachjett.ios.deepseek`, written **only**
  by a DEBUG environment variable `JETT_DEEPSEEK_API_KEY` in `App/ReadinessApp.swift`.
  There is deliberately no UI for it and you should not add one.

### Limits, currently client-side and advisory
```swift
Paywall.freeMessages = 5          // Core/Sources/ReadinessCore/Paywall.swift
Paywall.countdownAppearsAt = 2
BurstLimiter.capacity = 8         // Core/Sources/ReadinessCore/BurstLimiter.swift
BurstLimiter.refillInterval = 12  // seconds per token
```

### Entitlement. `App/Domain/Subscriptions.swift`
```swift
static let monthlyID = "com.coachjett.ios.pro.monthly"
static let yearlyID  = "com.coachjett.ios.pro.yearly"
private(set) var isSubscribed  // from Transaction.currentEntitlements
```

Bundle id is `com.coachjett.ios`.

## Prerequisite you will hit immediately

`DEVELOPMENT_TEAM` is empty in `Readiness.xcodeproj/project.pbxproj`. **App Attest needs a
real Team ID and a real App ID**, and the attestation payload is validated against
`<teamID>.<bundleID>`. Get the team set before starting the attestation work, or build
the Worker with attestation stubbed behind a flag and turn it on after.

## What to build

### Host

**Cloudflare Workers.** Edge-deployed, so it adds little to the round trip: latency is one
of this product's two stated levers. It streams `ReadableStream` responses natively, which
the coach needs. Secrets via `wrangler secret put`. Use **Durable Objects** for the token
bucket, which needs strong consistency, and KV or D1 for anything that can be eventually
consistent.

If you have a strong reason to prefer Supabase Edge Functions, that is acceptable; do not
pick something that cannot stream.

### Endpoints

```
POST /v1/coach     → streams SSE back to the client
POST /v1/meal      → single JSON response
POST /v1/attest    → exchanges an App Attest assertion for a short-lived session token
```

### Authentication, in two layers

1. **App Attest** proves this is a genuine, unmodified build of your app on real
   hardware. Generate a key with `DCAppAttestService`, attest it once, then sign each
   request (or each session-token exchange) with an assertion. Store the key id in the
   Keychain. This is the layer that stops someone curling your endpoint.

2. **StoreKit 2 entitlement.** The client sends the `jwsRepresentation` from
   `Transaction.currentEntitlements`. The Worker verifies the JWS signature against
   Apple's root certificates, then checks `bundleId`, that `productId` is one of the two
   above, and that it has not expired. This is how the server knows "subscriber" rather
   than trusting a boolean from the client.

Do not build accounts. The combination above gives you entitlement and abuse resistance
with no login, and the product currently has no cross-device story that would need one.

### Metering, server-side, authoritative

Port the two rules rather than inventing new numbers:

- **Free tier**: 5 coach messages, ever, per install. Key it to the App Attest key id,
  which is stable per install and not user-supplied. Returns a remaining count so the
  client can keep showing its countdown at 2 or fewer.
- **Burst**: token bucket, capacity 8, one token per 12 seconds. `BurstLimiter` in Core is
  the exact algorithm; match its behaviour including the clamp on negative elapsed time.

Both must be enforced for subscribers too: unlimited means no monthly cap, not no rate
limit. Add a per-account daily spend ceiling and a global kill switch; a bug in a retry
loop should cost you a rounding error, not a month of revenue.

### Prompts move server-side

`CoachPrompt.rules` and `CoachPrompt.data(context:unitsAreMetric:)` (both in
`App/Coach/CoachProvider.swift`, not in a file of their own), and the body assembly in
`CoachRequest.body`, move into the Worker. The meal system prompt in
`MealPhotoEstimator` moves too.

**Name this cost honestly in your report:** `CoachRequest` is pure, tested Swift in Core,
and there are tests covering its cache breakpoint and its history trimming
(`trim(_:to:)` dropping leading assistant turns, which the API rejects). Once assembly
moves, those tests cover nothing that ships. Port the behaviour *and its tests* to the
Worker; do not simply delete the Swift ones and leave the logic untested in TypeScript.

Keep `CoachContext` and its serialization in Swift. It is audited by a test suite called
"What leaves the device" which asserts no raw sample or timeseries array is ever included.
**That audit must still hold**, and it is now also the contract for your request schema.

### The tool loop stays on the client

The coach's tool calls fetch data that only exists on the device, in SwiftData. The
server cannot answer them. So the loop stays where it is: each round is one proxied
request, and `maximumToolRounds = 3` still bounds it. The Worker must accept a
conversation that already contains `tool_use` and `tool_result` blocks, and must validate
their shape rather than passing them through blindly.

### Provider routing

The coach currently calls Anthropic and the meal estimator calls DeepSeek's
Anthropic-compatible endpoint. The stated direction is DeepSeek for everything. Put the
choice in Worker config so it can change without an app release, and keep a fallback
provider for when one is down. Both speak the same Messages shape, which makes this
cheap.

## What changes on the client

- `ClaudeCoachProvider`: swap `endpoint` for the Worker URL, drop `x-api-key` and
  `anthropic-version`, send the session token instead. Stop building the provider body;
  send `CoachContext` plus messages. Keep the SSE parsing: have the Worker pass the
  provider's event stream through unchanged so `CoachEvent` parsing does not move.
- `MealPhotoEstimator`: same swap. The base64 resize (≤1280px, q0.8) stays on the client;
  it is bandwidth you do not want to pay for twice.
- `Keychain.apiKey`, `MealPhotoKey`, and the `JETT_DEEPSEEK_API_KEY` debug hook are all
  deleted once the Worker is live, along with the Anthropic key field in `ProfileView`.
  Do not delete them before, or development stops.
- Error mapping: the client already models `CoachError.notConfigured` and
  `MealPhotoEstimator.Failure.service(Int)`. Map proxy statuses onto them:
  401 attestation failed, 402 free tier exhausted (the client shows the paywall),
  429 burst limit (the client already says "One at a time, try again in Ns" and needs
  `Retry-After`), 503 provider down.
- `Subscriptions.isSubscribed` stays as the thing that drives the *UI*. It stops being
  what grants access.

## Edge cases that will bite

- **Offline and first launch.** Attestation needs the network. The app must not appear
  broken before the first successful attest; everything except the coach and meal photos
  works with no server at all, and should keep working.
- **Token expiry mid-stream.** Refresh before a request, not during one.
- **App Attest is per install.** Delete and reinstall and the free 5 resets. That is
  acceptable and not worth building identity to prevent; note it rather than solving it.
- **Clock skew** on the burst bucket. Trust the server's clock only.
- **Simulator.** `DCAppAttestService.isSupported` is false there. Development needs a
  bypass path, gated on a Worker-side flag plus a dev-only shared secret, never on a
  client-side `#if DEBUG` alone.
- **Streaming through the Worker** must not buffer. Verify a first token arrives at the
  device before the full response completes; a proxy that accumulates the body silently
  destroys the coach's feel.
- **`CoachSharing.isAllowed` still gates everything.** The proxy does not change consent.

## Verification

- Unit tests in the Worker for: JWS verification against a known-good and a tampered
  transaction, the token bucket at boundaries, the free-tier counter, and request schema
  rejection of an oversized or malformed body.
- An end-to-end check on device: coach answer streams token by token; meal photo returns
  an estimate; free tier exhausts at 5 and shows the paywall; burst limit returns 429 with
  `Retry-After` and the client's existing message appears.
- Confirm with a proxy tool that no provider key is present in any client request, and
  that `strings` on the built binary contains no key.
- `swift test --package-path Core` stays green. Build with
  `xcodebuild -project Readiness.xcodeproj -scheme Readiness -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -configuration Debug build`.

## Do not

- Do not embed a provider key in the app, obfuscated or otherwise, and do not fetch one
  at runtime into the client. All three end with the key on the device.
- Do not let the client choose the model, the token limit, or the system prompt.
- Do not add a user-facing API key field. That was tried and reverted; it dresses a
  development hook as a product feature.
- Do not weaken what `CoachContext` sends. The "What leaves the device" suite is the
  privacy promise made on the Health screen.
- Do not build accounts or a login.

## Deliverables

1. The Worker, deployed, with `wrangler.toml` and secrets documented but not committed.
2. Client changes behind a single configuration point so the old direct path can be
   restored during development.
3. Tests as above, Worker and Swift both green.
4. A short note covering: what moved server-side, which Swift tests were made obsolete and
   where their coverage now lives, the measured added latency versus calling the provider
   directly, and anything here you deliberately did not do, with the reason.
