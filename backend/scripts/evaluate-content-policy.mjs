// Explicitly opt-in: synthetic prompts only, real inference credits, no D1 or app accounts.
import { build } from 'esbuild';
import { readFile, writeFile } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import { fileURLToPath } from 'node:url';

if (!process.argv.includes('--run-paid-eval')) {
  console.error('Usage: node --env-file=.dev.vars scripts/evaluate-content-policy.mjs --run-paid-eval [--case=ID] [--review-only]');
  process.exit(2);
}
if (!process.env.OPENROUTER_API_KEY?.trim()) throw new Error('OPENROUTER_API_KEY is required.');
const root = fileURLToPath(new URL('../', import.meta.url));
// Compile the actual production request, parser, source checker, and prompt; no copied prompt.
const bundle = await build({ stdin: { contents: `
  export { reviewRequest } from './src/request-review';
  export { prepareBible } from './src/bible/prepare';
  export { cashCostMicros } from './src/billing-policy';
  export { requestCompletion } from './src/openrouter';
  export { moderatedAnswer } from './src/content-policy';
  export { AnswerSources } from './src/answer-sources';
  export { readJSON } from './src/http';
  export { sseData } from './src/sse';
`, resolveDir: root }, bundle: true, platform: 'node', format: 'esm', write: false });
const { reviewRequest, prepareBible, cashCostMicros, requestCompletion, moderatedAnswer, AnswerSources, readJSON, sseData } =
  await import(`data:text/javascript;base64,${Buffer.from(bundle.outputFiles[0].text).toString('base64')}`);
const cases = JSON.parse(await readFile(new URL('../test/fixtures/content-policy-cases.json', import.meta.url), 'utf8'));
const selected = process.argv.find(value => value.startsWith('--case='))?.slice(7);
if (selected && !cases.some(test => test.id === selected)) throw new Error('Unknown case.');
const results = [];
for (const [index, test] of cases.entries()) {
  if (selected && selected !== test.id) continue;
  const stream = index % 2 === 1;
  const signal = AbortSignal.timeout(45000);
  let usage;
  let reviewUsage;
  let actual;
  let error;
  try {
    const review = await reviewRequest(test.messages, process.env.OPENROUTER_API_KEY, `policy-eval-${randomUUID()}`, signal);
    reviewUsage = review.usage;
    actual = review.decision;
    if (review.decision === 'answer' && !process.argv.includes('--review-only')) {
      const bibleContext = await prepareBible(test.messages, { ESV_API_KEY: process.env.ESV_API_KEY,
        PASSAGES_RATE_LIMITER: { limit: async () => ({ success: true }) } }, 'synthetic-policy-eval', signal);
      const response = await requestCompletion(test.messages, process.env.OPENROUTER_API_KEY,
        `policy-eval-${randomUUID()}`, signal, stream, bibleContext, null, true);
      if (!response.ok) {
        await response.body?.cancel();
        throw new Error(`http_${response.status}`);
      }
      let content = '';
      let finish;
      let done = !stream;
      const sources = new AnswerSources();
      sources.addBible(bibleContext.passages);
      if (stream) {
        for await (const data of sseData(response.body, signal)) {
          if (data === '[DONE]') { done = true; break; }
          const frame = JSON.parse(data);
          if (frame.usage) usage = frame.usage;
          if (frame.error) throw new Error('upstream_error');
          const choice = frame.choices?.[0];
          sources.add(choice?.delta?.annotations);
          sources.add(choice?.message?.annotations);
          content += choice?.delta?.content ?? '';
          if (content.length > 49024) throw new Error('oversized_content');
          if (choice?.finish_reason) finish = choice.finish_reason;
        }
      } else {
        const body = await readJSON(response.body, 128 * 1024);
        usage = body.usage;
        if (body.error) throw new Error('upstream_error');
        content = body.choices?.[0]?.message?.content;
        finish = body.choices?.[0]?.finish_reason;
        sources.add(body.choices?.[0]?.message?.annotations);
      }
      if (!done || finish !== 'stop' || typeof content !== 'string' || !Number.isFinite(usage?.cost)) {
        throw new Error('incomplete_completion');
      }
      const result = moderatedAnswer(content);
      actual = result.decision;
      if (result.generated) sources.finish(result.text);
    }
  } catch (failure) {
    // Never print generated content, provider error bodies, or credentials.
    if (failure.accounting && typeof failure.accounting === 'object') reviewUsage = failure.accounting;
    const known = ['upstream_error', 'oversized_content', 'incomplete_completion', 'answer_unavailable', 'sources_unavailable'];
    error = signal.aborted ? 'timeout' : known.includes(failure.message) || /^http_\d{3}$/.test(failure.message)
      ? failure.message : 'evaluation_failed';
  }
  const result = { id: test.id, expected: test.expected, actual, stream, error,
    passed: !error && actual === test.expected, costMicros: (reviewUsage?.costMicros ?? 0) + (usage?.cost === undefined ? 0 : cashCostMicros(usage.cost)) };
  results.push(result);
  console.log(JSON.stringify(result));
}
const report = { checkedAt: new Date().toISOString(), passed: results.filter(result => result.passed).length,
  total: results.length, cashCostMicros: results.reduce((sum, result) => sum + (result.costMicros ?? 0), 0), results };
await writeFile(new URL(process.argv.includes('--review-only') ? '../../.dev/request-review-eval.json' : selected ? `../../.dev/content-policy-eval-${selected}.json` : '../../.dev/content-policy-eval.json', import.meta.url),
  JSON.stringify(report, null, 2) + '\n', { mode: 0o600 });
console.log(JSON.stringify({ passed: report.passed, total: report.total, cashCostMicros: report.cashCostMicros }));
if (report.passed !== report.total) process.exitCode = 1;
