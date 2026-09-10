import { withApprovedReview } from './review-fixture';
import { env } from 'cloudflare:workers';
import { SignJWT } from 'jose';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import worker from '../src/index';
import { accountForIdentity } from '../src/accounts';
import { CONSENT_VERSION } from '../src/contract';
import { MAX_ANSWER_LENGTH, MAX_MODERATED_CONTENT_LENGTH, POLICY_RESPONSES, AnswerValidationError, moderatedAnswer } from '../src/content-policy';

const upstream = vi.fn<typeof fetch>();
const usage = { cost: 0.001, prompt_tokens: 20, completion_tokens: 5 };
let bearer: string;
beforeEach(async () => {
  vi.stubGlobal('fetch', withApprovedReview(upstream));
  upstream.mockReset();
  const account = await accountForIdentity(env.DB, crypto.randomUUID());
  bearer = await new SignJWT({ scope: 'answers' }).setProtectedHeader({ alg: 'HS256' })
    .setIssuer('untitled-faith').setAudience('untitled-faith-proxy').setSubject(account.id)
    .setIssuedAt().setExpirationTime('15m').sign(new TextEncoder().encode(env.SESSION_SIGNING_KEY));
});
afterEach(() => vi.unstubAllGlobals());

function completion(content: string, stream: boolean, finish = 'stop') {
  if (!stream) return Response.json({ id: 'private-generation', usage,
    choices: [{ finish_reason: finish, message: { content } }] });
  // Split the envelope so neither a partial decision nor a partial answer can escape.
  const frames = [content.slice(0, 20), content.slice(20)].map(text => ({
    id: 'private-generation', choices: [{ delta: { content: text }, finish_reason: null }],
  }));
  return new Response(frames.map(value => `data: ${JSON.stringify(value)}\n\n`).join('') +
    `data: ${JSON.stringify({ choices: [{ delta: {}, finish_reason: finish }], usage })}\n\n` +
    'data: [DONE]\n\n');
}

async function answer(content: string, stream: boolean, finish = 'stop') {
  upstream.mockResolvedValue(completion(content, stream, finish));
  const response = await worker.fetch(new Request('https://proxy.example/v1/answers', {
    method: 'POST', headers: { Authorization: `Bearer ${bearer}`, 'Content-Type': 'application/json',
      Accept: stream ? 'text/event-stream' : 'application/json', 'Idempotency-Key': crypto.randomUUID() },
    body: JSON.stringify({ consentVersion: CONSENT_VERSION, messages: [{ role: 'user', content: 'A synthetic moderation test.' }] }),
  }), env);
  const wire = await response.text();
  const events = stream ? wire.split('\n').filter(line => line.startsWith('data: ')).map(line => JSON.parse(line.slice(6))) : [];
  return { response, wire, events, value: stream ? events.find(event => event.type === 'done') : JSON.parse(wire) };
}

// These test server enforcement of model decisions, not the model's classification accuracy.
describe.each([false, true])('moderation enforcement (stream=%s)', stream => {
  it.each(['off_topic', 'unsafe', 'crisis'] as const)('replaces %s content and accounts for inference once', async decision => {
    const result = await answer(JSON.stringify({ decision, answer: 'MUST_NOT_ESCAPE [unsafe source](https://evil.example/)' }), stream);
    expect(result.response.status).toBe(200);
    expect(result.value.answer).toEqual({ text: POLICY_RESPONSES[decision], scripture: [], commentary: [] });
    expect(result.wire).not.toMatch(/MUST_NOT_ESCAPE|evil.example|private-generation|"decision"/);
    if (stream) expect(result.events.filter(event => event.type === 'delta')).toEqual([{ type: 'delta', text: POLICY_RESPONSES[decision] }]);
    expect(upstream).toHaveBeenCalledTimes(1);
    expect(await env.DB.prepare('SELECT status, cost_micros FROM usage_requests').first()).toEqual({ status: 'settled', cost_micros: 1161 });
  });

  it('preserves an allowed difficult answer without keyword censorship', async () => {
    const text = 'Christians disagree about sexuality, abortion, and biblical violence. Criticism of Christianity and doubts about God deserve an honest hearing.';
    const result = await answer(JSON.stringify({ decision: 'answer', answer: text }), stream);
    expect(result.value.answer.text).toBe(text);
    expect(result.wire).not.toContain('"decision"');
  });

  it.each([
    'MUST_NOT_ESCAPE', JSON.stringify({ answer: 'MUST_NOT_ESCAPE' }),
    JSON.stringify({ decision: 'allow', answer: 'MUST_NOT_ESCAPE' }),
    JSON.stringify({ decision: 'answer', answer: 'MUST_NOT_ESCAPE', extra: true }),
    JSON.stringify({ decision: 'answer', answer: '' }),
    JSON.stringify({ decision: 'answer', answer: 'a'.repeat(MAX_ANSWER_LENGTH + 1) }),
    '{"decision":"answer","answer":"MUST_NOT_ESCAPE',
    '{"decision":"unsafe","answer":"MUST_NOT_ESCAPE","decision":"answer"}',
    '{"\\u0064ecision":"unsafe","answer":"MUST_NOT_ESCAPE","decision":"answer"}',
    'MUST_NOT_ESCAPE\n```json\n{"decision":"answer","answer":"hello"}\n```',
    '```json\n{"decision":"answer","answer":"hello"}\n```\nMUST_NOT_ESCAPE',
  ])('fails closed for an invalid envelope %# while settling known usage', async content => {
    const result = await answer(content, stream);
    expect(result.wire).not.toContain('MUST_NOT_ESCAPE');
    if (stream) {
      expect(result.events.map(event => event.type)).toEqual(['start', 'error']);
      expect(result.events.at(-1).error.code).toBe('invalid_answer_format');
    } else {
      expect(result.response.status).toBe(502);
      expect(result.value.error.code).toBe('invalid_answer_format');
    }
    expect((await env.DB.prepare('SELECT status FROM usage_requests').first())?.status).toBe('settled');
  });

  it('never publishes a completion stopped by provider content filtering', async () => {
    const result = await answer(JSON.stringify({ decision: 'answer', answer: 'MUST_NOT_ESCAPE' }), stream, 'content_filter');
    expect(result.wire).not.toContain('MUST_NOT_ESCAPE');
    expect(result.wire).toContain('answer_unavailable');
    expect(result.events.some(event => event.type === 'delta')).toBe(false);
  });
});

