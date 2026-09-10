import { authenticate } from "./auth";
import { requireAccount } from "./accounts";
import { APIError, jsonResponse, readJSON } from "./http";

// Crossway's ESV API (https://api.esv.org). Terms: up to 500 verses per query, 5,000 queries per day, 60 per
// minute, and clients may store no more than 500 verses locally. The key never leaves this Worker, and no
// passage text is cached here; the app keeps its own capped cache.
export const ESV_ENDPOINT = "https://api.esv.org/v3/passage/text/";
export const ESV_NOTICE = "Scripture quotations are from the ESV® Bible (The Holy Bible, English Standard Version®), " +
  "© 2001 by Crossway, a publishing ministry of Good News Publishers. Used by permission. All rights reserved.";
export const MAX_PASSAGES_PER_REQUEST = 8;
const REFERENCE = /^((?:[1-3] )?[A-Za-z]+(?: (?:of )?[A-Za-z]+)?) \d{1,3}(?::\d{1,3}(?:[-–]\d{1,3}(?::\d{1,3})?)?)?$/;
// Canonical book names as the app sends them; anything else is rejected before spending Crossway quota.
const BOOKS = new Set(("Genesis|Exodus|Leviticus|Numbers|Deuteronomy|Joshua|Judges|Ruth|1 Samuel|2 Samuel|1 Kings|2 Kings|" +
  "1 Chronicles|2 Chronicles|Ezra|Nehemiah|Esther|Job|Psalm|Psalms|Proverbs|Ecclesiastes|Song of Solomon|Isaiah|Jeremiah|" +
  "Lamentations|Ezekiel|Daniel|Hosea|Joel|Amos|Obadiah|Jonah|Micah|Nahum|Habakkuk|Zephaniah|Haggai|Zechariah|Malachi|" +
  "Matthew|Mark|Luke|John|Acts|Romans|1 Corinthians|2 Corinthians|Galatians|Ephesians|Philippians|Colossians|" +
  "1 Thessalonians|2 Thessalonians|1 Timothy|2 Timothy|Titus|Philemon|Hebrews|James|1 Peter|2 Peter|1 John|2 John|3 John|" +
  "Jude|Revelation").toLowerCase().split("|"));
const ESV_OPTIONS = {
  "include-passage-references": "false", "include-verse-numbers": "true", "include-first-verse-numbers": "true",
  "include-footnotes": "false", "include-footnote-body": "false", "include-headings": "false",
  "include-short-copyright": "false", "include-copyright": "false", "include-selahs": "true",
  "indent-poetry": "false", "indent-paragraphs": "0", "indent-declares": "0", "indent-psalm-doxology": "0", "line-length": "0",
};

export type ESVAccess = { ESV_API_KEY?: string; PASSAGES_RATE_LIMITER: RateLimit };
export type PassageEnv = Env & ESVAccess;
export type Passage = { reference: string; text: string };

/** GET /v1/passages?q=John+3:16;Romans+8:28 → { translation, notice, passages: [{ reference, text }] } */
export async function handlePassages(request: Request, env: PassageEnv): Promise<Response> {
  const userID = await authenticate(request, env.SESSION_SIGNING_KEY);
  await requireAccount(env.DB, userID);
  const references = parseReferences(new URL(request.url).searchParams.get("q"));
  const passages = await fetchESVPassages(references, env, userID,
    AbortSignal.any([request.signal, AbortSignal.timeout(10_000)]));
  return jsonResponse({ translation: "ESV", notice: ESV_NOTICE, passages });
}

/** Only call after app authentication. Both answer grounding and verse cards share this quota. */
export async function fetchESVPassages(references: string[], env: ESVAccess, userID: string,
  signal: AbortSignal, verseNumbers = true): Promise<Passage[]> {
  const validated = parseReferences(references.join(';'));
  const key = env.ESV_API_KEY?.trim();
  if (!key) throw new APIError(503, 'not_configured');
  if (!(await env.PASSAGES_RATE_LIMITER.limit({ key: `passages:${userID}` })).success) throw new APIError(429, 'rate_limited');
  return fetchPassages(validated, key, signal, verseNumbers);
}

export function parseReferences(query: string | null): string[] {
  if (!query || query.length > 400) throw new APIError(400, "invalid_request");
  const references = query.split(";").map(part => part.replace(/\s+/g, " ").trim()).filter(Boolean);
  const valid = (part: string) => {
    const book = REFERENCE.exec(part)?.[1];
    return book !== undefined && BOOKS.has(book.toLowerCase());
  };
  if (references.length < 1 || references.length > MAX_PASSAGES_PER_REQUEST || !references.every(valid)) {
    throw new APIError(400, "invalid_request");
  }
  return references;
}

async function fetchPassages(references: string[], key: string, signal: AbortSignal, verseNumbers: boolean): Promise<Passage[]> {
  const url = new URL(ESV_ENDPOINT);
  url.searchParams.set("q", references.join(";"));
  for (const [name, value] of Object.entries(ESV_OPTIONS)) url.searchParams.set(name, value);
  url.searchParams.set('include-verse-numbers', String(verseNumbers));
  url.searchParams.set('include-first-verse-numbers', String(verseNumbers));
  let response: Response;
  try {
    response = await fetch(url, { headers: { Authorization: `Token ${key}`, Accept: "application/json" }, redirect: "manual", signal });
  } catch {
    throw new APIError(502, "passages_unavailable");
  }
  if (!response.ok) {
    await response.body?.cancel();
    throw new APIError(response.status === 429 ? 429 : 502, response.status === 429 ? 'rate_limited' : 'passages_unavailable');
  }
  let body: unknown;
  try {
    body = await readJSON(response.body, 256 * 1024);
  } catch {
    throw new APIError(502, "passages_unavailable");
  }
  return normalizePassages(body);
}

/** Pairs each returned passage with its canonical reference and rewrites "[16]" verse markers as superscripts. */
export function normalizePassages(body: unknown): Passage[] {
  if (typeof body !== "object" || body === null) throw new APIError(502, "passages_unavailable");
  const { passages, passage_meta: meta } = body as { passages?: unknown; passage_meta?: unknown };
  if (!Array.isArray(passages) || !Array.isArray(meta) || passages.length !== meta.length) throw new APIError(502, "passages_unavailable");
  const result: Passage[] = [];
  passages.forEach((passage, index) => {
    const canonical = (meta[index] as { canonical?: unknown })?.canonical;
    if (typeof passage !== "string" || typeof canonical !== "string" || !canonical) return;
    const text = normalizeText(passage);
    if (text) result.push({ reference: canonical, text });
  });
  return result;
}

export function normalizeText(passage: string): string {
  const markers = passage.match(/\[\d+\]/g) ?? [];
  let text = passage.replace(/\s+/g, " ").trim();
  if (markers.length === 1) text = text.replace(/^\[\d+\]\s*/, "");
  return text.replace(/\[(\d+)\]/g, (_, digits: string) => superscript(digits)).replace(/\s+([,.;:!?])/g, "$1").trim();
}

function superscript(digits: string): string {
  return digits.replace(/\d/g, digit => "⁰¹²³⁴⁵⁶⁷⁸⁹"[Number(digit)]!);
}
