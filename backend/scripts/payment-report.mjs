import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { readFile, mkdir, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';
import { buildReport, renderReport, listAll, verifyScope, LIVE_ACCOUNT, STRIPE_PROJECT, DATABASE_ID } from './payment-report-core.mjs';

const exec = promisify(execFile);
const backend = fileURLToPath(new URL('../', import.meta.url));
const sqlURL = new URL('./payment-report.sql', import.meta.url);
const wrangler = resolve(backend, 'node_modules/wrangler/bin/wrangler.js');

export function parseOptions(args) {
  if (new Set(args).size !== args.length || args.some(arg => !['--json', '--help'].includes(arg))) {
    throw new Error('Usage: ./scripts/dev money [--json|--help]');
  }
  return { json: args.includes('--json'), help: args.includes('--help') };
}

async function commandJSON(command, args, label) {
  let stdout;
  try {
    ({ stdout } = await exec(command, args, {
      cwd: backend, encoding: 'utf8', timeout: 60_000, maxBuffer: 64 * 1024 * 1024,
      env: { ...process.env, STRIPE_API_KEY: '', STRIPE_SECRET_KEY: '',
        STRIPE_PROJECT_NAME: STRIPE_PROJECT, NO_COLOR: '1', WRANGLER_SEND_METRICS: 'false' },
    }));
  } catch {
    // Child errors can contain secrets, full API responses, or personal data. Never echo them.
    throw new Error(`${label} failed. Check Stripe CLI login for project ${STRIPE_PROJECT} and local Wrangler authentication, then rerun. No report was saved.`);
  }
  let result;
  try { result = JSON.parse(stdout); }
  catch { throw new Error(`${label} did not return JSON. No report was saved.`); }
  if (result?.error) throw new Error(`${label} returned an API error. No report was saved.`);
  return result;
}

export async function main(args) {
  const options = parseOptions(args);
  if (options.help) {
    console.log(`Usage: ./scripts/dev money [--json|--help]
Read-only LIVE Stripe + remote D1 report for Untitled Faith.
Stripe CLI profile: ${STRIPE_PROJECT}; required account: ${LIVE_ACCOUNT}.
Uses existing CLI authentication; no server secrets are loaded.
Saves sanitized report.json and report.md under ignored .dev/payments/<capture>/.
Default prints Markdown; --json prints JSON. All money is exact integer micro-USD in JSON.
Exit 0 = matched; 2 = report saved with review items; 1 = failed/incomplete capture.
Does not move money, change payouts, write to D1, or deploy.`);
    return;
  }
  const progress = message => console.error(message);
  progress('Reading Untitled Faith live Stripe and D1 accounting (read-only)...');
  const startedAt = new Date().toISOString();
  const get = (path, params = []) => commandJSON('stripe', ['get', path, '--project-name', STRIPE_PROJECT,
    '--live', '--stripe-version', '2026-08-26.dahlia', '--color', 'off', ...params], 'Stripe read');
  // Verify account before reading any payment data. Never use the global default Stripe profile.
  const account = await get('/v1/account');
  if (account.id !== LIVE_ACCOUNT) throw new Error('Wrong Stripe account. Select the Untitled Faith profile; no payments were read.');
  const config = JSON.parse(await readFile(resolve(backend, 'wrangler.jsonc'), 'utf8'));
  const binding = config.d1_databases?.find(db => db.binding === 'DB');
  if (binding?.database_id !== DATABASE_ID || binding.database_name !== 'untitled-faith-users' ||
      config.account_id !== 'c0f96de71bdc54889c1ad27ccc90dfc0') throw new Error('Unexpected production D1 configuration.');
  const sql = await readFile(sqlURL, 'utf8');
  const [databaseResult, balance] = await Promise.all([
    commandJSON(process.execPath, [wrangler, 'd1', 'execute', binding.database_name, '--config', resolve(backend, 'wrangler.jsonc'),
      '--remote', `--command=${sql}`, '--json'], 'D1 read'),
    get('/v1/balance'),
  ]);
  if (!Array.isArray(databaseResult) || databaseResult.length !== 1 || databaseResult[0].success !== true ||
      databaseResult[0].results?.length !== 1 || databaseResult[0].meta?.rows_written !== 0) {
    throw new Error('Unexpected D1 snapshot response.');
  }
  const ledger = JSON.parse(databaseResult[0].results[0].snapshot);
  verifyScope(account, balance, ledger);
  const cutoff = String(Math.floor(Date.now() / 1000));
  // Fixed upper bound and cursor pagination prevent missing older pages as new payments arrive.
  const bound = ['-d', `created[lte]=${cutoff}`];
  const [charges, transactions] = await Promise.all([
    listAll(get, '/v1/charges', [...bound, '--expand', 'data.balance_transaction']),
    listAll(get, '/v1/balance_transactions', bound),
  ]);
  const disputes = {};
  for (const charge of charges.filter(c => c.disputed)) {
    disputes[charge.id] = await listAll(get, '/v1/disputes', ['-d', `charge=${charge.id}`]);
  }
  const report = buildReport({ account, balance, ledger, charges, transactions, disputes,
    startedAt, finishedAt: new Date().toISOString() });
  const directory = resolve(backend, '../.dev/payments', `${report.finishedAt.replaceAll(':', '-')}-${process.pid}`);
  await mkdir(directory, { recursive: true, mode: 0o700 });
  const json = `${JSON.stringify(report, null, 2)}\n`;
  const markdown = renderReport(report);
  await writeFile(resolve(directory, 'report.json'), json, { flag: 'wx', mode: 0o600 });
  await writeFile(resolve(directory, 'report.md'), markdown, { flag: 'wx', mode: 0o600 });
  console.log(options.json ? json.trimEnd() : markdown);
  progress(`Saved ${directory}`);
  if (report.status !== 'matched') process.exitCode = 2;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main(process.argv.slice(2)).catch(error => { console.error(error.message); process.exitCode = 1; });
}
