import { cashCostMicros } from "./billing-policy";
import { isRecord, readJSON } from "./http";
import { settleUsage } from "./usage";

export async function reconcileUsage(db: D1Database, apiKey: string, now = Date.now()): Promise<void> {
  // Crashed requests retain their funds but must not leave the account permanently "in progress".
  await db.prepare("UPDATE usage_requests SET status = 'uncertain' WHERE status = 'reserved' AND updated_at < ?")
    .bind(now - 5 * 60 * 1000).run();
  const pending = await db.prepare(`SELECT id, generation_id FROM usage_requests
    WHERE status = 'uncertain' AND generation_id IS NOT NULL ORDER BY updated_at LIMIT 20`)
    .all<{ id: string; generation_id: string }>();
  const results = await Promise.all(pending.results.map(async row => {
    try {
      await db.prepare("UPDATE usage_requests SET updated_at = ? WHERE id = ? AND status = 'uncertain'").bind(now, row.id).run();
      const url = new URL("https://openrouter.ai/api/v1/generation");
      url.searchParams.set("id", row.generation_id);
      const response = await fetch(url, { headers: { Authorization: `Bearer ${apiKey}` }, redirect: "manual", signal: AbortSignal.timeout(10000) });
      if (!response.ok) { await response.body?.cancel(); return false; }
      const body = await readJSON(response.body, 32 * 1024);
      const value = isRecord(body) && isRecord(body.data) ? body.data : undefined;
      if (!value || value.id !== row.generation_id || typeof value.finish_reason !== "string" ||
          typeof value.total_cost !== "number" || typeof value.native_tokens_prompt !== "number" ||
          typeof value.native_tokens_completion !== "number") return false;
      await settleUsage(db, row.id, { costMicros: cashCostMicros(value.total_cost), promptTokens: value.native_tokens_prompt,
        completionTokens: value.native_tokens_completion, generationID: row.generation_id });
      return true;
    } catch { return false; } // Retain funds and retry; missing metadata is not evidence of zero cost.
  }));
  console.log(JSON.stringify({ event: "usage_reconciled", checked: results.length, settled: results.filter(Boolean).length }));
}
