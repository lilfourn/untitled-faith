import { APIError } from "./http";
import { parseFirstName } from "./account-profile";

export type Account = { id: string; app_account_token: string; paid_balance_micros: number; paid_reserved_micros: number; first_name: string | null };

export async function accountForIdentity(db: D1Database, identityHash: string, firstName?: string | null): Promise<Account> {
  const name = parseFirstName(firstName);
  const results = await db.batch([
    db.prepare(`INSERT INTO users(id, identity_hash, app_account_token, created_at, first_name) VALUES (?, ?, ?, ?, ?)
      ON CONFLICT(identity_hash) DO UPDATE SET first_name = COALESCE(excluded.first_name, users.first_name)`)
      .bind(crypto.randomUUID(), identityHash, crypto.randomUUID(), Date.now(), name),
    db.prepare("SELECT id, app_account_token, paid_balance_micros, paid_reserved_micros, first_name FROM users WHERE identity_hash = ?").bind(identityHash),
  ]);
  const account = results[1]?.results[0] as Account | undefined;
  if (!account) throw new APIError(503, "account_unavailable");
  return account;
}

export async function requireAccount(db: D1Database, id: string, allowDeleting = false): Promise<Account> {
  const account = await db.prepare("SELECT id, app_account_token, paid_balance_micros, paid_reserved_micros, first_name FROM users WHERE id = ? AND (deleting_at IS NULL OR ?)")
    .bind(id, allowDeleting ? 1 : 0).first<Account>();
  if (!account) throw new APIError(401, "unauthorized");
  return account;
}

export async function beginAccountDeletion(db: D1Database, id: string): Promise<boolean> {
  const result = await db.prepare(`UPDATE users SET deleting_at = COALESCE(deleting_at, ?) WHERE id = ? AND paid_balance_micros <= 0
    AND paid_reserved_micros = 0 AND NOT EXISTS
    (SELECT 1 FROM usage_requests WHERE user_id = ? AND status IN ('reserved', 'uncertain')) AND NOT EXISTS
    (SELECT 1 FROM checkout_intents WHERE user_id = ? AND status IN ('creating', 'open')) AND NOT EXISTS
    (SELECT 1 FROM stripe_payments WHERE user_id = ? AND (fee_confirmed = 0 OR dispute_open = 1)) RETURNING id`)
    .bind(Date.now(), id, id, id, id).first();
  if (result) return true;
  if (!await db.prepare("SELECT id FROM users WHERE id = ?").bind(id).first()) return false;
  throw new APIError(409, "account_has_unsettled_funding");
}

export async function cancelAccountDeletion(db: D1Database, id: string): Promise<void> {
  await db.prepare("UPDATE users SET deleting_at = NULL WHERE id = ?").bind(id).run();
}

export async function deleteAccountData(db: D1Database, id: string): Promise<void> {
  // Financial records remain unlinked for accounting; no prompts or answers exist in the database.
  const result = await db.prepare(`DELETE FROM users WHERE id = ? AND paid_balance_micros <= 0
    AND paid_reserved_micros = 0 AND NOT EXISTS
    (SELECT 1 FROM usage_requests WHERE user_id = ? AND status IN ('reserved', 'uncertain')) AND NOT EXISTS
    (SELECT 1 FROM checkout_intents WHERE user_id = ? AND status IN ('creating', 'open')) AND NOT EXISTS
    (SELECT 1 FROM stripe_payments WHERE user_id = ? AND (fee_confirmed = 0 OR dispute_open = 1)) RETURNING id`)
    .bind(id, id, id, id).first();
  if (!result && await db.prepare("SELECT id FROM users WHERE id = ?").bind(id).first()) {
    throw new APIError(409, "account_has_unsettled_funding");
  }
}

/** Resume database cleanup after Apple revocation was durably confirmed. */
export async function finishAccountDeletions(db: D1Database): Promise<void> {
  const overdue = await db.prepare("SELECT COUNT(*) AS count FROM users WHERE deleting_at < ?")
    .bind(Date.now() - 24 * 60 * 60 * 1000).first<{ count: number }>();
  if (overdue?.count) console.error(JSON.stringify({ event: "deletion_recovery_required", count: overdue.count }));
  const pending = await db.prepare("SELECT id FROM users WHERE deleting_at IS NOT NULL AND apple_revoked_at IS NOT NULL LIMIT 20")
    .all<{ id: string }>();
  let finished = 0;
  for (const account of pending.results) {
    try { await deleteAccountData(db, account.id); finished++; }
    catch { console.error(JSON.stringify({ event: "account_deletion_pending" })); }
  }
  if (pending.results.length) console.log(JSON.stringify({ event: "account_deletions_recovered", finished }));
}
