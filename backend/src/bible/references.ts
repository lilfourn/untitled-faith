import { bible } from './data';
import type { BiblePassage } from './types';

export type PassageRange = { start: number; end: number };
const normalize = (value: string) => value.toLowerCase().replace(/\./g, '').replace(/^([1-3])(?=[a-z])/, '$1 ').replace(/\s+/g, ' ').trim();
const names = new Map(bible.books.flatMap(book => [book.name, ...book.aliases].map(name => [normalize(name), book] as const)));
const escape = (value: string) => value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const bookPattern = [...names.keys()].sort((a, b) => b.length - a.length)
  .map(name => name.split(' ').map(escape).join('\\s*') + '\\.?').join('|');
const referencePattern = `\\b(${bookPattern})\\s*(\\d{1,3})(?::(\\d{1,3}))?(?:\\s*[-–—]\\s*(\\d{1,3})(?::(\\d{1,3}))?)?(?![\\d:])`;

export function referencesIn(text: string): PassageRange[] {
  const ranges: PassageRange[] = [];
  for (const match of text.matchAll(new RegExp(referencePattern, 'gi'))) {
    const book = names.get(normalize(match[1]!));
    if (!book) continue;
    const chapter = Number(match[2]);
    const verse = match[3] ? Number(match[3]) : undefined;
    const endChapter = match[5] || (match[4] && !verse) ? Number(match[4]) : chapter;
    const endVerse = match[5] ? Number(match[5]) : verse && match[4] ? Number(match[4]) : verse;
    if (chapter < 1 || chapter > book.chapters || endChapter < chapter || endChapter > book.chapters ||
        (verse !== undefined && verse < 1) || (endVerse !== undefined && endVerse < 1)) continue;
    const start = book.id * 1_000_000 + chapter * 1000 + (verse ?? 1);
    const end = book.id * 1_000_000 + endChapter * 1000 + (endVerse ?? 999);
    if (end < start) continue;
    // Do not turn a nonexistent reference into an unrelated nearest verse.
    const first = lowerBound(start);
    const last = lowerBound(end);
    if (verse !== undefined && bible.verses[first]?.[0] !== start) continue;
    if (endVerse !== undefined && bible.verses[last]?.[0] !== end) continue;
    if (bible.verses[first]?.[0] && bible.verses[first]![0] <= end) ranges.push({ start, end });
    if (ranges.length === 8) break;
  }
  return ranges;
}

export function lowerBound(id: number): number {
  let low = 0, high = bible.verses.length;
  while (low < high) {
    const middle = (low + high) >>> 1;
    if (bible.verses[middle]![0] < id) low = middle + 1;
    else high = middle;
  }
  return low;
}

/** Read a chapter/range from the complete corpus. Limits are applied by the context packer. */
export function readPassage(range: PassageRange): [number, string][] {
  return bible.verses.slice(lowerBound(range.start), lowerBound(range.end + 1));
}

export function passageFromVerses(verses: [number, string][]): BiblePassage {
  const first = verses[0]![0], last = verses.at(-1)![0];
  if (Math.floor(first / 1000) !== Math.floor(last / 1000)) throw new Error('Split Bible passages at chapter boundaries');
  const book = bible.books[Math.floor(first / 1_000_000) - 1]!;
  const chapter = Math.floor(first / 1000) % 1000;
  const startVerse = first % 1000, endVerse = last % 1000;
  const suffix = first === last ? '' : `–${endVerse}`;
  // This is a canonical reading link. The evidence is the bundled BSB, not a fetched web excerpt.
  const location = `${book.code}.${chapter}.${startVerse}` + (first === last ? '' : `-${endVerse}`);
  return { reference: `${book.name} ${chapter}:${startVerse}${suffix}`, translation: 'BSB',
    url: `https://www.bible.com/bible/3034/${location}`, text: verses.map(([, text]) => text).join(' ') };
}
