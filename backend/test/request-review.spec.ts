import { env } from 'cloudflare:workers';
import { SignJWT } from 'jose';
import { beforeEach, afterEach, describe, expect, it, vi } from 'vitest';
import worker from '../src/index';
import { accountForIdentity } from '../src/accounts';
import { CONSENT_VERSION, LEGACY_CONSENT_VERSION } from '../src/contract';
import { POLICY_RESPONSES } from '../src/content-policy';
import { parseReview, reviewRequest, REVIEW_MODEL } from '../src/request-review';
import { reconcileUsage } from '../src/reconcile-usage';
import { reviewCompletion } from './review-fixture';

const upstream = vi.fn<typeof fetch>();
let bearer: string;
beforeEach(async () => {
  upstream.mockReset();
  vi.stubGlobal('fetch', upstream);
  const account = await accountForIdentity(env.DB, crypto.randomUUID());
  bearer = await new SignJWT({ scope: 'answers' }).setProtectedHeader({ alg: 'HS256' })
    .setIssuer('untitled-faith').setAudience('untitled-faith-proxy').setSubject(account.id)
    .setIssuedAt().setExpirationTime('15m').sign(new TextEncoder().encode(env.SESSION_SIGNING_KEY));
});
afterEach(() => vi.unstubAllGlobals());

const interfaith = 'What is the modern day Christians relation with Jewish people today. How should I handle that relationship?';
const answerText = 'Jesus calls Christians to love their neighbors. Treat Jewish people with respect and kindness.';
function completion(stream: boolean, withUsage = true) {
  const content = JSON.stringify({ decision: 'answer', answer: answerText });
  const usage = withUsage ? { cost: 0.001, prompt_tokens: 20, completion_tokens: 5 } : undefined;
  return stream ? new Response(`data: ${JSON.stringify({ id: 'answer-generation', usage,
    choices: [{ delta: { content }, finish_reason: 'stop' }] })}\n\ndata: [DONE]\n\n`) :
    Response.json({ id: 'answer-generation', usage, choices: [{ message: { content }, finish_reason: 'stop' }] });
}
async function send(stream: boolean, key = crypto.randomUUID(), messages = [{ role: 'user', content: interfaith }], consentVersion = CONSENT_VERSION) {
  const response = await worker.fetch(new Request('https://proxy.example/v1/answers', {
    method: 'POST', headers: { Authorization: `Bearer ${bearer}`, 'Content-Type': 'application/json',
      Accept: stream ? 'text/event-stream' : 'application/json', 'Idempotency-Key': key },
    body: JSON.stringify({ consentVersion, messages }),
  }), env);
  return { status: response.status, wire: await response.text() };
}

