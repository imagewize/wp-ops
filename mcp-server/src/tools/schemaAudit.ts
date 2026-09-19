import { spawn } from "node:child_process";

interface SchemaTypeCheck {
  type: string;
  found: boolean;
}

interface PageSchemaResult {
  url: string;
  pageName: string;
  exists: boolean;
  httpStatus: number;
  redirectUrl?: string;
  hasSchema: boolean;
  schemaTypes: SchemaTypeCheck[];
  rawSchema?: string;
}

interface PageSource {
  kind: "custom" | "sitemap" | "default";
  // sitemap: the sitemap URL the pages came from
  sitemapUrl?: string;
  // sitemap: how many same-site URLs the sitemap listed before maxPages applied
  totalFound?: number;
}

interface SchemaAuditSummary {
  totalPages: number;
  pagesWithSchema: number;
  pagesWithoutSchema: number;
  pagesNotFound: number;
  pageSource: PageSource;
  schemaTypesFound: Record<string, number>;
  pages: PageSchemaResult[];
}

const SCHEMA_TYPES = [
  "Organization",
  "LocalBusiness",
  "Service",
  "Product",
  "WebSite",
  "BreadcrumbList",
  "Article",
  "FAQPage",
  "HowTo",
  "Person",
];

/**
 * Extract JSON-LD schema from HTML content
 */
function extractSchema(html: string): string[] {
  const schemas: string[] = [];
  const scriptRegex = /<script[^>]*type=["']application\/ld\+json["'][^>]*>(.*?)<\/script>/gis;
  let match;

  while ((match = scriptRegex.exec(html)) !== null) {
    schemas.push(match[1]);
  }

  return schemas;
}

/**
 * Check which schema types are present in JSON-LD content
 */
function checkSchemaTypes(rawSchema: string[]): SchemaTypeCheck[] {
  const found = new Set<string>();

  // Every @type anywhere in the tree: SEO plugins nest their nodes in an
  // "@graph" array rather than putting one @type at the top level
  const collect = (node: unknown): void => {
    if (Array.isArray(node)) {
      node.forEach(collect);
    } else if (node && typeof node === "object") {
      for (const [key, value] of Object.entries(node)) {
        if (key === "@type") {
          (Array.isArray(value) ? value : [value]).forEach((t) => typeof t === "string" && found.add(t));
        } else {
          collect(value);
        }
      }
    }
  };

  for (const schema of rawSchema) {
    try {
      collect(JSON.parse(schema));
    } catch {
      // Unparseable JSON-LD: fall back to matching "@type": "X" in the text
      for (const type of SCHEMA_TYPES) {
        if (new RegExp(`"@type"\\s*:\\s*(\\[[^\\]]*)?"${type}"`).test(schema)) found.add(type);
      }
    }
  }

  return SCHEMA_TYPES.map((type) => ({ type, found: found.has(type) }));
}

/**
 * Fetch a page in one request: body, HTTP status, and the Location target when
 * it redirects. Redirects are not followed — a URL that redirects is reported,
 * not audited under its old address.
 */
async function fetchPage(url: string): Promise<{ html: string; status: number; redirectUrl?: string }> {
  const marker = "\n__WP_OPS_STATUS__ ";
  return new Promise((resolve, reject) => {
    const child = spawn("curl", ["-s", "--max-time", "30", "-w", `${marker}%{http_code} %{redirect_url}`, url]);
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (d) => (stdout += d));
    child.stderr.on("data", (d) => (stderr += d));
    child.on("error", reject);
    child.on("close", (code) => {
      const at = stdout.lastIndexOf(marker);
      if (code !== 0 || at === -1) {
        // Network-level failure (DNS, timeout, TLS) — no HTTP status to report
        resolve({ html: "", status: 0 });
        return;
      }
      const [statusText, redirectUrl] = stdout.slice(at + marker.length).trim().split(" ");
      const status = parseInt(statusText, 10);
      resolve({
        html: stdout.slice(0, at),
        status: isNaN(status) ? 0 : status,
        redirectUrl: redirectUrl || undefined,
      });
    });
  });
}

