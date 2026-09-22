import { describe, expect, it } from "vitest"
import { AttestedInstall, MemberRoll } from "../src/index"

/** The smallest thing that behaves like Durable Object storage, plus the serialisation
 *  the platform guarantees: one caller inside `blockConcurrencyWhile` at a time. */
function fakeState() {
  const map = new Map<string, unknown>()
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
  const register = (install: AttestedInstall, member: number) =>
    install.fetch(
      new Request("https://attest/register", {
        method: "POST",
        body: JSON.stringify({ op: "register", key, member }),
      }),
    )

  it("is kept from the first registration", async () => {
    const install = new AttestedInstall(fakeState())
    expect(await (await register(install, 7)).json()).toEqual({ ok: true, member: 7 })
  })

  // Re-registering must not spend a second place. Otherwise a hundred founders becomes
  // however many times the first hundred people reinstalled.
  it("does not change when the same install registers again", async () => {
    const install = new AttestedInstall(fakeState())
    await register(install, 7)
    expect(await (await register(install, 999)).json()).toEqual({ ok: true, member: 7 })
  })

  it("is readable afterwards, and absent before", async () => {
    const install = new AttestedInstall(fakeState())
    const load = () =>
      install.fetch(
        new Request("https://attest/load", {
          method: "POST",
          body: JSON.stringify({ op: "load" }),
        }),
      )
    expect(await (await load()).json()).toEqual({ key: null, member: null })
    await register(install, 42)
    expect((await (await load()).json<{ member: number }>()).member).toBe(42)
  })
})
