import { afterEach, expect, it, vi } from 'vitest';
import { bible } from '../src/bible/data';
import { biblePrompt, retrieveBible } from '../src/bible/context';
import { readPassage, referencesIn } from '../src/bible/references';
import { searchBible } from '../src/bible/search';
import { MAX_BIBLE_CONTEXT_CHARACTERS, MAX_BIBLE_PASSAGES } from '../src/bible/types';
import { AnswerSources } from '../src/answer-sources';
import { generateAnswer } from '../src/openrouter';
import { streamAnswer } from '../src/openrouter-stream';
import { reservationMicros } from '../src/billing-policy';
import type { Message } from '../src/contract';

const messages = (content: string): Message[] => [{ role: 'user', content }];
afterEach(() => vi.unstubAllGlobals());

it('includes the full public-domain corpus, including both endpoints of all 66 books', () => {
  expect(bible.translation).toMatchObject({ id: 'BSB', license: 'Public domain' });
  expect(bible.verses).toHaveLength(31086);
  expect(bible.books).toHaveLength(66);
  for (const book of bible.books) {
    expect(readPassage(referencesIn(`${book.name} 1`)[0]!)).not.toHaveLength(0);
    expect(readPassage(referencesIn(`${book.name} ${book.chapters}`)[0]!)).not.toHaveLength(0);
  }
  expect(bible.verses[0]![0]).toBe(1001001);
  expect(bible.verses.at(-1)![0]).toBe(66022021);
});

it.each([
  ['Jn. 3:16', 43003016, 43003016], ['1John 1:8–9', 62001008, 62001009],
  ['Psalm 119', 19119001, 19119999], ['Romans 8', 45008001, 45008999],
  ['Romans 8:39–9:3', 45008039, 45009003], ['Genesis 1–2', 1001001, 1002999],
  ['First Peter 5:7', 60005007, 60005007], ['Song of Songs 2:1', 22002001, 22002001],
])('resolves %s using real canonical bounds', (query, start, end) => {
  expect(referencesIn(query)).toEqual([{ start, end }]);
});

it.each(['John 0', 'John 22', 'John 3:999', 'John 3:20-16', 'John 3:16-999', 'John 3:16-2:1', 'Psalms 151'])
  ('does not resolve nonexistent or reversed references: %s', query => { expect(referencesIn(query)).toEqual([]); });

it('places requested verses before neighbors and preserves exact text', () => {
  const context = retrieveBible(messages('Compare Romans 3:28 and James 2:24'));
  expect(context.passages.slice(0, 2).map(passage => passage.reference)).toEqual(['Romans 3:28', 'James 2:24']);
  expect(context.passages[0]!.text).toBe(readPassage(referencesIn('Romans 3:28')[0]!)[0]![1]);
  expect(context.passages.some(p => p.reference === 'Romans 3:25–27')).toBe(true);
  expect(context.passages.some(p => p.reference === 'James 2:25–26')).toBe(true);
  expect(context.passages.every(p => p.translation === 'BSB')).toBe(true);
});

it('reads a complete ordinary chapter and identifies budget-limited long chapters honestly', () => {
  const ordinary = retrieveBible(messages('Explain Romans 8'));
  expect(ordinary.passages[0]!.reference).toBe('Romans 8:1–39');
  expect(ordinary.limited).toBe(false);
  const long = retrieveBible(messages('Explain Psalm 119'));
  expect(long.passages[0]!.reference).toMatch(/^Psalms 119:1–/);
  expect(long.passages[0]!.reference).not.toBe('Psalms 119:1–176');
  expect(long.limited).toBe(true);
  expect(JSON.stringify(long).length).toBeLessThanOrEqual(MAX_BIBLE_CONTEXT_CHARACTERS);
});

it.each([
  'Explain Genesis 1-50', 'Compare John 1; Romans 1; Psalms 1; Job 1; Luke 1; Acts 1; Matthew 1; Genesis 1',
  'faith hope love prayer suffering forgiveness '.repeat(100),
])('bounds retrieval without changing the conversation: %s', question => {
  const input = messages(question), original = JSON.stringify(input);
  const context = retrieveBible(input);
  expect(context.passages.length).toBeLessThanOrEqual(MAX_BIBLE_PASSAGES);
  expect(JSON.stringify(context).length).toBeLessThanOrEqual(MAX_BIBLE_CONTEXT_CHARACTERS);
  expect(JSON.stringify(input)).toBe(original);
});

it('resolves a short follow-up from recent context without treating it as a new topic', () => {
  const context = retrieveBible([
    { role: 'user', content: 'Explain John 3:16' },
    { role: 'assistant', content: 'John 3:16 describes God’s love.' },
    { role: 'user', content: 'What does that mean for me?' },
  ]);
  expect(context.passages[0]!.reference).toBe('John 3:16');
});

it('does not let an old reference displace an explicit new one', () => {
  const context = retrieveBible([
    { role: 'user', content: 'Explain John 3:16' },
    { role: 'assistant', content: 'John 3:16 describes God’s love.' },
    { role: 'user', content: 'Explain Romans 8' },
  ]);
  expect(context.passages[0]!.reference).toBe('Romans 8:1–39');
});

