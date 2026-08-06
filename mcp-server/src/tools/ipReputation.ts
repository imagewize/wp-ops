import { existsSync, readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
// Same .env file trellis/security/check-ips.sh and check-deny-ips.sh read
// (ABUSEIPDB_KEY=...), so a key dropped in for the CLI scripts works here too.
const ENV_FILE = path.resolve(__dirname, "../../../trellis/security/.env");
const DENY_IPS_RELATIVE_PATH = "nginx-includes/all/deny-ips.conf.j2";

function loadAbuseIpDbKey(): string {
  if (process.env.WP_OPS_ABUSEIPDB_KEY) return process.env.WP_OPS_ABUSEIPDB_KEY;

  if (existsSync(ENV_FILE)) {
    const match = readFileSync(ENV_FILE, "utf-8").match(/^ABUSEIPDB_KEY=(.+)$/m);
    if (match) return match[1].trim();
  }

  throw new Error(
    `ABUSEIPDB_KEY not found. Set WP_OPS_ABUSEIPDB_KEY, or add it to ${ENV_FILE}:\n` +
      `  echo 'ABUSEIPDB_KEY=your_key_here' > ${ENV_FILE}\n` +
      "Get a free key (1,000 checks/day) at https://www.abuseipdb.com/register"
  );
}

export interface IpCheckResult {
  ip: string;
  score?: number;
  reports?: number;
  lastSeen?: string | null;
  country?: string;
  isp?: string;
  usageType?: string;
  domain?: string;
  tor?: boolean;
  error?: string;
}

async function checkOne(ip: string, apiKey: string): Promise<IpCheckResult> {
  const url = new URL("https://api.abuseipdb.com/api/v2/check");
  url.searchParams.set("ipAddress", ip);
  url.searchParams.set("maxAgeInDays", "90");

  try {
    const res = await fetch(url, {
      headers: { Key: apiKey, Accept: "application/json" },
      signal: AbortSignal.timeout(10_000),
    });
    const body = (await res.json()) as any;

    if (body.errors) {
      return { ip, error: body.errors.map((e: any) => e.detail ?? JSON.stringify(e)).join("; ") };
    }

    const d = body.data ?? {};
    return {
      ip,
      score: d.abuseConfidenceScore,
      reports: d.totalReports,
      lastSeen: d.lastReportedAt ?? null,
      country: d.countryCode,
      isp: d.isp,
      usageType: d.usageType,
      domain: d.domain,
      tor: d.isTor,
    };
  } catch (err) {
    return { ip, error: err instanceof Error ? err.message : String(err) };
  }
}

const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

// AbuseIPDB's free tier is 1 req/sec — check sequentially with a delay, same as
// check-ips.sh / check-deny-ips.sh, rather than firing requests concurrently.
export async function checkIpReputation(ips: string[]): Promise<IpCheckResult[]> {
  const apiKey = loadAbuseIpDbKey();
  const results: IpCheckResult[] = [];
  for (const ip of ips) {
    results.push(await checkOne(ip, apiKey));
    if (ip !== ips[ips.length - 1]) await sleep(1000);
  }
  return results;
}

export interface DenyListCheckResult {
  ips: IpCheckResult[];
  subnetsSkipped: number;
}

// Mirrors check-deny-ips.sh: reads every individual `deny <ip>;` line from a
// Trellis project's deny-ips.conf.j2 and checks each against AbuseIPDB, so
// stale blocks (score dropped to 0) are easy to spot. CIDR/subnet entries are
// skipped — AbuseIPDB checks single IPs, not ranges — and just counted.
export async function checkDenyList(trellisDir: string): Promise<DenyListCheckResult> {
  const confPath = path.join(trellisDir, DENY_IPS_RELATIVE_PATH);
  if (!existsSync(confPath)) {
    throw new Error(`deny-ips.conf.j2 not found at ${confPath}`);
  }

  const conf = readFileSync(confPath, "utf-8");
  const ips: string[] = [];
  let subnetsSkipped = 0;
  for (const m of conf.matchAll(/^deny ([0-9a-f:./]+);/gm)) {
    if (m[1].includes("/")) {
      subnetsSkipped++;
    } else {
      ips.push(m[1]);
    }
  }

  return { ips: await checkIpReputation(ips), subnetsSkipped };
}
