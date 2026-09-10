import { withApprovedReview } from './review-fixture';
import { env } from 'cloudflare:workers';
import { SignJWT } from 'jose';
import { afterEach, expect, it, vi } from 'vitest';
import worker from '../src/index';
import { accountForIdentity } from '../src/accounts';
import { CONSENT_VERSION } from '../src/contract';
import { prepareBible } from '../src/bible/prepare';
import { retrieveBible } from '../src/bible/context';
import { MAX_BIBLE_CONTEXT_CHARACTERS, MAX_BIBLE_PASSAGES } from '../src/bible/types';
import { readPassage, referencesIn } from '../src/bible/references';
import { AnswerSources } from '../src/answer-sources';
import { ESV_ENDPOINT, type ESVAccess } from '../src/esv';

const key = 'test-only-crossway-secret';
const access = (): ESVAccess => ({ ESV_API_KEY: key, PASSAGES_RATE_LIMITER: { limit: vi.fn(async () => ({ success: true })) } });
const messages = [{ role: 'user' as const, content: 'Explain John 11:35' }];
const body = { passages: ['Jesus wept.'], passage_meta: [{ canonical: 'John 11:35' }] };
const signal = () => new AbortController().signal;
afterEach(() => vi.unstubAllGlobals());

it('fetches one bounded batch with only references and the server key', async () => {
  const fetcher = vi.fn().mockResolvedValue(Response.json(body)); vi.stubGlobal('fetch', fetcher);
  const binding = access();
  const result = await prepareBible(messages, binding, 'opaque-user', signal());
  expect(fetcher).toHaveBeenCalledTimes(1);
  const [url, options] = fetcher.mock.calls[0]!;
  expect(url.origin + url.pathname).toBe(ESV_ENDPOINT);
  expect(url.searchParams.get('q')).toBe('John 11:35;John 11:32–34;John 11:36–38');
  expect(url.searchParams.get('include-verse-numbers')).toBe('false');
  expect(options.headers.Authorization).toBe(`Token ${key}`);
  expect(options.redirect).toBe('manual');
  expect(binding.PASSAGES_RATE_LIMITER.limit).toHaveBeenCalledWith({ key: 'passages:opaque-user' });
  expect(result.passages[0]).toEqual({ reference: 'John 11:35', translation: 'ESV',
    text: 'Jesus wept.', url: 'https://www.esv.org/John%2011%3A35/' });
  expect(JSON.stringify(result)).not.toContain(key);
  expect(result.passages.filter(p => p.reference === 'John 11:35')).toHaveLength(1);
});

it('caps an ESV batch and the combined ESV/BSB prompt size', async () => {
  const fetcher = vi.fn().mockResolvedValue(Response.json({ passages: ['Verified ESV text.'], passage_meta: [{ canonical: 'Psalm 119:1–16' }] }));
  vi.stubGlobal('fetch', fetcher);
  const result = await prepareBible([{ role: 'user', content: 'Explain Psalm 119' }], access(), 'user', signal());
  const query = fetcher.mock.calls[0]![0].searchParams.get('q') as string;
  expect(referencesIn(query).flatMap(readPassage).length).toBeLessThanOrEqual(48);
  expect(result.passages[0]!.translation).toBe('ESV');
  expect(JSON.stringify(result).length).toBeLessThanOrEqual(MAX_BIBLE_CONTEXT_CHARACTERS);
  expect(result.passages.length).toBeLessThanOrEqual(MAX_BIBLE_PASSAGES);
  expect(result.limited).toBe(true);
});

it.each([401, 429, 500, 302])('retains clearly labeled BSB when Crossway returns %s', async status => {
  vi.stubGlobal('fetch', vi.fn().mockResolvedValue(new Response('private upstream details', { status })));
  expect(await prepareBible(messages, access(), 'user', signal())).toEqual(retrieveBible(messages));
});

it('rejects oversized, malformed, and unrelated upstream evidence', async () => {
  for (const response of [new Response('x'.repeat(256 * 1024 + 1)), new Response('not json'),
    Response.json({ passages: ['wrong passage'], passage_meta: [{ canonical: 'Genesis 1:1' }] })]) {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(response));
    expect(await prepareBible(messages, access(), 'user', signal())).toEqual(retrieveBible(messages));
  }
});

