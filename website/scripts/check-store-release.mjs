// Run with: node scripts/check-store-release.mjs
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import vm from "node:vm";
import ts from "typescript";

function load(relativePath, context = {}) {
  const source = fs.readFileSync(path.join(import.meta.dirname, "..", relativePath), "utf8");
  const { outputText } = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS },
  });
  const exports = {};
  vm.runInNewContext(outputText, { exports, ...context });
  return exports;
}

(async () => {
  const { site } = load("src/content/site.ts");
  let requests = 0;
  const store = load("src/lib/app-store.ts", {
    require: () => ({ site }),
    fetch: async () => { requests++; throw new Error("Offline"); },
  });
  assert.equal(await store.getAppStoreUrl(), "https://apps.apple.com/app/headroom-ai-usage-meter/id6815808010");
  assert.equal(await store.isVersionLive("1.1.0"), true);
  assert.equal(await store.isVersionLive("1.0.0"), true);
  assert.equal(await store.isVersionLive(store.refreshVersion), true, "1.1.1 is a confirmed release");
  assert.equal(requests, 0, "A confirmed release must not depend on Apple's lookup service");
  assert.equal(await store.isVersionLive(store.seenVersion), false, "1.1.2 stays in review until the lookup says so");
  assert.equal(requests, 1, "An unconfirmed release uses Apple's lookup service");
  assert.equal(await store.isVersionLive("2.0.0"), false);
  assert.equal(requests, 2, "An unconfirmed future release still uses Apple's lookup service");
  assert.equal(store.compareVersions("1.10.0", "1.9.2"), 1);
  console.log("Store release checks passed, including offline availability.");
})().catch((error) => { console.error(error); process.exitCode = 1; });
