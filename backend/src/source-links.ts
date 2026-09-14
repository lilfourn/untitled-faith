type SourceLink = { start: number; end: number; text: string; label: string; url: string };

/** Read inline citation destinations without swallowing adjacent links or prose punctuation. */
export function* sourceLinks(text: string): Generator<SourceLink> {
  const opening = /\[([^\]\n]+)\]\(/g;
  for (let match; (match = opening.exec(text));) {
    const start = opening.lastIndex;
    let depth = 1;
    let end = start;
    for (; end < text.length; end++) {
      const character = text[end]!;
      if (/\s/.test(character)) break;
      if (character === '(') depth++;
      if (character === ')' && --depth === 0) break;
    }
    if (depth !== 0 || end === start) continue;
    opening.lastIndex = end + 1;
    yield { start: match.index, end: end + 1, text: text.slice(match.index, end + 1),
      label: match[1]!, url: text.slice(start, end) };
  }
}

export function replaceSourceLinks(text: string, replace: (link: SourceLink) => string): string {
  let result = '';
  let end = 0;
  for (const link of sourceLinks(text)) {
    result += text.slice(end, link.start) + replace(link);
    end = link.end;
  }
  return result + text.slice(end);
}
