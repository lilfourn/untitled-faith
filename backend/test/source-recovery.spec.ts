import { expect, it } from 'vitest';
import { AnswerSources } from '../src/answer-sources';
import { trustedURL } from '../src/web-search';
import { retrieveBible } from '../src/bible/context';
import { SYSTEM_PROMPT } from '../src/answer-prompt';

const hebrews = 'Now faith is the assurance of things hoped for, the conviction of things not seen.';
const esv = 'https://www.esv.org/verses/Heb.%2011%3A1/';
const gateway = 'https://www.biblegateway.com/passage/?search=Hebrews+11&version=ESV';
const annotation = (url: string, content: string, title = 'Hebrews 11:1') =>
  ({ type: 'url_citation', url_citation: { url, content, title } });

it('repairs the reproduced ESV verse-route and publisher footnote failure', () => {
  const sources = new AnswerSources();
  sources.add([
    annotation(esv, hebrews.replace('of things not seen', 'of e things not seen')),
    annotation(gateway, hebrews.replace('of things not seen', 'of (A) things not seen')),
  ]);
  const result = sources.resolve(`Faith is trust in God.\n\n> [Scripture] ${hebrews}\n[Hebrews 11:1 (ESV)](${esv})\n\nThis trust shapes how we live.`);
  expect(result.text).toContain('Faith is trust in God.');
  expect(result.text).toContain('This trust shapes how we live.');
  expect(result.quotes).toHaveLength(1);
  expect(result.quotes![0]!.text).toBe(hebrews);
  expect(result.sources![0]!.url).toBe(gateway);
  expect(result.text).toContain(`](${gateway})`);
});

it.each([esv, 'https://www.biblegateway.com/verse/en/Hebrews%2011:1'])('recognizes actual publisher verse route %s', url => {
  expect(trustedURL(url)?.href).toBe(url);
});

it('normalizes URL aliases and markup while rebuilding valid UTF-16 quotation ranges', () => {
  const sources = new AnswerSources();
  const url = 'https://www.esv.org/John%2011%3A35/';
  sources.addBible([{ reference: 'John 11:35', translation: 'ESV', url, text: 'Jesus wept.' }]);
  const result = sources.resolve('🙏 Comfort in grief.\r\n\r\n  > [Scripture] **“Jesus wept.”**\r\n\r\n\r\n**[John 11:35 (ESV)](https://esv.org/John+11:35#verse)**\r\n\r\nJesus cares.');
  expect(result.text).toContain(`](${url})`);
  expect(result.quotes![0]!.text).toBe('Jesus wept.');
  const quote = result.quotes![0]!;
  expect(result.text.slice(quote.startIndex, quote.endIndex)).toContain('> [Scripture] Jesus wept.');
  expect(result.text.slice(0, quote.startIndex)).toContain('🙏');
  expect(quote.attribution).toBe('John 11:35 - ESV');
});

it('keeps the explanation and good quote when another quotation or URL is unsupported', () => {
  const sources = new AnswerSources();
  sources.add([annotation(esv, hebrews)]);
  const result = sources.resolve(`Faith is trust in God.\n\n> [Scripture] ${hebrews}\n[Hebrews 11:1 - ESV](${esv})\n\n> [Scripture] Made-up words.\n[Wrong](https://evil.example/)\n\nExplore [prayer](https://www.gotquestions.org/not-retrieved.html) and seek wise counsel.`);
  expect(result.text).toContain('Faith is trust in God.');
  expect(result.text).toContain('Explore prayer and seek wise counsel.');
  expect(result.text).not.toContain('Made-up words');
  expect(result.text).not.toContain('evil.example');
  expect(result.text).not.toContain('not-retrieved');
  expect(result.quotes).toHaveLength(1);
});

it('recovers an attribution placed inside the blockquote', () => {
  const sources = new AnswerSources();
  sources.add([annotation(esv, hebrews)]);
  const result = sources.resolve(`> [Scripture] ${hebrews}\n> [Hebrews 11:1 - ESV](${esv})`);
  expect(result.quotes).toHaveLength(1);
});

it('trims verified commentary to the cumulative excerpt budget without discarding the answer', () => {
  const sources = new AnswerSources();
  const url = 'https://www.gotquestions.org/faith.html';
  const first = Array.from({length: 20}, (_, index) => `word${index}`).join(' ');
  const second = Array.from({length: 10}, (_, index) => `more${index}`).join(' ');
  sources.add([annotation(url, `${first} ${second}`, 'GotQuestions')]);
  const result = sources.resolve(`Here is an explanation.\n\n> [Commentary] ${first}\n[GotQuestions](${url})\n\n> [Commentary] ${second}\n[GotQuestions](${url})\n\nScripture remains primary.`);
  expect(result.quotes).toHaveLength(2);
  expect(result.quotes!.reduce((count, quote) => count + quote.text.split(/\s+/).length, 0)).toBe(25);
  expect(result.text).toContain('Scripture remains primary.');
});

