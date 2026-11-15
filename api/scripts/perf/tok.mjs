// a token for the measuring copy, signed with the development secret the tests use (never the live one): the student's record id as the subject, their session id as sid
import crypto from "node:crypto";
export function token(sub, sid, offices = ["student"]) {
  const b64 = (o) => Buffer.from(JSON.stringify(o)).toString("base64url");
  const now = Math.floor(Date.now() / 1000);
  const head = b64({ alg: "HS256" }), body = b64({ sub, sid, iat: now, exp: now + 12 * 3600, offices });
  const sig = crypto.createHmac("sha256", "test-only-secret-of-at-least-thirty-two-bytes").update(`${head}.${body}`).digest("base64url");
  return `${head}.${body}.${sig}`;
}
