import { requireAccount } from "./accounts";
import { billingPeriod, FREE_MONTHLY_CASH_MICROS, FREE_MONTHLY_QUESTIONS } from "./billing-policy";
import { APIError } from "./http";

export type Reservation = { id: string; funding: "free" | "paid"; reservedMicros: number };
export type InferenceUsage = { costMicros: number; promptTokens: number; completionTokens: number; generationID?: string };

const databaseErrors = ["account_missing", "request_already_processed", "request_in_progress", "free_allowance_exhausted", "free_pool_exhausted", "insufficient_funding"];
function errorCode(error: unknown): string | undefined {
  const message = error instanceof Error ? `${error.message} ${String(error.cause ?? "")}` : "";
  return databaseErrors.find(code => message.includes(code));
}

export async function reserveUsage(db: D1Database, userID: string, key: string, amount: number, now = new Date()): Promise<Reservation> {
  const { month, day } = billingPeriod(now);
  await db.prepare("INSERT INTO free_months(month, budget_micros) VALUES (?, ?) ON CONFLICT(month) DO NOTHING")
    .bind(month, FREE_MONTHLY_CASH_MICROS).run();
  const id = crypto.randomUUID();
  let freeFailure: string | undefined;
  for (const funding of ["free", "paid"] as const) {
    try {
      // free_daily_limit is retained as legacy ledger data, no longer enforced by the trigger.
      await db.prepare(`INSERT INTO usage_requests
        (id, user_id, idempotency_key, month, day, created_at, updated_at, funding, reserved_micros, free_daily_limit, free_monthly_limit, inference_stage)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'reserved')`).bind(id, userID, key, month, day, now.getTime(), now.getTime(),
        funding, amount, 0, FREE_MONTHLY_QUESTIONS).run();
      return { id, funding, reservedMicros: amount };
    } catch (error) {
      const code = errorCode(error);
      if (funding === "free" && (code === "free_allowance_exhausted" || code === "free_pool_exhausted")) {
        freeFailure = code;
        continue;
      }
      if (code === "insufficient_funding" && freeFailure) {
        if (freeFailure === "free_pool_exhausted") throw new APIError(402, "free_pool_exhausted");
        throw new APIError(402, "monthly_free_limit");
      }
      if (code) throw new APIError(code === "account_missing" ? 401 : code === "insufficient_funding" ? 402 : 409, code);
      throw error;
    }
  }
  throw new APIError(402, "insufficient_funding");
}

export async function settleUsage(db: D1Database, id: string, usage: InferenceUsage): Promise<void> {
  for (const value of [usage.costMicros, usage.promptTokens, usage.completionTokens]) {
    if (!Number.isSafeInteger(value) || value < 0) throw new Error("Invalid usage accounting");
  }
  await db.prepare(`UPDATE usage_requests SET status = 'settled', cost_micros = ? + review_cost_micros, prompt_tokens = ? + review_prompt_tokens,
    completion_tokens = ? + review_completion_tokens, generation_id = ?, updated_at = ?, needs_review_at = NULL, reconciliation_error = NULL WHERE id = ? AND status IN ('reserved', 'uncertain')`)
    .bind(usage.costMicros, usage.promptTokens, usage.completionTokens, usage.generationID ?? null, Date.now(), id).run();
}

export async function releaseUsage(db: D1Database, id: string): Promise<void> {
  const review = await db.prepare("SELECT review_cost_micros, review_prompt_tokens FROM usage_requests WHERE id = ?").bind(id)
    .first<{ review_cost_micros: number; review_prompt_tokens: number }>();
  if (review && (review.review_cost_micros > 0 || review.review_prompt_tokens > 0)) {
    await settleUsage(db, id, { costMicros: 0, promptTokens: 0, completionTokens: 0 });
    return;
  }
  await db.prepare("UPDATE usage_requests SET status = 'released', updated_at = ? WHERE id = ? AND status = 'reserved'")
    .bind(Date.now(), id).run();
}

