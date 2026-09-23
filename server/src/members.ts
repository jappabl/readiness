/**
 * Who gets a member number.
 *
 * The founding hundred are the first hundred people to install from the App Store.
 * TestFlight and Xcode installs are real devices running the real app, and attestation
 * cannot tell them apart from a store install, so registering alone would hand them the
 * places. The app's `AppTransaction` can: Apple signs it with how this copy was
 * obtained, and only a store copy says "Production".
 */
import { type Trust, verifierFor } from "./entitlement"

export async function isAppStoreInstall(signedAppTransaction: unknown, trust: Trust): Promise<boolean> {
  if (typeof signedAppTransaction !== "string" || !signedAppTransaction) return false
  try {
    // Production only, whatever the transaction says about itself. The library then
    // refuses anything whose receipt type is not Production, and anything for another
    // app, and it cannot be built at all until the app's Apple ID is configured.
    const verifier = await verifierFor("Production", trust)
    await verifier.verifyAndDecodeAppTransaction(signedAppTransaction)
    return true
  } catch {
    return false
  }
}
