import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const index = readFileSync("www/index.html", "utf8");
const js = readFileSync("www/assets/waitlist.js", "utf8");
const config = readFileSync("www/assets/waitlist-config.js", "utf8");
const gas = readFileSync("apps-script/Code.gs", "utf8");

test("waitlist assets use static-root-relative paths", () => {
  assert.match(index, /src="assets\/waitlist-config\.js"/);
  assert.match(index, /src="assets\/waitlist\.js"/);
  assert.doesNotMatch(index, /\/www\/assets/);
});

test("waitlist frontend posts to configurable endpoint without CORS dependency", () => {
  assert.match(config, /REVIEWNUDGE_WAITLIST_ENDPOINT/);
  assert.match(js, /mode:\s*"no-cors"/);
  assert.match(js, /source:\s*"reviewnudge-coming-soon"/);
});

test("apps script writes expected waitlist columns", () => {
  for (const column of ["received_at", "email", "source", "page", "referrer", "user_agent", "submitted_at_client"]) {
    assert.match(gas, new RegExp(column));
  }
});
