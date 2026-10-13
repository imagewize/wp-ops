import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StreamableHTTPClientTransport } from "@modelcontextprotocol/sdk/client/streamableHttp.js";

// Min's hosted MCP server (the imagewize/min WordPress plugin + wordpress/mcp-adapter).
// Min scans the *public* URL, so this needs no SSH: it is the outside half of the
// audit -> fix -> re-audit loop, next to wp_cli / ssh_command for the inside half.
export const DEFAULT_MIN_MCP_URL = "https://imagewize.com/wp-json/min/mcp";

export interface MinConnection {
  endpoint: string;
  user: string;
  password: string;
}

export interface StoreAuditOptions {
  url: string;
  speed: boolean;
  product: boolean;
  full: boolean;
}

export interface StoreAuditCheck {
  id: string;
  status: string;
  evidence: string;
}

export interface StoreAuditSummary {
  url: string;
  grade: string | null;
  score: number | null;
  topIssue: string | null;
  service: string | null;
  failing: StoreAuditCheck[];
  actions: { check: string; status: string; service: string; en: string }[];
  comparison: string | null;
  productFound: boolean | null;
  speed: { grade: string | null; score: number | null } | null;
  steps: { step: string; ok: boolean; error?: string }[];
  /** Whole reports, only when `full` was requested. */
  raw?: Record<string, unknown>;
}

type Json = Record<string, any>;

export function resolveMinConnection(env: NodeJS.ProcessEnv = process.env): MinConnection {
  const user = env.WP_OPS_MIN_MCP_USER;
  const password = env.WP_OPS_MIN_MCP_PASSWORD;
  if (!user || !password) {
    throw new Error(
      "Min MCP credentials missing. Set WP_OPS_MIN_MCP_USER (WordPress login) and " +
        "WP_OPS_MIN_MCP_PASSWORD (an application password for a user allowed to run audits) " +
        `in the MCP server's environment. WP_OPS_MIN_MCP_URL overrides ${DEFAULT_MIN_MCP_URL}.`
    );
  }
  return { endpoint: env.WP_OPS_MIN_MCP_URL || DEFAULT_MIN_MCP_URL, user, password };
}

/** Pull the tool result out of an MCP response: structuredContent, else JSON text. */
export function parseToolResult(result: any): { ok: boolean; data: Json; error?: string } {
  const text = Array.isArray(result?.content)
    ? result.content.map((c: any) => (c?.type === "text" ? c.text : "")).join("")
    : "";
  if (result?.isError) {
    return { ok: false, data: {}, error: text || "Tool returned an error" };
  }
  if (result?.structuredContent && typeof result.structuredContent === "object") {
    return { ok: true, data: result.structuredContent as Json };
  }
  try {
    return { ok: true, data: JSON.parse(text) as Json };
  } catch {
    return { ok: false, data: {}, error: `Unreadable tool result: ${text.slice(0, 200)}` };
  }
}

/** Condense the (large) reports into what an agent needs to decide the next step. */
export function summarise(
  url: string,
  store: Json | null,
  product: Json | null,
  speed: Json | null,
  steps: StoreAuditSummary["steps"],
  full: boolean
): StoreAuditSummary {
  // The product step returns the refreshed report, so prefer it for the grade.
  const report: Json = product ?? store ?? {};
  const checks: Json = report.aeo?.checks ?? {};
  const failing: StoreAuditCheck[] = Object.entries(checks)
    .filter(([, c]: [string, any]) => c?.status === "fail" || c?.status === "warn")
    .map(([id, c]: [string, any]) => ({ id, status: c.status, evidence: String(c.evidence ?? "") }))
    .sort((a, b) => (a.status === b.status ? 0 : a.status === "fail" ? -1 : 1));

  const perf = speed?.performance ?? null;
  const summary: StoreAuditSummary = {
    url,
    grade: report.aeo?.grade ?? null,
    score: report.aeo?.score ?? null,
    topIssue: report.aeo?.top_issue ?? null,
    service: report.service_match ?? null,
    failing,
    actions: (report.actions ?? []).map((a: Json) => ({
      check: a.check,
      status: a.status,
      service: a.service,
      en: a.en,
    })),
    comparison: report.comparison?.message?.en ?? null,
    productFound: typeof product?.meta?.product_found === "boolean" ? product.meta.product_found : null,
    speed: perf ? { grade: perf.grade ?? null, score: perf.score ?? null } : null,
    steps,
  };
  if (full) {
    summary.raw = { store, product, speed };
  }
  return summary;
}

export function formatStoreAudit(s: StoreAuditSummary): string {
  const lines: string[] = [`Store audit for ${s.url}: grade ${s.grade ?? "?"} (${s.score ?? "?"}/100)`];
  if (s.comparison) lines.push(s.comparison);
  if (s.speed) lines.push(`Speed (PageSpeed): ${s.speed.grade ?? "?"} (${s.speed.score ?? "?"})`);
  lines.push("");
  if (s.failing.length === 0) {
    lines.push("✅ No failing or warning checks.");
  } else {
    lines.push("Failing / warning checks:");
    for (const c of s.failing) {
      lines.push(`  ${c.status === "fail" ? "❌" : "⚠️ "} ${c.id}: ${c.evidence}`);
    }
  }
  if (s.actions.length > 0) {
    lines.push("", "Recommended fixes:");
    for (const a of s.actions) lines.push(`  - [${a.service}] ${a.en}`);
  }
  const failedSteps = s.steps.filter((x) => !x.ok);
  if (failedSteps.length > 0) {
    lines.push("", "Steps that did not complete:");
    for (const x of failedSteps) lines.push(`  - ${x.step}: ${x.error}`);
  }
  lines.push("", "```json", JSON.stringify(s, null, 2), "```");
  return lines.join("\n");
}

/**
 * Run Min's audit chain against a store: audit-store, then audit-product and
 * audit-speed (each needs the ticket audit-store issues, so order matters and
 * a failed audit-store stops the chain).
 */
export async function runStoreAudit(
  conn: MinConnection,
  opts: StoreAuditOptions
): Promise<StoreAuditSummary> {
  const auth = "Basic " + Buffer.from(`${conn.user}:${conn.password}`).toString("base64");
  const transport = new StreamableHTTPClientTransport(new URL(conn.endpoint), {
    requestInit: { headers: { Authorization: auth } },
  });
  const client = new Client({ name: "wp-ops", version: "0.1.0" });
  await client.connect(transport);

  const steps: StoreAuditSummary["steps"] = [];
  const call = async (step: string, timeout: number): Promise<Json | null> => {
    try {
      const res = await client.callTool({ name: `min-${step}`, arguments: { url: opts.url } }, undefined, {
        timeout,
      });
      const parsed = parseToolResult(res);
      steps.push({ step, ok: parsed.ok, ...(parsed.error ? { error: parsed.error } : {}) });
      return parsed.ok ? parsed.data : null;
    } catch (err) {
      steps.push({ step, ok: false, error: err instanceof Error ? err.message : String(err) });
      return null;
    }
  };

  try {
    const store = await call("audit-store", 120_000);
    if (!store) {
      return summarise(opts.url, null, null, null, steps, opts.full);
    }
    const product = opts.product ? await call("audit-product", 120_000) : null;
    const speed = opts.speed ? await call("audit-speed", 180_000) : null;
    return summarise(opts.url, store, product, speed, steps, opts.full);
  } finally {
    await client.close().catch(() => undefined);
  }
}
