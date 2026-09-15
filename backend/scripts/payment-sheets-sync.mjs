import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { mkdir, readFile, writeFile, rename, rm } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';
import { sheetData, updateRequests, SHEET_TITLE, serialDate } from './payment-sheet-data.mjs';

const exec = promisify(execFile);
const root = fileURLToPath(new URL('../../', import.meta.url));
const state = resolve(root, '.dev/google-accounting');
const configFile = resolve(state, 'sheet.json');
const receiptFile = resolve(state, 'last-sync.json');
const marker = 'untitled-faith-accounting-v1';

export function mostRecentWeeklyRun(now = new Date()) {
  const due = new Date(now);
  due.setHours(9, 0, 0, 0);
  due.setDate(due.getDate() - (due.getDay() + 6) % 7);
  if (due > now) due.setDate(due.getDate() - 7);
  return due;
}

async function jsonFile(path) {
  try { return JSON.parse(await readFile(path, 'utf8')); }
  catch (error) { if (error.code === 'ENOENT') return null; throw error; }
}
async function saveJSON(path, value) {
  const temp = `${path}.${process.pid}.tmp`;
  await writeFile(temp, `${JSON.stringify(value, null, 2)}\n`, { mode: 0o600 });
  await rename(temp, path);
}

async function google(args) {
  const env = { ...process.env, GOOGLE_WORKSPACE_CLI_CONFIG_DIR: resolve(state, 'auth') };
  // Use this task's OAuth login rather than inherited credentials for another Google account.
  for (const key of ['GOOGLE_WORKSPACE_CLI_TOKEN', 'GOOGLE_WORKSPACE_CLI_CREDENTIALS_FILE',
    'GOOGLE_WORKSPACE_CLI_CLIENT_ID', 'GOOGLE_WORKSPACE_CLI_CLIENT_SECRET', 'GOOGLE_APPLICATION_CREDENTIALS',
    'GOOGLE_WORKSPACE_PROJECT_ID', 'GOOGLE_WORKSPACE_CLI_LOG_FILE']) delete env[key];
  // Prevent gws from attaching an unrelated gcloud ADC quota project. OAuth remains in the isolated config.
  env.GOOGLE_APPLICATION_CREDENTIALS = '/dev/null';
  const configuration = await jsonFile(configFile);
  if (configuration?.serviceAccountEmail) {
    const keyFile = resolve(state, 'auth-service/key.json');
    const key = await jsonFile(keyFile);
    if (key?.type !== 'service_account' || key.client_email !== configuration.serviceAccountEmail ||
        key.project_id !== 'untitled-faith-accounting') throw new Error('Accounting service-account key does not match its configured identity.');
    env.GOOGLE_WORKSPACE_CLI_CONFIG_DIR = resolve(state, 'auth-service');
    env.GOOGLE_WORKSPACE_CLI_CREDENTIALS_FILE = keyFile;
  }
  let stdout;
  try { ({ stdout } = await exec('gws', args, { cwd: root, env, encoding: 'utf8', timeout: 60_000, maxBuffer: 32 * 1024 * 1024 })); }
  catch (error) { throw new Error(`Google request failed (CLI exit ${Number.isInteger(error.code) ? error.code : 'unavailable'}). Check the accounting Google login and API access.`); }
  const result = JSON.parse(stdout);
  if (result?.error) throw new Error('Google returned an API error.');
  return result;
}

async function fileDetails(id, account, serviceAccountEmail) {
  if (!/^[a-zA-Z0-9_-]+$/.test(id)) throw new Error('Invalid spreadsheet ID.');
  const file = await google(['drive', 'files', 'get', '--params', JSON.stringify({ fileId: id,
    fields: 'id,mimeType,trashed,properties,owners(emailAddress),permissions(type,role,emailAddress)' })]);
  if (file.mimeType !== 'application/vnd.google-apps.spreadsheet' || file.trashed || file.properties?.accounting !== marker ||
      !file.owners?.some(owner => owner.emailAddress === account)) throw new Error('Spreadsheet ownership or accounting marker mismatch.');
  if (!Array.isArray(file.permissions) || file.permissions.some(permission => permission.type !== 'user' ||
      !(permission.emailAddress === account && permission.role === 'owner' ||
        serviceAccountEmail && permission.emailAddress === serviceAccountEmail && permission.role === 'writer'))) {
    throw new Error('The accounting sheet has additional sharing. Review its access before syncing financial data.');
  }
  return file;
}

