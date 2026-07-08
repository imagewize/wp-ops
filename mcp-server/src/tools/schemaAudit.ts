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
  hasSchema: boolean;
  schemaTypes: SchemaTypeCheck[];
  rawSchema?: string;
}

interface SchemaAuditSummary {
  totalPages: number;
  pagesWithSchema: number;
  pagesWithoutSchema: number;
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
  return SCHEMA_TYPES.map((type) => ({
    type,
    found: rawSchema.some((schema) => {
      // Check for @type field with the type value
      try {
        const parsed = JSON.parse(schema);
        return parsed["@type"] === type || (Array.isArray(parsed["@type"]) && parsed["@type"].includes(type));
      } catch {
        // Fallback to string search if JSON parsing fails
        return schema.toLowerCase().includes(`"@type":"${type}"`);
      }
    }),
  }));
}

/**
 * Fetch a URL and extract schema
 */
async function fetchPage(url: string): Promise<{
  html: string;
  status: number;
}> {
  return new Promise((resolve, reject) => {
    const child = spawn("curl", ["-s", "-f", "--max-time", "30", url]);
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (d) => (stdout += d));
    child.stderr.on("data", (d) => (stderr += d));
    child.on("error", reject);
    child.on("close", (code) => {
      // curl returns 22 for HTTP 4xx errors when using -f flag
      if (code !== 0 && code !== 22) {
        reject(new Error(`curl failed with code ${code}: ${stderr}`));
        return;
      }

      // Try to get status from output (curl -w could be used but we're using -s -f)
      // For now, assume 200 if we got output, 404 if -f flag caused failure
      const status = code === 22 ? 404 : 200;
      resolve({ html: stdout, status });
    });
  });
}

/**
 * Get HTTP status code for a URL
 */
async function getHttpStatus(url: string): Promise<number> {
  return new Promise((resolve, reject) => {
    const child = spawn("curl", ["-s", "-o", "/dev/null", "-w", "%{http_code}", url]);
    let stdout = "";
    child.stdout.on("data", (d) => (stdout += d));
    child.on("error", reject);
    child.on("close", (code) => {
      if (code !== 0) {
        resolve(0);
        return;
      }
      const status = parseInt(stdout.trim(), 10);
      resolve(isNaN(status) ? 0 : status);
    });
  });
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

  // Check if page exists
  const status = await getHttpStatus(fullUrl);
  const exists = status === 200;

  if (!exists) {
    return {
      url: fullUrl,
      pageName,
      exists,
      httpStatus: status,
      hasSchema: false,
      schemaTypes: SCHEMA_TYPES.map((type) => ({ type, found: false })),
    };
  }

  // Fetch page content
  const { html } = await fetchPage(fullUrl);

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
  pages?: string[]
): Promise<SchemaAuditSummary> {
  // Normalize site URL
  if (!siteUrl.startsWith("http://") && !siteUrl.startsWith("https://")) {
    siteUrl = `https://${siteUrl}`;
  }
  if (!siteUrl.endsWith("/")) {
    siteUrl = `${siteUrl}/`;
  }

  // Default pages to check
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

  // Use custom pages if provided, otherwise use defaults
  const pagesToCheck = pages || defaultPages;

  const results: PageSchemaResult[] = [];
  const schemaTypesFound: Record<string, number> = {};
  SCHEMA_TYPES.forEach((type) => (schemaTypesFound[type] = 0));

  let pagesWithSchema = 0;
  let pagesWithoutSchema = 0;

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
    }

    // Be nice to the server
    await new Promise((resolve) => setTimeout(resolve, 500));
  }

  const totalPages = pagesWithSchema + pagesWithoutSchema;

  return {
    totalPages,
    pagesWithSchema,
    pagesWithoutSchema,
    schemaTypesFound,
    pages: results,
  };
}
