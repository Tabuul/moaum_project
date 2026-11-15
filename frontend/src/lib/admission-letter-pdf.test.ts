import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { A4, jpegSize, textWidth } from "./pdf-write.ts";
import { DEFAULT_NOTES, admissionLetterPdf, linesWithin, longDate, type LetterDoc } from "./admission-letter-pdf.ts";
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

/* The footer within the page's margins, whatever the address ─────────────────────────────────────────────────────────────── */

const MARGIN = 56;
/** a PDF string read back to its characters */
const unescaped = (s: string) => s.replace(/\\([0-7]{3})/g, (_, o: string) => String.fromCharCode(parseInt(o, 8))).replace(/\\(.)/g, "$1");
/** the lines of the footer as drawn (Helvetica 7.5, the only text on the letter in it), top line first */
function footerOf(bytes: Uint8Array) {
  const text = Buffer.from(bytes).toString("latin1");
  return [...text.matchAll(/BT \/F1 7\.5 Tf [\d. ]+ rg ([\d.-]+) ([\d.-]+) Td \(((?:[^()\\]|\\.)*)\) Tj ET/g)]
    .map((m) => ({ x: +m[1], y: +m[2], s: unescaped(m[3]) }))
    .sort((a, b) => b.y - a.y);
}
const squash = (s: string) => s.replace(/[\s·]/g, "");
function letterAt(origin: string, footer: string | null = null) {
  const letter: LetterDoc = {
    number: "MOAUM/ADM/26/000123", version: 1, verification_code: "ABCD-EFGH-IJKL", statement: "{}", issued_on: "2026-01-22", verifyPath: "/verify/document?key=ABCD-EFGH-IJKL",
    template: { signatory_name: SIGNATORY, signatory_title: "Deputy Registrar, Admissions, Examinations and Records", second_title: "For: Registrar", remarks: DEFAULT_NOTES.join("\n"), footer },
  };
  return footerOf(admissionLetterPdf(APP, letter, origin, { crest: crest(), signature: null, qr: fakeQr() }));
}

/** the address of the letter printed on AWS before the fix, a long Railway one, and the longest a host name can be */
const LONG = [
  "https://ip-10-20-41-127.us-east-2.compute.internal:3000",
  "https://moaum-portal-production.up.railway.app",
  `https://${"a".repeat(63)}.${"b".repeat(63)}.${"c".repeat(63)}.${"d".repeat(61)}:65535`,
];

test("the footer's line stands where it always stood when the address is short", () => {
  const lines = letterAt("https://portal.moaum.edu.ng");
  assert.deepEqual(lines.map((l) => [l.x, l.y]), [[MARGIN, 44]]);
  assert.equal(lines[0].s, "Document no MOAUM/ADM/26/000123 · version 1 · verification code ABCD-EFGH-IJKL · verify at https://portal.moaum.edu.ng/verify/document");
  const withFooter = letterAt("https://portal.moaum.edu.ng", "Not valid without the University's seal.");
  assert.deepEqual(withFooter.map((l) => [l.y, l.s.slice(0, 11)]), [[44, "Document no"], [33, "Not valid w"]]);
});

