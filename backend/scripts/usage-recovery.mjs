import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';

const root = fileURLToPath(new URL('../', import.meta.url));
const uuid = /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i;
const quote = value => `'${value.replaceAll("'", "''")}'`;

export function resolutionSQL({ request, kind, cost, prompt, completion, reason, operator }, now = Date.now()) {
  if (!uuid.test(request ?? '')) throw new Error('A request UUID is required.');
  if (!['verified', 'write_off'].includes(kind)) throw new Error('Kind must be verified or write_off.');
  for (const value of [cost, prompt, completion]) {
    if (!Number.isSafeInteger(value) || value < 0) throw new Error('Costs and token counts must be nonnegative safe integers.');
  }
  if (kind === 'write_off' && (cost || prompt || completion)) throw new Error('Write-offs must use zero for the unverified provider cost and tokens.');
  if (typeof reason !== 'string' || reason.trim().length < 10 || reason.length > 500 ||
      typeof operator !== 'string' || !operator.trim() || operator.length > 100) {
    throw new Error('Provide an operator and a 10–500 character evidence/reason note.');
  }
  if (!Number.isSafeInteger(now) || now < 0) throw new Error('Invalid timestamp.');
  return `INSERT INTO usage_resolutions
    (request_id, kind, provider_cost_micros, prompt_tokens, completion_tokens, reason, operator, created_at)
    VALUES (${quote(request)}, ${quote(kind)}, ${cost}, ${prompt}, ${completion}, ${quote(reason)}, ${quote(operator)}, ${now});`;
}

function main(args) {
  const flags = new Set(['--list', '--remote', '--apply']);
  const fields = new Set(['--inspect', '--request', '--kind', '--cost-micros', '--prompt-tokens', '--completion-tokens', '--reason', '--operator']);
  const values = new Map();
  for (let index = 0; index < args.length; index++) {
    const flag = args[index];
    if (!flags.has(flag) && !fields.has(flag)) throw new Error('Unknown option. Use --list or provide resolution fields; --apply is required for writes.');
    if (values.has(flag)) throw new Error('Duplicate option.');
    if (flags.has(flag)) values.set(flag, true);
    else {
      const value = args[++index];
      if (!value || value.startsWith('--')) throw new Error('Missing option value.');
      values.set(flag, value);
    }
  }
  const list = values.has('--list');
  const inspect = values.get('--inspect');
  if (inspect && (!uuid.test(inspect) || values.has('--apply') || [...fields].some(flag => flag !== '--inspect' && values.has(flag)))) throw new Error('--inspect requires only a request UUID and optional --remote.');
  if (list && (values.has('--apply') || [...fields].some(flag => values.has(flag)))) throw new Error('--list cannot be combined with resolution fields.');
  const sql = inspect ? `SELECT r.id, r.status, r.inference_stage, r.generation_id, r.cost_micros, r.review_cost_micros, r.reconciliation_error, a.kind, a.reason, a.operator, a.created_at FROM usage_requests r LEFT JOIN usage_resolutions a ON a.request_id = r.id WHERE r.id = ${quote(inspect)};` : list ? `SELECT id, status, inference_stage, generation_id, reserved_micros, review_cost_micros,
    reconciliation_attempts, reconciliation_error, needs_review_at, created_at FROM usage_requests
    WHERE status = 'uncertain' ORDER BY created_at LIMIT 100;` : resolutionSQL({
    request: values.get('--request'), kind: values.get('--kind'),
    cost: Number(values.get('--cost-micros')), prompt: Number(values.get('--prompt-tokens')),
    completion: Number(values.get('--completion-tokens')), reason: values.get('--reason'), operator: values.get('--operator'),
  });
  if (!list && !inspect && !values.has('--apply')) {
    console.log(sql);
    console.log('-- Preview only. Review the evidence and SQL before adding --apply. Default database is local; --remote explicitly selects production.');
    return;
  }
  const result = spawnSync(process.execPath, [resolve(root, 'node_modules/wrangler/bin/wrangler.js'),
    'd1', 'execute', 'untitled-faith-users', values.has('--remote') ? '--remote' : '--local', '--command', sql, '--json'],
  { cwd: root, stdio: 'inherit', shell: false });
  if (result.error || result.status !== 0) throw new Error('Database operation failed; do not assume the resolution was applied.');
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try { main(process.argv.slice(2)); }
  catch (error) { console.error(error.message); process.exitCode = 1; }
}
