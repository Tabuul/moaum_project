import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { appointedMessage, leftOffCount, uploadResultLines, type UploadResult } from "./appointments.ts";

test("the single appointment's message names an e-mail left off, another person's verified address (V749)", () => {
  assert.deepEqual(appointedMessage("ADEYEMI, Example", { employmentId: "e1", emailLeftOff: null }),
    { text: "Appointed: ADEYEMI, Example. The employment record is active.", kind: "ok" });
  assert.deepEqual(appointedMessage("ADEYEMI, Example", { employmentId: "e1" }).kind, "ok");
  assert.deepEqual(appointedMessage("SS/0001", null).text, "Appointed: SS/0001. The employment record is active.");
  const off = appointedMessage("ADEYEMI, Example", { employmentId: "e1", emailLeftOff: "taken@moaum.edu.ng" });
  assert.equal(off.kind, "warn");
  assert.match(off.text, /^Appointed: ADEYEMI, Example, without the e-mail taken@moaum\.edu\.ng: it is another person's, verified on their record\./);
  assert.match(off.text, /verifies their own address at My identity\.$/);
});

test("the upload's result note lists the rows not appointed and the appointed ones whose e-mail was left off, in the file's order (V749)", () => {
  const res: UploadResult = { appointed: 3, skipped: 1, rows: [
    { row: "2", staff_no: "SS/0001", name: "A, B", appointed: true },
    { row: "3", staff_no: "SS/0002", name: "C, D", appointed: true, email_left_off: "held@moaum.edu.ng" },
    { row: "4", staff_no: "SS/0003", name: "E, F", appointed: false, problems: ["The category is ACADEMIC or NON_ACADEMIC.", "Sex is M or F."] },
    { row: "5", staff_no: "SS/0004", name: "G, H", appointed: true, email_left_off: null },
  ] };
  assert.deepEqual(uploadResultLines(res), [
    { row: "3", text: "Row 3 (SS/0002): appointed without the e-mail held@moaum.edu.ng, another person's verified address" },
    { row: "4", text: "Row 4 (SS/0003): The category is ACADEMIC or NON_ACADEMIC. Sex is M or F." },
  ]);
  assert.equal(leftOffCount(res), 1);
  assert.deepEqual(uploadResultLines({ appointed: 1, skipped: 0, rows: [{ row: "2", staff_no: "X1", name: "X", appointed: true }] }), []);
  assert.equal(leftOffCount({ appointed: 0, skipped: 0, rows: [] }), 0);
});

test("the screen reads the names the API answers: emailLeftOff for one, email_left_off on an upload's row (V749)", () => {
  const here = import.meta.dirname ?? ".";
  const java = readFileSync(join(here, "../../../api/src/main/java/ng/edu/moaum/portal/hrm/AppointmentController.java"), "utf8");
  assert.match(java, /"emailLeftOff"/);
  const db = join(here, "../../../db");
  const v749 = readdirSync(db).find((f) => f.startsWith("V749__"));
  assert.ok(v749);
  const sql = readFileSync(join(db, v749), "utf8");
  const many = sql.slice(sql.indexOf("CREATE OR REPLACE FUNCTION hrm.appoint_many"), sql.indexOf("COMMENT ON FUNCTION hrm.appoint_many"));
  assert.ok(many.length > 0);
  assert.match(many, /'email_left_off'/);
  const screen = readFileSync(join(here, "../app/hr/appointments/Appointments.tsx"), "utf8");
  assert.match(screen, /appointedMessage\(/);
  assert.match(screen, /uploadResultLines\(result\)/);
});