test("a long address goes on to more lines inside the margins, every character of it printed, clear of the QR and the page's edge", () => {
  let lowered = 0, raised = 0;
  for (const origin of LONG) for (const footer of [null, "Not valid without the University's seal.", "A template footer long enough to need a second line of its own: ".repeat(3).trim()]) {
    const lines = letterAt(origin, footer);
    const what = `${origin} / ${footer ? footer.length : "no"} footer`;
    assert.ok(lines.length >= 2, `${what}: wrapped`);
    for (const l of lines) {
      assert.equal(l.x, MARGIN, `${what}: from the left margin`);
      const right = l.x + textWidth(l.s, 7.5);
      assert.ok(right <= A4.w - MARGIN + 0.01, `${what}: "${l.s}" ends at ${right.toFixed(1)} pt, past the right margin ${A4.w - MARGIN}`);
      assert.ok(l.y >= 18, `${what}: "${l.s}" at ${l.y} pt, above the page's foot`);
    }
    // the verification lines, then the template's: each reads back whole, 9 pt apart, the two 11 pt apart as the letter always had
    const k = footer ? lines.findIndex((_, i) => squash(lines.slice(i).map((l) => l.s).join("")) === squash(footer)) : lines.length;
    assert.ok(k > 0, `${what}: the template's footer reads back whole, under the verification`);
    const verify = lines.slice(0, k), tpl = lines.slice(k);
    assert.equal(squash(verify.map((l) => l.s).join("")), squash(`Document no MOAUM/ADM/26/000123 version 1 verification code ABCD-EFGH-IJKL verify at ${origin}/verify/document`), what);
    assert.ok(verify.some((l) => l.s.startsWith("verify at https://")), `${what}: "verify at" stays with its address`);
    for (const block of [verify, tpl]) for (let i = 1; i < block.length; i++) assert.equal(block[i - 1].y - block[i].y, 9, `${what}: a line's leading`);
    if (tpl.length) assert.equal(verify[verify.length - 1].y - tpl[0].y, 11, `${what}: the verification over the template's footer`);
    // where they stand: the last verification line at 44 pt, or the template's at 33, raised a line for each line more above it —
    // unless the top would then pass 72 pt (16 pt under For: Registrar at 88, 20 pt under the QR's foot at 96), when the whole comes
    // down by as much; and when even the page's foot (18 pt) leaves it too tall for that, the signatory's block goes up instead
    const top = (tpl.length ? 44 + (tpl.length - 1) * 9 : 44) + (verify.length - 1) * 9, low = tpl.length ? 33 : 44;
    const ceiling = Math.max(72, 18 + top - low);
    const down = Math.max(0, top - ceiling);
    assert.equal(lines[0].y, top - down, `${what}: the top line`);
    assert.equal(lines[lines.length - 1].y, low - down, `${what}: the last line`);
    if (down) lowered++;
    if (ceiling > 72) raised++;
  }
  assert.ok(lowered > 0, "a long address with a two-line template footer comes down from the signatory's lines");
  assert.ok(raised > 0, "the longest address with a two-line template footer raises the signatory's block");
});

/* The footer, the signatory's block and the QR never meet, whatever the body and the footer ─────────────────────────────── */

const TITLE = "Deputy Registrar, Admissions, Examinations and Records";
const CCE = { admissionRoute: "CCE", studyMode: "PART-TIME", centre: "Centre for Continuing Education", durationYears: 6 };
const CHANGED = { changedFrom: "B.Sc. (Ed.) AGRICULTURAL SCIENCE EDUCATION", changedTo: "B.Sc. AGRICULTURAL ECONOMICS AND EXTENSION", changedOn: "2026-02-01" };
const TEN = DEFAULT_NOTES.concat(DEFAULT_NOTES.slice(1, 5));
const LONG_NOTE = "Candidates shall present the originals of every credential named in the application at the screening, and any discrepancy found";
/** the bodies a letter can have: the template's six notes, ten, the 1000 characters the API takes (as seven long notes and as 166
 *  short ones), with and without a CCE admission's passport and a change of programme from and to long names */
