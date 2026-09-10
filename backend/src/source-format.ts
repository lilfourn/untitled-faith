import { trustedURL } from './web-search';

export type SourceEvidence = {
  id: string; title: string; url: string; kind: 'scripture' | 'commentary'; content: string;
  translation?: 'BSB' | 'ESV'; reference?: string; authoritative?: boolean;
};

export function normalizedQuotation(text: string, scripture: boolean): string {
  // Verse numbers and publisher cross-reference markers are not quotation wording.
  const content = scripture ? text.replace(/[⁰¹²³⁴⁵⁶⁷⁸⁹]+|\([A-Z]{1,3}\)|\[[a-zA-Z0-9]{1,3}\]/g, '') : text;
  return content.normalize('NFKC').replace(/[“”]/g, '"').replace(/[‘’]/g, "'").replace(/\s+/g, ' ').trim();
}

export function quotationMatches(quote: string, source: SourceEvidence): boolean {
  const normalized = normalizedQuotation(quote, source.kind === 'scripture');
  return normalized.length > 0 && normalizedQuotation(source.content, source.kind === 'scripture').includes(normalized);
}

export function sourceKey(value: string): string | undefined {
  const url = trustedURL(value);
  if (!url) return;
  url.hostname = url.hostname.replace(/^www\./, '');
  if (url.hostname === 'esv.org') {
    url.pathname = decodeURIComponent(url.pathname).replace(/\+/g, ' ').replace(/[–—]/g, '-');
  }
  url.pathname = url.pathname.replace(/\/$/, '');
  url.searchParams.sort();
  return url.href;
}

export function scriptureTranslation(url: URL): 'ESV' | undefined {
  const host = url.hostname.replace(/^www\./, '');
  if (host === 'esv.org' || (host === 'biblegateway.com' && url.searchParams.get('version')?.toUpperCase() === 'ESV') ||
      (host === 'bible.com' && /^\/(?:[a-z]{2}\/)?bible\/59\//i.test(url.pathname))) return 'ESV';
}

export function plainQuotation(text: string): string {
  return text.replace(/\*\*([^*]+)\*\*|__([^_]+)__|\*([^*]+)\*|_([^_]+)_|`([^`]+)`/g,
    (_match, ...groups: unknown[]) => String(groups.slice(0, 5).find(value => typeof value === 'string') ?? ''))
    .replace(/^\[(?:Scripture|Commentary)\]\s*/i, '')
    .replace(/\[([^\]\n]+)\]\([^\s)]+\)/g, '$1').trim();
}
