import { describe, expect, test } from "vitest"
import { APPLE_ROOT_G3 } from "../src/apple-root"
import { isAppStoreInstall } from "../src/members"
import { BUNDLE, forged, signed, TEST_ROOT } from "./storekit"

const APP_APPLE_ID = 6815046416
const trust = { bundleId: BUNDLE, roots: [TEST_ROOT], appAppleId: APP_APPLE_ID }

/** What `AppTransaction.shared` signs: proof of how this copy of the app was obtained. */
function appTransaction(overrides: object = {}) {
  const now = Date.now()
  return {
    receiptType: "Production",
    appAppleId: APP_APPLE_ID,
    bundleId: BUNDLE,
    applicationVersion: "3",
    originalApplicationVersion: "3",
    receiptCreationDate: now,
    originalPurchaseDate: now,
    ...overrides,
  }
}

// The founding hundred are the first hundred people to install from the App Store.
// TestFlight and Xcode installs are how we get there, and must not spend the places.
describe("who is an App Store install", () => {
  test("a copy from the App Store is", async () => {
    expect(await isAppStoreInstall(signed(appTransaction()), trust)).toBe(true)
  })

  test("a TestFlight copy is not", async () => {
    expect(await isAppStoreInstall(signed(appTransaction({ receiptType: "Sandbox" })), trust)).toBe(false)
  })

  test("a copy built from Xcode is not", async () => {
    expect(await isAppStoreInstall(signed(appTransaction({ receiptType: "Xcode" })), trust)).toBe(false)
  })

  test("a forged App Store copy is not", async () => {
    expect(await isAppStoreInstall(forged(appTransaction()), trust)).toBe(false)
  })

  test("a genuine copy of another app is not", async () => {
    expect(await isAppStoreInstall(signed(appTransaction({ bundleId: "com.someone.else" })), trust)).toBe(false)
    expect(await isAppStoreInstall(signed(appTransaction({ appAppleId: 1 })), trust)).toBe(false)
  })

  test("nothing counts until the app's Apple ID is configured", async () => {
    const unconfigured = { bundleId: BUNDLE, roots: [TEST_ROOT] }
    expect(await isAppStoreInstall(signed(appTransaction()), unconfigured)).toBe(false)
  })

  test("a chain that does not end at Apple is not trusted in production", async () => {
    const apple = { ...trust, roots: [APPLE_ROOT_G3] }
    expect(await isAppStoreInstall(signed(appTransaction()), apple)).toBe(false)
  })

  test("anything that is not a signed transaction is not", async () => {
    for (const junk of [undefined, "", "nonsense", 42]) {
      expect(await isAppStoreInstall(junk, trust), String(junk)).toBe(false)
    }
  })
})
