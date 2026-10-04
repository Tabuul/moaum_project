import { test } from "node:test";
import assert from "node:assert/strict";
import { documentHtml, withSerial } from "./html.ts";
import { DEFAULT_INSTITUTION, addressLine, contactLine, formatDocDate, formatMoney, normaliseInstitution } from "./institution.ts";
import { documentTitle, periodSubtitle, profileOf } from "./profiles.ts";

const inst = { ...DEFAULT_INSTITUTION, name: "Example University, Makurdi", motto: "Knowledge and Service", address: "No. 1 University Road", city: "Makurdi", state: "Benue State", country: "Nigeria", phone: "+234 800 000 0000", email: "info@example.edu.ng", website: "https://www.example.edu.ng" };

test("the printed document carries the official header, the title, the filters, a serial column and a running footer", () => {
  const html = documentHtml(inst, "STANDARD_REPORT", {
    title: "Payment transactions", subtitle: "School Fees — 2025/2026 Academic Session",
    meta: [["Faculty", "Science"], ["Status", "All"]], headers: ["Reference", "Student", "Amount"],
    rows: [["PAY-1", "Ada", 50000], ["PAY-2", "Grace", 75000.5]], generatedBy: "Bursar", reference: "EXU/DOC/1",
  }, "https://portal.example/crest.png");
  assert.ok(html.includes("EXAMPLE UNIVERSITY, MAKURDI"), "the name in capitals");
  assert.ok(html.includes("Knowledge and Service"), "the motto");
  assert.ok(html.includes("No. 1 University Road, Makurdi, Benue State, Nigeria"), "the address line");
  assert.ok(html.includes("Tel +234 800 000 0000  |  info@example.edu.ng  |  www.example.edu.ng"), "the contact line");
  assert.ok(html.includes("<h1>PAYMENT TRANSACTIONS</h1>"), "the title in capitals");
  assert.ok(html.includes("<span>Faculty</span><b>Science</b>"), "the filters used");
  assert.ok(html.includes('<th class="sn">S/N</th>') && html.includes('<td class="sn">1</td>') && html.includes('<td class="sn">2</td>'), "S/N leads the rows");
  assert.ok(html.includes("<thead>"), "the header repeats on every printed page (table-header-group)");
  assert.ok(html.includes("75,000.5"), "numbers are formatted");
  assert.ok(html.includes("Example University, Makurdi &nbsp;|&nbsp; PAYMENT TRANSACTIONS"), "the footer names the University and the title");
  assert.ok(html.includes("by Bursar") && html.includes("Ref EXU/DOC/1") && html.includes("OFFICIAL USE ONLY"));
  assert.ok(html.includes("size:A4 portrait"), "a standard report prints portrait");
});

test("a result statement is a student copy, a broadsheet prints landscape, and a receipt has no serial column", () => {
  assert.ok(documentHtml(inst, "RESULT", { title: "Statement of result", headers: ["Course"], rows: [["MTH 101"]] }, "").includes("STUDENT COPY"));
  assert.ok(documentHtml(inst, "BROADSHEET", { title: "Result broadsheet", headers: ["Matric"], rows: [["1"]] }, "").includes("size:A4 landscape"));
  const receipt = documentHtml(inst, "RECEIPT", { title: "Official payment receipt", headers: ["Item", "Amount"], rows: [["Fees", 1]] }, "");
  assert.ok(!receipt.includes("S/N"), "a receipt is not a numbered list");
  assert.ok(receipt.includes("OFFICIAL PAYMENT RECEIPT"));
});

test("the identity helpers never print undefined, null or a stray scheme", () => {
  const i = normaliseInstitution({ name: " Example University ", shortName: null, motto: "", website: "https://www.example.edu.ng/", logoVersion: "3", dateFormat: "SHORT" });
  assert.equal(i.name, "Example University");
  assert.equal(i.shortName, "MOAUM");
  assert.equal(i.motto, null);
  assert.equal(i.logoVersion, 3);
  assert.equal(contactLine(i), "www.example.edu.ng");
  assert.equal(addressLine({ ...i, city: "Makurdi", state: null, country: "Nigeria" }), "Makurdi, Nigeria");
  assert.equal(formatDocDate("2026-10-04T20:42:00Z", i), "04/10/2026");
  assert.equal(formatDocDate("2026-10-04T20:42:00Z", DEFAULT_INSTITUTION), "04 October 2026");
  assert.equal(formatDocDate(null), "—");
  assert.equal(formatMoney(1234567.891), "₦1,234,567.89");
  assert.equal(documentTitle(profileOf("RECEIPT")), "OFFICIAL PAYMENT RECEIPT");
  assert.equal(documentTitle(profileOf("RECEIPT"), "Hostel payment receipt"), "HOSTEL PAYMENT RECEIPT");
  assert.equal(periodSubtitle("2025/2026", 1), "2025/2026 Academic Session — First Semester");
  assert.equal(periodSubtitle(null, null), null);
  assert.deepEqual(withSerial([["a"], ["b"]], 41), [[41, "a"], [42, "b"]]);
});