it('ignores empty repeated annotations and excessive unused search results', () => {
  const sources = new AnswerSources();
  sources.add([annotation(esv, hebrews), annotation(esv, '')]);
  sources.add(Array.from({length: 30}, (_, index) => annotation(`https://www.gotquestions.org/page${index}.html`, 'Other text')));
  const result = sources.resolve(`Faith is trust.\n\n> [Scripture] ${hebrews}\n[Hebrews 11:1 - ESV](${esv})`);
  expect(result.quotes).toHaveLength(1);
  expect(result.sources).toHaveLength(1);
  expect(result.sources![0]).not.toHaveProperty('content');
  expect(result.sources![0]).not.toHaveProperty('authoritative');
});

it('retains the translation suffix when a source has a long title', () => {
  const sources = new AnswerSources();
  sources.add([annotation(esv, hebrews, 'Title '.repeat(40))]);
  const result = sources.resolve(`> [Scripture] ${hebrews}\n[Hebrews 11:1](${esv})`);
  expect(result.quotes![0]!.attribution).toMatch(/ - ESV$/);
  expect(result.quotes![0]!.attribution.length).toBeLessThanOrEqual(200);
});

it('does not accept changed words as a verified quotation', () => {
  const sources = new AnswerSources();
  sources.add([annotation(esv, hebrews)]);
  const result = sources.resolve(`Faith involves trust.\n\n> [Scripture] ${hebrews.replace('assurance', 'guarantee')}\n[Hebrews 11:1 - ESV](${esv})`);
  expect(result.text).toBe('Faith involves trust.');
  expect(result.quotes).toBeUndefined();
});

it('retrieves the central faith passages and gives the model an explicit output contract', () => {
  const context = retrieveBible([{ role: 'user', content: 'What does it mean to have faith?' }]);
  expect(context.passages.some(passage => passage.reference.startsWith('Hebrews 11:1'))).toBe(true);
  expect(context.passages.some(passage => passage.reference.startsWith('Ephesians 2:1'))).toBe(true);
  expect(SYSTEM_PROMPT).toContain('exactly two fields: "decision" and "answer"');
  expect(SYSTEM_PROMPT).toContain('A quotation by itself is not a complete answer.');
});


it('keeps quotation and response limits compatible with the phone after repairs', () => {
  const sources = new AnswerSources();
  sources.add([annotation(esv, hebrews)]);
  const blocks = Array.from({length: 22}, () => `> [Scripture] ${hebrews}\n[Hebrews 11:1 - ESV](${esv})`).join('\n\n');
  const result = sources.resolve(`Faith involves trust.\n\n${blocks}`);
  expect(result.quotes).toHaveLength(20);
  expect(result.text.length).toBeLessThanOrEqual(8000);
  let previousEnd = 0;
  for (const quote of result.quotes!) {
    expect(quote.startIndex).toBeGreaterThanOrEqual(previousEnd);
    expect(quote.endIndex).toBeLessThanOrEqual(result.text.length);
    expect(result.text.slice(quote.startIndex, quote.endIndex)).toContain(hebrews);
    previousEnd = quote.endIndex;
  }
});


it('deduplicates publisher aliases without erasing evidence or multiplying the quotation allowance', () => {
  const sources = new AnswerSources();
  const url = 'https://www.gotquestions.org/faith.html';
  const alias = 'https://gotquestions.org/faith.html';
  const quote = Array.from({length: 20}, (_, index) => `word${index}`).join(' ');
  sources.add([annotation(url, quote, 'GotQuestions'), annotation(alias, '', 'GotQuestions')]);
  const result = sources.resolve(`Faith involves trust.\n\n> [Commentary] ${quote}\n[GotQuestions](${url})\n\n> [Commentary] ${quote}\n[GotQuestions](${alias})`);
  expect(result.sources).toHaveLength(1);
  expect(result.quotes).toHaveLength(2);
  expect(result.quotes!.reduce((count, item) => count + item.text.split(/\s+/).length, 0)).toBe(25);
  expect(result.quotes![0]!.sourceID).toBe(result.quotes![1]!.sourceID);
  expect(result.text).not.toContain(`](${alias})`);
});