export async function holdUncertainUsage(db: D1Database, id: string, generationID?: string): Promise<void> {
  // A timeout is not proof that inference was free. Hold funds until provider reconciliation.
  await db.prepare("UPDATE usage_requests SET status = 'uncertain', generation_id = COALESCE(?, generation_id), updated_at = ? WHERE id = ? AND status = 'reserved'")
    .bind(generationID ?? null, Date.now(), id).run();
}

export async function usageSummary(db: D1Database, userID: string, now = new Date()) {
  const account = await requireAccount(db, userID);
  const { month, day, resetsAt } = billingPeriod(now);
  const counts = await db.prepare(`SELECT
    COUNT(*) AS total_requests,
    COALESCE(SUM(funding = 'free' AND status != 'released'), 0) AS free_used,
    COALESCE(SUM(funding = 'free' AND status != 'released' AND day = ?), 0) AS free_used_today,
    COALESCE(SUM(prompt_tokens), 0) AS prompt_tokens,
    COALESCE(SUM(completion_tokens), 0) AS completion_tokens,
    COALESCE(SUM(cost_micros), 0) AS cost_micros
    FROM usage_requests WHERE user_id = ? AND month = ?`).bind(day, userID, month).first<Record<string, number>>();
  // Outstanding holds survive a month boundary and can still block deletion.
  const recovery = await db.prepare(`SELECT COUNT(*) AS pending,
    COALESCE(SUM(needs_review_at IS NOT NULL), 0) AS needs_review FROM usage_requests
    WHERE user_id = ? AND status IN ('reserved', 'uncertain')`).bind(userID).first<{ pending: number; needs_review: number }>();
  const monthStart = new Date(`${month}-01T00:00:00Z`).getTime();
  const funds = await db.prepare(`SELECT
    COALESCE(SUM(CASE WHEN created_at < ? THEN delta_micros ELSE 0 END), 0) AS opening,
    COALESCE(SUM(CASE WHEN created_at >= ? AND kind IN ('contribution', 'refund') THEN delta_micros ELSE 0 END), 0) AS added
    FROM wallet_entries WHERE user_id = ?`).bind(monthStart, monthStart, userID).first<{ opening: number; added: number }>();
  // Display-only normalization: each free question has the 2-cent planning value plus the credit fee.
  // Enforcement still uses exact free counters and actual funded costs, never this percentage.
  const freeDisplayValue = 21_100;
  const remainingFree = Math.max(0, FREE_MONTHLY_QUESTIONS - (counts?.free_used ?? 0));
  const displayCapacity = FREE_MONTHLY_QUESTIONS * freeDisplayValue + Math.max(0, (funds?.opening ?? 0) + (funds?.added ?? 0));
  const displayRemaining = remainingFree * freeDisplayValue + Math.max(0, account.paid_balance_micros - account.paid_reserved_micros);
  const remainingPercent = Math.max(0, Math.min(100, Math.floor(displayRemaining * 100 / displayCapacity)));
  return { month, resetsAt, remainingPercent, currency: "USD", appAccountToken: account.app_account_token,
    // Legacy clients still decode daily fields. Their available-today value now equals
    // the whole remaining month; these fields impose no separate daily restriction.
    free: { dailyLimit: FREE_MONTHLY_QUESTIONS, monthlyLimit: FREE_MONTHLY_QUESTIONS,
      resetsAt,
      usedToday: counts?.free_used_today ?? 0, usedThisMonth: counts?.free_used ?? 0,
      remainingToday: remainingFree,
      remainingThisMonth: remainingFree },
    funding: { balanceMicros: account.paid_balance_micros, reservedMicros: account.paid_reserved_micros,
      availableMicros: Math.max(0, account.paid_balance_micros - account.paid_reserved_micros) },
    usage: { totalRequests: counts?.total_requests ?? 0, pendingRequests: recovery?.pending ?? 0, requestsNeedingReview: recovery?.needs_review ?? 0,
      promptTokens: counts?.prompt_tokens ?? 0, completionTokens: counts?.completion_tokens ?? 0,
      costMicros: counts?.cost_micros ?? 0 } };
}
