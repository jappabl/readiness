import { describe, expect, test } from "vitest"
import { InvalidRequest, MAX_MESSAGES, parseCoachBody, parseMealBody } from "../src/schema"

const user = (text: string) => ({ role: "user", content: text })
const good = { context: "HRV 55.8", messages: [user("why am I flat")], unitsAreMetric: false }

describe("the coach request", () => {
  test("a well-formed body parses", () => {
    expect(parseCoachBody(good).context).toBe("HRV 55.8")
  })

  test.each(["model", "max_tokens", "system", "tools", "betas", "thinking", "stream"])(
    "the client cannot set %s",
    (field) => {
      expect(() => parseCoachBody({ ...good, [field]: "anything" })).toThrow(InvalidRequest)
    },
  )

  test("a conversation opening on the assistant is refused", () => {
    const flipped = { ...good, messages: [{ role: "assistant", content: "hi" }, user("hi")] }
    expect(() => parseCoachBody(flipped)).toThrow(/start with a user message/)
  })

  test("an unknown role is refused", () => {
    expect(() => parseCoachBody({ ...good, messages: [{ role: "system", content: "x" }] }))
      .toThrow(InvalidRequest)
  })

  test("history longer than the client's own cap is refused", () => {
    const many = Array.from({ length: MAX_MESSAGES + 1 }, () => user("x"))
    expect(() => parseCoachBody({ ...good, messages: many })).toThrow(/too many messages/)
  })

  test("an oversized context is refused", () => {
    expect(() => parseCoachBody({ ...good, context: "x".repeat(20_000) })).toThrow(/context too large/)
  })

  test("empty and malformed bodies are refused", () => {
    expect(() => parseCoachBody(null)).toThrow(InvalidRequest)
    expect(() => parseCoachBody({ ...good, messages: [] })).toThrow(InvalidRequest)
    expect(() => parseCoachBody({ messages: [user("x")] })).toThrow(/context/)
  })

  test("tool blocks in content are allowed through, since the loop is client-side", () => {
    const withTool = {
      ...good,
      messages: [
        user("make it easier"),
        { role: "assistant", content: [{ type: "tool_use", id: "t1", name: "adjust_session", input: {} }] },
        { role: "user", content: [{ type: "tool_result", tool_use_id: "t1", content: "ok" }] },
      ],
    }
    expect(parseCoachBody(withTool).messages).toHaveLength(3)
  })
})

describe("the meal request", () => {
  const meal = { imageBase64: "abc", mediaType: "image/jpeg", note: "half an avocado" }

  test("a well-formed body parses", () => {
    expect(parseMealBody(meal).note).toBe("half an avocado")
  })

  test("the note is truncated rather than refused", () => {
    expect(parseMealBody({ ...meal, note: "x".repeat(5000) }).note).toHaveLength(1200)
  })

  test("a missing or absurd image is refused", () => {
    expect(() => parseMealBody({ ...meal, imageBase64: "" })).toThrow(InvalidRequest)
    expect(() => parseMealBody({ ...meal, imageBase64: "x".repeat(7_000_000) })).toThrow(/too large/)
  })

  test("an unsupported media type is refused", () => {
    expect(() => parseMealBody({ ...meal, mediaType: "image/heic" })).toThrow(InvalidRequest)
  })

  test("the client cannot set the model here either", () => {
    expect(() => parseMealBody({ ...meal, model: "something-expensive" })).toThrow(InvalidRequest)
  })
})
