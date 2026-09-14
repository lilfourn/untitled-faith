import { REVIEW_PROMPT, REVIEW_FORMAT, REVIEW_INPUT_PRICE, REVIEW_OUTPUT_PRICE, REVIEW_MAX_TOKENS } from './review-policy';
import { answerSystemPrompt } from "./answer-prompt";
import { MODERATED_RESPONSE_FORMAT } from "./content-policy";
import type { Message } from "./contract";
import { SEARCH_CALLS, SEARCH_RESULTS, SEARCH_CHARACTERS, SEARCH_COST_USD } from "./web-search";
import { biblePrompt, retrieveBible } from "./bible/context";
import type { BibleContext } from "./bible/types";

export const FREE_MONTHLY_QUESTIONS = 30;
// $60 in inference credits plus their 5.5% acquisition fee; preserves the owner's $100 total plan.
export const FREE_MONTHLY_CASH_MICROS = 63_300_000;
export const MAX_OUTPUT_TOKENS = 2048;
export const MAX_INPUT_PRICE = 3; // USD per million tokens; enforced in provider routing.
export const MAX_OUTPUT_PRICE = 15;

export function cashCostMicros(inferenceUSD: number): number {
  if (!Number.isFinite(inferenceUSD) || inferenceUSD < 0 || inferenceUSD > 100) throw new Error("Invalid inference cost");
  return Math.ceil(inferenceUSD * 1_000_000 * 1.055);
}

export function reservationMicros(messages: Message[], firstName: string | null = null,
  bibleContext: BibleContext = retrieveBible(messages)): number {
  // Deliberately conservative byte-based token estimate plus system/framing allowance.
  // The server also caps the actual request body at 1 MiB. Actual cost is reconciled after inference.
  const bytes = new TextEncoder().encode(JSON.stringify(messages) + answerSystemPrompt(firstName) +
    biblePrompt(bibleContext) + JSON.stringify(MODERATED_RESPONSE_FORMAT)).byteLength + 4096;
  // Reserve for tool selection and synthesis, retrieved UTF-8 excerpts, and the search fee.
  // usage.cost already includes search charges; settlement must not add that fee again.
  const rounds = SEARCH_CALLS + 2;
  const searchBytes = SEARCH_RESULTS * (SEARCH_CHARACTERS * 4 + 4096);
  const reviewBytes = new TextEncoder().encode(JSON.stringify(messages) + REVIEW_PROMPT + JSON.stringify(REVIEW_FORMAT)).byteLength + 4096;
  // Both primary and fallback routes fit these caps; an HTTP 429 rejection is unbilled.
  const reviewCost = (reviewBytes * REVIEW_INPUT_PRICE + REVIEW_MAX_TOKENS * REVIEW_OUTPUT_PRICE) / 1_000_000;
  return cashCostMicros(((bytes * rounds + searchBytes) * MAX_INPUT_PRICE +
    MAX_OUTPUT_TOKENS * rounds * MAX_OUTPUT_PRICE) / 1_000_000 + SEARCH_COST_USD * SEARCH_CALLS) + cashCostMicros(reviewCost);
}

export function billingPeriod(now = new Date()) {
  return { month: now.toISOString().slice(0, 7), day: now.toISOString().slice(0, 10),
    resetsAt: new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() + 1, 1)).toISOString() };
}