const BODIES: Record<string, { statement: object; remarks: string[] }> = {
  "six notes": { statement: {}, remarks: DEFAULT_NOTES },
  "CCE, passport, programme changed, six notes": { statement: { ...CCE, ...CHANGED }, remarks: DEFAULT_NOTES },
  "ten notes": { statement: {}, remarks: TEN },
  "CCE, passport, programme changed, ten notes": { statement: { ...CCE, ...CHANGED }, remarks: TEN },
  "CCE, passport, programme changed, 1000 characters of notes": { statement: { ...CCE, ...CHANGED }, remarks: Array.from({ length: 7 }, (_, i) => `${i + 1}. ${LONG_NOTE}`.slice(0, 141)) },
  "166 short notes": { statement: {}, remarks: Array.from({ length: 166 }, (_, i) => `N${i}.`) },
};
/** the University's address, Railway's, the AWS task's own (as printed before the fix), and the longest a host can be */
const ORIGINS = ["https://portal.moaum.edu.ng", "https://moaum-portal-production.up.railway.app", LONG[0], LONG[2]];
/** no template footer, a line of one, and the 600 characters the API takes */
const FOOTERS = [null, "Not valid without the University's seal.", "This letter is valid only as verified on the University's portal. ".repeat(10).slice(0, 600)];
/** the number and code as the database makes them (credentials.next_document_number, credentials.new_code: ADM/YYYY/NNNNNN, five
 *  groups of five), and a longer number at a later version */
const NUMBERS: [string, number, string][] = [["ADM/2026/000123", 2, "7Q2KX-M9P4T-ZB8RC-W3N6H-JY5DF"], ["MOAUM/REGISTRY/ADM/2026/000123456", 12, "7Q2KX-M9P4T-ZB8RC-W3N6H-JY5DF"]];
const SIGNATURE: LetterSignature = { jpegBase64: Buffer.from(fakeJpeg(800, 265)).toString("base64"), width: 800, height: 265 };
const fill = (n: string) => n.replace("{session}", "2025/2026").replace("{from}", " from 5th January, 2026").replace("{date}", "5th January, 2026");

function realLetter(o: { statement: object; remarks: string[]; origin: string; footer: string | null; number: string; version: number; code: string }) {
  const st = o.statement as { admissionRoute?: string; changedTo?: string };
  const letter: LetterDoc = {
    number: o.number, version: o.version, verification_code: o.code, statement: JSON.stringify(o.statement), issued_on: "2026-01-22", verifyPath: `/verify/document?key=${o.code}`,
    template: { signatory_name: SIGNATORY, signatory_title: TITLE, second_title: "For: Registrar", remarks: o.remarks.join("\n"), footer: o.footer },
    signature: SIGNATURE,
  };
  return admissionLetterPdf({ ...APP, programme: st.changedTo ?? APP.programme }, letter, o.origin,
    { crest: crest(), signature: signatureImageOf(letter.signature), qr: fakeQr(), passport: st.admissionRoute === "CCE" ? crest() : null });
}

/** each page's drawing read back from its content stream: its lines of text (face, size, baseline, characters), its images and the
 *  QR's cells */
function pagesOf(bytes: Uint8Array) {
  const text = Buffer.from(bytes).toString("latin1");
  return [...text.matchAll(/<< \/Length (\d+) >>\nstream\n/g)].map((m) => {
    const at = (m.index ?? 0) + m[0].length;
    const ops = text.slice(at, at + Number(m[1]));
    return {
      lines: [...ops.matchAll(/BT \/(F\d) ([\d.]+) Tf (?:[\d.-]+ Tc )?[\d. ]+ rg ([\d.-]+) ([\d.-]+) Td \(((?:[^()\\]|\\.)*)\) Tj ET/g)]
        .map((t) => ({ font: t[1], size: +t[2], x: +t[3], y: +t[4], s: unescaped(t[5]) })),
      images: [...ops.matchAll(/q ([\d.]+) 0 0 ([\d.]+) ([\d.-]+) ([\d.-]+) cm \/Im\d+ Do Q/g)].map((t) => ({ w: +t[1], h: +t[2], x: +t[3], y: +t[4] })),
      qr: [...ops.matchAll(/\n0 g ([\d.]+) ([\d.]+) ([\d.]+) ([\d.]+) re f/g)].map((t) => ({ x: +t[1], y: +t[2], w: +t[3], h: +t[4] })),
    };
  });
}
type Drawn = ReturnType<typeof pagesOf>[number];
/** the height a line of text takes about its baseline, a little generously: its descenders under it, its ascenders over */
const band = (l: { y: number; size: number }) => ({ low: l.y - 0.22 * l.size, high: l.y + 0.75 * l.size });

