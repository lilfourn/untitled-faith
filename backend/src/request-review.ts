import { POLICY_RESPONSES } from './content-policy';
import type { Message } from './contract';
import { isRecord, readJSON } from './http';
import { cashCostMicros } from './billing-policy';
import { InferenceError, type AnswerGeneration } from './openrouter';
import type { InferenceUsage } from './usage';

export { REVIEW_MODEL, type ReviewDecision } from './review-policy';
import { REVIEW_MODEL, REVIEW_INPUT_PRICE, REVIEW_OUTPUT_PRICE, REVIEW_MAX_TOKENS, REVIEW_PROMPT, REVIEW_FORMAT, type ReviewDecision } from './review-policy';

export function parseReview(content: unknown): ReviewDecision {
  // A single enum needs no JSON repair. Anchoring also rejects duplicate fields.
  const match = typeof content === 'string' && /^\s*\{\s*"decision"\s*:\s*"(answer|off_topic|unsafe|crisis)"\s*\}\s*$/.exec(content);
  if (!match) throw new Error('Invalid review');
  return match[1] as ReviewDecision;
}

export async function reviewRequest(messages: Message[], apiKey: string, userID: string, signal: AbortSignal,
  onGeneration: (id: string) => Promise<void> = async () => {}): Promise<{ decision: ReviewDecision; usage: InferenceUsage }> {
  let accounting: InferenceUsage | 'uncertain' = 'uncertain';
  let generationID: string | undefined;
  try {
    signal.throwIfAborted();
    const response = await fetch('https://openrouter.ai/api/v1/chat/completions', {
      method: 'POST', redirect: 'manual', signal,
      headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json', 'X-OpenRouter-Title': 'Untitled Faith' },
      body: JSON.stringify({ model: REVIEW_MODEL, user: userID,
        messages: [{ role: 'system', content: REVIEW_PROMPT }, ...messages],
        provider: { only: ['google-ai-studio', 'google-vertex'], data_collection: 'deny', require_parameters: true,
          max_price: { prompt: REVIEW_INPUT_PRICE, completion: REVIEW_OUTPUT_PRICE, request: 0 } },
        response_format: REVIEW_FORMAT, reasoning: { enabled: false }, temperature: 0,
        max_tokens: REVIEW_MAX_TOKENS, stream: false,
      }),
    });
    if (!response.ok) {
      await response.body?.cancel();
      throw new InferenceError(response.status === 429 ? 429 : 502, 'answer_unavailable',
        (response.status >= 300 && response.status < 400) || [400, 401, 402, 403, 404, 413, 422, 429].includes(response.status) ? 'unbilled' : 'uncertain');
    }
    const value = await readJSON(response.body, 32 * 1024);
    generationID = isRecord(value) && typeof value.id === 'string' ? value.id.slice(0, 255) : undefined;
    if (generationID) await onGeneration(generationID);
    const usage = isRecord(value) && isRecord(value.usage) ? value.usage : undefined;
    if (usage && typeof usage.cost === 'number' && typeof usage.prompt_tokens === 'number' &&
        typeof usage.completion_tokens === 'number' && Number.isSafeInteger(usage.prompt_tokens) && usage.prompt_tokens >= 0 &&
        Number.isSafeInteger(usage.completion_tokens) && usage.completion_tokens >= 0) {
      accounting = { costMicros: cashCostMicros(usage.cost), promptTokens: usage.prompt_tokens,
        completionTokens: usage.completion_tokens, generationID };
    }
    const choice = isRecord(value) && Array.isArray(value.choices) ? value.choices[0] : undefined;
    if (!isRecord(value) || value.error || !isRecord(choice) || choice.finish_reason !== 'stop' ||
        !isRecord(choice.message) || accounting === 'uncertain') throw new Error('Incomplete review');
    return { decision: parseReview(choice.message.content), usage: accounting };
  } catch (error) {
    if (error instanceof InferenceError) throw error;
    throw new InferenceError(signal.aborted ? 504 : 502, signal.aborted ? 'answer_timeout' : 'answer_unavailable', accounting, generationID);
  }
}

export async function reviewedAnswer(db: D1Database, reservationID: string, messages: Message[], apiKey: string,
  userID: string, signal: AbortSignal, generate: () => Promise<AnswerGeneration>): Promise<AnswerGeneration> {
  const review = await reviewRequest(messages, apiKey, userID, signal, async id => {
    await db.prepare("UPDATE usage_requests SET generation_id = ? WHERE id = ? AND status = 'reserved'").bind(id, reservationID).run();
  });
  if (review.decision !== 'answer') return { text: POLICY_RESPONSES[review.decision], usage: review.usage };
  // Checkpoint the first call before starting another. Settlement and reconciliation
  // add these costs exactly once; generation_id now belongs to the answer call.
  await db.prepare(`UPDATE usage_requests SET review_cost_micros = ?, review_prompt_tokens = ?,
    review_completion_tokens = ?, generation_id = NULL, updated_at = ? WHERE id = ? AND status = 'reserved'`)
    .bind(review.usage.costMicros, review.usage.promptTokens, review.usage.completionTokens, Date.now(), reservationID).run();
  if (signal.aborted) throw new InferenceError(504, 'answer_timeout', { costMicros: 0, promptTokens: 0, completionTokens: 0 });
  return generate();
}
