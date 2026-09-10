import { recoverSources } from './source-recovery';
import { quotationMatches, scriptureTranslation, sourceKey, type SourceEvidence } from './source-format';
import { APIError, isRecord } from './http';
import { sourceKind, trustedURL } from './web-search';
import type { BiblePassage } from './bible/types';
import { MAX_COMMENTARY_QUOTE_WORDS } from './quotation-policy';

export class SourceValidationError extends APIError {
  constructor(readonly reason: 'invalid_evidence' | 'source_limit' | 'unverified_link' | 'missing_quote_source' |
    'quotation_length' | 'translation_mismatch' | 'quotation_mismatch' | 'unlinked_quote') {
    super(502, 'sources_unavailable');
    this.name = 'SourceValidationError';
  }
}

export type AnswerSource = { id: string; title: string; url: string; kind: 'scripture' | 'commentary' };
export type AnswerQuote = { id: string; text: string; attribution: string; sourceID: string; startIndex: number; endIndex: number };
type RetrievedSource = SourceEvidence;

export class AnswerSources {
  private readonly sources = new Map<string, RetrievedSource>();

  /** Server-selected, verbatim corpus evidence. Never accept this from client request fields. */
  addBible(passages: BiblePassage[]): void {
    for (const passage of passages) {
      const url = trustedURL(passage.url);
      if (!url || !['BSB', 'ESV'].includes(passage.translation)) throw new SourceValidationError('invalid_evidence');
      const key = sourceKey(url.href)!;
      if (!this.sources.has(key) && this.sources.size >= 20) throw new SourceValidationError('source_limit');
      this.sources.set(key, { id: this.sources.get(key)?.id ?? crypto.randomUUID(), url: url.href,
        title: `${passage.reference} — ${passage.translation} (${passage.translation === 'ESV' ? 'Crossway' : 'bundled Bible'})`, kind: 'scripture',
        content: passage.text, translation: passage.translation, reference: passage.reference, authoritative: true });
    }
  }

  add(annotations: unknown): void {
    if (!Array.isArray(annotations)) return;
    for (const annotation of annotations) {
      if (!isRecord(annotation) || annotation.type !== 'url_citation' || !isRecord(annotation.url_citation)) continue;
      const value = annotation.url_citation;
      const url = typeof value.url === 'string' && value.url.length <= 2048 ? trustedURL(value.url) : undefined;
      if (!url) continue;
      const key = sourceKey(url.href)!;
      if (!this.sources.has(key) && this.sources.size >= 20) continue;
      const existing = this.sources.get(key);
      // A web annotation cannot replace the authoritative text already used for grounding.
      if (existing?.authoritative) continue;
      this.sources.set(key, { id: existing?.id ?? crypto.randomUUID(), url: existing?.url ?? url.href,
        title: typeof value.title === 'string' ? value.title.slice(0, 240) : url.hostname,
        kind: sourceKind(url), translation: scriptureTranslation(url),
        content: typeof value.content === 'string' && value.content.trim() ? value.content.slice(0, 20000) : existing?.content ?? '' });
    }
  }

  resolve(text: string): { text: string; sources?: AnswerSource[]; quotes?: AnswerQuote[] } {
    const repaired = recoverSources(text, [...this.sources.values()]);
    if (!repaired.text) throw new SourceValidationError('missing_quote_source');
    const result = this.finish(repaired.text);
    if (repaired.text !== text.trim()) {
      const { text: _text, ...counts } = repaired;
      console.log(JSON.stringify({ event: 'answer_sources_recovered', ...counts }));
    }
    return { text: repaired.text, ...result };
  }

  finish(text: string): { sources?: AnswerSource[]; quotes?: AnswerQuote[] } {
    const quotes: AnswerQuote[] = [];
    const quotedWords = new Map<string, number>();
    const cited = new Set<string>();
    // Links must identify retrieved web evidence or a passage actually supplied from the local corpus.
    for (const link of text.matchAll(/\[[^\]\n]+\]\((https?:\/\/[^\s]+)\)/g)) {
      const url = trustedURL(link[1]!);
      const source = url ? this.sources.get(sourceKey(url.href)!) : undefined;
      if (!source) throw new SourceValidationError('unverified_link');
      cited.add(source.url);
    }
    // A quote is a block followed immediately by the exact source URL. Offsets use UTF-16 on both platforms.
    const pattern = /^>[^\n]*(?:\n>[^\n]*)*\n(?:[ \t]*\n)?\[([^\]\n]+)\]\((https:\/\/[^\s]+)\)[ \t]*(?:\n|$)/gm;
    for (const match of text.matchAll(pattern)) {
      const quoteLines = match[0].split('\n').filter(line => line.startsWith('>'));
      const quote = quoteLines.map(line => line.replace(/^>[ \t]?/, '')).join(' ')
        .replace(/^\[(?:Scripture|Commentary)\]\s*/i, '').trim();
      const url = trustedURL(match[2]!);
      const source = url ? this.sources.get(sourceKey(url.href)!) : undefined;
      const words = quote.split(/\s+/).length + (quotedWords.get(source?.id ?? '') ?? 0);
      if (!source || !quote) throw new SourceValidationError('missing_quote_source');
      if (source.kind === 'commentary' && words > MAX_COMMENTARY_QUOTE_WORDS) {
        throw new SourceValidationError('quotation_length');
      }
      if (source.translation && !new RegExp(`\\b${source.translation}\\s*$`).test(match[1]!)) {
        throw new SourceValidationError('translation_mismatch');
      }
      if (!quotationMatches(quote, source)) throw new SourceValidationError('quotation_mismatch');
      quotedWords.set(source.id, words);
      quotes.push({ id: crypto.randomUUID(), text: quote, attribution: match[1]!.slice(0, 200), sourceID: source.id,
        startIndex: match.index, endIndex: match.index + match[0].length });
    }
    // Never silently render an unlinked blockquote as a sourced quotation.
    for (const line of text.matchAll(/^>/gm)) {
      if (!quotes.some(quote => line.index >= quote.startIndex && line.index < quote.endIndex)) throw new SourceValidationError('unlinked_quote');
    }
    const sources = [...this.sources.values()].filter(source => cited.has(source.url))
      .map(({ id, title, url, kind }) => ({ id, title, url, kind }));
    return sources.length ? { sources, quotes } : {};
  }
}
