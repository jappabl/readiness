# Coach Jett proxy

Holds the provider keys, decides entitlement, meters, composes the request, forwards.
The app never holds a key and never sends a provider body. Design and rationale:
`../docs/briefs/model-proxy.md`.

```
npm install
npm test          # 54 tests
npm run typecheck
npm run dev       # local worker on :8787
```

Secrets are never committed. Locally they live in `.dev.vars` (gitignored); in production:

```
wrangler secret put ANTHROPIC_API_KEY
wrangler secret put DEEPSEEK_API_KEY
wrangler secret put DEV_SHARED_SECRET
```

## What is finished

- Request validation, which is the control that keeps this a proxy rather than an open
  relay. The client cannot set the model, the token ceiling, the system prompt or the
  tools; attempting to is a 400, not a silent strip.
- Metering: burst bucket (capacity 8, one token per 12s) and the 5-message free tier,
  both inside one Durable Object transaction so they are correct under concurrency.
  Ports of the Swift originals in Core rather than new numbers.
- Prompt assembly, extracted from the Swift source rather than retyped, with the cache
  breakpoint and history trimming covered by tests mirroring `CoachRequestTests`.
- Streaming passthrough, unbuffered.
- Entitlement *claim* checks: bundle, product, expiry, revocation.

## What is not, and must be before this holds real keys

- **App Attest.** Off until the Xcode project has a real `DEVELOPMENT_TEAM`, because the
  payload is validated against `<teamID>.<bundleID>`. While off, a shared development
  secret is required instead, so the endpoint is never simply open. `identify()` returns
  501 rather than a permissive default if attestation is switched on before it is built.
- **StoreKit JWS signature verification.** The claim checks are done and tested; the
  signature and `x5c` chain validation are not. `verifySignature` throws rather than
  returning a permissive default, so a half-built verifier cannot quietly grant
  entitlement. Wire in Apple's `app-store-server-library` rather than hand-rolling X.509.
- **The client still calls providers directly.** Nothing here is load-bearing yet.

## A bug worth keeping in mind

The first version of the stream passthrough checked only whether the upstream response
had a body. Every error this worker produces has a body, so a provider authentication
failure came back to the client as `200 OK` with an event-stream content type and the
error JSON inside it — the client would have shown an empty answer and never run its
error path. Found by pointing the local worker at the real API with a deliberately wrong
key, not by reading the code. `streamOrPassError` now covers it.

## Testing against the simulator

The app reads `JettProxyURL` from Info.plist, and debug builds let an environment
variable override it:

```
SIMCTL_CHILD_JETT_PROXY_URL=http://localhost:8787 \
SIMCTL_CHILD_JETT_DEV_SECRET=local-dev-secret \
  xcrun simctl launch booted com.coachjett.app
```

App Transport Security blocks plain HTTP, so add `NSAppTransportSecurity` with
`NSAllowsLocalNetworking` to `App/Info.plist` **while testing and take it out again**. It
is deliberately not committed: a health app should not ship an ATS exception for the
convenience of a local worker.

`rm -rf server/.wrangler/state` resets the meter between runs. The Durable Object keeps
the free-message count, so without that reset the second test session starts at 402.
