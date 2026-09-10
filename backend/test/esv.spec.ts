import { env } from "cloudflare:workers";
import { SignJWT } from "jose";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import worker from "../src/index";
import { accountForIdentity } from "../src/accounts";
import { ESV_ENDPOINT, ESV_NOTICE, normalizeText, parseReferences } from "../src/esv";

const testEnv = { ...(env as Env), ESV_API_KEY: "test-only-esv-key" } as Env;

async function token() {
  const account = await accountForIdentity(testEnv.DB, crypto.randomUUID());
  return new SignJWT({ scope: "answers" }).setProtectedHeader({ alg: "HS256" }).setIssuer("untitled-faith")
    .setAudience("untitled-faith-proxy").setSubject(account.id).setIssuedAt().setExpirationTime("15m")
    .sign(new TextEncoder().encode(testEnv.SESSION_SIGNING_KEY));
}

async function request(q: string, bearer?: string) {
  const url = new URL("https://proxy.example/v1/passages");
  url.searchParams.set("q", q);
  return new Request(url, { headers: { Authorization: `Bearer ${bearer ?? await token()}` } });
}

const esvBody = {
  query: "John 3:16;Psalm 23:1-2", canonical: "John 3:16; Psalm 23:1–2",
  passage_meta: [{ canonical: "John 3:16" }, { canonical: "Psalm 23:1–2" }],
  passages: [
    "  [16] “For God so loved the world, that he gave his only Son, that whoever believes in him should not perish but have eternal life.\n\n",
    "    [1] The LORD is my shepherd; I shall not want.\n    [2] He makes me lie down in green pastures.\n    He leads me beside still waters.\n\n",
  ],
};

const upstream = vi.fn<typeof fetch>();
beforeEach(() => {
  vi.stubGlobal("fetch", upstream);
  upstream.mockReset().mockResolvedValue(Response.json(esvBody));
});
afterEach(() => vi.unstubAllGlobals());

describe("ESV passages", () => {
  it("fetches exact passages with the server key and normalizes verse markers", async () => {
    const response = await worker.fetch(await request("John 3:16;Psalm 23:1-2"), testEnv);
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ translation: "ESV", notice: ESV_NOTICE, passages: [
      { reference: "John 3:16", text: "“For God so loved the world, that he gave his only Son, that whoever believes in him should not perish but have eternal life." },
      { reference: "Psalm 23:1–2", text: "¹ The LORD is my shepherd; I shall not want. ² He makes me lie down in green pastures. He leads me beside still waters." },
    ] });
    const [url, options] = upstream.mock.calls[0]!;
    const sent = new URL(url as string);
    expect(sent.origin + sent.pathname).toBe(ESV_ENDPOINT);
    expect(sent.searchParams.get("q")).toBe("John 3:16;Psalm 23:1-2");
    expect(sent.searchParams.get("include-footnotes")).toBe("false");
    expect(sent.searchParams.get("include-headings")).toBe("false");
    expect((options?.headers as Record<string, string>).Authorization).toBe("Token test-only-esv-key");
    expect(options?.redirect).toBe("manual");
  });

  it("requires a signed session and never calls Crossway without one", async () => {
    const response = await worker.fetch(await request("John 3:16", "not-a-token"), testEnv);
    expect(response.status).toBe(401);
    expect(upstream).not.toHaveBeenCalled();
  });

  it("reports missing configuration without calling Crossway", async () => {
    const response = await worker.fetch(await request("John 3:16"), { ...testEnv, ESV_API_KEY: "" } as Env);
    expect(response.status).toBe(503);
    expect(await response.json()).toMatchObject({ error: { code: "not_configured" } });
    expect(upstream).not.toHaveBeenCalled();
  });

  it.each(["", "John", "John 3:16;".repeat(9) + "John 3:16", "DROP TABLE 1:1", "John 3:16-", "x".repeat(401)])
  ("rejects malformed reference lists: %j", async q => {
    const response = await worker.fetch(await request(q), testEnv);
    expect(response.status).toBe(400);
    expect(upstream).not.toHaveBeenCalled();
  });

  it.each([[500, 502], [401, 502], [429, 429]])("maps upstream status %d to %d", async (status, expected) => {
    upstream.mockResolvedValue(new Response("nope", { status }));
    const response = await worker.fetch(await request("John 3:16"), testEnv);
    expect(response.status).toBe(expected);
  });

  it("drops unparseable passages and rejects malformed upstream bodies", async () => {
    upstream.mockResolvedValue(Response.json({ passages: ["[1] Text"], passage_meta: [{ canonical: "" }] }));
    expect(await (await worker.fetch(await request("John 3:16"), testEnv)).json()).toMatchObject({ passages: [] });
    upstream.mockResolvedValue(Response.json({ passages: ["a"], passage_meta: [] }));
    expect((await worker.fetch(await request("John 3:16"), testEnv)).status).toBe(502);
  });
});

describe("reference parsing and text normalization", () => {
  it("accepts common forms", () => {
    expect(parseReferences("1 John 4:19; Song of Solomon 2:1;Genesis 1:1-2:3; Psalm 23")).toEqual([
      "1 John 4:19", "Song of Solomon 2:1", "Genesis 1:1-2:3", "Psalm 23",
    ]);
  });

  it("keeps verse numbers only for multi-verse passages", () => {
    expect(normalizeText("  [35] Jesus wept.\n")).toBe("Jesus wept.");
    expect(normalizeText("[5] Trust in the LORD\n    [6] In all your ways")).toBe("⁵ Trust in the LORD ⁶ In all your ways");
  });
});
