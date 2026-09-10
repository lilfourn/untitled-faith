// SSE framing is independent of network chunks, UTF-8 characters, and CRLF splits.
export async function* sseData(body: ReadableStream<Uint8Array>, signal: AbortSignal): AsyncGenerator<string> {
  const reader = body.getReader();
  const decoder = new TextDecoder('utf-8', { fatal: true, ignoreBOM: false });
  let buffer = '';
  let data: string[] = [];
  let bytes = 0;
  const abort = () => { void reader.cancel().catch(() => {}); };
  signal.addEventListener('abort', abort, { once: true });
  try {
    while (true) {
      signal.throwIfAborted();
      const { value, done } = await reader.read();
      signal.throwIfAborted();
      bytes += value?.byteLength ?? 0;
      if (bytes > 2 * 1024 * 1024) throw new Error('Stream too large');
      buffer += decoder.decode(value, { stream: !done });
      let end: number;
      while ((end = buffer.search(/[\r\n]/)) >= 0) {
        if (buffer[end] === '\r' && end === buffer.length - 1 && !done) break;
        const line = buffer.slice(0, end);
        buffer = buffer.slice(end + (buffer.slice(end, end + 2) === '\r\n' ? 2 : 1));
        if (!line) {
          if (data.length) yield data.join('\n');
          data = [];
        } else if (line.startsWith('data:')) {
          data.push(line.slice(5).replace(/^ /, ''));
        }
      }
      if (done) break;
    }
  } finally {
    signal.removeEventListener('abort', abort);
    await reader.cancel().catch(() => {});
    reader.releaseLock();
  }
}
