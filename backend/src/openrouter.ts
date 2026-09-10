import { answerSystemPrompt } from "./answer-prompt";
import { MAX_MODERATED_CONTENT_LENGTH, MODERATED_RESPONSE_FORMAT, moderatedAnswer } from "./content-policy";
import type { Message } from "./contract";
import { APIError, isRecord, readJSON } from "./http";
import { cashCostMicros, MAX_INPUT_PRICE, MAX_OUTPUT_PRICE, MAX_OUTPUT_TOKENS } from "./billing-policy";
import type { InferenceUsage } from "./usage";
import { WEB_SEARCH_TOOL, SEARCH_CALLS } from "./web-search";
import { SourceValidationError, AnswerSources, type AnswerSource, type AnswerQuote } from "./answer-sources";
import { biblePrompt, retrieveBible } from "./bible/context";
import type { BibleContext } from "./bible/types";

export class InferenceError extends APIError {
  constructor(status: number, code: string, readonly accounting: InferenceUsage | "unbilled" | "uncertain", readonly generationID?: string) {
    super(status, code);
  }
}

export type AnswerGeneration = { text: string; usage: InferenceUsage; sources?: AnswerSource[]; quotes?: AnswerQuote[] };

// Product decision: only the server controls the model. No automatic model fallback.
const MODEL = "google/gemini-3.8-flash";

export async function generateAnswer(messages: Message[], apiKey: string, userID: string, signal: AbortSignal,
  firstName: string | null = null, bibleContext: BibleContext = retrieveBible(messages), relevanceVerified = false): Promise<AnswerGeneration> {
  let generationID: string | undefined;
  let accounting: InferenceUsage | "uncertain" = "uncertain";
  let stage = "request";
  let upstreamStatus: number | undefined;
  let upstreamErrorCode: number | undefined;
  try {
    const response = await requestCompletion(messages, apiKey, userID, signal, false, bibleContext, firstName, relevanceVerified);
    upstreamStatus = response.status;
    stage = "http_status";
    if (!response.ok) {
      await response.body?.cancel();
      throw new InferenceError(response.status === 429 ? 429 : 502, "answer_unavailable",
        ((response.status >= 300 && response.status < 400) || [400, 401, 402, 403, 404, 413, 422, 429].includes(response.status)) ? "unbilled" : "uncertain");
    }
    stage = "read_json";
    const value = await readJSON(response.body, 128 * 1024);
    stage = "validate_completion";
    if (isRecord(value) && isRecord(value.error) && typeof value.error.code === "number") upstreamErrorCode = value.error.code;
    generationID = isRecord(value) && typeof value.id === "string" ? value.id.slice(0, 255) : undefined;
    const usage = isRecord(value) && isRecord(value.usage) ? value.usage : undefined;
    if (usage && typeof usage.cost === "number" && typeof usage.prompt_tokens === "number" &&
        typeof usage.completion_tokens === "number" && Number.isSafeInteger(usage.prompt_tokens) &&
        Number.isSafeInteger(usage.completion_tokens) && usage.prompt_tokens >= 0 && usage.completion_tokens >= 0) {
      accounting = { costMicros: cashCostMicros(usage.cost), promptTokens: usage.prompt_tokens,
        completionTokens: usage.completion_tokens, generationID };
    }
    const choice = isRecord(value) && Array.isArray(value.choices) ? value.choices[0] : undefined;
    const message = isRecord(choice) && isRecord(choice.message) ? choice.message : undefined;
    // An HTTP 200 can still contain an upstream error, refusal, or truncated completion.
    if (!isRecord(value) || value.error || !isRecord(choice) || choice.finish_reason !== "stop" ||
        typeof message?.content !== "string" || !message.content.trim() || message.content.length > MAX_MODERATED_CONTENT_LENGTH) {
      throw new APIError(502, "answer_unavailable");
    }
    if (accounting === "uncertain") throw new InferenceError(502, "answer_unavailable", accounting, generationID);
    const sources = new AnswerSources();
    sources.addBible(bibleContext.passages);
    sources.add(message.annotations);
    stage = "moderation";
    const result = moderatedAnswer(message.content);
    stage = "sources";
    return { text: result.text, usage: accounting, ...(result.generated ? sources.finish(result.text) : {}) };
  } catch (error) {
    const failureText = error instanceof Error ? error.message : "";
    const failureKind = /redirect/i.test(failureText) ? "redirect" : /header/i.test(failureText) ? "headers"
      : /signal|abort/i.test(failureText) ? "signal" : /fetch|network|connect/i.test(failureText) ? "network" : "other";
    console.log(JSON.stringify({ event: "inference_failed", stage, upstreamStatus, upstreamErrorCode,
      sourceFailure: error instanceof SourceValidationError ? error.reason : undefined,
      errorType: error instanceof Error ? error.name : "unknown", failureKind,
      keyHasControlCharacters: /[\r\n]/.test(apiKey) }));
    if (error instanceof InferenceError) throw error;
    if (signal.aborted) throw new InferenceError(504, "answer_timeout", accounting, generationID);
    // Never return provider bodies, credentials, routing information, or model metadata.
    throw new InferenceError(502, "answer_unavailable", accounting, generationID);
  }
}

export function requestCompletion(messages: Message[], apiKey: string, userID: string, signal: AbortSignal, stream: boolean,
  bibleContext: BibleContext = retrieveBible(messages), firstName: string | null = null, relevanceVerified = false): Promise<Response> {
  return fetch("https://openrouter.ai/api/v1/chat/completions", {
      method: "POST",
      // Workerd's deployed fetch rejects redirect:"error". Manual never follows a redirect or forwards credentials.
      redirect: "manual",
      signal,
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
        "X-OpenRouter-Title": "Untitled Faith",
      },
      body: JSON.stringify({
        model: MODEL,
        // The subject must be an opaque app account ID, never an Apple ID or email.
        user: userID,
        messages: [{ role: "system", content: answerSystemPrompt(firstName) + (relevanceVerified ? '\nAn independent request reviewer has approved the latest request as relevant in this conversation. Answer its faith or pastoral aspect, or ask a brief clarifying question if needed. Do not reclassify a respectful interfaith question as off_topic. Continue enforcing all safety and source requirements on your answer.' : '') + '\n\n' + biblePrompt(bibleContext) }, ...messages],
        provider: { only: ["google-ai-studio", "google-vertex"], data_collection: "deny", require_parameters: true,
          max_price: { prompt: MAX_INPUT_PRICE, completion: MAX_OUTPUT_PRICE, request: 0 } },
        response_format: MODERATED_RESPONSE_FORMAT,
        // Leave room for the checked answer inside the existing completion cap.
        reasoning: { effort: "low", exclude: true },
        tools: [WEB_SEARCH_TOOL],
        max_tool_calls: SEARCH_CALLS,
        stream,
        ...(stream ? { stream_options: { include_usage: true } } : {}),
        max_tokens: MAX_OUTPUT_TOKENS,
      }),
    });
}
