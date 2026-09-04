import { readFileSync } from "node:fs";
import type { EnvEntry } from "../registry.js";
import { runWpCliRaw } from "./wpCli.js";

export interface DraftHeader {
  slug: string;
  title: string;
  metaTitle: string;
  metaDescription: string;
  tags: string[];
  category: string;
}

export interface PublishPostResult {
  postId: number;
  permalink: string;
  created: boolean;
  status: string;
  sourceBytes: number;
  storedBytes: number;
  sourceLdJson: number;
  storedLdJson: number;
  thumbnailId?: number;
  imageUrl?: string;
  warnings: string[];
  verified: boolean;
}

// Mirrors wp-cli/content-creation/publish-post.sh.
//
// NOTE ON --user: this never passes --user to WP-CLI, and that is load-bearing.
// WP-CLI tears down kses filters at init priority 11 only when --user is
// ABSENT, so omitting it is what lets <script type="application/ld+json">
// survive the write. Passing --user for an account lacking unfiltered_html
// re-adds the filters and silently strips the schema. Do not "fix" this.
//
// The body is shipped to the target as base64 inside a `wp eval` call rather
// than scp'd: that keeps one code path across SSH, a local path and a Trellis
// VM, since runWpCliRaw already resolves all three. A ~25KB post encodes to
// ~34KB, comfortably inside ARG_MAX.

const HEADER_PATTERNS: Record<keyof DraftHeader, RegExp> = {
  slug: /^<!--\s*SUGGESTED POST SLUG:\s*(.*?)\s*-->$/m,
  title: /^<!--\s*SUGGESTED TITLE:\s*(.*?)\s*-->$/m,
  metaTitle: /^<!--\s*SUGGESTED META TITLE\s*\([^)]*\):\s*(.*?)\s*-->$/m,
  metaDescription: /^<!--\s*SUGGESTED META\s*\([^)]*\):\s*(.*?)\s*-->$/m,
  tags: /^<!--\s*SUGGESTED TAGS:\s*(.*?)\s*-->$/m,
  category: /^<!--\s*SUGGESTED CATEGORY:\s*(.*?)\s*-->$/m,
};

export function parseDraftHeader(raw: string): DraftHeader {
  const pick = (re: RegExp) => raw.match(re)?.[1]?.trim() ?? "";
  return {
    slug: pick(HEADER_PATTERNS.slug).replace(/^\/|\/$/g, ""),
    title: pick(HEADER_PATTERNS.title),
    metaTitle: pick(HEADER_PATTERNS.metaTitle),
    metaDescription: pick(HEADER_PATTERNS.metaDescription),
    tags: pick(HEADER_PATTERNS.tags).split(",").map((t) => t.trim()).filter(Boolean),
    category: pick(HEADER_PATTERNS.category),
  };
}

