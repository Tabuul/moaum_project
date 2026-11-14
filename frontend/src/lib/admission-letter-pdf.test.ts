import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { jpegSize } from "./pdf-write.ts";
import { DEFAULT_NOTES, admissionLetterPdf, longDate, type LetterDoc } from "./admission-letter-pdf.ts";
import { signatureImageOf, type LetterSignature } from "./letter-signature.ts";

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

/* V759: the signature uploaded for the template's signatory ───────────────────────────────────────────────────────────────── */

/** the head of a JPEG of a size (SOI, a JFIF APP0, a baseline SOF0): the drawing reads only its size */
function fakeJpeg(w: number, h: number): Uint8Array {
  return new Uint8Array([
    0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46, 0x00, 0x01, 0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00,
    0xff, 0xc0, 0x00, 0x11, 0x08, h >> 8, h & 0xff, w >> 8, w & 0xff, 0x03, 0x01, 0x22, 0x00, 0x02, 0x11, 0x01, 0x03, 0x11, 0x01,
    0xff, 0xd9,
  ]);
}

const SIGNATORY = "Andrew Aondoakaa Anjah, MAUA, MIMC";
const APP = {
  applicationNo: "APP/26/000123", session: "2025/2026", name: "OGBONYOHE, Ode Richard Olamilekan", surname: "OGBONYOHE", otherNames: "Ode Richard Olamilekan",
  jambKey: "202550543585DA", entryLevel: 100, programme: "B.Sc. COMPUTER SCIENCE", faculty: "Science", department: "Computer Science", degreeType: "UNDER GRADUATE",
  durationSemesters: 8, registrationOpens: "2026-01-05", decision: "OFFERED", decisionReleasedAt: "2026-01-22T09:00:00Z", decisionBasis: "NM", acceptedAt: "2026-01-23T09:00:00Z",
};
function letterWith(signature: LetterSignature | null, remarks = DEFAULT_NOTES.join("\n")) {
  const letter: LetterDoc = {
    number: "MOAUM/ADM/26/000123", version: 1, verification_code: "ABCD-EFGH-IJKL", statement: "{}", issued_on: "2026-01-22", verifyPath: "/verify/document?key=ABCD-EFGH-IJKL",
    template: { title: "CONFIRMATION OF OFFER OF ADMISSION", subtitle: "{session} ACADEMIC SESSION", signatory_name: SIGNATORY, signatory_title: "Deputy Registrar, Admissions, Examinations and Records", second_title: "For: Registrar", remarks },
    signature,
  };
  // as both routes do: the letter JSON's signature read by signatureImageOf
  return admissionLetterPdf(APP, letter, "https://portal.example", { crest: crest(), signature: signatureImageOf(letter.signature), qr: fakeQr() });
}

/** the page's drawing read back from its operators: each image drawn (its box, and its size in pixels), each line of text with its
 *  baseline, and the QR's cells */
function readBack(bytes: Uint8Array) {
  const text = Buffer.from(bytes).toString("latin1");
  const objs = new Map<string, { w: number; h: number }>();
  for (const m of text.matchAll(/(\d+) 0 obj\n<< \/Type \/XObject \/Subtype \/Image \/Width (\d+) \/Height (\d+)/g)) objs.set(m[1], { w: +m[2], h: +m[3] });
  const names = new Map<string, { w: number; h: number }>();
  for (const m of (/\/XObject << ([^>]*) >>/.exec(text)?.[1] ?? "").matchAll(/\/(Im\d+) (\d+) 0 R/g)) { const o = objs.get(m[2]); if (o) names.set(m[1], o); }
  const draws = [...text.matchAll(/q ([\d.]+) 0 0 ([\d.]+) ([\d.-]+) ([\d.-]+) cm \/(Im\d+) Do Q/g)].map((m) => ({ w: +m[1], h: +m[2], x: +m[3], y: +m[4], px: names.get(m[5]) }));
  const lines = [...text.matchAll(/([\d.-]+) ([\d.-]+) Td \(((?:[^()\\]|\\.)*)\) Tj/g)].map((m) => ({ x: +m[1], y: +m[2], s: m[3] }));
  const qrCells = [...text.matchAll(/\n0 g ([\d.]+) ([\d.]+) ([\d.]+) ([\d.]+) re f/g)].map((m) => ({ x: +m[1], y: +m[2], w: +m[3], h: +m[4] }));
  return { draws, lines, qrCells };
}

/** the signature as drawn, the signatory's name, and what must stay clear of it */
function placed(bytes: Uint8Array, px: { w: number; h: number }) {
  const r = readBack(bytes);
  const sig = r.draws.find((d) => d.px?.w === px.w && d.px?.h === px.h);
  const name = r.lines.find((l) => l.s === SIGNATORY);
  assert.ok(name, "the signatory's name is on the letter");
  return { ...r, sig, name };
}

