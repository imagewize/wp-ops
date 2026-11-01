import { test } from "node:test";
import assert from "node:assert/strict";
import {
  buildRemoteCommand,
  isReadOnlySshCommand,
  tokenizeCommand,
} from "../src/tools/sshPassthrough.js";

const readOnly = (cmd: string) => isReadOnlySshCommand(cmd);

test("simple allowlisted commands are read-only", () => {
  assert.equal(readOnly("ls -la /srv/www"), true);
  assert.equal(readOnly("wc -l file"), true);
  assert.equal(readOnly("rm -rf /"), false);
  assert.equal(readOnly(""), false);
});

test("find is read-only unless it carries mutating primaries", () => {
  assert.equal(readOnly("find /home/web -mtime +90"), true);
  for (const bad of ["-delete", "-exec", "-execdir", "-ok", "-okdir", "-fprint", "-fls"]) {
    assert.equal(readOnly(`find /home/web ${bad} x`), false, bad);
  }
});

test("awk allows plain programs and -F/-v only", () => {
  assert.equal(readOnly("awk '{print $1}' file"), true);
  assert.equal(readOnly("awk -F'|' '{print $1}' file"), true);
  assert.equal(readOnly("awk -v x=1 '{print x}' file"), true);
  assert.equal(readOnly("awk '{system(\"id\")}' file"), false);
  assert.equal(readOnly("awk '{print > \"out\"}' file"), false);
  assert.equal(readOnly("awk '{print | \"sh\"}' file"), false);
  assert.equal(readOnly("awk '{getline}' file"), false);
});

test("awk refuses file-writing and code-loading options", () => {
  for (const opt of ["-i inplace", "-o out", "--profile=out", "-f prog.awk", "-l ext", "-E prog.awk", "--include x"]) {
    assert.equal(readOnly(`awk ${opt} '{print}' file`), false, opt);
  }
});

test("pipelines need every segment read-only", () => {
  assert.equal(readOnly("find /home/web -mtime +90 | wc -l"), true);
  assert.equal(readOnly("cat a | grep b | wc -l"), true);
  assert.equal(readOnly("find /x -delete | wc -l"), false);
  assert.equal(readOnly("cat a | sh"), false);
});

test("malformed pipelines are rejected", () => {
  assert.equal(readOnly("| wc -l"), false);
  assert.equal(readOnly("cat a |"), false);
  assert.equal(readOnly("cat a | | wc"), false);
});

test("quoted or glued pipes are literal arguments", () => {
  assert.equal(readOnly("grep 'a|b' file"), true);
  assert.equal(readOnly("ls|wc"), false);
  assert.ok(tokenizeCommand("grep 'a|b' file").every((t) => !t.isPipe));
  assert.ok(tokenizeCommand("grep \"|\" file").every((t) => !t.isPipe));
  assert.ok(tokenizeCommand("grep \\| file").every((t) => !t.isPipe));
});

test("buildRemoteCommand passes only real pipes through unquoted", () => {
  const piped = buildRemoteCommand(tokenizeCommand("cat a | wc -l"));
  assert.match(piped, / \| /);
  const quoted = buildRemoteCommand(tokenizeCommand("echo '|'"));
  assert.doesNotMatch(quoted, /(^| )\|( |$)/);
});

test("credential paths still require confirmation inside a pipeline", () => {
  assert.equal(readOnly("cat .env | wc -l"), false);
});
