import { expect, it } from 'vitest';
import { AnswerSources } from '../src/answer-sources';
import { trustedURL, WEB_SEARCH_TOOL } from '../src/web-search';
import { reservationMicros } from '../src/billing-policy';

const url = 'https://www.gotquestions.org/what-is-prayer.html';
const quote = 'Prayer is communication with God.';
const text = `A helpful explanation:\n\n> [Commentary] ${quote}\n[GotQuestions](${url})\n\nScripture remains the primary source.`;
const annotation = (url: string, content = quote) => ({ type: 'url_citation', url_citation: { url, title: 'What is prayer?', content } });

it('builds a distinct, source-linked quote only from matching retrieved content', () => {
  const sources = new AnswerSources();
  sources.add([annotation(url)]);
  const result = sources.finish(text);
  expect(result.sources).toHaveLength(1);
  expect(result.sources![0]).toMatchObject({ url, kind: 'commentary' });
  expect(result.quotes![0]).toMatchObject({ text: quote, sourceID: result.sources![0]!.id, attribution: 'GotQuestions' });
  const block = result.quotes![0]!;
  expect(text.slice(block.startIndex, block.endIndex)).toContain('> [Commentary]');
  expect(result.sources![0]).not.toHaveProperty('content');
});

it.each([
  'https://gotquestions.org.evil.example/article', 'https://gotquestions.org@evil.example/article',
  'http://www.gotquestions.org/article', 'https://www.gotquestions.org:444/article',
  'https://www.bible.com/events/123', 'https://www.bible.com/reading-plans/123',
  'https://www.biblegateway.com/blog/example', 'https://www.esv.org/resources/',
  'https://www.bible.com/bible/compare/reading-plans', 'https://www.bible.com/bible/compare/ROM.11.17-18/article',
  'https://ccel.org/forums/topic', 'https://newadvent.org/news/',
  'https://newadvent.org/bible/joh001.htm', 'https://opc.org/nh.html',
  'https://vatican.va/content/news.html', 'https://oca.org/news/',
  'https://oca.org/orthodoxy/the-orthodox-faith-fake/article',
  'https://ccel.org.evil.example/ccel/author/book', 'https://evil.ccel.org/ccel/author/book',
  'https://ccel.org/ccel/../forums/topic',
  'https://stanford.edu/entries/evil/', 'https://plato.stanford.edu/about.html',
  'https://plato.stanford.edu.evil.example/entries/evil/',
  'https://sbc.net/bfm2000/', 'https://bfm.sbc.net/bfm2000-fake/',
  'https://umc.org/en/content/unrelated-news', 'https://ag.org/News/',
  'https://bookofconcord.org/resources/', 'https://thegospelcoalition.org/article/news/',
  'https://bible.org/article-fake/example', 'https://bible.org/user/1',
  'https://churchofengland.org/prayer-and-worship/worship-texts-and-resources/book-common-prayer-fake/',
])('rejects unapproved citation URLs: %s', value => { expect(trustedURL(value)).toBeUndefined(); });

it.each([
  ['https://www.biblegateway.com/passage/?search=John+3%3A16&version=ESV', 'scripture'],
  ['https://www.bible.com/bible/59/JHN.3.16.ESV', 'scripture'],
  ['https://www.bible.com/bible/compare/ROM.11.17-18', 'scripture'],
  ['https://www.esv.org/John+3:16/', 'scripture'],
  ['https://bibleproject.com/articles/prayer/', 'commentary'],
  [url, 'commentary'],
])('classifies approved source %s as %s', (url, kind) => {
  const sources = new AnswerSources();
  sources.add([annotation(url)]);
  expect(sources.finish(`[Read source](${url})`).sources![0]!.kind).toBe(kind);
});

it('rejects fabricated links, unsupported quotations, and unlinked quotes', () => {
  const sources = new AnswerSources();
  sources.add([annotation(url)]);
  expect(() => sources.finish(text.replace(quote, 'Invented quotation'))).toThrow('sources_unavailable');
  expect(() => sources.finish(`[Source](https://www.gotquestions.org/invented-page.html)`)).toThrow('sources_unavailable');
  expect(() => sources.finish(`> ${quote}`)).toThrow('sources_unavailable');
});

it('counts the total quoted words per commentary source', () => {
  const content = Array(26).fill('word').join(' ');
  const sources = new AnswerSources();
  sources.add([annotation(url, content)]);
  expect(() => sources.finish(`> [Commentary] ${content}\n[Source](${url})`)).toThrow('sources_unavailable');
});

it('handles UTF-16 offsets, multiline quotes, and typographic punctuation', () => {
  const sources = new AnswerSources();
  sources.add([annotation(url, 'A “word” with\nspacing.')]);
  const result = sources.finish(`🙏\n\n> [Commentary] A "word"\n> with spacing.\n[Source](${url})`);
  expect(result.quotes![0]!.startIndex).toBe(4);
});

