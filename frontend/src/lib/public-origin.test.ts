import { after, test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { configuredOrigin, publicOrigin, publicOriginOf } from "./public-origin.ts";

/** a request as Next hands it to a route on AWS: its own URL names the task's private address and port */
const INTERNAL = "https://ip-10-20-41-127.us-east-2.compute.internal:3000/applicant/status/letter?print=1";
const req = (h: Record<string, string>, url = INTERNAL) => new Request(url, { headers: h });

// the header rule's tests run as on a server with no configured address, whatever the shell running them has set
const SHELL_PORTAL_URL = process.env.MOAUM_PORTAL_URL;
delete process.env.MOAUM_PORTAL_URL;
/** a test run with MOAUM_PORTAL_URL set to a value (or unset for undefined), put back as it was afterwards */
function withPortalUrl(v: string | undefined, f: () => void) {
  const before = process.env.MOAUM_PORTAL_URL;
  if (v === undefined) delete process.env.MOAUM_PORTAL_URL; else process.env.MOAUM_PORTAL_URL = v;
  try { f(); } finally { if (before === undefined) delete process.env.MOAUM_PORTAL_URL; else process.env.MOAUM_PORTAL_URL = before; }
}

test("a configured MOAUM_PORTAL_URL is the address, whatever the request's headers or its own URL say", () => {
  const railway = req({ "x-forwarded-host": "moaum-portal-production.up.railway.app", "x-forwarded-proto": "https" });
  // CloudFront forwarding its origin's name as Host, never the viewer's: the configured address still prints
  const cloudfront = req({ host: "moaumpp-prod-123.us-east-2.elb.amazonaws.com", "x-forwarded-proto": "https" });
  for (const [v, want] of [
    ["https://portal.moaum.edu.ng", "https://portal.moaum.edu.ng"],
    ["https://portal.moaum.edu.ng/", "https://portal.moaum.edu.ng"],
    ["  https://Portal.MOAUM.edu.ng:443/\n", "https://portal.moaum.edu.ng"],
    ["https://portal.moaum.edu.ng:8443", "https://portal.moaum.edu.ng:8443"],
    ["http://localhost:3000", "http://localhost:3000"],
    ["http://[::1]:3000", "http://[::1]:3000"],
  ]) {
    withPortalUrl(v, () => {
      assert.equal(configuredOrigin(), want, JSON.stringify(v));
      assert.equal(publicOrigin(railway), want, `${JSON.stringify(v)} over the forwarded host`);
      assert.equal(publicOrigin(cloudfront), want, `${JSON.stringify(v)} over the load balancer's name`);
      assert.equal(publicOrigin(req({})), want, `${JSON.stringify(v)} over the task's own address`);
      assert.equal(publicOriginOf(new Headers(), "https://fallback.example"), want, `${JSON.stringify(v)} over the fallback`);
    });
  }
  // read when the address is asked for, not once: a change of the variable is seen by the next document
  withPortalUrl("https://one.example", () => assert.equal(publicOrigin(railway), "https://one.example"));
  withPortalUrl("https://two.example", () => assert.equal(publicOrigin(railway), "https://two.example"));
});

test("MOAUM_PORTAL_URL unset or blank: the request's headers, as before", () => {
  for (const v of [undefined, "", "   "]) {
    withPortalUrl(v, () => {
      assert.equal(configuredOrigin(), null, JSON.stringify(v));
      assert.equal(publicOrigin(req({ "x-forwarded-host": "portal.moaum.edu.ng", "x-forwarded-proto": "https" })), "https://portal.moaum.edu.ng");
      assert.equal(publicOrigin(req({})), "https://ip-10-20-41-127.us-east-2.compute.internal:3000");
      assert.equal(publicOriginOf(new Headers()), "");
    });
  }
});

test("a malformed MOAUM_PORTAL_URL is ignored, as if unset: a path, a query, a user, no scheme, another scheme, a bad port", () => {
  const forwarded = req({ "x-forwarded-host": "portal.moaum.edu.ng", "x-forwarded-proto": "https" });
  for (const bad of [
    "portal.moaum.edu.ng", "//portal.moaum.edu.ng", "http//portal.moaum.edu.ng", "https://", "https:///portal", "ftp://portal.moaum.edu.ng",
    "javascript:alert(1)", "https://portal.moaum.edu.ng/portal", "https://portal.moaum.edu.ng//", "https://portal.moaum.edu.ng/verify/document",
    "https://portal.moaum.edu.ng?x=1", "https://portal.moaum.edu.ng/?", "https://portal.moaum.edu.ng#top", "https://user:pw@portal.moaum.edu.ng",
    "https://user@portal.moaum.edu.ng", "https:\\\\portal.moaum.edu.ng", "https://portal moaum.edu.ng", "https://portal.moaum.edu.ng:0",
    "https://portal.moaum.edu.ng:65536", "https://portal.moaum.edu.ng:x", "https://-portal.moaum.edu.ng", "https://portal..moaum.edu.ng",
    "https://portal.moaum.edu.ng, https://other.example", "<https://portal.moaum.edu.ng>",
  ]) {
    withPortalUrl(bad, () => {
      assert.equal(configuredOrigin(), null, JSON.stringify(bad));
      assert.equal(publicOrigin(forwarded), "https://portal.moaum.edu.ng", `${JSON.stringify(bad)}: the headers' rule`);
      assert.equal(publicOrigin(req({})), "https://ip-10-20-41-127.us-east-2.compute.internal:3000", `${JSON.stringify(bad)}: the request's own`);
    });
  }
  // the value as given, not the environment, when one is passed
  assert.equal(configuredOrigin("https://portal.moaum.edu.ng/"), "https://portal.moaum.edu.ng");
  assert.equal(configuredOrigin("https://portal.moaum.edu.ng/x"), null);
});

after(() => { if (SHELL_PORTAL_URL !== undefined) process.env.MOAUM_PORTAL_URL = SHELL_PORTAL_URL; });

test("behind the load balancer the letter's address is the one the person opened, never the task's own", () => {
  // the ALB keeps the Host the browser sent and says https; Next adds X-Forwarded-Host from it
  assert.equal(publicOrigin(req({ host: "portal.moaum.edu.ng", "x-forwarded-proto": "https" })), "https://portal.moaum.edu.ng");
  assert.equal(publicOrigin(req({ "x-forwarded-host": "portal.moaum.edu.ng", host: "ip-10-20-41-127.us-east-2.compute.internal:3000", "x-forwarded-proto": "https" })), "https://portal.moaum.edu.ng");
  // Railway: its own domain forwarded
  assert.equal(publicOrigin(req({ "x-forwarded-host": "moaum-portal-production.up.railway.app", "x-forwarded-proto": "https" }, "http://[::]:8080/x")), "https://moaum-portal-production.up.railway.app");
});

test("a host alone is served over https unless the proxy says http; a development server keeps its own address", () => {
  assert.equal(publicOrigin(req({ host: "portal.moaum.edu.ng" })), "https://portal.moaum.edu.ng");
  assert.equal(publicOrigin(req({ host: "localhost:3000", "x-forwarded-proto": "http" }, "http://localhost:3000/x")), "http://localhost:3000");
  assert.equal(publicOrigin(req({ host: "127.0.0.1:3000", "x-forwarded-proto": "http" }, "http://127.0.0.1:3000/x")), "http://127.0.0.1:3000");
  assert.equal(publicOrigin(req({ host: "[::1]:3000", "x-forwarded-proto": "http" }, "http://[::1]:3000/x")), "http://[::1]:3000");
  // the scheme's own port is dropped, as a browser writes the address; a name is written in lower case
  assert.equal(publicOrigin(req({ host: "Portal.MOAUM.edu.ng:443", "x-forwarded-proto": "https" })), "https://portal.moaum.edu.ng");
  assert.equal(publicOrigin(req({ host: "portal.moaum.edu.ng:8443", "x-forwarded-proto": "https" })), "https://portal.moaum.edu.ng:8443");
  // a scheme that is neither http nor https is not believed
  assert.equal(publicOrigin(req({ host: "portal.moaum.edu.ng", "x-forwarded-proto": "javascript" })), "https://portal.moaum.edu.ng");
  assert.equal(publicOrigin(req({ host: "portal.moaum.edu.ng", "x-forwarded-proto": "HTTPS" })), "https://portal.moaum.edu.ng");
});

test("a chain of proxies' comma-separated values: the first, the one the person reached", () => {
  assert.equal(publicOrigin(req({ "x-forwarded-host": "portal.moaum.edu.ng, moaumpp-prod-123.us-east-2.elb.amazonaws.com", "x-forwarded-proto": "https,http" })), "https://portal.moaum.edu.ng");
  assert.equal(publicOrigin(req({ "x-forwarded-host": "  portal.moaum.edu.ng ,other", "x-forwarded-proto": " http , https" })), "http://portal.moaum.edu.ng");
});

test("no header names a host: the request's own origin, or nothing at all from headers alone", () => {
  assert.equal(publicOrigin(req({})), "https://ip-10-20-41-127.us-east-2.compute.internal:3000");
  assert.equal(publicOrigin(req({ "x-forwarded-host": "", host: " , " })), "https://ip-10-20-41-127.us-east-2.compute.internal:3000");
  assert.equal(publicOriginOf(new Headers()), "");
  assert.equal(publicOriginOf(new Headers({ "x-forwarded-proto": "https" }), "https://fallback.example"), "https://fallback.example");
  assert.equal(publicOriginOf(new Headers({ host: "portal.moaum.edu.ng", "x-forwarded-proto": "https" })), "https://portal.moaum.edu.ng");
});

test("a hostile or malformed host is passed over, never printed: a path, a user, a query, whitespace, a bad port", () => {
  const fallback = "https://ip-10-20-41-127.us-east-2.compute.internal:3000";
  for (const bad of [
    "evil.example/verify", "evil.example/", "user@evil.example", "evil.example?x=1", "evil.example#x", "evil example", "evil.example\tx",
    "evil.example:0", "evil.example:65536", "evil.example:", "evil.example:80x", ":443", "-evil.example", "evil-.example", "evil..example",
    "evil.example.", "[::1", "[zz::1]", "[:::]", "évil.example", "<script>", "https://evil.example", "a".repeat(64) + ".example",
  ]) {
    assert.equal(publicOrigin(req({ "x-forwarded-host": bad, "x-forwarded-proto": "https" })), fallback, `x-forwarded-host ${JSON.stringify(bad)}`);
    assert.equal(publicOriginOf(new Headers({ host: bad })), "", `host ${JSON.stringify(bad)}`);
  }
  // a hostile X-Forwarded-Host gives way to a good Host, not to the request's own URL
  assert.equal(publicOrigin(req({ "x-forwarded-host": "evil.example/path", host: "portal.moaum.edu.ng", "x-forwarded-proto": "https" })), "https://portal.moaum.edu.ng");
  // a long but valid name stays itself: what fits the page is the letter's business (admission-letter-pdf)
  const long = `${"a".repeat(63)}.${"b".repeat(63)}.example`;
  assert.equal(publicOrigin(req({ host: long, "x-forwarded-proto": "https" })), `https://${long}`);
});

test("no route or library prints the server's own address, or keeps a copy of the rule of its own", () => {
  // the request's own URL's origin (url.origin, new URL(req.url).origin) or the headers read again outside this one helper;
  // a browser's own window.location is its public address already
  const src = fileURLToPath(new URL("../", import.meta.url));
  const found: string[] = [];
  const walk = (dir: string) => {
    for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
      const p = path.join(dir, e.name);
      if (e.isDirectory()) { walk(p); continue; }
      if (!/\.tsx?$/.test(e.name) || e.name.endsWith(".test.ts") || p === fileURLToPath(new URL("./public-origin.ts", import.meta.url))) continue;
      fs.readFileSync(p, "utf8").split("\n").forEach((line, i) => {
        if (/\burl\.origin\b|URL\((?:req|request)\.url\)\.origin|x-forwarded-host/i.test(line) && !line.includes("window.location")) found.push(`${path.relative(src, p)}:${i + 1}`);
      });
    }
  };
  walk(src);
  assert.deepEqual(found, []);
});
