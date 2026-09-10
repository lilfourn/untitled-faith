import { MAX_MODERATED_CONTENT_LENGTH, moderatedAnswer } from './content-policy';
import type { Message } from './contract';
import { isRecord } from './http';
import { cashCostMicros } from './billing-policy';
import { InferenceError, requestCompletion, type AnswerGeneration } from './openrouter';
import type { InferenceUsage } from './usage';
import { sseData } from './sse';
import { SourceValidationError, AnswerSources } from './answer-sources';
import { retrieveBible } from './bible/context';
import type { BibleContext } from './bible/types';

export async function streamAnswer(messages: Message[], apiKey: string, userID: string, signal: AbortSignal,
  onGeneration: (id: string) => Promise<void>, firstName: string | null = null,
  bibleContext: BibleContext = retrieveBible(messages), relevanceVerified = false): Promise<AnswerGeneration> {
  let generationID: string | undefined;
  let accounting: InferenceUsage | 'uncertain' = 'uncertain';
  let text = '';
  const sources = new AnswerSources();
  sources.addBible(bibleContext.passages);
  let finish: unknown;
  let done = false;
  let stage = 'request';
  try {
    const response = await requestCompletion(messages, apiKey, userID, signal, true, bibleContext, firstName, relevanceVerified);
    if (!response.ok) {
      await response.body?.cancel();
      throw new InferenceError(response.status === 429 ? 429 : 502, 'answer_unavailable',
        [400, 401, 402, 403, 404, 413, 422, 429].includes(response.status) ? 'unbilled' : 'uncertain');
    }
    if (!response.body) throw new Error('Missing stream');
    const headerID = response.headers.get('X-Generation-Id');
    if (headerID) { generationID = headerID.slice(0, 255); await onGeneration(generationID); }
    stage = 'stream';
    for await (const data of sseData(response.body, signal)) {
      if (data === '[DONE]') { done = true; break; }
      const value: unknown = JSON.parse(data);
      if (!isRecord(value)) throw new Error('Invalid chunk');
      if (!generationID && typeof value.id === 'string') {
        generationID = value.id.slice(0, 255);
        await onGeneration(generationID);
      }
      const usage = isRecord(value.usage) ? value.usage : undefined;
      if (usage && typeof usage.cost === 'number' && typeof usage.prompt_tokens === 'number' &&
          typeof usage.completion_tokens === 'number' && Number.isSafeInteger(usage.prompt_tokens) &&
          Number.isSafeInteger(usage.completion_tokens) && usage.prompt_tokens >= 0 && usage.completion_tokens >= 0) {
        accounting = { costMicros: cashCostMicros(usage.cost), promptTokens: usage.prompt_tokens,
          completionTokens: usage.completion_tokens, generationID };
      }
      if (value.error) throw new Error('Upstream error');
      const choice = Array.isArray(value.choices) ? value.choices[0] : undefined;
      if (isRecord(choice)) {
        if (isRecord(choice.delta)) sources.add(choice.delta.annotations);
        if (isRecord(choice.message)) sources.add(choice.message.annotations);
        const content = isRecord(choice.delta) ? choice.delta.content : undefined;
        if (content != null && typeof content !== 'string') throw new Error('Invalid text');
        if (typeof content === 'string' && content) {
          if (finish != null || text.length + content.length > MAX_MODERATED_CONTENT_LENGTH) throw new Error('Invalid completion');
          text += content;
        }
        // OpenRouter can repeat the finish reason on its final usage frame.
        if (choice.finish_reason != null) {
          if (finish != null && finish !== choice.finish_reason) throw new Error('Conflicting finish reason');
          finish = choice.finish_reason;
        }
      }
    }
    if (!done || finish !== 'stop' || !text.trim() || accounting === 'uncertain') throw new Error('Incomplete stream');
    stage = 'moderation';
    const result = moderatedAnswer(text);
    stage = 'sources';
    return { text: result.text, usage: accounting, ...(result.generated ? sources.finish(result.text) : {}) };
  } catch (error) {
    console.log(JSON.stringify({ event: 'inference_failed', stage,
      sourceFailure: error instanceof SourceValidationError ? error.reason : undefined,
      errorType: error instanceof Error ? error.name : 'unknown' }));
    if (error instanceof InferenceError) throw error;
    throw new InferenceError(signal.aborted ? 504 : 502, signal.aborted ? 'answer_timeout' : 'answer_unavailable', accounting, generationID);
  }
}