it('makes no Crossway call when unconfigured, rate-limited, or there is no passage', async () => {
  const fetcher = vi.fn(); vi.stubGlobal('fetch', fetcher);
  await prepareBible(messages, { ...access(), ESV_API_KEY: '' }, 'user', signal());
  await prepareBible([{ role: 'user', content: 'Hello' }], access(), 'user', signal());
  await prepareBible(messages, { ...access(), PASSAGES_RATE_LIMITER: { limit: async () => ({ success: false }) } }, 'user', signal());
  expect(fetcher).not.toHaveBeenCalled();
});

it('validates ESV wording and translation against Crossway evidence', () => {
  const sources = new AnswerSources();
  const url = 'https://www.esv.org/Song%20of%20Solomon%202%3A1/';
  sources.addBible([{ reference: 'Song of Solomon 2:1', translation: 'ESV', text: 'Fixture text.', url }]);
  const answer = `> [Scripture] Fixture text.\n[Song of Solomon 2:1 — ESV](${url})`;
  expect(sources.finish(answer).sources![0]!.title).toContain('Crossway');
  expect(() => sources.finish(answer.replace('ESV]', 'BSB]'))).toThrow('sources_unavailable');
  expect(() => sources.finish(answer.replace('Fixture text.', 'Changed text.'))).toThrow('sources_unavailable');
});

it.each([false, true])('keeps credentials behind the signed-in proxy through answer generation (stream=%s)', async stream => {
  const account = await accountForIdentity(env.DB, crypto.randomUUID());
  const token = await new SignJWT({ scope: 'answers' }).setProtectedHeader({ alg: 'HS256' })
    .setIssuer('untitled-faith').setAudience('untitled-faith-proxy').setSubject(account.id)
    .setIssuedAt().setExpirationTime('5m').sign(new TextEncoder().encode(env.SESSION_SIGNING_KEY));
  const answer = '> [Scripture] Jesus wept.\n[John 11:35 — ESV](https://www.esv.org/John%2011%3A35/)';
  const content = JSON.stringify({ decision: 'answer', answer });
  const usage = { cost: .001, prompt_tokens: 50, completion_tokens: 20 };
  const fetcher = vi.fn().mockImplementation(async (url: URL | string) => {
    if (new URL(url).hostname === 'api.esv.org') return Response.json(body);
    return stream ? new Response(`data: ${JSON.stringify({ id: 'esv-generation', choices: [{ delta: { content }, finish_reason: 'stop' }], usage })}\n\ndata: [DONE]\n\n`) :
      Response.json({ id: 'esv-generation', choices: [{ message: { content }, finish_reason: 'stop' }], usage });
  });
  vi.stubGlobal('fetch', withApprovedReview(fetcher));
  const request = (authorization: string) => new Request('https://proxy.example/v1/answers', { method: 'POST', headers: {
    Authorization: authorization, 'Content-Type': 'application/json', 'Idempotency-Key': crypto.randomUUID(),
    Accept: stream ? 'text/event-stream' : 'application/json',
  }, body: JSON.stringify({ consentVersion: CONSENT_VERSION, messages }) });
  const bindings = { ...env, ...access() };
  expect((await worker.fetch(request('Bearer invalid'), bindings)).status).toBe(401);
  expect(fetcher).not.toHaveBeenCalled();
  const response = await worker.fetch(request(`Bearer ${token}`), bindings);
  const result = await response.text();
  expect(response.status).toBe(200);
  expect(fetcher).toHaveBeenCalledTimes(2); // one Crossway batch, one model call
  const modelOptions = fetcher.mock.calls[1]![1];
  expect(modelOptions.headers.Authorization).toBe(`Bearer ${env.OPENROUTER_API_KEY}`);
  expect(modelOptions.body).toContain('Jesus wept.');
  expect(modelOptions.body).not.toContain(key);
  expect(modelOptions.body).not.toContain(token);
  expect(result).toContain('Crossway');
  expect(result).toContain('Jesus wept.');
  expect(result).not.toContain(key);
  expect(result).not.toContain(env.OPENROUTER_API_KEY);
  expect(result).not.toContain(token);
  expect((await env.DB.prepare('SELECT status FROM usage_requests WHERE user_id = ?').bind(account.id).first())?.status).toBe('settled');
});
