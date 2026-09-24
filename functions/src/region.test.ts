import assert from "node:assert/strict";
import { test } from "node:test";

test("every function runs in London (europe-west2)", async () => {
  process.env.GCLOUD_PROJECT ??= "demo-ratio";
  const functions = (await import("./index.js")) as Record<string, { __endpoint?: { region?: string[] } }>;
  const endpoints = Object.entries(functions).filter(([, f]) => f?.__endpoint);
  assert.ok(endpoints.length > 20);
  for (const [name, f] of endpoints) assert.deepEqual(f.__endpoint!.region, ["europe-west2"], name);
});