/** a page's parts: the footer (top line first), the signatory's lines, the signature, the QR, and all else (the notes and above) */
function partsOf(pg: Drawn) {
  const foot = pg.lines.filter((l) => l.font === "F1" && l.size === 7.5).sort((x, y) => y.y - x.y);
  const signatory = pg.lines.filter((l) => l.x === MARGIN && l.size === 10.5 && [SIGNATORY, TITLE, "For: Registrar"].includes(l.s));
  const signature = pg.images.filter((i) => i.x === MARGIN && i.w <= 140.01 && i.h <= 48.01);
  const rest = [
    ...pg.lines.filter((l) => !foot.includes(l) && !signatory.includes(l)).map(band),
    ...pg.images.filter((i) => !signature.includes(i)).map((i) => ({ low: i.y, high: i.y + i.h })),
  ];
  return { foot, signatory, signature, rest, footTop: Math.max(...foot.map((l) => band(l).high)), restLow: Math.min(...rest.map((r) => r.low)) };
}

test("the footer, the signatory's block and the QR never meet, nor the notes the block, and nothing leaves the page — every body, every footer", () => {
  let closer = 0;
  for (const body of ["CCE, passport, programme changed, 1000 characters of notes", "166 short notes"]) assert.ok(BODIES[body].remarks.join("\n").length <= 1000, `${body}: within what the API takes`);
  for (const [body, b] of Object.entries(BODIES)) {
    for (const origin of ORIGINS) for (const footer of FOOTERS) for (const [number, version, code] of NUMBERS) {
      const what = `${body} / ${origin.slice(8, 40)} / ${footer ? `${footer.length}-character` : "no"} footer / ${number}`;
      const pages = pagesOf(realLetter({ statement: b.statement, remarks: b.remarks, origin, footer, number, version, code }));
      const notes: string[] = [];
      pages.forEach((pg, k) => {
        const where = `${what}, page ${k + 1} of ${pages.length}`;
        const { foot, signatory, signature, rest, footTop, restLow } = partsOf(pg);
        // the footer on every page: inside the margins, above the page's foot, the verifying address whole
        assert.ok(foot.length >= 1, `${where}: the footer`);
        for (const l of foot) {
          assert.equal(l.x, MARGIN, where);
          assert.ok(l.x + textWidth(l.s, 7.5) <= A4.w - MARGIN + 0.01, `${where}: "${l.s}" past the right margin`);
          assert.ok(l.y >= 18, `${where}: "${l.s}" at ${l.y} pt, under the page's foot`);
        }
        assert.ok(squash(foot.map((l) => l.s).join("")).includes(squash(`verify at ${origin}/verify/document`)), `${where}: the address whole`);
        // nothing off the page
        for (const r of [...rest, ...signatory.map(band), ...signature.map((i) => ({ low: i.y, high: i.y + i.h }))]) assert.ok(r.low >= 0 && r.high <= A4.h, `${where}: ${r.low}-${r.high} off the page`);
        notes.push(...pg.lines.filter((l) => l.x === MARGIN + 30).map((l) => l.s));
        if (k < pages.length - 1) {
          // a page the notes go on from: no signatory and no QR, the notes over the footer
          assert.equal(signatory.length + signature.length + pg.qr.length, 0, `${where}: the block only on the last page`);
          assert.ok(restLow - footTop >= 4, `${where}: the notes (down to ${restLow.toFixed(1)}) over the footer (${footTop.toFixed(1)})`);
          return;
        }
        // the last page: the signatory's three lines, the signature over the name, the QR beside them
        assert.deepEqual(signatory.map((l) => l.s), [SIGNATORY, TITLE, "For: Registrar"], where);
        assert.equal(signature.length, 1, `${where}: the signature`);
        assert.ok(pg.qr.length > 0, `${where}: the QR`);
        const qrLow = Math.min(...pg.qr.map((c) => c.y)), qrHigh = Math.max(...pg.qr.map((c) => c.y + c.h));
        const lastLine = signatory[signatory.length - 1];
        const blockLow = Math.min(qrLow, ...signatory.map((l) => band(l).low));
        const blockHigh = Math.max(qrHigh, ...signatory.map((l) => band(l).high), ...signature.map((i) => i.y + i.h));
        // the footer's top line 16 pt under the signatory's last line and 20 pt under the QR's foot: clear of both
        assert.ok(foot[0].y <= lastLine.y - 16 + 0.01, `${where}: the footer's top line at ${foot[0].y} pt, "${lastLine.s}" at ${lastLine.y} pt`);
        assert.ok(foot[0].y <= qrLow - 20 + 0.01, `${where}: the footer's top line at ${foot[0].y} pt, the QR's foot at ${qrLow} pt`);
        assert.ok(blockLow - footTop >= 2, `${where}: the block's foot (${blockLow.toFixed(1)}) over the footer's top (${footTop.toFixed(1)})`);
        // the notes, and all above them, over the block's top (the signature's and the QR's)
        assert.ok(restLow - blockHigh >= 4, `${where}: the notes (down to ${restLow.toFixed(1)}) over the block (up to ${blockHigh.toFixed(1)})`);
      });
      // every note printed once, in order, whatever the pages
      assert.equal(squash(notes.join("")), squash(b.remarks.map(fill).join("")), `${what}: the notes`);
      // one page for every body a template's notes can make with the University's addresses and a footer of a line or none
      const ordinary = ORIGINS.indexOf(origin) < 3 && (footer === null || footer.length < 100);
      if (body === "166 short notes") assert.ok(pages.length > 1, `${what}: on to a second page`);
      else if (ordinary) assert.equal(pages.length, 1, `${what}: one page`);
      // set at the Registry's own spacing (20 pt between COURSE and PROGRAMME) whenever that fits, closer only when it does not
      const kv = (s: string) => pages[0].lines.find((l) => l.s === s && l.font === "F3")?.y ?? NaN;
      const step = kv("COURSE:") - kv("PROGRAMME:");
      if (body === "six notes" && ordinary) assert.equal(step, 20, `${what}: the Registry's spacing`);
      if (step < 20) closer++;
      assert.ok(step >= 14 && step <= 20, `${what}: a step of ${step} pt`);
    }
  }
  assert.ok(closer > 0, "a long body is set closer to stay on its page");
});

