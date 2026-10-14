import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync, existsSync } from "node:fs";
import manifest from "../src/app/manifest.ts";

const sw = readFileSync(new URL("../public/sw.js", import.meta.url), "utf8");

test("manifest is installable: name, standalone, start url and icons that exist on disk", () => {
  const m = manifest();
  assert.equal(m.display, "standalone");
  assert.equal(m.start_url, "/dashboard");
  const sizes = (m.icons ?? []).map((i) => i.sizes);
  assert.ok(sizes.includes("192x192") && sizes.includes("512x512"));
  assert.ok((m.icons ?? []).some((i) => i.purpose === "maskable"));
  for (const i of m.icons ?? []) assert.ok(existsSync(new URL(`../public${i.src}`, import.meta.url)), `${i.src} missing`);
});

test("service worker never handles writes and never caches pages or data", () => {
  assert.match(sw, /req\.method !== "GET"\) return/);
  assert.doesNotMatch(sw, /cache\.put\([^)]*navigate/);
  // only static build output and icons are ever stored
  const puts = sw.match(/c\.put\(/g) ?? [];
  assert.equal(puts.length, 1);
  assert.match(sw, /_next\/static\//);
});

test("the offline screen is a static file with no user data", () => {
  const html = readFileSync(new URL("../public/offline.html", import.meta.url), "utf8");
  assert.match(html, /You are offline/);
  assert.match(sw, /offline\.html/);
});
