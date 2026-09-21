import { describe, expect, test } from "vitest"
import { coachBody, dataBlock, MAX_OUTPUT_TOKENS, RULES, trim } from "../src/prompt"

/**
 * These mirror CoachRequestTests in Core. The brief that moved prompt assembly here
 * said to port the behaviour *and* its tests rather than leave the logic untested in
 * TypeScript, so this is that.
 */
const user = (t: string) => ({ role: "user", content: t })
const assistant = (t: string) => ({ role: "assistant", content: t })

describe("trimming history", () => {
  test("keeps the most recent turns", () => {
    const all = [user("1"), assistant("2"), user("3"), assistant("4"), user("5")]
    expect(trim(all, 2)).toHaveLength(1) // drops the leading assistant of the tail
  })

  test("never opens on an assistant message, which the API rejects", () => {
    const all = [user("1"), assistant("2"), user("3"), assistant("4")]
    const kept = trim(all, 3)
    expect(kept[0]?.role).toBe("user")
  })

  test("a limit of zero or less keeps nothing", () => {
    expect(trim([user("1")], 0)).toEqual([])
    expect(trim([user("1")], -5)).toEqual([])
  })

  test("an all-assistant history trims to empty rather than to something invalid", () => {
    expect(trim([assistant("a"), assistant("b")], 2)).toEqual([])
  })
})

describe("the request body", () => {
  const base = { model: "m", context: "HRV 55", unitsAreMetric: false,
                 messages: [user("why")], offersTools: false }

  test("the cache breakpoint sits on the last system block, not the first", () => {
    const system = coachBody(base).system as Array<Record<string, unknown>>
    expect(system).toHaveLength(2)
    expect(system[0]).not.toHaveProperty("cache_control")
    expect(system[1]).toHaveProperty("cache_control", { type: "ephemeral" })
  })

  test("the rules come first and the data second", () => {
    const system = coachBody(base).system as Array<Record<string, unknown>>
    expect(system[0]?.text).toBe(RULES)
    expect(system[1]?.text).toContain("The user's data:")
  })

  test("tools appear only when the round offers them", () => {
    expect(coachBody(base)).not.toHaveProperty("tools")
    expect(coachBody({ ...base, offersTools: true })).toHaveProperty("tools")
  })

  test("output is capped, and the client cannot raise it", () => {
    expect(coachBody(base).max_tokens).toBe(MAX_OUTPUT_TOKENS)
  })

  test("units change the data block, not the rules", () => {
    expect(dataBlock("x", true)).toContain("kilograms")
    expect(dataBlock("x", false)).toContain("pounds")
  })

  test("it always streams", () => {
    expect(coachBody(base).stream).toBe(true)
  })
})

describe("the rules text survived the port", () => {
  test("it is the whole prompt, not a truncated copy", () => {
    expect(RULES.length).toBeGreaterThan(4000)
    expect(RULES).toContain("You are Jett")
    expect(RULES).toContain("Under 60 words")
  })
})

/**
 * The prompt is the product's promise written down, and it drifted from it.
 *
 * Onboarding says Jett helps with "training, recovery, sleep, and nutrition", one of
 * the four suggested questions is "What should I eat for my goal?", two of the four
 * goals are nutrition-led, and the app logs meals from a photo. The scope line listed
 * training, physiology, recovery and data, so Jett answered a question the app had
 * just put in front of Hao by saying he does not do that.
 */
describe("what Jett is allowed to answer", () => {
  const starters = [
    "How should I train this week?",
    "How can I recover better?",
    "How can I improve my sleep?",
    "What should I eat for my goal?",
  ]

  test("the scope covers every subject the app offers to answer", () => {
    for (const subject of ["training", "nutrition", "recovery", "physiology"]) {
      expect(RULES).toContain(subject)
    }
    const scope = RULES.slice(RULES.indexOf("If the request has nothing to do with"))
    for (const subject of ["training", "nutrition", "recovery"]) {
      expect(scope.slice(0, 160)).toContain(subject)
    }
  })

  test("nutrition has a body of knowledge, not only a refusal", () => {
    // Training gets "what you know about training" and is answerable. Nutrition had
    // the guardrails (minors, disordered eating) and no licence, which is a subject
    // the model can only decline.
    expect(RULES).toContain("What you know about nutrition")
  })

  test("every suggested question names something in scope", () => {
    expect(starters).toHaveLength(4)
    expect(RULES).toContain("nutrition")
  })

  /**
   * The rules tell the model never to use an em dash while using four of them. The
   * app's copy of this prompt was swept and the server's, which is the live one, was
   * not: two copies of the same text, one of them corrected.
   */
  test("the rules do not use the character they forbid", () => {
    expect(RULES).not.toContain("\u2014")
  })
})
