import { withApprovedReview } from './review-fixture';
import { env } from 'cloudflare:workers';
import { createExecutionContext, waitOnExecutionContext } from 'cloudflare:test';
import { SignJWT } from 'jose';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import worker from '../src/index';
import { accountForIdentity } from '../src/accounts';
import { CONSENT_VERSION, MAX_CONTEXT_LENGTH, parseAnswerRequest } from '../src/contract';
import { MAX_MODERATED_CONTENT_LENGTH } from '../src/content-policy';
import { sseData } from '../src/sse';

const allowed = (answer: string) => JSON.stringify({ decision: 'answer', answer });
const upstream = vi.fn<typeof fetch>();
const usage = { cost: 0.001, prompt_tokens: 20, completion_tokens: 5 };
const encoder = new TextEncoder();
const frame = (value: unknown) => `data: ${JSON.stringify(value)}\r\n\r\n`;
const chunk = (content: string, finish_reason: string | null = null) => ({
  id: 'private-generation', model: 'private-model', choices: [{ delta: { content }, finish_reason }],
});
const finished = (reason = 'stop') => frame({ ...chunk('', reason), usage }) + 'data: [DONE]\r\n\r\n';
const response = (text: string) => new Response(text, { headers: { 'Content-Type': 'text/event-stream' } });
let bearer: string;

beforeEach(async () => {
  vi.stubGlobal('fetch', withApprovedReview(upstream));
  upstream.mockReset().mockImplementation(async () => response(frame(chunk(allowed('Hello 🙏'))) + finished()));
  const account = await accountForIdentity(env.DB, crypto.randomUUID());
  bearer = await new SignJWT({ scope: 'answers' }).setProtectedHeader({ alg: 'HS256' })
    .setIssuer('untitled-faith').setAudience('untitled-faith-proxy').setSubject(account.id)
    .setIssuedAt().setExpirationTime('15m').sign(new TextEncoder().encode(env.SESSION_SIGNING_KEY));
});
afterEach(() => vi.unstubAllGlobals());

function request(key = crypto.randomUUID(), messages = [{ role: 'user', content: 'Hello' }]) {
  return new Request('https://proxy.example/v1/answers', { method: 'POST', headers: {
    Authorization: `Bearer ${bearer}`, 'Content-Type': 'application/json', Accept: 'text/event-stream', 'Idempotency-Key': key,
  }, body: JSON.stringify({ consentVersion: CONSENT_VERSION, messages }) });
}

it('streams only app events, settles usage before done, and preserves every context message', async () => {
  const messages = Array.from({ length: 41 }, (_, i) => ({ role: i % 2 ? 'assistant' : 'user', content: `Message ${i}` }));
  const result = await worker.fetch(request(undefined, messages), env);
  const body = await result.text();
  expect(result.headers.get('Content-Type')).toContain('text/event-stream');
  expect(body).toContain('"type":"delta","text":"Hello 🙏"');
  expect(body).toContain('"type":"done"');
  expect(body).not.toMatch(/private-generation|private-model|prompt_tokens|cost/);
  const sent = JSON.parse(upstream.mock.calls[0]![1]!.body as string);
  expect(sent.stream).toBe(true);
  expect(sent.stream_options).toEqual({ include_usage: true });
  expect(sent.messages.slice(1)).toEqual(messages);
  expect(await env.DB.prepare('SELECT status, cost_micros FROM usage_requests').first()).toEqual({ status: 'settled', cost_micros: 1161 });
});

it('withholds text until checks finish and never duplicates a paid request', async () => {
  let source!: ReadableStreamDefaultController<Uint8Array>;
  upstream.mockResolvedValue(new Response(new ReadableStream<Uint8Array>({ start(controller) { source = controller; } })));
  const key = crypto.randomUUID();
  const result = await worker.fetch(request(key), env);
  const reader = result.body!.getReader();
  expect(new TextDecoder().decode((await reader.read()).value)).toContain('"type":"start"');
  source.enqueue(encoder.encode(frame(chunk(allowed('First')))));
  let delivered = false;
  const next = reader.read().then(value => { delivered = true; return value; });
  expect((await worker.fetch(request(key), env)).status).toBe(409);
  expect(upstream).toHaveBeenCalledTimes(1);
  expect(delivered).toBe(false);
  source.enqueue(encoder.encode(finished()));
  source.close();
  expect(new TextDecoder().decode((await next).value)).toContain('"text":"First"');
  expect(new TextDecoder().decode((await reader.read()).value)).toContain('"type":"done"');
  expect((await reader.read()).done).toBe(true);
});

it('parses comments, split UTF-8, split CRLF, and multiline SSE data', async () => {
  const bytes = encoder.encode(': heartbeat\r\ndata: {"text":\r\ndata: "🙏"}\r\n\r\n');
  let offset = 0;
  const stream = new ReadableStream<Uint8Array>({ pull(controller) {
    if (offset === bytes.length) controller.close(); else controller.enqueue(bytes.slice(offset, ++offset));
  } });
  const events = [];
  for await (const data of sseData(stream, new AbortController().signal)) events.push(JSON.parse(data));
  expect(events).toEqual([{ text: '🙏' }]);
});

