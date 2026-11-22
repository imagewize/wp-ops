import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { existsSync, readFileSync, unlinkSync } from "node:fs";
import { randomBytes } from "node:crypto";
import { tmpdir } from "node:os";
import { IMAGE_CHUNK_BYTES, imageStagingSnippets } from "../src/tools/publishPost.js";

// Linux caps a single argv token at 128KB (MAX_ARG_STRLEN); a ~99KB JPEG encoded
// as one token overflowed it ("Argument list too long").
const MAX_ARG_STRLEN = 128 * 1024;

test("a small image stages in one snippet", () => {
  assert.equal(imageStagingSnippets(randomBytes(1000), "a.jpg").length, 1);
});

test("a 99KB image (the one that failed) is split and every snippet fits one argv token", () => {
  const snippets = imageStagingSnippets(randomBytes(99123), "a.jpg");
  assert.ok(snippets.length > 1);
  for (const s of snippets) assert.ok(s.length < MAX_ARG_STRLEN, `snippet is ${s.length} chars`);
});

test("a multi-megabyte image still keeps every snippet under the cap", () => {
  const snippets = imageStagingSnippets(randomBytes(IMAGE_CHUNK_BYTES * 20 + 7), "a.jpg");
  assert.equal(snippets.length, 21);
  for (const s of snippets) assert.ok(s.length < MAX_ARG_STRLEN);
});

test("running the snippets in order reproduces the file byte for byte", () => {
  const name = `wp-ops-staging-test-${process.pid}.bin`;
  const bytes = randomBytes(IMAGE_CHUNK_BYTES * 2 + 123);
  const target = `${tmpdir()}/${name}`;
  try {
    let out = "";
    for (const s of imageStagingSnippets(bytes, name)) {
      out = execFileSync("php", ["-r", s.replace("sys_get_temp_dir()", `'${tmpdir()}'`)], {
        encoding: "utf8",
      });
    }
    assert.equal(out, `${target}|${bytes.length}`);
    assert.ok(readFileSync(target).equals(bytes));
  } finally {
    if (existsSync(target)) unlinkSync(target);
  }
});

test("re-staging the same name truncates rather than appends to a stale file", () => {
  const name = `wp-ops-staging-test-stale-${process.pid}.bin`;
  const target = `${tmpdir()}/${name}`;
  const run = (b: Buffer) => {
    for (const s of imageStagingSnippets(b, name)) {
      execFileSync("php", ["-r", s.replace("sys_get_temp_dir()", `'${tmpdir()}'`)]);
    }
  };
  try {
    run(randomBytes(IMAGE_CHUNK_BYTES + 500));
    const second = randomBytes(300);
    run(second);
    assert.ok(readFileSync(target).equals(second));
  } finally {
    if (existsSync(target)) unlinkSync(target);
  }
});
