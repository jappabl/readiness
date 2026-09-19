import { describe, expect, test } from "vitest"
import { streamOrPassError } from "../src/index"

describe("passing a provider response back", () => {
  test("a provider error is not laundered into a 200", async () => {
    const upstream = new Response(JSON.stringify({ error: "invalid x-api-key" }), {
      status: 401, headers: { "content-type": "application/json" },
    })
    const out = streamOrPassError(upstream, false)
    expect(out.status).toBe(401)
    expect(out.headers.get("content-type")).toBe("application/json")
  })

  test("a 5xx stays a 5xx rather than becoming an empty stream", () => {
    const out = streamOrPassError(new Response("upstream down", { status: 503 }), true)
    expect(out.status).toBe(503)
  })

  test("a successful stream is wrapped as SSE and marked with entitlement", () => {
    const body = new ReadableStream()
    const out = streamOrPassError(new Response(body, { status: 200 }), true)
    expect(out.status).toBe(200)
    expect(out.headers.get("content-type")).toBe("text/event-stream")
    expect(out.headers.get("x-jett-subscriber")).toBe("true")
  })

  test("a 200 with no body is passed through rather than wrapped", () => {
    const out = streamOrPassError(new Response(null, { status: 204 }), false)
    expect(out.status).toBe(204)
  })
})
