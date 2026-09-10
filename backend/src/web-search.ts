// Product-approved sources. Keep the search filter and citation validation together.
export const TRUSTED_DOMAINS = ['biblegateway.com', 'bible.com', 'esv.org', 'bibleproject.com', 'gotquestions.org'];
export const SEARCH_RESULTS = 5;
export const SEARCH_CHARACTERS = 2000;
export const SEARCH_CALLS = 1;
export const SEARCH_COST_USD = 0.007; // Exa fast, up to ten results (OpenRouter, September 2026).

export const WEB_SEARCH_TOOL = {
  type: 'openrouter:web_search',
  parameters: { engine: 'exa', mode: 'fast', max_uses: SEARCH_CALLS, max_results: SEARCH_RESULTS,
    max_total_results: SEARCH_RESULTS, max_characters: SEARCH_CHARACTERS, allowed_domains: TRUSTED_DOMAINS },
};

export function trustedURL(value: string): URL | undefined {
  try {
    const url = new URL(value);
    const host = url.hostname.replace(/^www\./, '');
    if (url.protocol !== 'https:' || url.username || url.password || url.port || !TRUSTED_DOMAINS.includes(host)) return;
    url.hash = '';
    if (['biblegateway.com', 'bible.com', 'esv.org'].includes(host) && sourceKind(url) !== 'scripture') return;
    return url;
  } catch { return; }
}

export function sourceKind(url: URL): 'scripture' | 'commentary' {
  const host = url.hostname.replace(/^www\./, '');
  // Publishers also host articles/devotionals. Only passage routes are Scripture sources.
  if (host === 'biblegateway.com' && (/^\/(passage|verse)\/?$/i.test(url.pathname) ||
      /^\/verse\/(?:[a-z]{2}\/)?[^/]*\d[^/]*\/?$/i.test(decodeURIComponent(url.pathname)))) return 'scripture';
  if (host === 'bible.com' && /^\/(?:[a-z]{2}\/)?bible\/\d+\//i.test(url.pathname)) return 'scripture';
  // YouVersion also publishes actual passage text on its translation-comparison route.
  if (host === 'bible.com' && /^\/(?:[a-z]{2}\/)?bible\/compare\/[1-3]?[a-z]{2,3}\.\d{1,3}(?:\.\d{1,3}(?:-\d{1,3})?)?\/?$/i.test(url.pathname)) return 'scripture';
  if (host === 'esv.org' && /^\/(?:verses\/)?(?:song[ +]of[ +](?:solomon|songs)|(?:[1-3][ +]?)?[a-z]+\.?)[ +]?\d/i.test(decodeURIComponent(url.pathname))) return 'scripture';
  return 'commentary';
}
