#!/usr/bin/env node
/* Mints the token Keycloak would issue, signed with the API's development
   secret (MOAUM_AUTH_HMAC_SECRET), for a person holding the given offices.
   Development and CI only: production verifies tokens against Keycloak.

     node api/scripts/dev-token.mjs --secret "$MOAUM_AUTH_HMAC_SECRET" \
          --sub 5f0c4a2e-... --offices academic,registrar [--ttl 3600]

   No dependencies: HS256 is an HMAC over two base64url strings.           */
import { createHmac, randomUUID } from "node:crypto";

const args = Object.fromEntries(
  process.argv.slice(2).reduce((acc, a, i, all) => {
    if (a.startsWith("--")) acc.push([a.slice(2), all[i + 1] && !all[i + 1].startsWith("--") ? all[i + 1] : "true"]);
    return acc;
  }, []),
);

const secret = args.secret ?? process.env.MOAUM_AUTH_HMAC_SECRET;
if (!secret || Buffer.byteLength(secret) < 32) {
  console.error("--secret (or MOAUM_AUTH_HMAC_SECRET) is required and must be at least 32 bytes");
  process.exit(2);
}
const sub = args.sub ?? randomUUID();
const offices = (args.offices ?? "academic").split(",").map((s) => s.trim()).filter(Boolean);
const ttl = Number(args.ttl ?? 3600);
const now = Math.floor(Date.now() / 1000);

const b64 = (o) => Buffer.from(JSON.stringify(o)).toString("base64url");
const head = b64({ alg: "HS256", typ: "JWT" });
const body = b64({ sub, iat: now, exp: now + ttl, offices });
const sig = createHmac("sha256", secret).update(`${head}.${body}`).digest("base64url");

console.error(`subject ${sub}\noffices ${offices.join(", ")}\nexpires in ${ttl}s\n`);
console.log(`${head}.${body}.${sig}`);
