import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { jpegSize } from "./pdf-write.ts";
import { UNIVERSITY, facultyTick, screeningFormsPdf, type FormsInput } from "./screening-forms-pdf.ts";

function crest() {
  try {
    const data = new Uint8Array(fs.readFileSync(path.join(process.cwd(), "public", "crest.jpg")));
    const size = jpegSize(data);
    return size ? { data, width: size.width, height: size.height } : null;
  } catch {
    return null;
  }
}

const fixture: FormsInput = {
  prefill: {
    surname: "ACHIR", other_names: "Benedict Prince", jamb_reg_no: "20261089937GA", programme: "B.Sc. COMPUTER SCIENCE", entry_mode: "UTME", session: "2026/2027", application_no: "APP/26/000123",
    sex: "M", state_of_origin: "Benue", lga: "Gwer East", faculty: "SCIENCE", department: "MATHEMATICS AND COMPUTER SCIENCE", date_of_birth: "2006-01-06", email: "invented@example.com", phone: "08030000000", next_of_kin: "Rebecca Achir, mother, 08160000000",
  },
  answers: {
    nationality: "Nigeria", marital_status: "Single", religion: "Christianity", sponsor_name: "Mrs Rebecca Achir", sponsor_address: "No. 26 Dagye Street, Kaduna, Kaduna State", postal_address: "No. 26 Dagye Street, Kaduna, Kaduna State",
    home_address: "No. 26 Dagye Street, Kaduna, Kaduna State", working_experience: "", place_of_birth: "Aliade", primary_school: "Righton International School, Sabo Tasha, Kaduna", primary_fees_per_term: "10600",
    secondary_school: "Gwazachat Academy, U/Barde, Sabo Tasha", secondary_fees_per_term: "16400", parent_profession: "Businessman", parent_income: "1000000", guardian_name: "Mrs Rebecca Achir",
    guardian_address: "No. 26 Dagye Street, Kaduna, Kaduna State", guardian_mobile: "08164259535", kin_name: "Rebecca Achir", kin_relationship: "Mother", kin_mobile: "08164259535",
    blood_group: "O+", children: "", ethnic_group: "Tiv", mobile: "08139911852", alt_mobile: "09040519378", personal_email: "invented@example.com", bank_account_no: "0109440964", bank_location: "Kaduna State",
    extracurricular: "Football", hobbies: "Singing", secondary_graduation_year: "2024",
  },
  institutions: [
    { name: "Righton International School, Sabo Tasha, Kaduna", from_year: 2012, to_year: 2017, certificate: "FSLC", award_year: 2017 },
    { name: "Gwazachat Academy, U/Barde, Sabo Tasha", from_year: 2018, to_year: 2024, certificate: "SSCE", award_year: 2024 },
  ],
  olevel: ["ENGLISH LANGUAGE:C6", "GENERAL MATHEMATICS:C6", "BIOLOGY:B2", "CHEMISTRY:A1", "PHYSICS:B2", "MARKETING:C4", "CHRISTIAN RELIGIOUS STUDIES:C4", "GEOGRAPHY:B3", "CIVIC EDUCATION:C6"]
    .map((s) => { const [subject, grade] = s.split(":"); return { exam_body: "WAEC", exam_number: "4192507003", exam_year: 2024, subject, grade }; }),
  form: { screening_no: "SCR/2026/000123", state: "SUCCESSFUL", submitted_at: "2026-09-20T10:00:00Z", declaration_at: "2026-09-20T10:00:00Z", membership: "Nil", decided_at: "2026-09-25T09:00:00Z", decided_office: "academic", decision_reason: null },
  acceptancePaidOn: "2026-09-12T08:00:00Z",
  passport: null,
  crest: crest(),
  printedOn: new Date("2026-09-27T12:00:00Z"),
};

test("the five screening forms print as one PDF under the University's name, filled from the answers", () => {
  const bytes = screeningFormsPdf(fixture);
  const text = new TextDecoder("latin1").decode(bytes);
  assert.ok(text.startsWith("%PDF-1.4"));
  assert.ok(text.includes("/Count 5"), "five pages");
  for (const s of [UNIVERSITY, "FORM: A", "SCREENING OF FRESH UNDERGRADUATE STUDENTS", "SECTION A: PERSONAL DATA", "SECTION B: ACADEMIC RECORD", "SECTION C: ACADEMIC RECORD",
    "SECTION D: FOR OFFICIAL USE ONLY", "SUPPLEMENTARY BIODATA FORM", "STUDENT DATA CAPTURE FORM", "Gwazachat Academy", "CIVIC EDUCATION", "YOU HAVE BEEN SUCCESSFULLY SCREENED"]) {
    assert.ok(text.includes(s), `contains ${s}`);
  }
  assert.ok(!/BENUE STATE/i.test(text), "the former University's name is nowhere on the forms");
  const out = process.env.SCREENING_FORMS_OUT;
  if (out) fs.writeFileSync(out, bytes);
});

test("the faculty group ticked follows the faculty's name", () => {
  assert.equal(facultyTick("SCIENCE"), "Scs.");
  assert.equal(facultyTick("Basic Medical Sciences"), "CHS");
  assert.equal(facultyTick("LAW"), "Law");
  assert.equal(facultyTick("MANAGEMENT SCIENCES"), "Mgt. Sc");
  assert.equal(facultyTick(null), null);
});
