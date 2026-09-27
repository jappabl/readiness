/**
 * Telling Hao about an install that crossed a daily line in `limits.ts`.
 *
 * Nothing here can fail a request: it runs after the decision, it never throws, and a
 * webhook that is down, slow or wrong costs a log line and nothing else. The install is
 * named by a short hash, never its attested key id, so the logs never hold anything that
 * could be replayed or tied back to a device.
 */
import type { DailyUsage } from "./limits"
import { ABUSE_ALERT_MESSAGES, ABUSE_ALERT_PHOTOS } from "./limits"

export interface AlarmEnv {
  /// Optional. Set with `wrangler secret put ALERT_WEBHOOK_URL`, never in code or
  /// `wrangler.toml`: the address is the only thing standing between a stranger and
  /// Hao's phone.
  ALERT_WEBHOOK_URL?: string
}

type Fetcher = (url: string, init: RequestInit) => Promise<Response>

const WEBHOOK_TIMEOUT_MS = 5000

export async function installTag(id: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(id))
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("").slice(0, 12)
}

export async function alertAbuse(
  id: string,
  usage: DailyUsage,
  env: AlarmEnv,
  fetcher: Fetcher = (url, init) => fetch(url, init),
): Promise<void> {
  try {
    const install = await installTag(id)
    // Always, whether or not a webhook is set: `wrangler tail` and the Cloudflare logs
    // are the channel that needs no configuration.
    console.warn(JSON.stringify({
      event: "abuse_alert",
      install,
      day: usage.day,
      messages: usage.messages,
      photos: usage.photos,
      limits: { messages: ABUSE_ALERT_MESSAGES, photos: ABUSE_ALERT_PHOTOS },
    }))

    const url = (env.ALERT_WEBHOOK_URL ?? "").trim()
    if (!url) return
    const text = `Coach Jett: install ${install} used ${usage.messages} coach messages and `
      + `${usage.photos} meal photos on ${usage.day} (UTC). Alert only, nothing was blocked.`
    // `text` for Slack, `content` for Discord. ntfy reads `text` through a template in
    // the URL; the server README has the exact address.
    const response = await fetcher(url, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ text, content: text }),
      signal: AbortSignal.timeout(WEBHOOK_TIMEOUT_MS),
    })
    if (!response.ok) {
      console.warn(JSON.stringify({ event: "abuse_alert_webhook_failed", install, status: response.status }))
    }
  } catch (error) {
    // The error is not logged: a fetch error can carry the URL, and the URL is a secret.
    console.warn(JSON.stringify({ event: "abuse_alert_webhook_failed", name: (error as Error)?.name ?? "error" }))
  }
}
