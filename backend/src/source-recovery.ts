import { MAX_COMMENTARY_QUOTE_WORDS } from './quotation-policy';
import { plainQuotation, quotationMatches, sourceKey, type SourceEvidence } from './source-format';

const quotedLine = /^ {0,3}>[ \t]?(.*)$/;
const attribution = /^[ \t]*(?:[-–—][ \t]*)?(?:\*\*)?\[([^\]\n]+)\]\((https:\/\/[^\s]+)\)(?:\*\*)?[ \t]*$/;

/** Repair individual citation presentation; never discard unrelated answer prose. */
export function recoverSources(text: string, evidence: readonly SourceEvidence[]) {
  const byURL = new Map(evidence.map(source => [sourceKey(source.url), source]));
  const find = (url: string) => { const key = sourceKey(url); return key ? byURL.get(key) : undefined; };
  const lines = text.replace(/\r\n?/g, '\n').split('\n');
  const chunks: { text: string; quote: boolean }[] = [];
  const quotedWords = new Map<string, number>();
  let removedQuotes = 0, repairedQuotes = 0, shortenedQuotes = 0, removedLinks = 0, keptQuotes = 0;

  for (let index = 0; index < lines.length;) {
    if (!quotedLine.test(lines[index]!)) { chunks.push({ text: lines[index++]!, quote: false }); continue; }
    const quoteLines: string[] = [];
    while (index < lines.length && quotedLine.test(lines[index]!)) {
      quoteLines.push(quotedLine.exec(lines[index++]!)![1]!);
    }
    let citation = attribution.exec(quoteLines.at(-1) ?? '');
    if (citation) quoteLines.pop();
    else {
      let next = index;
      while (next < lines.length && !lines[next]!.trim()) next++;
      citation = attribution.exec(lines[next] ?? '');
      if (citation) index = next + 1;
    }
    let quote = plainQuotation(quoteLines.join(' '));
    let source = citation ? find(citation[2]!) : undefined;
    const variants = [quote, quote.replace(/^[“"]([\s\S]*)[”"]$/, '$1')];
    let match = source && variants.find(value => quotationMatches(value, source!));
    if (!match) {
      // The selected web excerpt can contain footnote noise. Prefer another verified ESV
      // excerpt for the same wording, and link to the evidence actually used.
      const alternate = evidence.find(candidate => candidate.kind === 'scripture' && candidate.translation === 'ESV' &&
        variants.some(value => quotationMatches(value, candidate)));
      if (alternate) {
        source = alternate;
        match = variants.find(value => quotationMatches(value, alternate));
      }
    }
    if (!source || !match || keptQuotes >= 20) { removedQuotes++; continue; }
    quote = match;
    if (source.kind === 'commentary') {
      const available = MAX_COMMENTARY_QUOTE_WORDS - (quotedWords.get(source.id) ?? 0);
      if (available <= 0) { removedQuotes++; continue; }
      const words = quote.split(/\s+/);
      if (words.length > available) { quote = words.slice(0, available).join(' '); shortenedQuotes++; }
      quotedWords.set(source.id, (quotedWords.get(source.id) ?? 0) + Math.min(words.length, available));
    }
    // Derive Scripture attribution from the selected evidence, especially when another
    // excerpt repaired the original citation. Keep the translation suffix after truncation.
    const label = source.kind === 'scripture' ? source.reference ?? source.title.split('\n')[0]! : citation?.[1] ?? source.title;
    const baseLabel = label.replace(/\s*[-–—(]?\s*(?:ESV|BSB)\)?\s*$/i, '').replace(/[\[\]\r\n]/g, ' ').trim().slice(0, 180);
    const safeLabel = source.translation ? `${baseLabel} - ${source.translation}` : baseLabel;
    chunks.push({ text: `> [${source.kind === 'scripture' ? 'Scripture' : 'Commentary'}] ${quote}\n[${safeLabel}](${source.url})\n`, quote: true });
    keptQuotes++;
    repairedQuotes++;
  }

  // Resolving aliases can lengthen labels. Drop complete quotation blocks, never cut one in half.
  while (chunks.map(chunk => chunk.text).join('\n').length > 8000) {
    let index = chunks.length - 1;
    while (index >= 0 && !chunks[index]!.quote) index--;
    if (index < 0) break;
    chunks.splice(index, 1);
    removedQuotes++;
  }
  let length = chunks.map(chunk => chunk.text).join('\n').length;
  const repaired = chunks.map(chunk => chunk.text).join('\n').replace(/\[([^\]\n]+)\]\(([^\s)]+)\)/g,
    (link, label: string, url: string) => {
      const source = find(url);
      const replacement = source ? `[${label}](${source.url})` : label;
      if (!source || length + replacement.length - link.length > 8000) {
        removedLinks++;
        length += label.length - link.length;
        return label;
      }
      length += replacement.length - link.length;
      return replacement;
    }).trim();
  return { text: repaired, removedQuotes, repairedQuotes, shortenedQuotes, removedLinks };
}