test("the signature uploaded for the template's signatory stands on the name, in proportion, clear of the notes and the QR (V759)", () => {
  const { sig, name, lines, qrCells } = placed(letterWith({ jpegBase64: Buffer.from(fakeJpeg(800, 265)).toString("base64"), width: 800, height: 265 }), { w: 800, h: 265 });
  assert.ok(sig, "the signature is drawn");
  // in its own proportions, as large as the 140 x 48 pt space allows
  assert.ok(Math.abs(sig.w / sig.h - 800 / 265) < 0.01);
  assert.ok(sig.w <= 140.01 && sig.h <= 48.01);
  assert.ok(Math.abs(sig.w - 140) < 0.01, "a wide signature fills the width");
  // where the name starts, just above it: clear of its capitals (about 7 pt at 10.5 pt), never more than a line above
  assert.equal(sig.x, name.x);
  assert.ok(sig.y - name.y >= 9 && sig.y - name.y <= 16, `the signature stands ${sig.y - name.y} pt above the name's baseline`);
  // no line of the notes (or anything else) between the name and 10 pt above the signature's top
  const top = sig.y + sig.h;
  assert.deepEqual(lines.filter((l) => l.y > name.y && l.y < top + 10).map((l) => l.s), []);
  const notesBottom = Math.min(...lines.filter((l) => l.y > name.y).map((l) => l.y));
  assert.ok(notesBottom - top >= 20, `the last note's baseline is ${notesBottom - top} pt above the signature`);
  // the QR is on the right, wholly beyond the signature
  assert.ok(qrCells.length > 0);
  assert.ok(sig.x + sig.w < Math.min(...qrCells.map((c) => c.x)));
});

test("a square signature stands on the same line; a long set of notes moves the signature down with the name, never into them (V759)", () => {
  const wide = placed(letterWith({ jpegBase64: Buffer.from(fakeJpeg(800, 265)).toString("base64") }), { w: 800, h: 265 });
  const square = placed(letterWith({ jpegBase64: Buffer.from(fakeJpeg(600, 600)).toString("base64") }), { w: 600, h: 600 });
  assert.ok(wide.sig && square.sig);
  assert.equal(square.sig.y, wide.sig.y, "both stand on the same line above the name");
  assert.ok(Math.abs(square.sig.h - 48) < 0.01 && Math.abs(square.sig.w - 48) < 0.01, "a square signature fills the height");
  const long = DEFAULT_NOTES.concat(DEFAULT_NOTES.slice(1, 5)).join("\n");
  const low = placed(letterWith({ jpegBase64: Buffer.from(fakeJpeg(800, 265)).toString("base64") }, long), { w: 800, h: 265 });
  const ls = low.sig;
  assert.ok(ls);
  assert.ok(low.name.y < wide.name.y, "the notes took more of the page");
  assert.equal(ls.y - low.name.y, wide.sig.y - wide.name.y, "the signature moves with the name");
  assert.deepEqual(low.lines.filter((l) => l.y > low.name.y && l.y < ls.y + ls.h + 10).map((l) => l.s), []);
});

test("a small scan prints at its own size (150 dots an inch at most) on the same corner above the name, never blown up into blocks (V759)", () => {
  const wide = placed(letterWith({ jpegBase64: Buffer.from(fakeJpeg(800, 265)).toString("base64") }), { w: 800, h: 265 });
  // 60 x 20 pixels, the smallest the API takes: 28.8 x 9.6 points, where it was enlarged to 140 x 46.67 (about 31 dots an inch)
  const tiny = placed(letterWith({ jpegBase64: Buffer.from(fakeJpeg(60, 20)).toString("base64") }), { w: 60, h: 20 });
  assert.ok(wide.sig && tiny.sig);
  assert.ok(Math.abs(tiny.sig.w - 28.8) < 0.01 && Math.abs(tiny.sig.h - 9.6) < 0.01, `${tiny.sig.w} x ${tiny.sig.h}`);
  assert.equal(tiny.sig.x, tiny.name.x, "it starts where the name starts");
  assert.equal(tiny.sig.y, wide.sig.y, "it stands on the same line above the name");
  // 300 pixels wide fills the space, as the screen's hint says
  const enough = placed(letterWith({ jpegBase64: Buffer.from(fakeJpeg(300, 100)).toString("base64") }), { w: 300, h: 100 });
  assert.ok(enough.sig && Math.abs(enough.sig.w - 140) < 0.01);
});

test("without a signature the letter leaves the same space above the name for a hand signature (V759)", () => {
  const signed = placed(letterWith({ jpegBase64: Buffer.from(fakeJpeg(800, 265)).toString("base64") }), { w: 800, h: 265 });
  assert.equal(signed.name.y, 118, "the name stands where it stood before V759 (176 - 58)");
  for (const none of [null, { jpegBase64: Buffer.from("not an image").toString("base64") }]) {
    const bare = placed(letterWith(none), { w: 800, h: 265 });
    assert.equal(bare.sig, undefined, "no signature is drawn");
    assert.equal(bare.draws.length, 1, "only the crest");
    assert.equal(bare.name.y, signed.name.y, "the name stays where it is with a signature");
  }
});

test("dates read as the Registry writes them", () => {
  assert.equal(longDate("2026-01-05"), "5th January, 2026");
  assert.equal(longDate("2026-03-22"), "22nd March, 2026");
  assert.equal(longDate("2026-11-13"), "13th November, 2026");
  assert.equal(longDate(null), "");
});
