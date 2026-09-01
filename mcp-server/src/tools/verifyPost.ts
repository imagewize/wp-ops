import type { EnvEntry } from "../registry.js";
import { runWpCliRaw } from "./wpCli.js";

export interface VerifyCheck {
  name: string;
  status: "pass" | "warn" | "fail";
  detail: string;
}

export interface VerifyPostResult {
  postId: number;
  status: string;
  permalink: string;
  storedBytes: number;
  storedLdJson: number;
  storedScripts: number;
  renderedLdJson: number;
  schemaTypes: string[];
  thumbnailId: number;
  checks: VerifyCheck[];
  passed: boolean;
}

// Mirrors wp-cli/content-creation/verify-post.sh. The point of this tool is the
// comparison between what is STORED in post_content and what actually RENDERS —
// every way content silently disappears on this stack is invisible to a
// post_content diff:
//
//   - kses strips <script type="application/ld+json"> when WP-CLI runs with a
//     --user lacking unfiltered_html. The post saves fine; the schema is gone.
//   - A self-closing custom block (`<!-- wp:ns/block {...} /-->`) written via
//     WP-CLI saves as a genuinely EMPTY block: Gutenberg builds its InnerBlocks
//     template client-side on insert, so nothing hydrates. No output, not even a
//     broken-block placeholder.
//   - A cached page keeps serving the previous render after an update.
//
// Reuses runWpCliRaw rather than reimplementing local/SSH/VM dispatch.

// Reported as key=value lines so the reader stays a plain split() rather than a
// JSON round-trip through two shells.
const WORKER = String.raw`
$ref = '__POST_REF__';
$post = ctype_digit( $ref ) ? get_post( (int) $ref ) : get_page_by_path( trim( $ref, '/' ), OBJECT, 'post' );
if ( ! $post ) { echo "ABORT=1\n"; return; }
$c = $post->post_content;
echo "id=" . $post->ID . "\n";
echo "status=" . $post->post_status . "\n";
echo "permalink=" . get_permalink( $post->ID ) . "\n";
echo "stored_bytes=" . strlen( $c ) . "\n";
echo "ldjson=" . substr_count( $c, 'application/ld+json' ) . "\n";
echo "scripts=" . substr_count( $c, '<script' ) . "\n";
echo "thumbnail=" . ( get_post_thumbnail_id( $post->ID ) ?: '0' ) . "\n";
echo "meta_title=" . ( get_post_meta( $post->ID, '_genesis_title', true ) ?: '' ) . "\n";
echo "meta_desc_len=" . strlen( (string) get_post_meta( $post->ID, '_genesis_description', true ) ) . "\n";
preg_match_all( '/<!-- wp:([a-z0-9-]+\/[a-z0-9-]+) (\{[^}]*\} )?\/-->/', $c, $m );
echo "selfclosing=" . count( $m[0] ) . "\n";
echo "selfclosing_names=" . implode( ',', array_unique( $m[1] ) ) . "\n";
preg_match_all( '/href="(\/[^"#][^"]*)"/', $c, $lm );
echo "internal_list=" . implode( ' ', array_unique( $lm[1] ) ) . "\n";
`.trim();

function parseKeyValues(stdout: string): Record<string, string> {
  const out: Record<string, string> = {};
  for (const line of stdout.split("\n")) {
    const idx = line.indexOf("=");
    if (idx > 0) out[line.slice(0, idx).trim()] = line.slice(idx + 1).trim();
  }
  return out;
}

function schemaTypesFrom(html: string): string[] {
  const types = new Set<string>();
  const re = /"@type"\s*:\s*"([A-Za-z]+)"/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(html)) !== null) types.add(m[1]);
  return [...types].sort();
}

