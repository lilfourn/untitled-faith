import type { Message } from '../contract';
import { APIError } from '../http';
import { fetchESVPassages, type ESVAccess } from '../esv';
import { retrieveBible } from './context';
import { passageFromVerses, readPassage, referencesIn } from './references';
import { MAX_BIBLE_CONTEXT_CHARACTERS, MAX_BIBLE_PASSAGES, type BibleContext, type BiblePassage } from './types';

/** Discover cheaply with BSB, then fetch up to 3 ESV selections in one server-to-server request. */
export async function prepareBible(messages: Message[], env: ESVAccess, userID: string, signal: AbortSignal): Promise<BibleContext> {
  const background = retrieveBible(messages);
  if (!env.ESV_API_KEY?.trim() || !background.passages.length) return background;
  // At most 48 verses requested. Crossway applies its own per-book licensing limits as well.
  const selections = background.passages.slice(0, 3).flatMap(passage => {
    const range = referencesIn(passage.reference)[0];
    const rows = range ? readPassage(range).slice(0, 16) : [];
    return rows.length ? [passageFromVerses(rows).reference] : [];
  });
  if (!selections.length) return background;
  try {
    const fetched = await fetchESVPassages(selections, env, userID,
      AbortSignal.any([signal, AbortSignal.timeout(6000)]), false);
    const requested = selections.flatMap(referencesIn);
    const passages: BiblePassage[] = fetched.flatMap(passage => {
      const actual = referencesIn(passage.reference);
      if (actual.length !== 1 || !requested.some(range => actual[0]!.start >= range.start && actual[0]!.end <= range.end)) return [];
      return [{ ...passage, translation: 'ESV' as const,
        url: `https://www.esv.org/${encodeURIComponent(passage.reference.replace(/[–—]/g, '-'))}/` }];
    });
    if (!passages.length) return background;
    const result: BibleContext = { passages: [], limited: background.limited };
    const included = new Set<string>();
    const normalize = (reference: string) => reference.replace(/^Psalms\b/, 'Psalm').replace(/[–—]/g, '-');
    for (const passage of [...passages, ...background.passages]) {
      if (included.has(normalize(passage.reference))) continue;
      if (result.passages.length >= MAX_BIBLE_PASSAGES ||
          JSON.stringify({ passages: [...result.passages, passage], limited: false }).length > MAX_BIBLE_CONTEXT_CHARACTERS) {
        result.limited = true;
        continue;
      }
      result.passages.push(passage);
      included.add(normalize(passage.reference));
    }
    return result;
  } catch {
    if (signal.aborted) throw new APIError(504, 'answer_timeout');
    // Crossway downtime/quota exhaustion must never cause BSB to be relabeled ESV.
    // The answer can use verified web evidence or paraphrase the BSB background.
    return background;
  }
}
