import { cashCostMicros } from "./billing-policy";
import { isRecord, readJSON } from "./http";
import { settleUsage } from "./usage";

type PendingUsage = { id: string; generation_id: string | null };

export async function reconcileUsage(db: D1Database, apiKey: string, now = Date.now()): Promise<void> {
  // Only a durable pre-dispatch checkpoint proves that no provider call started.
  await db.prepare(`UPDATE usage_requests SET status = 'released', updated_at = ?
    WHERE status = 'reserved' AND inference_stage = 'reserved' AND generation_id IS NULL
      AND review_cost_micros = 0 AND updated_at < ?`).bind(now, now - 5 * 60 * 1000).run();
  await db.prepare("UPDATE usage_requests SET status = 'uncertain' WHERE status = 'reserved' AND updated_at < ?")
    .bind(now - 5 * 60 * 1000).run();
  const pending = await db.prepare(`SELECT id, generation_id FROM usage_requests
    WHERE status = 'uncertain' ORDER BY updated_at LIMIT 20`).all<PendingUsage>();
  const results = await Promise.all(pending.results.map(async row => {
    let failure = row.generation_id ? "provider_unavailable" : "missing_generation_id";
    try {
      await db.prepare(`UPDATE usage_requests SET updated_at = ?, reconciliation_attempts = reconciliation_attempts + 1
        WHERE id = ? AND status = 'uncertain'`).bind(now, row.id).run();
      if (row.generation_id) {
        const url = new URL("https://openrouter.ai/api/v1/generation");
        url.searchParams.set("id", row.generation_id);
        const response = await fetch(url, { headers: { Authorization: `Bearer ${apiKey}` }, redirect: "manual", signal: AbortSignal.timeout(10000) });
        if (!response.ok) {
          failure = `provider_http_${response.status}`;
          await response.body?.cancel();
        } else {
          const body = await readJSON(response.body, 32 * 1024);
          const value = isRecord(body) && isRecord(body.data) ? body.data : undefined;
          failure = "invalid_metadata";
          if (value && value.id === row.generation_id && typeof value.finish_reason === "string" &&
              typeof value.total_cost === "number" && typeof value.native_tokens_prompt === "number" &&
              typeof value.native_tokens_completion === "number") {
            await settleUsage(db, row.id, { costMicros: cashCostMicros(value.total_cost), promptTokens: value.native_tokens_prompt,
              completionTokens: value.native_tokens_completion, generationID: row.generation_id });
            return true;
          }
        }
      }
    } catch { /* Retain funds; a timeout or database failure is not evidence of zero cost. */ }
    await db.prepare("UPDATE usage_requests SET reconciliation_error = ? WHERE id = ? AND status = 'uncertain'")
      .bind(failure, row.id).run();
    return false;
  }));
  // Age is measured from creation, not the moving last-attempt timestamp.
  await db.prepare(`UPDATE usage_requests SET needs_review_at = COALESCE(needs_review_at, ?)
    WHERE status = 'uncertain' AND (created_at <= ? OR reconciliation_attempts >= 8)`)
    .bind(now, now - 24 * 60 * 60 * 1000).run();
  const review = await db.prepare(`SELECT COUNT(*) AS count, MIN(created_at) AS oldest
    FROM usage_requests WHERE status = 'uncertain' AND needs_review_at IS NOT NULL`).first<{ count: number; oldest: number | null }>();
  if (review?.count) console.error(JSON.stringify({ event: "usage_recovery_required", count: review.count,
    oldestAgeMS: now - (review.oldest ?? now) }));
  console.log(JSON.stringify({ event: "usage_reconciled", checked: results.length, settled: results.filter(Boolean).length }));
}
