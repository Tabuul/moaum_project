import { test } from "node:test";
import assert from "node:assert/strict";
import { addressOf, fromDomainWarning, limitOf, paceWords, smtpHostWarning } from "./mail-sending.ts";

test("Microsoft's servers for incoming mail are named as such", () => {
  assert.match(smtpHostWarning("smtp.mail.outlook.com") ?? "", /smtp\.office365\.com/);
  assert.match(smtpHostWarning(" moaum-edu-ng.mail.protection.outlook.com ") ?? "", /incoming/);
  assert.equal(smtpHostWarning("smtp.office365.com"), null);
});

test("a From address on another domain than the mailbox is warned of", () => {
  assert.equal(addressOf("MOAUM Portal <Portal@MOAUM.edu.ng>"), "portal@moaum.edu.ng");
  assert.match(fromDomainWarning("moaum@bsum.edu.ng", "notifications@moaum.edu.ng") ?? "", /moaum\.edu\.ng, the mailbox on bsum\.edu\.ng/);
  assert.equal(fromDomainWarning("moaum@bsum.edu.ng", ""), null);
  assert.equal(fromDomainWarning("portal@moaum.edu.ng", "MOAUM Portal <notices@moaum.edu.ng>"), null);
});

test("the pace and how long the waiting e-mail takes", () => {
  const words = paceWords({ perMinute: 30, perDay: 10000, lastMinute: 12, lastDay: 4000, allowance: 18 }, 177941);
  assert.match(words, /^30 a minute, 10,000 a day\. Tried 12 in the last minute and 4,000 in the last 24 hours; 18 more may go now\./);
  assert.match(words, /177,941 e-mails waiting take about 18 days/);
  assert.match(paceWords({ lastMinute: 0, lastDay: 0 }, 5), /^no limit a minute, no limit a day\. Tried 0/);
  assert.equal(limitOf(""), null);
  assert.equal(limitOf("10,000"), 10000);
});