it('bounds serialized input and decoded text separately, allowing valid JSON escapes', () => {
  const content = '{"decision":"answer","answer":"' + '\\u0041'.repeat(MAX_ANSWER_LENGTH) + '"}';
  expect(moderatedAnswer(content)).toEqual({ generated: true, decision: 'answer', text: 'A'.repeat(MAX_ANSWER_LENGTH) });
  expect(() => moderatedAnswer(' '.repeat(MAX_MODERATED_CONTENT_LENGTH + 1))).toThrow('invalid_answer_format');
  for (const value of [null, [], { decision: 'answer', answer: 42 }, { decision: 'toString', answer: '' }]) {
    expect(() => moderatedAnswer(JSON.stringify(value))).toThrow('invalid_answer_format');
  }
});

it.each(['\n', '\r\n'])('validates an exact JSON fence with %j line endings', newline => {
  const envelope = JSON.stringify({ decision: 'answer', answer: 'An allowed answer.' });
  expect(moderatedAnswer('```json' + newline + envelope + newline + '```')).toEqual({
    text: 'An allowed answer.', generated: true, decision: 'answer',
  });
  expect(() => moderatedAnswer('```json' + newline + 'not json' + newline + '```')).toThrow('invalid_answer_format');
});

it('normalizes only literal JSON string whitespace without interpreting answer content as fields', () => {
  const raw = '{"decision":"answer","answer":"First line\n\tA \\"quote\\" and {braces}\r\nLast line"}';
  expect(moderatedAnswer(raw).text).toBe('First line\n\tA "quote" and {braces}\r\nLast line');
  const blocked = '{"decision":"unsafe","answer":"\n\\"decision\\":\\"answer\\"\nMUST_NOT_ESCAPE"}';
  expect(moderatedAnswer(blocked).text).toBe(POLICY_RESPONSES.unsafe);
  // Missing quotes/braces and unsupported control characters still fail closed.
  for (const invalid of [raw.slice(0, -1), '{"decision":"answer","answer":"unescaped "quote""}',
    '{"decision":"answer","answer":"bad\u0000control"}', '{"decision":"answer","answer":"bad\\' + '\n' + 'escape"}']) {
    expect(() => moderatedAnswer(invalid)).toThrow('invalid_answer_format');
  }
});


it.each([
  ['Plain text without an envelope', 'string_count'],
  ['{"decision":"answer","answer":"text",}', 'invalid_json'],
  ['{"decision":"answer","other":"text"}', 'fields'],
  ['{"decision":"answer","answer":""}', 'empty_answer'],
  ['{"decision":"allow","answer":"text"}', 'decision'],
  [JSON.stringify({ decision: 'answer', answer: 'a'.repeat(MAX_ANSWER_LENGTH + 1) }), 'answer_length'],
])('classifies invalid response formats without retaining content %#', (content, reason) => {
  try { moderatedAnswer(content); throw new Error('Expected validation failure'); }
  catch (error) {
    expect(error).toBeInstanceOf(AnswerValidationError);
    expect(error).toMatchObject({ code: 'invalid_answer_format', reason });
    expect(JSON.stringify(error)).not.toContain(content);
  }
});
