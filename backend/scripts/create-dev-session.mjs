import { SignJWT } from "jose";
import { spawnSync } from "node:child_process";
import { randomUUID } from "node:crypto";

// Operator-only harness. There is deliberately no public token-minting endpoint.
const secret = process.env.SESSION_SIGNING_KEY;
if (!secret || secret.length < 32) throw new Error("Set a random SESSION_SIGNING_KEY of at least 32 bytes in .dev.vars.");
const target = process.argv.includes("--remote") ? "--remote" : "--local";
const subject = process.env.FAITH_USER_ID ?? randomUUID();
if (!/^[a-f0-9-]{36}$/i.test(subject)) throw new Error("FAITH_USER_ID must be an account UUID.");
const query = process.env.FAITH_USER_ID
  ? `SELECT id FROM users WHERE id = '${subject}' AND deleting_at IS NULL`
  : `INSERT INTO users(id, identity_hash, app_account_token, created_at) VALUES ('${subject}', 'development:${subject}', '${randomUUID()}', ${Date.now()}) RETURNING id`;
const result = spawnSync(process.execPath, ["node_modules/wrangler/bin/wrangler.js", "d1", "execute", "untitled-faith-users", target, "--json", "--command", query],
  { encoding: "utf8", env: process.env });
if (result.status !== 0 || !result.stdout.includes(subject)) throw new Error("Could not find or create the development account. Apply the database migrations first.");
process.stderr.write(`Development account (${target.slice(2)}): ${subject}\n`);
const token = await new SignJWT({ scope: "answers" })
  .setProtectedHeader({ alg: "HS256", typ: "JWT" })
  .setIssuer("untitled-faith")
  .setAudience("untitled-faith-proxy")
  .setSubject(subject)
  .setIssuedAt()
  .setExpirationTime("15m")
  .sign(new TextEncoder().encode(secret));
process.stdout.write(`${token}\n`);