it.each([
  ['What does the Bible say about anxiety?', 'Philippians 4:4–9'],
  ['How can I forgive someone who hurt me?', 'Matthew 6:9–15'],
  ['What does Scripture teach about suffering?', 'Job 2:7–13'],
  ['How should I pray?', 'Luke 11:1–13'],
  ['How does salvation work?', 'Ephesians 2:1–10'],
])('provides contextual starting passages for %s', (question, reference) => {
  const context = retrieveBible(messages(question));
  expect(context.passages.map(p => p.reference)).toContain(reference);
  expect(context.passages.length).toBeGreaterThan(2);
  expect(context.limited).toBe(true);
});

it('searches uncommon wording across the corpus without a topic guide or network call', () => {
  const network = vi.fn(); vi.stubGlobal('fetch', network);
  const results = searchBible('Melchizedek');
  const books = new Set(results.map(result => Math.floor(bible.verses[result.index]![0] / 1000000)));
  expect(books).toContain(1);
  expect(books).toContain(58);
  expect(network).not.toHaveBeenCalled();
  expect(searchBible('zzzznotabibleword')).toEqual([]);
  expect(() => searchBible('constructor prototype __proto__')).not.toThrow();
});

it('validates a bundled quotation without web search and rejects changed text or translation', () => {
  const context = retrieveBible(messages('John 11:35'));
  const passage = context.passages[0]!;
  const sources = new AnswerSources(); sources.addBible(context.passages);
  const answer = `> [Scripture] ${passage.text}\n[John 11:35 — BSB](${passage.url})`;
  expect(sources.finish(answer).quotes![0]!.text).toBe(passage.text);
  expect(sources.finish(answer).sources![0]!.title).toContain('bundled Bible');
  expect(() => sources.finish(answer.replace('BSB]', 'ESV]'))).toThrow('sources_unavailable');
  expect(() => sources.finish(answer.replace(passage.text, 'Fabricated words.'))).toThrow('sources_unavailable');
  // A matching URL annotation must not overwrite the local evidence.
  sources.add([{ type: 'url_citation', url_citation: { url: passage.url, content: 'Fabricated words.' } }]);
  expect(() => sources.finish(answer.replace(passage.text, 'Fabricated words.'))).toThrow('sources_unavailable');
  expect(sources.finish(answer).sources![0]).not.toHaveProperty('content');
  expect(sources.finish(answer).sources![0]).not.toHaveProperty('translation');
});

it('counts the actual extra Bible evidence in the existing usage reservation', () => {
  expect(reservationMicros(messages('Explain Romans 8'))).toBeGreaterThan(reservationMicros(messages('Hello')));
  expect(biblePrompt(retrieveBible(messages('Explain Romans 8')))).toContain('not the entire Bible in context');
});

const usage = { cost: .001, prompt_tokens: 30, completion_tokens: 5 };
it.each([false, true])('grounds and checks the answer in one provider request (stream=%s)', async stream => {
  const input = messages('John 11:35'), context = retrieveBible(input), passage = context.passages[0]!;
  const answer = `Jesus shares in human grief. [John 11:35 — BSB](${passage.url})`;
  const content = JSON.stringify({ decision: 'answer', answer });
  const upstream = vi.fn().mockResolvedValue(stream ? new Response(
    `data: ${JSON.stringify({ id: 'test-generation', choices: [{ delta: { content }, finish_reason: 'stop' }], usage })}\n\n` +
    'data: [DONE]\n\n') : Response.json({ id: 'test-generation', choices: [{ message: { content }, finish_reason: 'stop' }], usage }));
  vi.stubGlobal('fetch', upstream);
  const signal = new AbortController().signal;
  const result = stream ? await streamAnswer(input, 'test-key', 'test-user', signal, async () => {}) :
    await generateAnswer(input, 'test-key', 'test-user', signal);
  expect(upstream).toHaveBeenCalledTimes(1);
  const sent = JSON.parse(upstream.mock.calls[0]![1].body);
  expect(sent.messages[0].content).toContain(passage.text);
  expect(sent.messages[0].content).toContain('Do not use paid web search');
  expect(sent.messages.slice(1)).toEqual(input);
  expect(result.sources![0]!.url).toBe(passage.url);
  expect(result.quotes).toEqual([]);
  expect(result.usage.costMicros).toBe(1055);
});

it('splits cross-chapter evidence into independently readable citation links', () => {
  const context = retrieveBible(messages('Explain Romans 8:39-9:3'));
  expect(context.passages.slice(0, 2).map(p => [p.reference, p.url])).toEqual([
    ['Romans 8:39', 'https://www.bible.com/bible/3034/ROM.8.39'],
    ['Romans 9:1–3', 'https://www.bible.com/bible/3034/ROM.9.1-3'],
  ]);
  expect(context.limited).toBe(false);
});
