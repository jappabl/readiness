/**
 * Refunds, from Apple's own notifications.
 *
 * The purchase a phone carries is signed before any refund and stays valid until its
 * period ends. Without this, somebody could buy a year, ask Apple for their money back,
 * and keep Pro for the rest of the year. Apple posts an App Store Server Notification
 * when it refunds a transaction, and when it reverses a refund; this keeps the latest
 * word per transaction, and entitlement checks it.
 */
import { decodeJWSPayload, verifierFor, type Trust } from "./entitlement"

export type RefundEvent = "revoke" | "restore"

/**
 * REFUND ends a transaction, and so does REVOKE, which is a family member losing access
 * through Family Sharing. REFUND_REVERSED gives it back. Everything else Apple sends is
 * acknowledged and changes nothing here: renewals and expiries already reach the server
 * through the purchase the phone carries.
 */
export function refundEvent(notificationType: string): RefundEvent | null {
  if (notificationType === "REFUND" || notificationType === "REVOKE") return "revoke"
  if (notificationType === "REFUND_REVERSED") return "restore"
  return null
}

export interface RefundRecord {
  revoked: boolean
  /** Apple's signedDate for the notification that set this. */
  at: number
}

/**
 * Apple's latest word stands. It retries for days and promises nothing about order, so
 * a refund can arrive after the reversal that cancelled it, and must not undo it.
 */
export function applyRefund(current: RefundRecord | undefined, event: RefundEvent, at: number): RefundRecord {
  if (current && at <= current.at) return current
  return { revoked: event === "revoke", at }
}

/** Verified against Apple's root, like every purchase. Throws if it is not Apple's. */
export async function verifiedNotification(
  signedPayload: string,
  trust: Trust,
): Promise<{ type: string; signedDate: number; transactionId: string | null }> {
  const claimed = (decodeJWSPayload(signedPayload) as { data?: { environment?: string } }).data?.environment
  const verifier = await verifierFor(claimed, trust)
  const payload = await verifier.verifyAndDecodeNotification(signedPayload)
  const inner = payload.data?.signedTransactionInfo
  // The transaction inside is signed separately, and checked separately.
  const transaction = inner ? await verifier.verifyAndDecodeTransaction(inner) : undefined
  return {
    type: String(payload.notificationType ?? ""),
    signedDate: payload.signedDate ?? 0,
    transactionId: transaction?.transactionId ?? null,
  }
}

/**
 * One per transaction. A Durable Object rather than KV so that a refund and its
 * reversal landing together cannot both read the old record and both write.
 */
export class RefundLedger implements DurableObject {
  constructor(private state: DurableObjectState) {}

  async fetch(request: Request): Promise<Response> {
    const body = (await request.json()) as { op?: "record"; event?: RefundEvent; at?: number }
    return await this.state.blockConcurrencyWhile(async () => {
      const current = await this.state.storage.get<RefundRecord>("record")
      if (body.op === "record" && body.event && typeof body.at === "number") {
        const next = applyRefund(current, body.event, body.at)
        if (next !== current) await this.state.storage.put("record", next)
        return Response.json({ revoked: next.revoked })
      }
      return Response.json({ revoked: current?.revoked ?? false })
    })
  }
}