async function createSheet(workbook, account) {
  const existing = await google(['drive', 'files', 'list', '--params', JSON.stringify({
    q: `trashed = false and appProperties has { key='accounting' and value='${marker}' }`,
    fields: 'files(id),nextPageToken', pageSize: 100 })]);
  if (existing.nextPageToken || existing.files?.length > 1) throw new Error('Multiple accounting sheets found; select the intended sheet explicitly.');
  let id = existing.files?.[0]?.id;
  if (!id) {
    await readFile(workbook); // Fail before creating a file if the verified workbook is missing.
    const created = await google(['drive', 'files', 'create', '--params', JSON.stringify({ fields: 'id', ignoreDefaultVisibility: true }),
      '--json', JSON.stringify({ name: SHEET_TITLE, mimeType: 'application/vnd.google-apps.spreadsheet', appProperties: { accounting: marker }, properties: { accounting: marker } }),
      '--upload', workbook, '--upload-content-type', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet']);
    id = created.id;
  }
  await fileDetails(id, account);
  const config = { schemaVersion: 1, spreadsheetID: id, googleAccount: account };
  await saveJSON(configFile, config);
  return config;
}

async function captureReport() {
  let stdout;
  try { ({ stdout } = await exec(process.execPath, [resolve(root, 'backend/scripts/payment-report.mjs'), '--json'],
    { cwd: root, encoding: 'utf8', timeout: 10 * 60_000, maxBuffer: 32 * 1024 * 1024 })); }
  catch (error) {
    if (error.code === 2 && error.stdout) stdout = error.stdout; // A complete report with review items is still useful.
    else throw new Error('Stripe/D1 report failed. The sheet keeps its previous snapshot and update time.');
  }
  return JSON.parse(stdout);
}

async function sync(config) {
  if (config.schemaVersion !== 1 || !config.googleAccount) throw new Error('Unexpected Google accounting configuration.');
  await fileDetails(config.spreadsheetID, config.googleAccount, config.serviceAccountEmail);
  const report = await captureReport();
  const data = sheetData(report);
  const metadata = await google(['sheets', 'spreadsheets', 'get', '--params', JSON.stringify({
    spreadsheetId: config.spreadsheetID, fields: 'sheets(properties),properties(timeZone)' })]);
  const requests = updateRequests(data, metadata.sheets.map(sheet => sheet.properties));
  requests.unshift({ updateSpreadsheetProperties: { properties: { timeZone: 'Etc/UTC', autoRecalc: 'HOUR' }, fields: 'timeZone,autoRecalc' } });
  const body = JSON.stringify({ requests });
  if (Buffer.byteLength(body) > 180_000) throw new Error('Accounting data exceeds the current CLI request size. No sheet cells were changed; expand the importer before retrying.');
  await google(['sheets', 'spreadsheets', 'batchUpdate', '--params', JSON.stringify({ spreadsheetId: config.spreadsheetID }), '--json', body]);
  const readback = await google(['sheets', 'spreadsheets', 'values', 'batchGet', '--params', JSON.stringify({
    spreadsheetId: config.spreadsheetID, ranges: ["'Balances'!B3:B4", "'Balances'!B12:B16", "'Balances'!B26:B27"],
    valueRenderOption: 'UNFORMATTED_VALUE', dateTimeRenderOption: 'SERIAL_NUMBER' })]);
  verifyReadback(report, readback);
  const receipt = { spreadsheetID: config.spreadsheetID, capturedAt: report.finishedAt, syncedAt: new Date().toISOString(),
    syncAccount: config.serviceAccountEmail ?? config.googleAccount,
    status: report.status, reviewItems: report.issues.length, payments: report.payments.length };
  await saveJSON(receiptFile, receipt);
  console.log(JSON.stringify({ ...receipt, url: `https://docs.google.com/spreadsheets/d/${config.spreadsheetID}/edit` }));
}

export function verifyReadback(report, readback) {
  const expected = [
    [serialDate(report.finishedAt), report.issues.length],
    [report.allocations.totalUsageFundingMicros / 1e6, report.allocations.totalDeveloperShareMicros / 1e6,
      report.usage.paidSpentMicros / 1e6, report.usage.remainingLedgerMicros / 1e6, report.usage.positiveUserBalancesMicros / 1e6],
    [report.stripeCash.balanceDifferenceMicros / 1e6,
      (report.usage.remainingLedgerMicros - report.usage.positiveUserBalancesMicros - report.usage.negativeUserBalancesMicros - report.usage.detachedBalanceMicros) / 1e6],
  ];
  if (readback.valueRanges?.length !== expected.length) throw new Error('Missing Google readback ranges.');
  expected.forEach((values, i) => values.forEach((value, j) => {
    const actual = readback.valueRanges[i].values?.[j]?.[0];
    if (typeof actual !== 'number' || Math.abs(actual - value) > 0.0000005) throw new Error('Google readback did not match the accounting snapshot.');
  }));
}

export async function main(args) {
  if (args.includes('--help')) {
    console.log('Usage: ./scripts/dev money-sync [--scheduled] | --create <verified.xlsx> --account <email>\nUses the isolated accounting Google login under .dev/google-accounting/auth.\nWeekly schedule: Monday 9 AM local time. Manual runs refresh immediately.');
    return;
  }
  const create = args.length === 4 && args[0] === '--create' && args[2] === '--account' && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(args[3]);
  const scheduled = args.length === 1 && args[0] === '--scheduled';
  if (args.length && !create && !scheduled) throw new Error('Unknown option. Run money-sync --help.');
  await mkdir(state, { recursive: true, mode: 0o700 });
  const lock = resolve(state, 'sync.lock');
  try { await mkdir(lock); }
  catch (error) {
    if (error.code !== 'EEXIST') throw error;
    const owner = await jsonFile(resolve(lock, 'owner.json'));
    if (!Number.isInteger(owner?.pid)) throw new Error('Accounting sync lock is initializing or needs review.');
    try { process.kill(owner.pid, 0); throw new Error('Another accounting sync is running.'); }
    catch (error) { if (error.code !== 'ESRCH') throw error; }
    await rm(lock, { recursive: true });
    await mkdir(lock);
  }
  await saveJSON(resolve(lock, 'owner.json'), { pid: process.pid });
  try {
    const previous = await jsonFile(receiptFile);
    if (scheduled && previous && new Date(previous.syncedAt) >= mostRecentWeeklyRun()) {
      console.log('Weekly accounting snapshot is already current.'); return;
    }
    let config = await jsonFile(configFile);
    const expectedAccount = create ? args[3] : config?.googleAccount;
    if (!expectedAccount) throw new Error('Create the accounting sheet first with money-sync --create <verified.xlsx> --account <email>.');
    if (config && config.googleAccount !== expectedAccount) throw new Error('Existing accounting sheet belongs to a different configured account.');
    const identity = await google(['drive', 'about', 'get', '--params', '{"fields":"user(emailAddress)"}']);
    if (identity.user?.emailAddress !== (config?.serviceAccountEmail ?? expectedAccount)) throw new Error('Google login does not match the configured accounting identity.');
    if (!config && create) config = await createSheet(resolve(root, args[1]), expectedAccount);
    await sync(config);
  } finally { await rm(lock, { recursive: true }); }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main(process.argv.slice(2)).catch(error => { console.error(error.message); process.exitCode = 1; });
}