test("a CCE letter with a change of programme, its real number and code: the footer stays under For: Registrar (the review's case)", () => {
  const pages = pagesOf(realLetter({ statement: { ...CCE, changedFrom: "B.Sc. MATHEMATICS", changedTo: "B.Sc. COMPUTER SCIENCE", changedOn: "2026-02-01" }, remarks: DEFAULT_NOTES,
    origin: "https://portal.moaum.edu.ng", footer: null, number: "ADM/2026/000123", version: 2, code: "7Q2KX-M9P4T-ZB8RC-W3N6H-JY5DF" }));
  assert.equal(pages.length, 1);
  const { foot, signatory, footTop } = partsOf(pages[0]);
  const forRegistrar = signatory.find((l) => l.s === "For: Registrar");
  assert.ok(forRegistrar);
  assert.ok(forRegistrar.y < 88, `the notes brought the block down (For: Registrar at ${forRegistrar.y} pt)`);
  assert.equal(foot.length, 2, "the real number and code take the address to a second line");
  assert.equal(foot[0].y, forRegistrar.y - 16, "the footer's top line 16 pt under For: Registrar");
  assert.ok(band(forRegistrar).low - footTop >= 2);
  assert.ok(foot[1].y >= 18);
});

test("a footer of many lines raises the signatory's block rather than run under it or off the page", () => {
  const pages = pagesOf(realLetter({ statement: {}, remarks: DEFAULT_NOTES, origin: LONG[2], footer: FOOTERS[2], number: NUMBERS[1][0], version: NUMBERS[1][1], code: NUMBERS[1][2] }));
  assert.equal(pages.length, 1);
  const { foot, signatory, footTop } = partsOf(pages[0]);
  assert.ok(signatory[0].y > 118, `the name raised from 118 pt to ${signatory[0].y} pt`);
  assert.equal(foot[foot.length - 1].y, 18, "the footer down to the page's foot");
  assert.equal(foot[0].y, signatory[2].y - 16, "its top line 16 pt under For: Registrar");
  assert.ok(band(signatory[2]).low - footTop >= 2);
});

