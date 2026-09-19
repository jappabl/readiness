/**
 * What the client is allowed to say.
 *
 * This is the control that makes the proxy a proxy rather than an open relay. The
 * client sends context and turns; it does not get to pick the model, the token ceiling,
 * the system prompt or the tools. Anything that would let it do so is rejected outright
 * rather than stripped, because silently ignoring a field someone went to the trouble of
 * sending hides an attempt worth knowing about.
 */

/** Matches the client's own history cap in ClaudeCoachProvider. */
export const MAX_MESSAGES = 16
/** Generous for a compact context block, tight enough to stop a prompt smuggled in it. */
export const MAX_CONTEXT_BYTES = 16_000
export const MAX_MESSAGE_BYTES = 40_000
/** The client resizes to 1280px at q0.8 before sending; this is well above that. */
export const MAX_IMAGE_BYTES = 6_000_000
export const MAX_NOTE_CHARS = 1200

/** Fields only the server may decide. Their presence is a rejection, not a warning. */
const FORBIDDEN = ["model", "max_tokens", "system", "tools", "betas", "fallbacks",
                   "output_config", "thinking", "stream"] as const

export class InvalidRequest extends Error {}

export interface CoachBody {
  context: string
  messages: Array<Record<string, unknown>>
  unitsAreMetric: boolean
  offersTools: boolean
}

export interface MealBody {
  imageBase64: string
  mediaType: string
  note: string
}

function bytes(value: string): number {
  return new TextEncoder().encode(value).length
}

function rejectForbidden(raw: Record<string, unknown>): void {
  for (const key of FORBIDDEN) {
    if (key in raw) throw new InvalidRequest(`the client may not set "${key}"`)
  }
}

export function parseCoachBody(raw: unknown): CoachBody {
  if (typeof raw !== "object" || raw === null) throw new InvalidRequest("body must be an object")
  const object = raw as Record<string, unknown>
  rejectForbidden(object)

  const context = object.context
  if (typeof context !== "string") throw new InvalidRequest("context must be a string")
  if (bytes(context) > MAX_CONTEXT_BYTES) throw new InvalidRequest("context too large")

  const messages = object.messages
  if (!Array.isArray(messages) || messages.length === 0) {
    throw new InvalidRequest("messages must be a non-empty array")
  }
  if (messages.length > MAX_MESSAGES) throw new InvalidRequest("too many messages")
  if (bytes(JSON.stringify(messages)) > MAX_MESSAGE_BYTES) {
    throw new InvalidRequest("messages too large")
  }
  for (const message of messages) {
    if (typeof message !== "object" || message === null) {
      throw new InvalidRequest("each message must be an object")
    }
    const role = (message as Record<string, unknown>).role
    if (role !== "user" && role !== "assistant") throw new InvalidRequest("bad role")
    if (!("content" in (message as Record<string, unknown>))) {
      throw new InvalidRequest("message has no content")
    }
  }
  // The API rejects a conversation that opens on the assistant, and the tool loop
  // sends histories that have been trimmed client-side, so check rather than assume.
  if ((messages[0] as Record<string, unknown>).role !== "user") {
    throw new InvalidRequest("conversation must start with a user message")
  }

  return {
    context,
    messages: messages as Array<Record<string, unknown>>,
    unitsAreMetric: object.unitsAreMetric === true,
    offersTools: object.offersTools === true,
  }
}

export function parseMealBody(raw: unknown): MealBody {
  if (typeof raw !== "object" || raw === null) throw new InvalidRequest("body must be an object")
  const object = raw as Record<string, unknown>
  rejectForbidden(object)

  const image = object.imageBase64
  if (typeof image !== "string" || image.length === 0) {
    throw new InvalidRequest("imageBase64 must be a non-empty string")
  }
  if (image.length > MAX_IMAGE_BYTES) throw new InvalidRequest("image too large")

  const mediaType = object.mediaType
  if (mediaType !== "image/jpeg" && mediaType !== "image/png") {
    throw new InvalidRequest("unsupported media type")
  }

  const note = typeof object.note === "string" ? object.note.slice(0, MAX_NOTE_CHARS) : ""
  return { imageBase64: image, mediaType, note }
}