it('deduplicates repeated annotations and does not expose unused results', () => {
  const sources = new AnswerSources();
  sources.add([annotation(url), annotation(url), annotation('https://bibleproject.com/articles/unused')]);
  expect(sources.finish(text).sources).toHaveLength(1);
});

it('requests restricted search with a bounded search budget', () => {
  expect(WEB_SEARCH_TOOL.parameters.allowed_domains).toEqual(['biblegateway.com', 'bible.com', 'esv.org', 'bibleproject.com', 'gotquestions.org',
    'ccel.org', 'newadvent.org', 'opc.org', 'vatican.va', 'oca.org',
    'bookofconcord.org', 'bfm.sbc.net', 'umc.org', 'ag.org', 'churchofengland.org',
    'thegospelcoalition.org', 'bible.org', 'plato.stanford.edu']);
  expect(WEB_SEARCH_TOOL.parameters.engine).toBe('exa');
  expect(WEB_SEARCH_TOOL.parameters.max_uses).toBe(1);
  expect(reservationMicros([{ role: 'user', content: 'Hello' }])).toBeGreaterThan(7000);
});

it.each([
  'https://ccel.org/ccel/augustine/confessions/confessions',
  'https://www.newadvent.org/fathers/1301.htm',
  'https://www.newadvent.org/summa/1002.htm',
  'https://www.opc.org/wcf.html', 'https://opc.org/lc.html', 'https://opc.org/sc.html',
  'https://www.vatican.va/archive/ENG0015/_P2.HTM',
  'https://www.oca.org/orthodoxy/the-orthodox-faith/doctrine-scripture/the-holy-trinity',
  'https://bookofconcord.org/augsburg-confession/',
  'https://bookofconcord.org/small-catechism/',
  'https://bookofconcord.org/defense/', 'https://bookofconcord.org/epitome/',
  'https://bookofconcord.org/solid-declaration/',
  'https://bfm.sbc.net/bfm2000/',
  'https://www.umc.org/en/content/articles-of-religion',
  'https://www.umc.org/en/content/confession-of-faith',
  'https://www.umc.org/content/by-water-and-the-spirit-a-united-methodist-understanding-of-baptism',
  'https://ag.org/Beliefs/Statement-of-Fundamental-Truths',
  'https://www.churchofengland.org/prayer-and-worship/worship-texts-and-resources/book-common-prayer/articles-religion',
  'https://www.thegospelcoalition.org/essays/', 'https://www.thegospelcoalition.org/themelios/',
  'https://bible.org/article/content-and-extent-old-testament-canon',
  'https://plato.stanford.edu/entries/philosophy-religion/',
])('requires retrieved, matching evidence for theological commentary: %s', url => {
  // Synthetic evidence checks the citation boundary, not the theology of these works.
  const sources = new AnswerSources();
  const answer = `A teaching aid explains:\n\n> [Commentary] ${quote}\n[Teaching aid](${url})\n`;
  expect(() => sources.finish(answer)).toThrow('sources_unavailable');
  sources.add([annotation(url)]);
  expect(sources.finish(answer).sources![0]!.kind).toBe('commentary');
  expect(() => sources.finish(answer.replace(quote, 'Invented wording.'))).toThrow('sources_unavailable');
  sources.add([annotation(url, Array(26).fill('word').join(' '))]);
  expect(() => sources.finish(answer.replace(quote, Array(26).fill('word').join(' ')))).toThrow('sources_unavailable');
});

it('accepts a verified 109-word Scripture quotation that previously discarded an entire prayer answer', () => {
  const sources = new AnswerSources();
  const text = Array.from({ length: 109 }, (_, i) => `word${i}`).join(' ');
  const url = 'https://www.esv.org/Luke%2011%3A1-13/';
  sources.addBible([{ reference: 'Luke 11:1–13', translation: 'ESV', url, text }]);
  const answer = `Prayer expresses trust in God.\n\n> [Scripture] ${text}\n[Luke 11:9–13 — ESV](${url})\n`;
  expect(sources.finish(answer).quotes![0]!.text).toBe(text);
  expect(() => sources.finish(answer.replace('word53', 'invented'))).toThrow('sources_unavailable');
  expect(() => sources.finish(answer.replace('— ESV', '— BSB'))).toThrow('sources_unavailable');
});

it('does not impose a Scripture word limit, including across blocks', () => {
  const sources = new AnswerSources();
  const url = 'https://www.esv.org/Luke+11/';
  const words = Array(500).fill('word').join(' ');
  sources.addBible([{ reference: 'Luke 11', translation: 'ESV', url, text: words }]);
  const answer = `> [Scripture] ${words}\n[Luke 11 — ESV](${url})\n`;
  expect(sources.finish(answer).quotes).toHaveLength(1);
  expect(sources.finish(answer + `\n> [Scripture] word\n[Luke 11 — ESV](${url})\n`).quotes).toHaveLength(2);
});