// Strip the SUGGESTED header and any Blade doc-comments — WordPress would
// otherwise store them as literal text in post_content.
export function stripDraftHeader(raw: string): string {
  return raw
    .split("\n")
    .filter((l) => !/^<!--\s*SUGGESTED /.test(l) && !/^\{\{--/.test(l))
    .join("\n")
    .replace(/^\s*\n+/, "");
}

function phpQuote(s: string): string {
  return Buffer.from(s, "utf8").toString("base64");
}

// A self-closing custom block never hydrates when written via WP-CLI: Gutenberg
// builds its InnerBlocks template client-side on insert, so piping the one-liner
// the inserter produces into post_content saves a genuinely empty block with no
// visible output. The pattern is verify-post's, so the two tools agree on what
// counts — including the attribute-less form verify-post already matched.
const SELF_CLOSING_BLOCK = /<!-- wp:([a-z0-9-]+\/[a-z0-9-]+) (?:\{[^}]*\} )?\/-->/g;

export function selfClosingBlockNames(body: string): string[] {
  return [...new Set(Array.from(body.matchAll(SELF_CLOSING_BLOCK), (m) => m[1]))];
}

// Rewrite the Article JSON-LD block's `image` to a verified upload URL.
// Parsed as real JSON rather than patched with a regex: the block is genuine
// JSON-LD and a textual edit corrupts it silently on any nesting. Mirrors
// publish-post.sh's prepare_body().
export function injectArticleImage(body: string, url: string): { body: string; injected: boolean } {
  let injected = false;
  const out = body.replace(
    /<script type="application\/ld\+json">([\s\S]*?)<\/script>/g,
    (whole, inner: string) => {
      let parsed: Record<string, unknown>;
      try {
        parsed = JSON.parse(inner);
      } catch {
        return whole;
      }
      if (parsed["@type"] !== "Article") return whole;
      parsed.image = url;
      injected = true;
      return `<script type="application/ld+json">\n${JSON.stringify(parsed, null, 2)}\n</script>`;
    }
  );
  return { body: injected ? out : body, injected };
}

// Upload a local image and return its attachment ID and verified URL.
// The file is shipped as base64 inside `wp eval` for the same reason the post
// body is: it keeps one code path across SSH, a local path and a Trellis VM,
// where an scp would only cover the first.
export async function uploadFeaturedImage(
  entry: EnvEntry,
  imagePath: string,
  title: string,
  alt: string
): Promise<{ attachmentId: number; url: string }> {
  const bytes = readFileSync(imagePath);
  const remoteName = imagePath.split("/").pop() ?? "featured.jpg";

  const write = await runWpCliRaw(entry, [
    "eval",
    `$p = sys_get_temp_dir() . '/' . basename( base64_decode( '${phpQuote(remoteName)}' ) );` +
      `file_put_contents( $p, base64_decode( '${bytes.toString("base64")}' ) ); echo $p;`,
  ]);
  if (write.code !== 0) {
    throw new Error(`Could not stage the image on the target (exit ${write.code}): ${write.stderr || write.stdout}`);
  }
  const remotePath = write.stdout.trim().split("\n").pop()?.trim() ?? "";
  if (!remotePath) throw new Error("Could not determine the staged image path on the target.");

  const imported = await runWpCliRaw(entry, [
    "media",
    "import",
    remotePath,
    `--title=${title}`,
    `--alt=${alt}`,
    "--porcelain",
  ]);
  // Clean up the staged copy whether or not the import succeeded.
  await runWpCliRaw(entry, ["eval", `@unlink( base64_decode( '${phpQuote(remotePath)}' ) );`]);

  if (imported.code !== 0) {
    throw new Error(`wp media import failed (exit ${imported.code}): ${imported.stderr || imported.stdout}`);
  }
  const attachmentId = Number(imported.stdout.trim().split("\n").pop()?.replace(/\D/g, ""));
  if (!attachmentId) throw new Error(`Could not parse an attachment ID from: ${imported.stdout.trim()}`);

  const guid = await runWpCliRaw(entry, ["post", "get", String(attachmentId), "--field=guid"]);
  const url = guid.stdout.trim().split("\n").pop()?.trim() ?? "";
  return { attachmentId, url };
}

export async function runPublishPost(
  entry: EnvEntry,
  draftPath: string,
  options: {
    updateId?: number;
    status?: string;
    /** Local image file to upload, attach and inject into the Article schema. */
    imagePath?: string;
    /** Alt text for an uploaded image. Defaults to the post title. */
    imageAlt?: string;
    /** An already-uploaded attachment to attach instead of uploading one. */
    imageAttachmentId?: number;
    /** Publish even though the draft has self-closing custom blocks that will save empty. */
    allowSelfClosingBlocks?: boolean;
    dryRun?: boolean;
  } = {}
): Promise<PublishPostResult> {
  const raw = readFileSync(draftPath, "utf8");
  const header = parseDraftHeader(raw);
  let body = stripDraftHeader(raw);

  const warnings: string[] = [];

  if (!header.title) throw new Error(`No "<!-- SUGGESTED TITLE: ... -->" found in ${draftPath}`);
  if (!header.slug && !options.updateId) {
    throw new Error(`No "<!-- SUGGESTED POST SLUG: /slug/ -->" found and no updateId given`);
  }

  // Upload the featured image first: its URL goes into the Article schema, so
  // it must be known before the source byte counts that the verification
  // compares against are taken.
  let thumbnailId = options.imageAttachmentId;
  let imageUrl: string | undefined;
  if (options.imagePath && !options.dryRun) {
    const uploaded = await uploadFeaturedImage(
      entry,
      options.imagePath,
      header.title,
      options.imageAlt || header.title
    );
    thumbnailId = uploaded.attachmentId;
    imageUrl = uploaded.url;
    const { body: withImage, injected } = injectArticleImage(body, uploaded.url);
    body = withImage;
    if (!injected) warnings.push("No Article JSON-LD block found — image URL not injected into schema");
  }

  const sourceBytes = Buffer.byteLength(body, "utf8");
  const sourceLdJson = (body.match(/application\/ld\+json/g) ?? []).length;
  const sourceScripts = (body.match(/<script/g) ?? []).length;

  if (sourceBytes < 500) {
    throw new Error(`Body is only ${sourceBytes} bytes — refusing to publish a near-empty post`);
  }
  if (header.metaTitle.length > 55) {
    warnings.push(`Meta title is ${header.metaTitle.length} chars (>55) — will truncate once "| Site" is appended`);
  }
  if (header.metaDescription.length > 155) {
    warnings.push(`Meta description is ${header.metaDescription.length} chars (>155) — will truncate in SERPs`);
  }
  for (const bad of ["wp:columns", "wp:callout", "wp:acf/"]) {
    if (body.includes(bad)) warnings.push(`Draft contains "${bad}" — renders as a broken block in posts`);
  }
  // Fails rather than warns, matching verify-post and the near-empty-body check
  // above: the block saves empty, nothing errors, and a post_content diff shows
  // nothing — so a warning printed next to a successful publish is read too late.
  const selfClosing = selfClosingBlockNames(body);
  if (selfClosing.length) {
    const detail =
      `Draft contains ${selfClosing.length} self-closing custom block(s) (${selfClosing.join(", ")}) — ` +
      "they will save EMPTY via WP-CLI.";
    if (!options.allowSelfClosingBlocks) {
      throw new Error(
        `${detail} Hand-build the full serialized markup, or pass allowSelfClosingBlocks: true ` +
          "to publish anyway (only correct for a genuinely dynamic, server-rendered block)."
      );
    }
    warnings.push(`${detail} Published anyway — allowSelfClosingBlocks was set.`);
  }

  if (options.dryRun) {
    return {
      postId: 0,
      permalink: "",
      created: false,
      status: "dry-run",
      sourceBytes,
      storedBytes: 0,
      sourceLdJson,
      storedLdJson: 0,
      warnings,
      verified: false,
    };
  }

  const worker = String.raw`
$body = base64_decode( '${phpQuote(body)}' );
if ( strlen( $body ) !== ${sourceBytes} ) { echo "ABORT=transit-length\n"; return; }
// wp_update_post()/wp_insert_post() call wp_unslash() internally and expect slashed
// input, so an unslashed body loses every literal backslash. Slash after the transit
// check above so that check still measures the real payload.
$body = wp_slash( $body );
$update_id = ${options.updateId ? String(options.updateId) : "0"};
$slug = base64_decode( '${phpQuote(header.slug)}' );
if ( $update_id ) {
  $before = get_post( $update_id );
  if ( ! $before ) { echo "ABORT=missing-post\n"; return; }
  // The draft header is the source of truth for the title and meta description:
  // the SEO meta below is rewritten from it on every run, so leaving post_title
  // and post_excerpt alone let a stale title outlive the SEO title it should match.
  // post_name and post_status are deliberately NOT touched — rewriting the slug
  // would break the live URL silently, and an update must not flip a draft live.
  if ( $slug && $before->post_name !== $slug ) { echo "warn_slug=" . $before->post_name . "\n"; }
  $id = wp_update_post( array(
    'ID'           => $update_id,
    'post_title'   => wp_slash( base64_decode( '${phpQuote(header.title)}' ) ),
    'post_content' => $body,
    'post_excerpt' => wp_slash( base64_decode( '${phpQuote(header.metaDescription)}' ) ),
  ), true );
  $created = 0;
} else {
  $existing = $slug ? get_page_by_path( $slug, OBJECT, 'post' ) : null;
  if ( $existing ) { echo "ABORT=duplicate-slug\nexisting=" . $existing->ID . "\n"; return; }
  $id = wp_insert_post( array(
    'post_type'    => 'post',
    'post_status'  => base64_decode( '${phpQuote(options.status ?? "publish")}' ),
    'post_author'  => 1,
    'post_title'   => wp_slash( base64_decode( '${phpQuote(header.title)}' ) ),
    'post_name'    => $slug,
    'post_content' => $body,
    'post_excerpt' => wp_slash( base64_decode( '${phpQuote(header.metaDescription)}' ) ),
  ), true );
  $created = 1;
}
if ( is_wp_error( $id ) ) { echo "ABORT=" . $id->get_error_code() . "\nmessage=" . $id->get_error_message() . "\n"; return; }
$id = (int) $id;

$mt = base64_decode( '${phpQuote(header.metaTitle)}' );
$md = base64_decode( '${phpQuote(header.metaDescription)}' );
if ( $mt ) { update_post_meta( $id, '_genesis_title', $mt ); }
if ( $md ) { update_post_meta( $id, '_genesis_description', $md ); }
${thumbnailId ? `update_post_meta( $id, '_thumbnail_id', ${thumbnailId} );` : ""}

$cat = base64_decode( '${phpQuote(header.category)}' );
if ( $cat ) {
  $t = get_term_by( 'name', $cat, 'category' );
  if ( $t ) { wp_set_post_categories( $id, array( (int) $t->term_id ) ); }
  else { echo "warn_category=" . $cat . "\n"; }
}

$tags = json_decode( base64_decode( '${phpQuote(JSON.stringify(header.tags))}' ), true );
$assign = array(); $missing = array();
foreach ( (array) $tags as $tag ) {
  $t = get_term_by( 'name', $tag, 'post_tag' );
  if ( ! $t ) { $t = get_term_by( 'slug', sanitize_title( $tag ), 'post_tag' ); }
  if ( $t ) { $assign[] = $t->name; } else { $missing[] = $tag; }
}
if ( $assign ) { wp_set_post_terms( $id, $assign, 'post_tag', false ); }
if ( $missing ) { echo "warn_tags=" . implode( ',', $missing ) . "\n"; }

$saved = get_post( $id );
echo "id=" . $id . "\n";
echo "created=" . $created . "\n";
echo "status=" . $saved->post_status . "\n";
echo "permalink=" . get_permalink( $id ) . "\n";
echo "stored_bytes=" . strlen( $saved->post_content ) . "\n";
echo "stored_ldjson=" . substr_count( $saved->post_content, 'application/ld+json' ) . "\n";
echo "stored_scripts=" . substr_count( $saved->post_content, '<script' ) . "\n";
`.trim();

  const res = await runWpCliRaw(entry, ["eval", worker]);
  if (res.code !== 0) {
    throw new Error(`WP-CLI could not write the post (exit ${res.code}): ${res.stderr || res.stdout}`);
  }

  const kv: Record<string, string> = {};
  for (const line of res.stdout.split("\n")) {
    const i = line.indexOf("=");
    if (i > 0) kv[line.slice(0, i).trim()] = line.slice(i + 1).trim();
  }

  if (kv.ABORT) {
    if (kv.ABORT === "duplicate-slug") {
      throw new Error(`A post with slug "${header.slug}" already exists (ID ${kv.existing}). Pass updateId to overwrite it.`);
    }
    if (kv.ABORT === "transit-length") {
      throw new Error("Body length changed in transit — refusing to write a corrupted post.");
    }
    throw new Error(`Publish aborted: ${kv.ABORT}${kv.message ? ` — ${kv.message}` : ""}`);
  }

  if (kv.warn_slug) {
    warnings.push(
      `Slug in draft ("${header.slug}") differs from the post's slug ("${kv.warn_slug}") — ` +
        `left unchanged, since rewriting it would break the live URL. Change it in WordPress and add a redirect if intended.`
    );
  }
  if (kv.warn_category) warnings.push(`Category "${kv.warn_category}" does not exist — post left uncategorized`);
  if (kv.warn_tags) warnings.push(`Tag(s) not found and NOT created: ${kv.warn_tags}`);

  const storedBytes = Number(kv.stored_bytes ?? 0);
  const storedLdJson = Number(kv.stored_ldjson ?? 0);
  const storedScripts = Number(kv.stored_scripts ?? 0);

  // The verification this tool exists for.
  if (storedBytes !== sourceBytes) {
    warnings.push(`VERIFY FAILED: stored ${storedBytes} bytes but source was ${sourceBytes} — content altered on write`);
  } else if (storedLdJson !== sourceLdJson || storedScripts !== sourceScripts) {
    warnings.push(
      `VERIFY FAILED: script/JSON-LD blocks stripped (stored ${storedLdJson}/${storedScripts}, ` +
        `source ${sourceLdJson}/${sourceScripts}) — kses?`
    );
  }

  return {
    postId: Number(kv.id),
    permalink: kv.permalink ?? "",
    created: kv.created === "1",
    status: kv.status ?? "",
    sourceBytes,
    storedBytes,
    sourceLdJson,
    storedLdJson,
    thumbnailId,
    imageUrl,
    warnings,
    verified: storedBytes === sourceBytes && storedLdJson === sourceLdJson && storedScripts === sourceScripts,
  };
}

export function formatPublishPost(r: PublishPostResult): string {
  const lines: string[] = [];
  if (r.status === "dry-run") {
    lines.push("Dry run — no changes made.");
    lines.push(`Body: ${r.sourceBytes} bytes, ${r.sourceLdJson} JSON-LD block(s)`);
  } else {
    lines.push(`${r.created ? "Created" : "Updated"} post ${r.postId} (${r.status})`);
    lines.push(r.permalink);
    lines.push("");
    lines.push(`Stored ${r.storedBytes} bytes (source ${r.sourceBytes}), JSON-LD ${r.storedLdJson}/${r.sourceLdJson}`);
    if (r.thumbnailId) lines.push(`Featured image: attachment ${r.thumbnailId}${r.imageUrl ? ` — ${r.imageUrl}` : ""}`);
    lines.push("");
    lines.push(r.verified ? "VERIFIED: content stored intact." : "VERIFICATION FAILED — see warnings.");
  }
  if (r.warnings.length) {
    lines.push("");
    lines.push("Warnings:");
    for (const w of r.warnings) lines.push(`  - ${w}`);
  }
  return lines.join("\n");
}