describe.each([false, true])('independent request review (stream=%s)', stream => {
  it('uses a different model with full context and settles both calls as one question', async () => {
    upstream.mockResolvedValueOnce(reviewCompletion()).mockResolvedValueOnce(completion(stream));
    const key = crypto.randomUUID();
    const messages = [{ role: 'user', content: 'How do Christians relate to other religions?' },
      { role: 'assistant', content: 'We can discuss interfaith relationships.' }, { role: 'user', content: interfaith }];
    const result = await send(stream, key, messages);
    expect(result.wire).toContain(answerText);
    expect(result.wire).not.toMatch(/review-generation|answer-generation|"decision"/);
    const review = JSON.parse(upstream.mock.calls[0]![1]!.body as string);
    const answer = JSON.parse(upstream.mock.calls[1]![1]!.body as string);
    expect(review.model).toBe(REVIEW_MODEL);
    expect(review.model).not.toBe(answer.model);
    expect(review.messages.slice(1)).toEqual(messages);
    expect(review.tools).toBeUndefined();
    expect(review.provider).toMatchObject({ data_collection: 'deny', require_parameters: true,
      only: ['google-ai-studio', 'google-vertex'] });
    expect(answer.messages[0].content).toContain('independent request reviewer');
    expect(await env.DB.prepare('SELECT status, cost_micros, prompt_tokens, completion_tokens FROM usage_requests').first())
      .toEqual({ status: 'settled', cost_micros: 1161, prompt_tokens: 30, completion_tokens: 8 });
    expect((await send(stream, key, messages)).status).toBe(409);
    expect(upstream).toHaveBeenCalledTimes(2);
  });

  it.each(['off_topic', 'unsafe', 'crisis'] as const)('returns %s before answer generation or search', async decision => {
    upstream.mockResolvedValueOnce(reviewCompletion(decision));
    const { wire } = await send(stream);
    expect(wire).toContain(POLICY_RESPONSES[decision]);
    expect(upstream).toHaveBeenCalledTimes(1);
    expect(await env.DB.prepare('SELECT status, cost_micros FROM usage_requests').first())
      .toEqual({ status: 'settled', cost_micros: 106 });
  });

  it('falls back to the cheaper answer model once and settles one question', async () => {
    upstream.mockResolvedValueOnce(reviewCompletion())
      .mockResolvedValueOnce(new Response(null, { status: 429 }))
      .mockResolvedValueOnce(completion(stream));
    const key = crypto.randomUUID();
    expect((await send(stream, key)).wire).toContain(answerText);
    const primary = JSON.parse(upstream.mock.calls[1]![1]!.body as string);
    const fallback = JSON.parse(upstream.mock.calls[2]![1]!.body as string);
    expect(primary.model).toBe('google/gemini-3.8-flash');
    expect(fallback.model).toBe('openai/gpt-5.6-luna');
    expect(fallback.messages).toEqual(primary.messages);
    expect(fallback.tools).toEqual(primary.tools);
    expect(fallback.response_format).toEqual(primary.response_format);
    expect(fallback.reasoning).toEqual({ effort: 'low', exclude: true });
    expect(fallback.provider).toEqual({ only: ['openai'], data_collection: 'deny', require_parameters: true,
      max_price: { prompt: 0.4, completion: 1.8, request: 0 } });
    expect(fallback.max_tokens).toBe(primary.max_tokens);
    expect(fallback.stream).toBe(stream);
    expect(await env.DB.prepare('SELECT status, cost_micros FROM usage_requests').first())
      .toEqual({ status: 'settled', cost_micros: 1161 });
    expect((await send(stream, key)).status).toBe(409);
    expect(upstream).toHaveBeenCalledTimes(3);
  });

  it('falls back for review without bypassing the review decision', async () => {
    upstream.mockResolvedValueOnce(new Response(null, { status: 429 }))
      .mockResolvedValueOnce(reviewCompletion('unsafe'));
    expect((await send(stream)).wire).toContain(POLICY_RESPONSES.unsafe);
    const fallback = JSON.parse(upstream.mock.calls[1]![1]!.body as string);
    expect(fallback.model).toBe('openai/gpt-4.1-nano');
    expect(fallback.reasoning).toBeUndefined();
    expect(fallback.tools).toBeUndefined();
    expect(fallback.max_tokens).toBe(128);
    expect(fallback.provider).toMatchObject({ only: ['openai'], data_collection: 'deny', require_parameters: true,
      max_price: { prompt: 0.2, completion: 0.8, request: 0 } });
    expect(upstream).toHaveBeenCalledTimes(2);
    expect((await env.DB.prepare('SELECT cost_micros FROM usage_requests').first())?.cost_micros).toBe(106);
  });

  it('keeps older apps on their disclosed Google routes', async () => {
    upstream.mockResolvedValueOnce(reviewCompletion())
      .mockResolvedValueOnce(new Response(null, { status: 429 }));
    expect((await send(stream, undefined, undefined, LEGACY_CONSENT_VERSION)).wire).toContain('answer_unavailable');
    expect(upstream).toHaveBeenCalledTimes(2);
    expect(upstream.mock.calls.map(call => JSON.parse(call[1]!.body as string).model))
      .toEqual([REVIEW_MODEL, 'google/gemini-3.8-flash']);
  });

  it('fails closed for malformed review and settles its known cost', async () => {
    const response = await reviewCompletion().json() as { choices: { message: { content: string } }[] };
    response.choices[0]!.message.content = '{"decision":"answer","decision":"unsafe"}';
    upstream.mockResolvedValueOnce(Response.json(response));
    expect((await send(stream)).wire).toContain('answer_unavailable');
    expect(upstream).toHaveBeenCalledTimes(1);
    expect((await env.DB.prepare('SELECT cost_micros FROM usage_requests').first())?.cost_micros).toBe(106);
  });

  it('settles only review cost when the answer call is known unbilled', async () => {
    upstream.mockResolvedValueOnce(reviewCompletion()).mockImplementation(async () => new Response(null, { status: 429 }));
    expect((await send(stream)).wire).toContain('answer_unavailable');
    expect(await env.DB.prepare('SELECT status, cost_micros FROM usage_requests').first())
      .toEqual({ status: 'settled', cost_micros: 106 });
  });

  it('reconciles uncertain answer usage without losing or double charging review cost', async () => {
    upstream.mockResolvedValueOnce(reviewCompletion()).mockResolvedValueOnce(completion(stream, false));
    expect((await send(stream)).wire).toContain('answer_unavailable');
    expect(await env.DB.prepare('SELECT status, generation_id, review_cost_micros FROM usage_requests').first())
      .toEqual({ status: 'uncertain', generation_id: 'answer-generation', review_cost_micros: 106 });
    upstream.mockResolvedValueOnce(Response.json({ data: { id: 'answer-generation', finish_reason: 'stop',
      total_cost: 0.001, native_tokens_prompt: 20, native_tokens_completion: 5 } }));
    await reconcileUsage(env.DB, 'test-key');
    await reconcileUsage(env.DB, 'test-key');
    expect(await env.DB.prepare('SELECT status, cost_micros, prompt_tokens FROM usage_requests').first())
      .toEqual({ status: 'settled', cost_micros: 1161, prompt_tokens: 30 });
    expect(upstream).toHaveBeenCalledTimes(3);
  });

  it('releases unbilled review failures and never runs the answer model', async () => {
    upstream.mockImplementation(async () => new Response(null, { status: 429 }));
    expect((await send(stream)).wire).toContain('answer_unavailable');
    expect((await env.DB.prepare('SELECT status FROM usage_requests').first())?.status).toBe('released');
    expect(upstream).toHaveBeenCalledTimes(2);
  });
});

it.each([null, 'answer', '{"decision":"allow"}', '{"decision":"answer","extra":true}',
  '{"decision":"answer","decision":"off_topic"}', '```json\n{"decision":"answer"}\n```'])('rejects invalid review %j', value => {
  expect(() => parseReview(value)).toThrow('Invalid review');
});

it('does not start inference after cancellation', async () => {
  await expect(reviewRequest([{ role: 'user', content: interfaith }], 'test', 'opaque', AbortSignal.abort()))
    .rejects.toMatchObject({ code: 'answer_timeout' });
  expect(upstream).not.toHaveBeenCalled();
});
