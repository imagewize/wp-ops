import { test } from "node:test";
import assert from "node:assert/strict";
import { siteurlCoveredByHome } from "../src/tools/dbPull.js";

test("Bedrock siteurl (home + /wp on both ends) is covered by the home pass", () => {
  assert.equal(
    siteurlCoveredByHome("https://example.com/wp", "https://example.com", "http://example.test/wp", "http://example.test"),
    true
  );
});

test("siteurl equal to home on both ends is covered", () => {
  assert.equal(siteurlCoveredByHome("https://example.com", "https://example.com", "http://example.test", "http://example.test"), true);
});

test("a suffix on one end only needs its own siteurl pass", () => {
  assert.equal(siteurlCoveredByHome("https://example.com/wp", "https://example.com", "http://example.test", "http://example.test"), false);
});

test("siteurl on a different host than home needs its own pass", () => {
  assert.equal(
    siteurlCoveredByHome("https://cms.example.com", "https://example.com", "http://cms.example.test", "http://example.test"),
    false
  );
});
