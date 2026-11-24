import { test } from "node:test";
import assert from "node:assert/strict";
import { bffResponseHeaders, forbidsStore, scriptRead } from "./bff-headers.ts";

const reply = (h: Record<string, string>) => bffResponseHeaders(new Headers(h));

test("a no-store reply reaches the browser as the API set it, with nosniff (V749)", () => {
  // a staff identity photograph: never kept by the browser, never read as anything but an image
  assert.deepEqual(reply({ "content-type": "image/jpeg", "cache-control": "no-store, private", "x-content-type-options": "nosniff" }), [
    ["content-type", "image/jpeg"], ["x-content-type-options", "nosniff"], ["cache-control", "no-store, private"],
  ]);
  // Spring Security's default on a JSON reply
  assert.deepEqual(reply({ "content-type": "application/json", "cache-control": "no-cache, no-store, max-age=0, must-revalidate" }), [
    ["content-type", "application/json"], ["cache-control", "no-cache, no-store, max-age=0, must-revalidate"],
  ]);
});

test("any other caching word is dropped as before, so a replaced photograph is never shown stale (V749)", () => {
  // a student's passport and an HR staff photograph: private, max-age=600 — dropped; nosniff still passed
  assert.deepEqual(reply({ "content-type": "image/jpeg", "cache-control": "private, max-age=600", "x-content-type-options": "nosniff" }), [
    ["content-type", "image/jpeg"], ["x-content-type-options", "nosniff"],
  ]);
  // a candidate's photograph: max-age=3600 — dropped
  assert.deepEqual(reply({ "content-type": "image/png", "cache-control": "max-age=3600" }), [["content-type", "image/png"]]);
  // no-cache alone is not no-store
  assert.deepEqual(reply({ "cache-control": "no-cache" }), []);
});

test("only the headers the BFF passes, each as the API set it", () => {
  assert.deepEqual(reply({
    "content-type": "application/json", "x-correlation-id": "c-1", location: "/api/v1/x/1", "set-cookie": "a=b", "x-powered-by": "x", etag: "\"1\"",
  }), [["content-type", "application/json"], ["x-correlation-id", "c-1"], ["location", "/api/v1/x/1"]]);
  assert.deepEqual(reply({}), []);
});

test("no-store is read as a directive, in any case and spacing, never as part of another word", () => {
  assert.equal(forbidsStore("no-store"), true);
  assert.equal(forbidsStore("private,NO-STORE"), true);
  assert.equal(forbidsStore("  No-Store  , max-age=0"), true);
  assert.equal(forbidsStore("private, max-age=600"), false);
  assert.equal(forbidsStore("no-cache"), false);
  assert.equal(forbidsStore("x-no-store-later=1"), false);
  assert.equal(forbidsStore(""), false);
  assert.equal(forbidsStore(null), false);
  assert.equal(forbidsStore(undefined), false);
});

test("a download's file name reaches a page's own script, never a link the browser opens itself (V779)", () => {
  const csv = { "content-type": "text/csv; charset=utf-8", "content-disposition": 'attachment; filename="summer-2025-2026-selections.csv"', "cache-control": "no-store" };
  const asked = (h: Record<string, string>) => bffResponseHeaders(new Headers(csv), new Headers(h));
  // fetch() from the Summer desk (saveFile): Sec-Fetch-Mode cors (same-origin is the other mode a script's read carries)
  assert.deepEqual(asked({ "sec-fetch-mode": "cors", "sec-fetch-dest": "empty" }), [
    ["content-type", "text/csv; charset=utf-8"], ["cache-control", "no-store"], ["content-disposition", 'attachment; filename="summer-2025-2026-selections.csv"'],
  ]);
  assert.ok(asked({ "sec-fetch-mode": "same-origin" }).some(([k]) => k === "content-disposition"));
  // a document opened in a new tab, an <a download>, an image, an embedded frame: as before, no disposition, so each opens or saves as it always has
  for (const mode of ["navigate", "no-cors", "websocket", ""]) {
    assert.ok(!asked({ "sec-fetch-mode": mode }).some(([k]) => k === "content-disposition"), mode || "(no Fetch Metadata)");
  }
  assert.ok(!bffResponseHeaders(new Headers(csv)).some(([k]) => k === "content-disposition"), "no request given: as before");
  assert.equal(scriptRead(new Headers({ "sec-fetch-mode": " CORS " })), true);
  assert.equal(scriptRead(null), false);
});
