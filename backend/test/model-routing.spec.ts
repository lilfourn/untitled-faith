import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import { requestWithRateLimitFallback, type ModelRoute } from '../src/model-routing';

const upstream = vi.fn<typeof fetch>();
const routes = [
  { model: 'primary', providers: ['primary-provider'] },
  { model: 'fallback', providers: ['fallback-provider'] },
] as const satisfies readonly [ModelRoute, ...ModelRoute[]];
const body = { messages: [{ role: 'user', content: 'Question' }],
  provider: { data_collection: 'deny' as const, require_parameters: true as const,
    max_price: { prompt: 3, completion: 15, request: 0 } } };
const run = (signal = new AbortController().signal) => requestWithRateLimitFallback(body, routes, 'test-key', signal);
beforeEach(() => { upstream.mockReset(); vi.stubGlobal('fetch', upstream); });
afterEach(() => vi.unstubAllGlobals());

it('closes a rejected response before trying one fallback with the same deadline', async () => {
  const cancel = vi.fn();
  const primary = new Response(new ReadableStream({ cancel }), { status: 429 });
  const success = new Response('done');
  upstream.mockResolvedValueOnce(primary).mockImplementationOnce(async () => {
    expect(cancel).toHaveBeenCalledOnce();
    return success;
  });
  const signal = new AbortController().signal;
  expect(await run(signal)).toBe(success);
  expect(upstream.mock.calls.every(call => call[1]!.signal === signal)).toBe(true);
  expect(upstream.mock.calls.every(call => call[1]!.redirect === 'manual')).toBe(true);
});

it.each([200, 400, 401, 402, 403, 500, 502, 504])('never retries status %s', async status => {
  const response = new Response('private provider data', { status });
  upstream.mockResolvedValue(response);
  expect(await run()).toBe(response);
  expect(upstream).toHaveBeenCalledOnce();
});

it('does not switch models for an OpenRouter platform rate limit', async () => {
  const response = new Response(null, { status: 429, headers: { 'X-RateLimit-Limit': '20', 'Retry-After': '60' } });
  upstream.mockResolvedValue(response);
  expect(await run()).toBe(response);
  expect(upstream).toHaveBeenCalledOnce();
});

it('stops after the fallback is also rate limited', async () => {
  upstream.mockImplementation(async () => new Response(null, { status: 429 }));
  expect((await run()).status).toBe(429);
  expect(upstream).toHaveBeenCalledTimes(2);
});

it('does not make the fallback request if cancelled after the first rejection', async () => {
  const abort = new AbortController();
  upstream.mockImplementation(async () => {
    abort.abort();
    return new Response(null, { status: 429 });
  });
  await expect(run(abort.signal)).rejects.toThrow();
  expect(upstream).toHaveBeenCalledOnce();
});

it('never retries a transport failure with unknown accounting', async () => {
  upstream.mockRejectedValue(new TypeError('network failure'));
  await expect(run()).rejects.toThrow('network failure');
  expect(upstream).toHaveBeenCalledOnce();
});
