import { spawn } from "node:child_process";

interface RedirectAuditResult {
  url: string;
  status: number;
  redirects: number;
  finalUrl: string;
  httpRedirect: boolean;
  httpRedirectTarget?: string;
  wwwRedirect: boolean;
  wwwRedirectTarget?: string;
  securityHeaders: {
    hsts: boolean;
    csp: boolean;
    xFrameOptions: boolean;
    xContentTypeOptions: boolean;
  };
}

interface AuditSummary {
  totalTests: number;
  passedTests: number;
  failedTests: number;
  overallStatus: "PASS" | "FAIL";
  pages: RedirectAuditResult[];
}

function shellQuote(arg: string): string {
  return `'${arg.replace(/'/g, `'\\''`)}'`;
}

/**
 * Run curl to get HTTP response details
 */
async function runCurl(url: string): Promise<{
  httpCode: number;
  redirects: number;
  finalUrl: string;
  headers: Record<string, string>;
}> {
  return new Promise((resolve, reject) => {
    const child = spawn(
      "curl",
      [
        "-sI",
        "-L",
        "-w",
        "\n__STATS__\nredirects:%{num_redirects}\nfinal_url:%{url_effective}\nhttp_code:%{http_code}\n",
        url,
      ]
    );
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (d) => (stdout += d));
    child.stderr.on("data", (d) => (stderr += d));
    child.on("error", reject);
    child.on("close", (code) => {
      if (code !== 0) {
        reject(new Error(`curl failed with code ${code}: ${stderr}`));
        return;
      }

      const lines = stdout.split("\n");
      const stats: Record<string, string> = {};
      let inHeaders = true;
      const headers: Record<string, string> = {};

      for (const line of lines) {
        if (line.startsWith("__STATS__")) {
          inHeaders = false;
          continue;
        }
        if (!inHeaders) {
          const [key, ...valueParts] = line.split(":");
          if (key && valueParts.length > 0) {
            stats[key.trim().toLowerCase()] = valueParts.join(":").trim();
          }
          continue;
        }

        // Parse headers
        const headerMatch = line.match(/^([^:]+):\s*(.*)$/);
        if (headerMatch) {
          const headerName = headerMatch[1];
          const headerValue = headerMatch[2].trim();
          headers[headerName.toLowerCase()] = headerValue;
        }
      }

      resolve({
        httpCode: parseInt(stats["http_code"] || "0", 10),
        redirects: parseInt(stats["redirects"] || "0", 10),
        finalUrl: stats["final_url"] || url,
        headers,
      });
    });
  });
}

/**
 * Check HTTP to HTTPS redirect
 */
async function checkHttpRedirect(url: string): Promise<{
  httpUrl: string;
  redirectsTo: string | null;
  status: number | null;
}> {
  const httpUrl = url.replace(/^https:/, "http:");
  return new Promise((resolve, reject) => {
    const child = spawn("curl", ["-sI", httpUrl]);
    let stdout = "";
    child.stdout.on("data", (d) => (stdout += d));
    child.on("error", reject);
    child.on("close", (code) => {
      if (code !== 0) {
        resolve({ httpUrl, redirectsTo: null, status: null });
        return;
      }

      const lines = stdout.split("\n");
      let status: number | null = null;
      let location: string | null = null;

      for (const line of lines) {
        const statusMatch = line.match(/^HTTP\/\d\.\d"?\s+(\d+)/);
        if (statusMatch) {
          status = parseInt(statusMatch[1], 10);
        }
        const locationMatch = line.match(/^Location:\s*(.*)/i);
        if (locationMatch) {
          location = locationMatch[1].trim();
        }
      }

      resolve({ httpUrl, redirectsTo: location, status });
    });
  });
}

/**
 * Check www canonicalization
 */
async function checkWwwRedirect(domain: string): Promise<{
  wwwUrl: string;
  redirectsTo: string | null;
  status: number | null;
}> {
  const wwwUrl = `http://www.${domain}/`;
  return new Promise((resolve, reject) => {
    const child = spawn("curl", ["-sI", wwwUrl]);
    let stdout = "";
    child.stdout.on("data", (d) => (stdout += d));
    child.on("error", reject);
    child.on("close", (code) => {
      if (code !== 0) {
        resolve({ wwwUrl, redirectsTo: null, status: null });
        return;
      }

      const lines = stdout.split("\n");
      let status: number | null = null;
      let location: string | null = null;

      for (const line of lines) {
        const statusMatch = line.match(/^HTTP\/\d\.\d"?\s+(\d+)/);
        if (statusMatch) {
          status = parseInt(statusMatch[1], 10);
        }
        const locationMatch = line.match(/^Location:\s*(.*)/i);
        if (locationMatch) {
          location = locationMatch[1].trim();
        }
      }

      resolve({ wwwUrl, redirectsTo: location, status });
    });
  });
}

/**
 * Check security headers for a URL
 */
async function checkSecurityHeaders(url: string): Promise<{
  hsts: boolean;
  csp: boolean;
  xFrameOptions: boolean;
  xContentTypeOptions: boolean;
}> {
  return new Promise((resolve, reject) => {
    const child = spawn("curl", ["-sI", url]);
    let stdout = "";
    child.stdout.on("data", (d) => (stdout += d));
    child.on("error", reject);
    child.on("close", (code) => {
      if (code !== 0) {
        resolve({
          hsts: false,
          csp: false,
          xFrameOptions: false,
          xContentTypeOptions: false,
        });
        return;
      }

      const headers = stdout.toLowerCase();
      resolve({
        hsts: headers.includes("strict-transport-security"),
        csp: headers.includes("content-security-policy"),
        xFrameOptions: headers.includes("x-frame-options"),
        xContentTypeOptions: headers.includes("x-content-type-options"),
      });
    });
  });
}

/**
 * Audit a single URL for redirect chain issues
 */
async function auditUrl(url: string): Promise<RedirectAuditResult> {
  // Normalize URL
  if (!url.startsWith("http://") && !url.startsWith("https://")) {
    url = `https://${url}`;
  }
  if (!url.endsWith("/")) {
    url = `${url}/`;
  }

  // Extract domain (stripped of any leading "www." so the www check below
  // builds "www.example.com" rather than "www.www.example.com" for sites
  // whose canonical URL is already the www form)
  const domainMatch = url.match(/^https?:\/\/([^\/]+)/);
  const domain = (domainMatch ? domainMatch[1] : "").replace(/^www\./i, "");

  // Test HTTPS page
  const httpsResult = await runCurl(url);

  // Check HTTP redirect
  const httpRedirect = await checkHttpRedirect(url);

  // Check www redirect
  const wwwRedirect = await checkWwwRedirect(domain);

  // Check security headers
  const securityHeaders = await checkSecurityHeaders(url);

  return {
    url,
    status: httpsResult.httpCode,
    redirects: httpsResult.redirects,
    finalUrl: httpsResult.finalUrl,
    httpRedirect: httpRedirect.status === 301 && httpRedirect.redirectsTo === url,
    httpRedirectTarget: httpRedirect.redirectsTo || undefined,
    wwwRedirect:
      wwwRedirect.status === 301 && wwwRedirect.redirectsTo === `https://${domain}/`,
    wwwRedirectTarget: wwwRedirect.redirectsTo || undefined,
    securityHeaders,
  };
}

/**
 * Run a comprehensive redirect audit
 */
export async function runRedirectAudit(
  urls: string[],
  checkWww: boolean = true,
  checkSecurityHeaders: boolean = true
): Promise<AuditSummary> {
  const results: RedirectAuditResult[] = [];
  let passedTests = 0;
  let failedTests = 0;

  // Audit each URL
  for (const url of urls) {
    try {
      const result = await auditUrl(url);
      results.push(result);

      // Count tests
      // Test 1: HTTPS page should return 200 with 0 redirects
      if (result.status === 200 && result.redirects === 0) {
        passedTests++;
      } else {
        failedTests++;
      }

      // Test 2: HTTP should redirect to HTTPS
      if (result.httpRedirect) {
        passedTests++;
      } else {
        failedTests++;
      }

      // Test 3: www should redirect to non-www
      if (checkWww && result.wwwRedirect) {
        passedTests++;
      } else if (checkWww) {
        failedTests++;
      }
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      results.push({
        url,
        status: 0,
        redirects: -1,
        finalUrl: url,
        httpRedirect: false,
        httpRedirectTarget: undefined,
        wwwRedirect: false,
        wwwRedirectTarget: undefined,
        securityHeaders: {
          hsts: false,
          csp: false,
          xFrameOptions: false,
          xContentTypeOptions: false,
        },
      });
      failedTests += 3; // All 3 tests fail
    }
  }

  const totalTests = passedTests + failedTests;
  const overallStatus = failedTests === 0 ? "PASS" : "FAIL";

  return {
    totalTests,
    passedTests,
    failedTests,
    overallStatus,
    pages: results,
  };
}
