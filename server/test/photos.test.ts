import { describe, expect, test } from "vitest"
import {
  BURST_CAPACITY,
  FREE_MESSAGES,
  FREE_PHOTOS,
  freshBucket,
  meterDecision,
  refundPhoto,
  type MeterState,
} from "../src/limits"
import { estimateFoundFood } from "../src/prompt"

const NOW = 1_700_000_000_000
const fresh = (): MeterState => ({ bucket: freshBucket(), freeUsed: 0, freePhotosUsed: 0 })

// Meal photo estimates cost money every time, so free installs get a taste and Pro gets
// the rest. Typing a meal in never reaches the server and stays free.
describe("free meal photo estimates", () => {
  test("a free user gets exactly the free photos, then a 402", () => {
    let state = fresh()
    for (let i = 0; i < FREE_PHOTOS; i++) {
      const out = meterDecision(state, false, NOW + i * 60_000, "photo")
      expect(out.allowed).toBe(true)
      state = out.state
    }
    expect(meterDecision(state, false, NOW + 600_000, "photo")).toMatchObject({ allowed: false, status: 402 })
  })

  test("the free tier is three", () => {
    expect(FREE_PHOTOS).toBe(3)
  })

  // Separate counts: using up the coach must not cost a photo, or the other way round.
  test("photos and coach answers are counted separately", () => {
    let state = fresh()
    for (let i = 0; i < FREE_PHOTOS; i++) state = meterDecision(state, false, NOW + i * 60_000, "photo").state
    const coach = meterDecision(state, false, NOW + 600_000, "message")
    expect(coach.allowed).toBe(true)
    expect(coach.state.freeUsed).toBe(1)
    expect(coach.state.freePhotosUsed).toBe(FREE_PHOTOS)

    let used: MeterState = { bucket: freshBucket(), freeUsed: FREE_MESSAGES, freePhotosUsed: 0 }
    used = meterDecision(used, false, NOW, "photo").state
    expect(used.freePhotosUsed).toBe(1)
  })

  test("a subscriber's photos are unlimited and never counted", () => {
    const out = meterDecision({ bucket: freshBucket(), freeUsed: 0, freePhotosUsed: 99 }, true, NOW, "photo")
    expect(out.allowed).toBe(true)
    expect(out.state.freePhotosUsed).toBe(99)
  })

  test("burst still applies to photos, and a burst refusal costs no free photo", () => {
    let state = fresh()
    for (let i = 0; i < BURST_CAPACITY; i++) state = meterDecision(state, true, NOW, "photo").state
    const refused = meterDecision(state, false, NOW, "photo")
    expect(refused).toMatchObject({ allowed: false, status: 429 })
    expect(refused.state.freePhotosUsed).toBe(0)
  })

  // A record from before photos were counted has no photo field. It must read as zero,
  // not as NaN, which would compare false against the limit and let everything through.
  test("a stored state with no photo count starts at zero", () => {
    const old = { bucket: freshBucket(), freeUsed: 2 } as MeterState
    const out = meterDecision(old, false, NOW, "photo")
    expect(out.allowed).toBe(true)
    expect(out.state.freePhotosUsed).toBe(1)
  })

  test("the default kind is still a coach message", () => {
    const out = meterDecision(fresh(), false, NOW)
    expect(out.state.freeUsed).toBe(1)
    expect(out.state.freePhotosUsed).toBe(0)
  })
})

// Three is few enough that losing one to a network error or an empty plate would feel
// like being cheated, so a photo that produced no estimate is handed back.
describe("handing back a photo that produced nothing", () => {
  test("a refund returns one free photo", () => {
    expect(refundPhoto({ ...fresh(), freePhotosUsed: 2 }).freePhotosUsed).toBe(1)
  })

  test("a refund never goes below zero", () => {
    expect(refundPhoto(fresh()).freePhotosUsed).toBe(0)
    expect(refundPhoto({ bucket: freshBucket(), freeUsed: 0 } as MeterState).freePhotosUsed).toBe(0)
  })

  test("a refund leaves the burst bucket and coach count alone", () => {
    const state: MeterState = { bucket: { tokens: 3, updated: NOW }, freeUsed: 4, freePhotosUsed: 2 }
    const refunded = refundPhoto(state)
    expect(refunded.bucket).toEqual(state.bucket)
    expect(refunded.freeUsed).toBe(4)
  })
})

describe("whether an estimate found food", () => {
  const reply = (text: string) => JSON.stringify({ content: [{ type: "text", text }] })

  test("an estimate with calories found food", () => {
    expect(estimateFoundFood(reply('{"name":"Grapes, about 1 cup","calories":104,"protein":1.1,"carbs":27,"fat":0.2}'))).toBe(true)
  })

  test("an estimate wrapped in prose still counts", () => {
    expect(estimateFoundFood(reply('Here you go: {"name":"Toast","calories":80,"protein":3,"carbs":15,"fat":1}'))).toBe(true)
  })

  test("an empty object found nothing", () => {
    expect(estimateFoundFood(reply("{}"))).toBe(false)
  })

  // Zero calories is a real answer (water, black coffee) and is charged like any other.
  // Refunding it would also be a loophole: a note asking for "0 calories, real numbers in
  // the name" would make every estimate free.
  test("zero calories is still an estimate", () => {
    expect(estimateFoundFood(reply('{"name":"Water","calories":0,"protein":0,"carbs":0,"fat":0}'))).toBe(true)
  })

  test("an estimate with no number for calories found nothing", () => {
    expect(estimateFoundFood(reply('{"name":"Something"}'))).toBe(false)
    expect(estimateFoundFood(reply('{"name":"Toast","calories":"80"}'))).toBe(false)
  })

  test("a reply that is not the provider's shape found nothing", () => {
    for (const junk of ["", "not json", "{}", JSON.stringify({ content: "x" })]) {
      expect(estimateFoundFood(junk), junk).toBe(false)
    }
  })
})