export async function runVerifyPost(
  entry: EnvEntry,
  postRef: string,
  options: { checkLinks?: boolean } = {}
): Promise<VerifyPostResult> {
  const res = await runWpCliRaw(entry, ["eval", WORKER.replace("__POST_REF__", postRef)]);
  if (res.code !== 0) {
    throw new Error(`WP-CLI could not read the post (exit ${res.code}): ${res.stderr || res.stdout}`);
  }
  const kv = parseKeyValues(res.stdout);
  if (kv.ABORT === "1" || !kv.id) {
    throw new Error(`Post "${postRef}" not found.`);
  }

  const storedBytes = Number(kv.stored_bytes ?? 0);
  const storedLdJson = Number(kv.ldjson ?? 0);
  const storedScripts = Number(kv.scripts ?? 0);
  const thumbnailId = Number(kv.thumbnail ?? 0);
  const metaTitle = kv.meta_title ?? "";
  const metaDescLen = Number(kv.meta_desc_len ?? 0);
  const selfClosing = Number(kv.selfclosing ?? 0);
  const permalink = kv.permalink ?? "";

  const checks: VerifyCheck[] = [];

  checks.push(
    storedLdJson > 0
      ? { name: "stored-jsonld", status: "pass", detail: `${storedLdJson} JSON-LD block(s) in post_content` }
      : {
          name: "stored-jsonld",
          status: "warn",
          detail: "No JSON-LD in post_content (fine if the SEO plugin emits all schema)",
        }
  );

  checks.push(
    selfClosing > 0
      ? {
          name: "self-closing-blocks",
          status: "fail",
          detail:
            `${selfClosing} self-closing custom block(s) (${kv.selfclosing_names}) — these save EMPTY ` +
            "when written via WP-CLI; hand-build the serialized markup instead",
        }
      : { name: "self-closing-blocks", status: "pass", detail: "No self-closing custom blocks" }
  );

  if (!metaTitle) {
    checks.push({ name: "meta-title", status: "warn", detail: "No _genesis_title — SEO plugin falls back to the post title" });
  } else if (metaTitle.length > 55) {
    checks.push({ name: "meta-title", status: "warn", detail: `Meta title is ${metaTitle.length} chars (>55) — will truncate` });
  } else {
    checks.push({ name: "meta-title", status: "pass", detail: `Meta title set (${metaTitle.length} chars)` });
  }

  if (metaDescLen === 0) {
    checks.push({ name: "meta-description", status: "warn", detail: "No _genesis_description set" });
  } else if (metaDescLen > 155) {
    checks.push({ name: "meta-description", status: "warn", detail: `Meta description is ${metaDescLen} chars (>155) — will truncate` });
  } else {
    checks.push({ name: "meta-description", status: "pass", detail: `Meta description set (${metaDescLen} chars)` });
  }

  checks.push(
    thumbnailId > 0
      ? { name: "featured-image", status: "pass", detail: `Featured image set (attachment ${thumbnailId})` }
      : { name: "featured-image", status: "warn", detail: "No featured image — og:image falls back to the site logo" }
  );

  // ---- live render ----
  let renderedLdJson = 0;
  let schemaTypes: string[] = [];

  if (!permalink) {
    checks.push({ name: "live-render", status: "fail", detail: "No permalink returned — cannot check the live page" });
  } else {
    let html = "";
    let httpStatus = 0;
    try {
      const resp = await fetch(permalink, { redirect: "follow" });
      httpStatus = resp.status;
      html = await resp.text();
    } catch (err) {
      checks.push({ name: "live-render", status: "fail", detail: `Could not fetch ${permalink}: ${(err as Error).message}` });
    }

    if (httpStatus && httpStatus !== 200) {
      checks.push({ name: "live-render", status: "fail", detail: `${permalink} returned HTTP ${httpStatus}` });
    } else if (html) {
      checks.push({ name: "live-render", status: "pass", detail: "HTTP 200" });
      renderedLdJson = (html.match(/application\/ld\+json/g) ?? []).length;
      schemaTypes = schemaTypesFrom(html);

      checks.push(
        storedLdJson > 0 && renderedLdJson < storedLdJson
          ? {
              name: "rendered-jsonld",
              status: "fail",
              detail: `Only ${renderedLdJson} JSON-LD block(s) render but ${storedLdJson} are stored — stripped on output`,
            }
          : {
              name: "rendered-jsonld",
              status: "pass",
              detail: `${renderedLdJson} JSON-LD block(s) render (>= ${storedLdJson} stored)`,
            }
      );

      // An InnerBlocks wrapper that saved empty renders as a div with no content.
      if (/class="wp-block-[a-z0-9-]+-cta[^"]*"><\/div>/.test(html)) {
        checks.push({ name: "empty-cta", status: "fail", detail: "A CTA block wrapper rendered EMPTY on the live page" });
      }

      if (options.checkLinks !== false) {
        const paths = (kv.internal_list ?? "").split(" ").filter((p) => p && !p.includes("?"));
        if (paths.length) {
          const origin = new URL(permalink).origin;
          const broken: string[] = [];
          await Promise.all(
            paths.map(async (p) => {
              try {
                const r = await fetch(origin + p, { method: "HEAD", redirect: "follow" });
                if (r.status !== 200) broken.push(`${p} -> ${r.status}`);
              } catch {
                broken.push(`${p} -> unreachable`);
              }
            })
          );
          checks.push(
            broken.length
              ? { name: "internal-links", status: "fail", detail: `Broken internal link(s): ${broken.join(", ")}` }
              : { name: "internal-links", status: "pass", detail: `${paths.length} internal link(s) all resolve` }
          );
        }
      }
    }
  }

  return {
    postId: Number(kv.id),
    status: kv.status ?? "",
    permalink,
    storedBytes,
    storedLdJson,
    storedScripts,
    renderedLdJson,
    schemaTypes,
    thumbnailId,
    checks,
    passed: !checks.some((c) => c.status === "fail"),
  };
}

export function formatVerifyPost(r: VerifyPostResult): string {
  const lines: string[] = [];
  lines.push(`Post ${r.postId} (${r.status}) — ${r.permalink}`);
  lines.push(`Stored: ${r.storedBytes} bytes, ${r.storedLdJson} JSON-LD block(s), ${r.storedScripts} script tag(s)`);
  lines.push("");
  for (const c of r.checks) {
    const mark = c.status === "pass" ? "PASS" : c.status === "warn" ? "WARN" : "FAIL";
    lines.push(`  ${mark}  ${c.detail}`);
  }
  if (r.schemaTypes.length) {
    lines.push("");
    lines.push(`Schema types rendered: ${r.schemaTypes.join(", ")}`);
  }
  lines.push("");
  lines.push(r.passed ? "All checks passed." : "One or more checks FAILED.");
  return lines.join("\n");
}
