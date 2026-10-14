import { test } from "node:test";
import assert from "node:assert/strict";
import { doingWord } from "./act-words.ts";

/* a page's window, enough for lib/activity: its address, fetch and listeners (window.event is the event being handled) */
type Listener = (e: unknown) => void;
const added: Record<string, Listener[]> = {};
const waiting: ((r: Response) => void)[] = [];
/** the server answers the oldest request still waiting */
const answer = (r: Response = new Response("{}")) => waiting.shift()?.(r);
const page = {
  location: { href: "https://portal.example/finance/fees", origin: "https://portal.example", pathname: "/finance/fees" },
  event: undefined as unknown,
  fetch: (() => new Promise<Response>((resolve) => { waiting.push(resolve); })) as typeof fetch,
  addEventListener: (type: string, l: Listener) => { (added[type] ??= []).push(l); },
};
(globalThis as unknown as { window: typeof page }).window = page;
const activity = await import("./activity.ts");

test("a busy button reads the act under way in its own word", () => {
  assert.equal(doingWord("Save changes"), "Saving…");
  assert.equal(doingWord("Approve"), "Approving…");
  assert.equal(doingWord("Sign out"), "Signing out…");
  assert.equal(doingWord("Sign in"), "Signing in…");
  assert.equal(doingWord("Turn off the window"), "Turning off…");
  assert.equal(doingWord("Set up"), "Saving…");
  assert.equal(doingWord("Export CSV"), "Preparing CSV…");
  assert.equal(doingWord("Upload the filled sheet"), "Uploading…");
  assert.equal(doingWord("Submit for approval"), "Submitting…");
  // the thing acted on is kept where it says more: exports, payments, the examination, results
  assert.equal(doingWord("Export PDF"), "Preparing PDF…");
  assert.equal(doingWord("Export to Excel"), "Preparing Excel…");
  assert.equal(doingWord("Pay now"), "Initiating payment…");
  assert.equal(doingWord("Verify payment"), "Verifying payment…");
  assert.equal(doingWord("Start exam"), "Starting exam…");
  assert.equal(doingWord("Publish results"), "Publishing results…");
  assert.equal(doingWord("Look it up"), "Looking…");
  // "Signup" is not "Sign up"; a word the list does not know keeps the label
  assert.equal(doingWord("Signup"), null);
  assert.equal(doingWord("Next"), null);
  assert.equal(doingWord("  "), null);
});

test("only the requests the person waits for are watched", () => {
  assert.equal(activity.watched("/api/bff/api/v1/finance/fees"), true);
  assert.equal(activity.watched("/api/auth/sign-out", { method: "POST" }), true);
  assert.equal(activity.watched("/finance/fees?_rsc=abc", { headers: { RSC: "1" } }), true);
  // a background poll, a router prefetch, a beacon, the framework's own files, another site
  assert.equal(activity.watched("/api/bff/api/v1/helpdesk/counts", { headers: { "X-Background": "1" } }), false);
  assert.equal(activity.watched("/api/bff/api/v1/x", { headers: new Headers({ "x-background": "1" }) }), false);
  assert.equal(activity.watched("/finance?_rsc=1", { headers: [["Next-Router-Prefetch", "1"]] }), false);
  assert.equal(activity.watched("/finance?_rsc=1", { headers: { "next-router-segment-prefetch": "/_tree" } }), false);
  assert.equal(activity.watched("/api/bff/api/v1/x", { method: "POST", keepalive: true }), false);
  assert.equal(activity.watched("/_next/static/chunks/main.js"), false);
  assert.equal(activity.watched("https://webpay.interswitchng.com/pay"), false);
});

test("the examination room is never shown as loading", () => {
  assert.equal(activity.quietPath("/student/cbt/room/123"), true);
  assert.equal(activity.quietPath("/post-utme/cbt/room/9"), true);
  assert.equal(activity.quietPath("/student/cbt"), false);
  page.location.pathname = "/student/cbt/room/123";
  assert.equal(activity.watched("/api/bff/api/v1/cbt/attempts/1/answers", { method: "PUT" }), false);
  page.location.pathname = "/finance/fees";
});

test("a request is counted from the moment it is sent until it settles, not on a timer", async () => {
  activity.installActivity();
  let heard = 0;
  const off = activity.subscribe(() => { heard++; });
  assert.equal(activity.inFlight(), 0);
  const p = window.fetch("/api/bff/api/v1/finance/fees", { method: "POST" });
  assert.equal(activity.inFlight(), 1);
  assert.ok(heard >= 1);
  // a background poll in the meantime is not counted
  const bg = window.fetch("/api/bff/api/v1/helpdesk/counts", { headers: { "X-Background": "1" } });
  assert.equal(activity.inFlight(), 1);
  answer();
  await p;
  await Promise.resolve();
  assert.equal(activity.inFlight(), 0);
  answer();
  await bg;
  off();
  // the guard against a second click and a second submission is in place
  assert.equal(added.click?.length, 1);
  assert.equal(added.submit?.length, 1);
});

test("a navigation is under way until the next screen's content has all come, not only its headers", async () => {
  activity.installActivity();
  let push: ReadableStreamDefaultController<Uint8Array> | null = null;
  const body = new ReadableStream<Uint8Array>({ start(c) { push = c; } });
  const p = window.fetch("/finance/held-scripts?_rsc=x", { headers: { RSC: "1" } });
  answer(new Response(body));
  const res = await p;
  await new Promise((r) => setImmediate(r));
  assert.equal(activity.inFlight(), 1, "the headers have come, the content has not");
  push!.enqueue(new TextEncoder().encode("0:[\"$\",\"div\"]"));
  push!.close();
  await res.text();
  await new Promise((r) => setImmediate(r));
  assert.equal(activity.inFlight(), 0, "the content has all come");
});

test("the shown screen is stale only while the next one is on its way, never during an act", async () => {
  activity.installActivity();
  // an act: its button is busy, the screen is not stale
  const act = window.fetch("/api/bff/api/v1/finance/fees", { method: "POST" });
  assert.equal(activity.inFlight(), 1);
  assert.equal(activity.screensInFlight(), 0);
  answer();
  await act;
  await Promise.resolve();
  // a filter or a page of a list: the router fetches the next screen; stale until its content has all come
  let push: ReadableStreamDefaultController<Uint8Array> | null = null;
  const body = new ReadableStream<Uint8Array>({ start(c) { push = c; } });
  const nav = window.fetch("/finance/payments?level=800&_rsc=y", { headers: { RSC: "1" } });
  assert.equal(activity.screensInFlight(), 1);
  answer(new Response(body));
  const res = await nav;
  await new Promise((r) => setImmediate(r));
  assert.equal(activity.screensInFlight(), 1, "the headers have come, the rows have not");
  push!.enqueue(new TextEncoder().encode("0:[]"));
  push!.close();
  await res.text();
  await new Promise((r) => setImmediate(r));
  assert.equal(activity.screensInFlight(), 0);
  // a prefetch is never a screen on its way
  const pre = window.fetch("/finance/payments?_rsc=z", { headers: { RSC: "1", "Next-Router-Prefetch": "1" } });
  assert.equal(activity.screensInFlight(), 0);
  answer();
  await pre;
});
