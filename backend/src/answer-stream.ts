import { reviewedAnswer } from './request-review';
import type { Message } from './contract';
import { APIError } from './http';
import { InferenceError } from './openrouter';
import { streamAnswer } from './openrouter-stream';
import { holdUncertainUsage, releaseUsage, settleUsage } from './usage';
import type { BibleContext } from './bible/types';

export function answerStream(request: Request, env: Env, messages: Message[], userID: string,
  reservationID: string, requestID: string, ctx?: ExecutionContext, firstName: string | null = null,
  bibleContext?: BibleContext): Response {
  const abort = new AbortController();
  const signal = AbortSignal.any([request.signal, abort.signal, AbortSignal.timeout(45000)]);
  const encoder = new TextEncoder();
  let cancelled = false;
  const body = new ReadableStream<Uint8Array>({
    start(controller) {
      const send = (value: unknown) => {
        if (!cancelled) controller.enqueue(encoder.encode(`data: ${JSON.stringify(value)}\n\n`));
      };
      const work = (async () => {
        const started = Date.now();
        let status = 200;
        try {
          send({ type: 'start', requestID });
          const result = await reviewedAnswer(env.DB, reservationID, messages, env.OPENROUTER_API_KEY, userID, signal,
            () => streamAnswer(messages, env.OPENROUTER_API_KEY, userID, signal,
            async id => {
              // Keep only accounting metadata for recovery; chat text is never stored here.
              await env.DB.prepare("UPDATE usage_requests SET generation_id = ? WHERE id = ? AND status = 'reserved'")
                .bind(id, reservationID).run();
            }, firstName, bibleContext, true));
          await settleUsage(env.DB, reservationID, result.usage);
          // Never expose provider text before the complete moderation and source checks.
          send({ type: 'delta', text: result.text });
          send({ type: 'done', answer: { text: result.text, scripture: [], commentary: [],
            ...(result.sources ? { sources: result.sources, quotes: result.quotes } : {}) }, requestID });
        } catch (error) {
          const failure = error instanceof APIError ? error : new APIError(500, 'internal_error');
          status = failure.status;
          try {
            if (error instanceof InferenceError && error.accounting === 'unbilled') await releaseUsage(env.DB, reservationID);
            else if (error instanceof InferenceError && typeof error.accounting === 'object') await settleUsage(env.DB, reservationID, error.accounting);
            else await holdUncertainUsage(env.DB, reservationID, error instanceof InferenceError ? error.generationID : undefined);
          } catch {
            // The existing reconciler recovers stale reservations if settlement is unavailable.
            status = 500;
          }
          send({ type: 'error', error: { code: failure.code }, requestID });
        } finally {
          if (!cancelled) controller.close();
          console.log(JSON.stringify({ event: 'answer_stream_completed', requestID, status, durationMS: Date.now() - started }));
        }
      })();
      ctx?.waitUntil(work);
      return work;
    },
    cancel() { cancelled = true; abort.abort(); },
  });
  return new Response(body, { headers: {
    'Content-Type': 'text/event-stream; charset=utf-8', 'Cache-Control': 'no-store, no-transform',
    'X-Content-Type-Options': 'nosniff',
  } });
}
