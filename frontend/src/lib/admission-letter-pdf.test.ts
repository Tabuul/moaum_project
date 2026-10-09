import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { jpegSize } from "./pdf-write.ts";
import { DEFAULT_NOTES, admissionLetterPdf, longDate } from "./admission-letter-pdf.ts";

function crest() {
  try {
    const data = new Uint8Array(fs.readFileSync(path.join(process.cwd(), "public", "crest.jpg")));
    const size = jpegSize(data);
    return size ? { data, width: size.width, height: size.height } : null;
  } catch {
    return null;
  }
}

/** a QR-shaped matrix (a chequerboard) so the drawing runs without the server-only QR library */
function fakeQr(size = 29) {
  const dark = new Uint8Array(size * size);
  for (let i = 0; i < dark.length; i++) dark[i] = (i + Math.floor(i / size)) % 2;
  return { size, dark };
}

test("the letter of admission draws the Registry's format on one page", () => {
  const bytes = admissionLetterPdf({
    applicationNo: "APP/26/000123", session: "2025/2026", name: "OGBONYOHE, Ode Richard Olamilekan", surname: "OGBONYOHE", otherNames: "Ode Richard Olamilekan",
    jambKey: "202550543585DA", entryLevel: 100, programme: "B.Sc. COMPUTER SCIENCE", faculty: "Science", department: "Computer Science", degreeType: "UNDER GRADUATE",
    durationSemesters: 8, registrationOpens: "2026-01-05", decision: "OFFERED", decisionReleasedAt: "2026-01-22T09:00:00Z", decisionBasis: "NM", acceptedAt: "2026-01-23T09:00:00Z",
  }, {
    number: "MOAUM/ADM/26/000123", version: 1, verification_code: "ABCD-EFGH-IJKL", statement: "{}", issued_on: "2026-01-22", verifyPath: "/verify/document?key=ABCD-EFGH-IJKL",
    template: {
      title: "CONFIRMATION OF OFFER OF ADMISSION", subtitle: "{session} ACADEMIC SESSION", signatory_name: "Andrew Aondoakaa Anjah, MAUA, MIMC",
      signatory_title: "Deputy Registrar, Admissions, Examinations and Records", second_title: "For: Registrar", remarks: DEFAULT_NOTES.join("\n"),
    },
  }, "https://portal.example", { crest: crest(), signature: null, qr: fakeQr() });
  assert.ok(bytes.length > 2000);
  const text = Buffer.from(bytes).toString("latin1");
  assert.match(text, /CONFIRMATION OF OFFER OF ADMISSION/);
  assert.match(text, /202550543585DA/);
  assert.match(text, /8 SEMESTERS/);
  assert.match(text, /5th January, 2026/);
  assert.match(text, /Deputy Registrar, Admissions, Examinations and Records/);
  assert.equal((text.match(/\/Type \/Page\b/g) ?? []).length, 1);
  const out = process.env.LETTER_SAMPLE_OUT;
  if (out) fs.writeFileSync(out, bytes);
});

test("a CCE admission's letter names the Centre, part-time study and the duration in years (V379)", () => {
  const bytes = admissionLetterPdf({
    applicationNo: "APP/25/000901", session: "2025/2026", name: "IORLIAM, Doosuur", surname: "IORLIAM", otherNames: "Doosuur",
    jambKey: "202512345678CC", entryLevel: 100, programme: "B.Sc. COMPUTER SCIENCE", faculty: "Science", decision: "OFFERED",
    decisionReleasedAt: "2026-02-02T09:00:00Z", decisionBasis: "OTHER", acceptedAt: "2026-02-03T09:00:00Z",
  }, {
    number: "MOAUM/ADM/25/000901", version: 1, verification_code: "WXYZ-ABCD-EFGH", issued_on: "2026-02-03", verifyPath: "/verify/document?key=WXYZ-ABCD-EFGH",
    statement: JSON.stringify({ admissionRoute: "CCE", studyMode: "PART-TIME", centre: "Centre for Continuing Education", durationYears: 6 }),
  }, "https://portal.example", { crest: crest(), signature: null, qr: fakeQr(), passport: crest() });
  const text = Buffer.from(bytes).toString("latin1");
  assert.match(text, /CENTRE FOR CONTINUING EDUCATION/);
  assert.match(text, /PART-TIME/);
  assert.match(text, /6 YEARS \\?\(PART-TIME\\?\)/);  // a PDF string escapes its parentheses
  assert.doesNotMatch(text, /SEMESTERS/);
  assert.equal((text.match(/\/Type \/Page\b/g) ?? []).length, 1);
});

test("dates read as the Registry writes them", () => {
  assert.equal(longDate("2026-01-05"), "5th January, 2026");
  assert.equal(longDate("2026-03-22"), "22nd March, 2026");
  assert.equal(longDate("2026-11-13"), "13th November, 2026");
  assert.equal(longDate(null), "");
});