it.each([
  ['missing DONE', frame(chunk('Partial')) + frame({ ...chunk('', 'stop'), usage }), 'settled'],
  ['missing usage', frame(chunk('Partial', 'stop')) + 'data: [DONE]\n\n', 'uncertain'],
  ['length limit', frame(chunk('Partial')) + finished('length'), 'settled'],
  ['empty text', finished(), 'settled'],
  ['malformed JSON', frame(chunk('Partial')) + 'data: nope\n\n', 'uncertain'],
  ['provider error', frame(chunk('Partial')) + frame({ error: { message: 'private failure' }, usage }), 'settled'],
  ['oversized text', frame(chunk('a'.repeat(MAX_MODERATED_CONTENT_LENGTH + 1))), 'uncertain'],
])('treats %s as a failed answer while preserving accounting', async (_label, data, status) => {
  upstream.mockResolvedValue(response(data));
  const body = await (await worker.fetch(request(), env)).text();
  expect(body).toContain('"type":"error"');
  expect(body).not.toContain('"type":"done"');
  expect(body).not.toContain('private failure');
  expect(body).not.toContain('"type":"delta"');
  expect((await env.DB.prepare('SELECT status FROM usage_requests').first())?.status).toBe(status);
});

it('settles review cost when answer inference is rejected', async () => {
  upstream.mockResolvedValue(new Response('private rejection', { status: 429 }));
  expect(await (await worker.fetch(request(), env)).text()).toContain('"error":{"code":"answer_unavailable","status":429}');
  expect((await env.DB.prepare('SELECT status FROM usage_requests').first())?.status).toBe('settled');
});

it('cancels an upstream read on client disconnect and holds uncertain usage for reconciliation', async () => {
  let source!: ReadableStreamDefaultController<Uint8Array>;
  const cancel = vi.fn();
  upstream.mockResolvedValue(new Response(new ReadableStream<Uint8Array>({ start(c) { source = c; }, cancel })));
  const ctx = createExecutionContext();
  const result = await worker.fetch(request(), env, ctx);
  const reader = result.body!.getReader();
  await reader.read();
  source.enqueue(encoder.encode(frame(chunk('Partial'))));
  await vi.waitFor(async () => {
    expect((await env.DB.prepare('SELECT generation_id FROM usage_requests').first())?.generation_id).toBe('private-generation');
  });
  await reader.cancel();
  await waitOnExecutionContext(ctx);
  expect(cancel).toHaveBeenCalled();
  expect(await env.DB.prepare('SELECT status, generation_id FROM usage_requests').first())
    .toEqual({ status: 'uncertain', generation_id: 'private-generation' });
});

it('rejects over-limit full history without silently shortening it or making an inference call', async () => {
  const messages = Array.from({ length: 27 }, () => ({ role: 'user', content: 'a'.repeat(8000) }));
  expect(messages.reduce((n, message) => n + message.content.length, 0)).toBeGreaterThan(MAX_CONTEXT_LENGTH);
  const result = await worker.fetch(request(undefined, messages), env);
  expect(result.status).toBe(413);
  expect(upstream).not.toHaveBeenCalled();
  expect(() => parseAnswerRequest({ consentVersion: CONSENT_VERSION, messages: Array(1001).fill({ role: 'user', content: 'a' }) })).toThrow('context_too_large');
});


it('carries retrieved citations and checked quotations through SSE and settles the combined cost once', async () => {
  const url = 'https://www.gotquestions.org/what-is-prayer.html';
  const text = `> [Commentary] Prayer is communication with God.\n[GotQuestions](${url})\n`;
  const citation = { type: 'url_citation', url_citation: { url, title: 'What is prayer?', content: 'Prayer is communication with God.' } };
  upstream.mockResolvedValue(response(frame({ ...chunk(''), choices: [{ delta: { annotations: [citation] }, finish_reason: null }] }) +
    frame(chunk(allowed(text))) + frame({ ...chunk('', 'stop'), usage: { ...usage, cost: 0.008 } }) + 'data: [DONE]\n\n'));
  const body = await (await worker.fetch(request(), env)).text();
  const done = body.split('\n').filter(line => line.startsWith('data: ')).map(line => JSON.parse(line.slice(6))).find(event => event.type === 'done');
  expect(done.answer.sources[0]).toMatchObject({ url, kind: 'commentary' });
  expect(done.answer.quotes[0]).toMatchObject({ text: 'Prayer is communication with God.', sourceID: done.answer.sources[0].id });
  expect(JSON.parse(upstream.mock.calls[0]![1]!.body as string).tools[0].parameters.allowed_domains).toContain('gotquestions.org');
  expect((await env.DB.prepare('SELECT cost_micros FROM usage_requests').first())?.cost_micros).toBe(8546);
});

it('does not mark an unsupported quotation complete but still accounts for provider work', async () => {
  upstream.mockResolvedValue(response(frame(chunk(allowed('> [Commentary] Invented quotation.\n[Source](https://evil.example/)\n'))) + finished()));
  const body = await (await worker.fetch(request(), env)).text();
  expect(body).toContain('"type":"error"');
  expect(body).not.toContain('"type":"done"');
  expect(body).toContain('"code":"sources_unavailable"');
  expect(body).not.toContain('Invented quotation');
  expect(body).not.toContain('"type":"delta"');
  expect((await env.DB.prepare('SELECT status FROM usage_requests').first())?.status).toBe('settled');
});


it('treats manual redirects as unbilled and does not forward credentials', async () => {
  upstream.mockResolvedValue(new Response(null, { status: 307, headers: { Location: 'https://untrusted.example' } }));
  const body = await (await worker.fetch(request(), env)).text();
  expect(body).toContain('"type":"error"');
  expect(body).not.toContain('untrusted.example');
  expect(upstream).toHaveBeenCalledTimes(1);
  expect(upstream.mock.calls[0]![1]!.redirect).toBe('manual');
  expect(await env.DB.prepare('SELECT status, cost_micros FROM usage_requests').first())
    .toEqual({ status: 'settled', cost_micros: 106 });
});
