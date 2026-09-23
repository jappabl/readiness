import { describe, expect, it } from "vitest"
import { AttestedInstall, MemberRoll } from "../src/index"

/** The smallest thing that behaves like Durable Object storage, plus the serialisation
 *  the platform guarantees: one caller inside `blockConcurrencyWhile` at a time. */
function fakeState(seed: Record<string, unknown> = {}) {
  const map = new Map<string, unknown>(Object.entries(seed))
  let queue: Promise<unknown> = Promise.resolve()
  return {
    storage: {
      get: async <T>(k: string) => map.get(k) as T | undefined,
      put: async (k: string, v: unknown) => void map.set(k, v),
    },
    blockConcurrencyWhile: <T>(fn: () => Promise<T>): Promise<T> => {
      const run = queue.then(fn)
      queue = run.catch(() => undefined)
      return run as Promise<T>
    },
  } as unknown as DurableObjectState
}

const key = { keyId: "k", publicKey: "p", counter: 0 } as never

describe("the member roll", () => {
  it("issues one and then the next", async () => {
    const roll = new MemberRoll(fakeState())
    expect(await (await roll.fetch()).json()).toEqual({ member: 1 })
    expect(await (await roll.fetch()).json()).toEqual({ member: 2 })
    expect(await (await roll.fetch()).json()).toEqual({ member: 3 })
  })

  // The whole reason this is a durable object and not a counter in KV. Two people
  // registering in the same instant must not both become member fourteen.
  it("never hands the same number to two callers at once", async () => {
    const roll = new MemberRoll(fakeState())
    const claims = await Promise.all(
      Array.from({ length: 50 }, async () => (await roll.fetch()).json<{ member: number }>()),
    )
    const numbers = claims.map((c) => c.member).sort((a, b) => a - b)
    expect(new Set(numbers).size).toBe(50)
    expect(numbers[0]).toBe(1)
    expect(numbers[49]).toBe(50)
  })
})

describe("an install's member number", () => {
  const send = (install: AttestedInstall, body: object) =>
    install.fetch(new Request("https://attest/op", { method: "POST", body: JSON.stringify(body) }))
  const load = async (install: AttestedInstall) =>
    (await (await send(install, { op: "load" })).json<{ member: number | null }>()).member

  // Registering proves the install is real. It no longer says whether it is from the
  // App Store, so it no longer spends a place: TestFlight installs register too.
  it("is not issued by registering", async () => {
    const install = new AttestedInstall(fakeState())
    expect(await (await send(install, { op: "register", key })).json()).toEqual({ ok: true })
    expect(await load(install)).toBeNull()
  })

  it("is kept from the first claim", async () => {
    const install = new AttestedInstall(fakeState())
    expect(await (await send(install, { op: "claim", member: 7 })).json()).toEqual({ member: 7 })
    expect(await load(install)).toBe(7)
  })

  // Claiming again must not spend a second place. Otherwise a hundred founders becomes
  // however many times the first hundred people opened the app.
  it("does not change when the same install claims again", async () => {
    const install = new AttestedInstall(fakeState())
    await send(install, { op: "claim", member: 7 })
    expect(await (await send(install, { op: "claim", member: 999 })).json()).toEqual({ member: 7 })
  })

  // Numbers handed out before launch went to our own phones and to TestFlight. The
  // launch roll starts again at one, so an old number must not come back as a claim
  // on somebody else's.
  it("ignores a number from the pre-launch roll", async () => {
    const install = new AttestedInstall(fakeState({ member: 3 }))
    expect(await load(install)).toBeNull()
    expect(await (await send(install, { op: "claim", member: 1 })).json()).toEqual({ member: 1 })
  })
})
