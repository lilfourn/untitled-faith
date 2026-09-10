import { APIError } from "./http";

// Only verified server payment adapters may call this boundary. Never accept amounts from the app.
export type VerifiedContribution = {
  provider: "app_store" | "stripe_apple_pay";
  transactionID: string;
  userID: string;
  grossMicros: number;
  feeMicros: number;
  developerShareBasisPoints?: number;
};

export async function creditContribution(db: D1Database, payment: VerifiedContribution): Promise<void> {
  const shareBps = payment.developerShareBasisPoints ?? 0;
  if (!Number.isSafeInteger(payment.grossMicros) || !Number.isSafeInteger(payment.feeMicros) ||
      payment.grossMicros <= 0 || payment.grossMicros > 1_000_000_000 || payment.feeMicros < 0 ||
      payment.feeMicros >= payment.grossMicros || !payment.transactionID || payment.transactionID.length > 255 ||
      !Number.isInteger(shareBps) || shareBps < 0 || shareBps > 300) {
    throw new APIError(400, "invalid_contribution");
  }
  // Round to the nearest cent using integer arithmetic, matching the amount shown in the wizard.
  const developerMicros = Math.floor((payment.grossMicros * shareBps + 50_000_000) / 100_000_000) * 10_000;
  if (developerMicros > payment.grossMicros - payment.feeMicros) throw new APIError(400, "invalid_contribution");
  const now = Date.now();
  const result = await db.batch([
    db.prepare(`INSERT INTO contributions(id, provider, transaction_id, user_id, gross_micros, fee_micros, net_micros,
      developer_share_bps, developer_share_micros, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT(provider, transaction_id) DO NOTHING`)
      .bind(crypto.randomUUID(), payment.provider, payment.transactionID, payment.userID, payment.grossMicros, payment.feeMicros,
        payment.grossMicros - payment.feeMicros, shareBps, developerMicros, now, now),
    db.prepare("SELECT user_id, gross_micros, fee_micros, developer_share_bps FROM contributions WHERE provider = ? AND transaction_id = ?")
      .bind(payment.provider, payment.transactionID),
  ]);
  const row = result[1]?.results[0] as { user_id: string; gross_micros: number; fee_micros: number; developer_share_bps: number } | undefined;
  if (row?.user_id !== payment.userID || row?.gross_micros !== payment.grossMicros || row?.fee_micros !== payment.feeMicros ||
      row?.developer_share_bps !== shareBps) {
    throw new APIError(409, "contribution_conflict");
  }
}

export async function reverseContribution(db: D1Database, provider: VerifiedContribution["provider"], transactionID: string): Promise<void> {
  // A refunded, already-spent contribution creates a negative balance, preventing further funded use.
  const now = Date.now();
  await db.batch([
    db.prepare("INSERT INTO contribution_reversals(provider, transaction_id, created_at) VALUES (?, ?, ?) ON CONFLICT DO NOTHING")
      .bind(provider, transactionID, now),
    db.prepare("UPDATE contributions SET status = 'reversed', updated_at = ? WHERE provider = ? AND transaction_id = ? AND status = 'credited'")
      .bind(now, provider, transactionID),
  ]);
}
