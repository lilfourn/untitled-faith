/** Keep JSON on one physical line, including for clients using Unicode line readers. */
export function answerEvent(value: unknown): Uint8Array {
  const json = JSON.stringify(value).replace(/[\u0085\u2028\u2029]/g,
    character => `\\u${character.charCodeAt(0).toString(16).padStart(4, '0')}`);
  return new TextEncoder().encode(`data: ${json}\n\n`);
}
