import { reviewedAnswer } from './request-review';
import { handleReliability } from './reliability-routes';
import { authenticate } from "./auth";
import { handleAppleAuth } from "./apple-auth";
import { CONSENT_VERSION, MAX_REQUEST_BYTES, parseAnswerRequest } from "./contract";
import { APIError, isRecord, jsonResponse, readJSON } from "./http";
import { generateAnswer, InferenceError } from "./openrouter";
import { finishAccountDeletions, requireAccount } from "./accounts";
import { reservationMicros } from "./billing-policy";
import { holdUncertainUsage, releaseUsage, reserveUsage, settleUsage, usageSummary } from "./usage";
import { reconcileUsage } from "./reconcile-usage";
import { answerStream } from "./answer-stream";
import { handlePassages, PassageEnv } from "./esv";
import { prepareBible } from "./bible/prepare";
import { handlePayments, paymentReturnPage } from './payments/routes';
import { reconcilePayments } from './payments/reconciliation';
import { retryStripeEvents } from './payments/webhook';

export default {
  async scheduled(_controller, env): Promise<void> {
    await reconcileUsage(env.DB, env.OPENROUTER_API_KEY);
    await retryStripeEvents(env);
    await reconcilePayments(env);
    await finishAccountDeletions(env.DB);
  },
  async fetch(request: Request, env: Env, ctx?: ExecutionContext): Promise<Response> {
    const requestID = crypto.randomUUID();
    const started = Date.now();
    let status = 200;
    const tracked = (response: Response) => {
      status = response.status;
      const headers = new Headers(response.headers);
      headers.set('X-Request-ID', requestID);
      return new Response(response.body, { status: response.status, headers });
    };
    try {
      const url = new URL(request.url);
      const reliability = await handleReliability(request, env);
      if (reliability) return tracked(reliability);
      if (url.pathname === "/health" && request.method === "GET") return jsonResponse({ status: "ok" });
      if (request.method === 'GET') {
        const page = paymentReturnPage(url.pathname);
        if (page) return page;
        if (url.pathname === '/.well-known/apple-app-site-association') return jsonResponse({
          applinks: { details: [{ appIDs: ['BZT8F2M765.com.lukefournier.UntitledFaith'],
            components: [{ '/': '/payments/open' }] }] },
        });
      }
      if (url.pathname.startsWith('/v1/payments/') || url.pathname === '/v1/owner/payments') {
        return tracked(await handlePayments(request, env, ctx));
      }
      if (url.pathname.startsWith("/v1/auth/")) return tracked(await handleAppleAuth(request, env));
      if (url.pathname === "/v1/me/usage" && request.method === "GET") {
        const userID = await authenticate(request, env.SESSION_SIGNING_KEY);
        return jsonResponse(await usageSummary(env.DB, userID));
      }
      if (url.pathname === "/v1/passages" && request.method === "GET") return tracked(await handlePassages(request, env as PassageEnv));
      if (url.pathname !== "/v1/answers") throw new APIError(404, "not_found");
      if (request.method !== "POST") throw new APIError(405, "method_not_allowed");
      if (!env.OPENROUTER_API_KEY?.trim() || !env.SESSION_SIGNING_KEY || env.SESSION_SIGNING_KEY.length < 32) {
        throw new APIError(503, "not_configured");
      }
      const userID = await authenticate(request, env.SESSION_SIGNING_KEY);
      const account = await requireAccount(env.DB, userID);
      if (!(await env.ANSWERS_RATE_LIMITER.limit({ key: `answers:${userID}` })).success) {
        throw new APIError(429, "rate_limited");
      }
      if (request.headers.get("Content-Type")?.split(";")[0]?.trim().toLowerCase() !== "application/json") {
        throw new APIError(415, "invalid_request");
      }
      const body = await readJSON(request.body, MAX_REQUEST_BYTES);
      const messages = parseAnswerRequest(body);
      // Older apps disclose Google only; retain their original routing until they update.
      const allowFallback = isRecord(body) && body.consentVersion === CONSENT_VERSION;
      const idempotencyKey = request.headers.get("Idempotency-Key");
      if (!idempotencyKey || !/^[a-zA-Z0-9_-]{16,128}$/.test(idempotencyKey)) throw new APIError(400, "idempotency_key_required");
      const bibleContext = await prepareBible(messages, env as PassageEnv, userID, request.signal);
      const reservation = await reserveUsage(env.DB, userID, idempotencyKey, reservationMicros(messages, account.first_name, bibleContext));
      if (request.headers.get("Accept")?.split(",").some(value => value.trim() === "text/event-stream")) {
        return answerStream(request, env, messages, userID, reservation.id, requestID, ctx, account.first_name, bibleContext, allowFallback);
      }
      const signal = AbortSignal.any([request.signal, AbortSignal.timeout(45000)]);
      let result;
      try {
        result = await reviewedAnswer(env.DB, reservation.id, messages, env.OPENROUTER_API_KEY, userID, signal,
          () => generateAnswer(messages, env.OPENROUTER_API_KEY, userID, signal, account.first_name, bibleContext, true, allowFallback), allowFallback);
      } catch (error) {
        if (error instanceof InferenceError && error.accounting === "unbilled") await releaseUsage(env.DB, reservation.id);
        else if (error instanceof InferenceError && typeof error.accounting === "object") await settleUsage(env.DB, reservation.id, error.accounting);
        else await holdUncertainUsage(env.DB, reservation.id, error instanceof InferenceError ? error.generationID : undefined);
        throw error;
      }
      await settleUsage(env.DB, reservation.id, result.usage);
      // Checked source quotations share the existing app response contract.
      return jsonResponse({ answer: { text: result.text, scripture: [], commentary: [],
            ...(result.sources ? { sources: result.sources, quotes: result.quotes } : {}) }, requestID });
    } catch (error) {
      const failure = error instanceof APIError ? error : new APIError(500, "internal_error");
      status = failure.status;
      if (status >= 500) console.error(JSON.stringify({ event: 'request_failed', requestID, status, errorCode: failure.code }));
      return tracked(jsonResponse({ error: { code: failure.code }, requestID }, status));
    } finally {
      console.log(JSON.stringify({ event: "request_completed", requestID, status, durationMS: Date.now() - started }));
    }
  },
} satisfies ExportedHandler<Env>;