/**
 * Fetch a URL's body, following redirects. Returns null on any HTTP or network error.
 */
async function fetchText(url: string): Promise<string | null> {
  return new Promise((resolve) => {
    const child = spawn("curl", ["-s", "-f", "-L", "--max-time", "30", url]);
    let stdout = "";
    child.stdout.on("data", (d) => (stdout += d));
    child.on("error", () => resolve(null));
    child.on("close", (code) => resolve(code === 0 ? stdout : null));
  });
}

/**
 * Pull the <loc> values out of a sitemap or sitemap index
 */
function parseLocs(xml: string): string[] {
  const locs: string[] = [];
  const locRegex = /<loc>\s*(?:<!\[CDATA\[)?\s*(.*?)\s*(?:\]\]>)?\s*<\/loc>/gis;
  let match;
  while ((match = locRegex.exec(xml)) !== null) {
    locs.push(match[1].replace(/&amp;/g, "&"));
  }
  return locs;
}

// Checked in order: WordPress core, then the index Yoast / Rank Math / The SEO
// Framework serve, then the plain path most other generators use.
const SITEMAP_PATHS = ["wp-sitemap.xml", "sitemap_index.xml", "sitemap.xml"];

/**
 * Build the page list from the site's own sitemap, so the audit checks pages
 * that exist rather than guessed paths. From a sitemap index, only the page
 * sitemaps are read when there are any (wp-sitemap-posts-page-1.xml,
 * page-sitemap.xml); a flat sitemap is taken as-is. Returns null when no
 * sitemap lists any URL on this site.
 */
async function discoverSitemapPages(
  siteUrl: string,
  maxPages: number
): Promise<{ pages: string[]; sitemapUrl: string; totalFound: number } | null> {
  const siteHost = new URL(siteUrl).hostname;

  for (const sitemapPath of SITEMAP_PATHS) {
    const sitemapUrl = new URL(sitemapPath, siteUrl).toString();
    const xml = await fetchText(sitemapUrl);
    if (!xml) continue;

    let urls: string[] = [];
    if (/<sitemapindex/i.test(xml)) {
      const children = parseLocs(xml);
      const pageChildren = children.filter((u) => /page/i.test(u.split("/").pop() || ""));
      for (const child of pageChildren.length > 0 ? pageChildren : children) {
        const childXml = await fetchText(child);
        if (childXml) urls.push(...parseLocs(childXml));
      }
    } else if (/<urlset/i.test(xml)) {
      urls = parseLocs(xml);
    }

    const seen = new Set<string>();
    const sameSite = urls.filter((u) => {
      let host: string;
      try {
        host = new URL(u).hostname;
      } catch {
        return false;
      }
      if (host !== siteHost || seen.has(u)) return false;
      seen.add(u);
      return true;
    });
    if (sameSite.length === 0) continue;

    // Always lead with the homepage, whether or not the sitemap lists it
    const homepage = new URL("/", siteUrl).toString();
    const ordered = [homepage, ...sameSite.filter((u) => u !== homepage)];
    const pages = ordered.slice(0, maxPages).map((u) => {
      const path = new URL(u).pathname;
      return `${path === "/" ? "Homepage" : path}|${u}`;
    });
    return { pages, sitemapUrl, totalFound: ordered.length };
  }

  return null;
}

/**
 * Audit a single page for schema markup
 */