test("notes too long for a page go on to the next at the Registry's spacing: the block and the QR after them, the footer on every page", () => {
  const remarks = BODIES["166 short notes"].remarks;
  const pages = pagesOf(realLetter({ statement: {}, remarks, origin: ORIGINS[0], footer: null, number: NUMBERS[0][0], version: NUMBERS[0][1], code: NUMBERS[0][2] }));
  assert.ok(pages.length >= 3, `${pages.length} pages`);
  // the University's heading on the first page only; the notes numbered on from page to page
  assert.equal(pages.filter((pg) => pg.lines.some((l) => l.s === "APPLICANT'S NAME:")).length, 1);
  assert.ok(pages[0].lines.some((l) => l.s === "APPLICANT'S NAME:"));
  const numbers = pages.flatMap((pg) => pg.lines.filter((l) => l.x === MARGIN + 14).map((l) => l.s));
  assert.deepEqual(numbers, remarks.map((_, i) => `${i + 1}.`));
  for (const pg of pages) for (const l of pg.lines.filter((x) => x.x === MARGIN + 30)) assert.ok(l.y >= 44 + 20, `a note at ${l.y} pt, over the footer`);
  // each page's notes 14.175 pt apart: the Registry's own leading
  const first = pages[0].lines.filter((l) => l.x === MARGIN + 30);
  assert.ok(Math.abs(first[0].y - first[1].y - 14.175) < 0.01);
  assert.ok(pages.slice(0, -1).every((pg) => pg.qr.length === 0 && pg.images.length <= 2) && pages[pages.length - 1].qr.length > 0);
});

test("linesWithin keeps each part whole where it fits, breaks an address at its dots and slashes, and drops nothing", () => {
  const W = A4.w - 2 * MARGIN;
  const parts = ["Document no MOAUM/ADM/26/000123", "version 1", "verification code ABCD-EFGH-IJKL", `verify at ${LONG[2]}/verify/document`];
  const lines = linesWithin(parts, W, 7.5);
  for (const l of lines) assert.ok(textWidth(l, 7.5) <= W, l);
  assert.equal(squash(lines.join("")), squash(parts.join("")));
  assert.equal(lines[0], "Document no MOAUM/ADM/26/000123 · version 1 · verification code ABCD-EFGH-IJKL");
  assert.ok(lines.slice(1, -1).every((l) => /[./-]$/.test(l)), "each break after a dot, a slash or a hyphen");
  // a short set is one line, joined as before
  assert.deepEqual(linesWithin(["a", "b", "", "c"], W, 7.5), ["a · b · c"]);
  // a word with nowhere to break is cut where the width ends, never past it
  const solid = linesWithin(["x".repeat(400)], 100, 7.5);
  assert.ok(solid.length > 1 && solid.every((l) => textWidth(l, 7.5) <= 100));
  assert.equal(solid.join(""), "x".repeat(400));
  assert.deepEqual(linesWithin([], W, 7.5), []);
});

test("dates read as the Registry writes them", () => {
  assert.equal(longDate("2026-01-05"), "5th January, 2026");
  assert.equal(longDate("2026-03-22"), "22nd March, 2026");
  assert.equal(longDate("2026-11-13"), "13th November, 2026");
  assert.equal(longDate(null), "");
});