async function auditPage(
  pageName: string,
  pageUrl: string,
  baseUrl: string
): Promise<PageSchemaResult> {
  const fullUrl = new URL(pageUrl, baseUrl).toString();

  const { html, status, redirectUrl } = await fetchPage(fullUrl);
  const exists = status === 200;

  if (!exists) {
    return {
      url: fullUrl,
      pageName,
      exists,
      httpStatus: status,
      redirectUrl,
      hasSchema: false,
      schemaTypes: SCHEMA_TYPES.map((type) => ({ type, found: false })),
    };
  }

  // Extract schema
  const rawSchemas = extractSchema(html);
  const hasSchema = rawSchemas.length > 0;

  // Check schema types
  const schemaTypes = checkSchemaTypes(rawSchemas);

  return {
    url: fullUrl,
    pageName,
    exists,
    httpStatus: status,
    hasSchema,
    schemaTypes,
    rawSchema: hasSchema ? rawSchemas.join("\n") : undefined,
  };
}

/**
 * Run a comprehensive schema audit
 */
export async function runSchemaAudit(
  siteUrl: string,
  pages?: string[],
  maxPages = 25
): Promise<SchemaAuditSummary> {
  // Normalize site URL
  if (!siteUrl.startsWith("http://") && !siteUrl.startsWith("https://")) {
    siteUrl = `https://${siteUrl}`;
  }
  if (!siteUrl.endsWith("/")) {
    siteUrl = `${siteUrl}/`;
  }

  // Fallback when the site has no usable sitemap: common paths, several of
  // which won't exist on any given site
  const defaultPages = [
    "Homepage|/",
    "Services|/services/",
    "About|/about/",
    "About Us|/about-us/",
    "Contact|/contact/",
    "Contact Us|/contact-us/",
    "Portfolio|/portfolio/",
    "Shop|/shop/",
    "Blog|/blog/",
    "Insights|/insights/",
    "News|/news/",
  ];

  // Custom pages if provided, else the site's sitemap, else the common paths
  let pagesToCheck: string[];
  let pageSource: PageSource;
  if (pages && pages.length > 0) {
    pagesToCheck = pages;
    pageSource = { kind: "custom" };
  } else {
    const discovered = await discoverSitemapPages(siteUrl, maxPages);
    if (discovered) {
      pagesToCheck = discovered.pages;
      pageSource = { kind: "sitemap", sitemapUrl: discovered.sitemapUrl, totalFound: discovered.totalFound };
    } else {
      pagesToCheck = defaultPages;
      pageSource = { kind: "default" };
    }
  }

  const results: PageSchemaResult[] = [];
  const schemaTypesFound: Record<string, number> = {};
  SCHEMA_TYPES.forEach((type) => (schemaTypesFound[type] = 0));

  let pagesWithSchema = 0;
  let pagesWithoutSchema = 0;
  let pagesNotFound = 0;

  // Audit each page
  for (const pageEntry of pagesToCheck) {
    const [pageName, pageUrl] = pageEntry.split("|");
    try {
      const result = await auditPage(pageName, pageUrl, siteUrl);
      results.push(result);

      if (result.exists) {
        if (result.hasSchema) {
          pagesWithSchema++;
          // Count schema types
          result.schemaTypes.forEach((check) => {
            if (check.found) {
              schemaTypesFound[check.type] = (schemaTypesFound[check.type] || 0) + 1;
            }
          });
        } else {
          pagesWithoutSchema++;
        }
      } else {
        pagesNotFound++;
      }
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      results.push({
        url: new URL(pageUrl, siteUrl).toString(),
        pageName,
        exists: false,
        httpStatus: 0,
        hasSchema: false,
        schemaTypes: SCHEMA_TYPES.map((type) => ({ type, found: false })),
      });
      // Don't count as without schema since page doesn't exist
      pagesNotFound++;
    }

    // Be nice to the server
    await new Promise((resolve) => setTimeout(resolve, 500));
  }

  const totalPages = pagesWithSchema + pagesWithoutSchema;

  return {
    totalPages,
    pagesWithSchema,
    pagesWithoutSchema,
    pagesNotFound,
    pageSource,
    schemaTypesFound,
    pages: results,
  };
}
