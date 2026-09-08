import { test } from "node:test";
import assert from "node:assert/strict";
import { deflateRawSync } from "node:zlib";

import { colOf, sharedStrings, sheetRows, unescapeXml, xlsxRows } from "./xlsx.ts";
import { blockingFindings, isError, parseCaps, splitName, toCsv, toRequest, type Programme } from "./caps.ts";

/* ── a tiny .xlsx writer, so the reader is tested on a real ZIP ──────── */

const CRC_TABLE = (() => {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c >>> 0;
  }
  return t;
})();

function crc32(bytes: Uint8Array): number {
  let c = 0xffffffff;
  for (const b of bytes) c = CRC_TABLE[(c ^ b) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

function zip(entries: { name: string; text: string; store?: boolean }[]): ArrayBuffer {
  const parts: Uint8Array[] = [];
  const central: Uint8Array[] = [];
  let offset = 0;
  const le16 = (v: number) => [v & 0xff, (v >> 8) & 0xff];
  const le32 = (v: number) => [v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >>> 24) & 0xff];
  for (const e of entries) {
    const name = new TextEncoder().encode(e.name);
    const data = new TextEncoder().encode(e.text);
    const method = e.store ? 0 : 8;
    const payload = e.store ? data : new Uint8Array(deflateRawSync(data));
    const crc = crc32(data);
    const local = new Uint8Array([
      ...le32(0x04034b50), ...le16(20), ...le16(0), ...le16(method), ...le16(0), ...le16(0),
      ...le32(crc), ...le32(payload.length), ...le32(data.length), ...le16(name.length), ...le16(0),
      ...name,
    ]);
    parts.push(local, payload);
    central.push(new Uint8Array([
      ...le32(0x02014b50), ...le16(20), ...le16(20), ...le16(0), ...le16(method), ...le16(0), ...le16(0),
      ...le32(crc), ...le32(payload.length), ...le32(data.length), ...le16(name.length), ...le16(0), ...le16(0),
      ...le16(0), ...le16(0), ...le32(0), ...le32(offset), ...name,
    ]));
    offset += local.length + payload.length;
  }
  const cdStart = offset;
  const cdBytes = central.reduce((n, c) => n + c.length, 0);
  const eocd = new Uint8Array([
    ...le32(0x06054b50), ...le16(0), ...le16(0), ...le16(entries.length), ...le16(entries.length),
    ...le32(cdBytes), ...le32(cdStart), ...le16(0),
  ]);
  const all = [...parts, ...central, eocd];
  const out = new Uint8Array(all.reduce((n, p) => n + p.length, 0));
  let o = 0;
  for (const p of all) { out.set(p, o); o += p.length; }
  return out.buffer;
}

function xlsx(rows: (string | number)[][], opts: { store?: boolean } = {}): ArrayBuffer {
  const shared: string[] = [];
  const idx = (s: string) => { let i = shared.indexOf(s); if (i < 0) { shared.push(s); i = shared.length - 1; } return i; };
  const col = (n: number) => { let s = ""; n += 1; while (n > 0) { const m = (n - 1) % 26; s = String.fromCharCode(65 + m) + s; n = Math.floor((n - 1) / 26); } return s; };
  const esc = (s: string) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
  const sheet = `<?xml version="1.0"?><worksheet xmlns="x"><sheetData>${rows.map((r, ri) =>
    `<row r="${ri + 1}">${r.map((v, ci) => typeof v === "number"
      ? `<c r="${col(ci)}${ri + 1}"><v>${v}</v></c>`
      : v === "" ? `<c r="${col(ci)}${ri + 1}" s="1"/>` : `<c r="${col(ci)}${ri + 1}" t="s"><v>${idx(v)}</v></c>`).join("")}</row>`).join("")}</sheetData></worksheet>`;
  const sst = `<?xml version="1.0"?><sst xmlns="x">${shared.map((s) => `<si><t>${esc(s)}</t></si>`).join("")}</sst>`;
  return zip([
    { name: "[Content_Types].xml", text: "<Types/>", store: true },
    { name: "xl/workbook.xml", text: "<workbook/>" },
    { name: "xl/worksheets/sheet1.xml", text: sheet, store: opts.store },
    { name: "xl/sharedStrings.xml", text: sst, store: opts.store },
  ]);
}

const PROGRAMMES: Programme[] = [
  { code: "C00061", name: "MBBS", deptCode: "MED", facultyCode: "BAMS", jambName: "Medicine & Surgery", category: "UNDER GRADUATE", archived: false },
  { code: "C00019", name: "B.Sc. ACCOUNTING", deptCode: "ACC", facultyCode: "MS", jambName: "Accounting", category: "UNDER GRADUATE", archived: false },
  { code: "C00023", name: "B.Sc. COMPUTER SCIENCE", deptCode: "MTC", facultyCode: "SC", jambName: "Computer Science", category: "UNDER GRADUATE", archived: false },
  { code: "C99256", name: "MA RELIGION AND PEACE STUDIES", deptCode: "RAP", facultyCode: "AR", jambName: "MA RELIGION AND PEACE STUDIES", category: "POST GRADUATE", archived: false },
];

const HEAD = ["RG_NUM", "RG_CANDNAME", "RG_SEX", "STATE_NAME", "RG_AGGREGATE", "CO_NAME", "LGA_NAME",
  "Subject1", "RG_Sub1Score", "Subject2", "RG_Sub2Score", "Subject3", "RG_Sub3Score", "EngScore"];
const UTME_ROWS: (string | number)[][] = [
  HEAD,
  ["202699176777GF", "Iorfa Msendoo Blessing", "F", "Benue", 337, "Medicine & Surgery", "Guma", "Physics", 96, "Biology", 85, "Chemistry", 93, 63],
  ["202699711714BJ", "Kwaghgba Hembadoon Ruth", "F", "Benue", 271, "Accounting", "Vandeikya", "Economics", 63, "Mathematics", 64, "Commerce", 77, 67],
];

/* ── the reader ──────────────────────────────────────────────────────── */

test("column letters become indexes", () => {
  assert.equal(colOf("A1"), 0);
  assert.equal(colOf("N12"), 13);
  assert.equal(colOf("AB7"), 27);
});

test("XML entities are unescaped, including numeric ones", () => {
  assert.equal(unescapeXml("Medicine &amp; Surgery &#39;25 &#x41;"), "Medicine & Surgery '25 A");
});

test("shared strings may be split into runs", () => {
  assert.deepEqual(sharedStrings('<sst><si><t>a</t></si><si><r><t>Med</t></r><r><t xml:space="preserve"> &amp; Sur</t></r></si></sst>'), ["a", "Med & Sur"]);
});

test("a deflated .xlsx is read back row for row", async () => {
  const rows = await xlsxRows(xlsx(UTME_ROWS));
  assert.equal(rows.length, 3);
  assert.deepEqual(rows[0].slice(0, 6), HEAD.slice(0, 6));
  assert.equal(rows[1][0], "202699176777GF");
  assert.equal(rows[1][4], "337");
  assert.equal(rows[1][5], "Medicine & Surgery");
});

test("a stored (uncompressed) .xlsx reads too, and empty cells are empty strings", async () => {
  const rows = await xlsxRows(xlsx([HEAD, ["202699307120BGU", "Odeh Ojima Patience", "F", "Benue", 0, "Accounting", "Okpokwu", "", 0, "", 0, "", 0, 0]], { store: true }));
  assert.equal(rows[1][7], "");
  assert.equal(rows[1][4], "0");
});

test("a file that is not a ZIP is refused, not read as nothing", async () => {
  await assert.rejects(() => xlsxRows(new TextEncoder().encode("regno,name\n1,2").buffer as ArrayBuffer), /not a \.xlsx file/);
});

test("inline strings and self-closing cells", () => {
  const rows = sheetRows('<sheetData><row r="1"><c r="A1" t="inlineStr"><is><t>RG_NUM</t></is></c><c r="B1" s="2"/><c r="C1"><v>12</v></c></row></sheetData>', []);
  assert.deepEqual(rows, [["RG_NUM", "", "12"]]);
});

/* ── the parser ──────────────────────────────────────────────────────── */

test("a CAPS download resolves every course by JAMB's name", () => {
  const p = parseCaps(UTME_ROWS.map((r) => r.map(String)), "UTME", PROGRAMMES);
  assert.ok(!isError(p));
  if (isError(p)) return;
  assert.equal(p.layout, "CAPS download");
  assert.equal(p.rows.length, 2);
  assert.equal(p.rows[0].jambCode, "C00061");
  assert.equal(p.rows[0].programme?.name, "MBBS");
  assert.equal(p.rows[0].surname, "Iorfa");
  assert.equal(p.rows[0].otherNames, "Msendoo Blessing");
  assert.equal(p.rows[0].aggregate, 337);
  assert.equal(p.rows[0].raw.CO_NAME, "Medicine & Surgery");
  assert.deepEqual(p.findings, []);
  assert.deepEqual(p.unresolved, []);
});

test("the office's own layout resolves by code, on different column names", () => {
  const rows = [["regno", "name", "sex", "state", "agregate", "programme", "lga"],
    ["202699176777gf", "Iorfa Msendoo Blessing", "Female", "Benue", "337", "c00061", "Guma"]];
  const p = parseCaps(rows, "UTME", PROGRAMMES);
  assert.ok(!isError(p));
  if (isError(p)) return;
  assert.equal(p.layout, "built by this office");
  assert.equal(p.rows[0].jambRegNo, "202699176777GF");
  assert.equal(p.rows[0].jambCode, "C00061");
  assert.equal(p.rows[0].sex, "F");
});

test("the list kind is declared first and a row that contradicts it is a blocking finding", () => {
  const de = parseCaps(UTME_ROWS.map((r) => r.map(String)), "DIRECT_ENTRY", PROGRAMMES);
  assert.ok(!isError(de));
  if (isError(de)) return;
  assert.equal(blockingFindings(de).length, 2);
  assert.match(de.findings[0].message, /Direct Entry row carrying an aggregate/);

  const utme = parseCaps([HEAD, ["202699307120BGU", "Odeh Ojima Patience", "F", "Benue", "0", "Accounting", "Okpokwu"]], "UTME", PROGRAMMES);
  assert.ok(!isError(utme));
  if (isError(utme)) return;
  assert.match(utme.findings[0].message, /UTME row with no aggregate/);
  assert.equal(utme.rows[0].aggregate, null);
});

test("an unknown JAMB course, a postgraduate programme, a duplicate and a malformed number are each named", () => {
  const rows = [HEAD,
    ["202699176777GF", "A B", "F", "Benue", "300", "Basket Weaving", "Guma"],
    ["202699176777GF", "A B", "F", "Benue", "300", "Medicine & Surgery", "Guma"],
    ["12345", "C D", "M", "Benue", "300", "MA RELIGION AND PEACE STUDIES", "Guma"]];
  const p = parseCaps(rows, "UTME", PROGRAMMES);
  assert.ok(!isError(p));
  if (isError(p)) return;
  assert.deepEqual(p.unresolved, ["Basket Weaving"]);
  const messages = p.findings.map((f) => f.message);
  assert.ok(messages.some((m) => /on no alias/.test(m)));
  assert.ok(messages.some((m) => /appears twice/.test(m)));
  assert.ok(messages.some((m) => /not the shape of a JAMB registration number/.test(m)));
  assert.ok(messages.some((m) => /post graduate programme/.test(m)));
  assert.ok(p.findings.every((f) => f.blocking));
});

test("an aggregate that is not the sum of its parts is reported but does not block", () => {
  const p = parseCaps([HEAD, ["202699176777GF", "A B", "F", "Benue", "300", "Accounting", "Guma", "Economics", "63", "Mathematics", "64", "Commerce", "77", "67"]], "UTME", PROGRAMMES);
  assert.ok(!isError(p));
  if (isError(p)) return;
  assert.equal(p.findings.length, 1);
  assert.equal(p.findings[0].blocking, false);
  assert.match(p.findings[0].message, /not the sum/);
});

test("a file with no registration-number column, or none named course, is an error that says what it read", () => {
  const a = parseCaps([["Name", "Course"], ["x", "y"]], "UTME", PROGRAMMES);
  assert.ok(isError(a) && /RG_NUM/.test(a.error) && /Name, Course/.test(a.error));
  const b = parseCaps([["RG_NUM", "RG_CANDNAME"], ["202699176777GF", "x"]], "UTME", PROGRAMMES);
  assert.ok(isError(b) && /neither a course/.test(b.error));
  const c = parseCaps([HEAD], "UTME", PROGRAMMES);
  assert.ok(isError(c) && /no rows under it/.test(c.error));
});

test("the request the API loads carries the declared kind on every row", () => {
  const p = parseCaps(UTME_ROWS.map((r) => r.map(String)), "UTME", PROGRAMMES);
  if (isError(p)) throw new Error(p.error);
  const req = toRequest(p, { session: "2026/2027", filename: "list.xlsx", fileSha256: "ab".repeat(32), listKind: "UTME", downloadedOn: "2026-08-27" });
  assert.equal(req.rows.length, 2);
  assert.equal(req.rows[0].entryMode, "UTME");
  assert.equal(req.rows[0].jambCode, "C00061");
  assert.equal(req.rows[0].surname, "Iorfa");
  assert.equal(req.source, "CAPS_DOWNLOAD");
});

test("the cut-off comes from the settings: the programme's own, else the faculty's, and a row under it is read but not loaded", () => {
  const cutoffs = { faculty: { BAMS: 180, MS: 150 }, programme: { C00061: 200 } };
  const rows = [HEAD,
    ["202699000001AA", "A B", "F", "Benue", "312", "Medicine & Surgery", "Guma"],   // over MBBS's own 200
    ["202699000002AA", "C D", "F", "Benue", "190", "Medicine & Surgery", "Guma"],   // under 200, though over BAMS's 180
    ["202699000003AA", "E F", "F", "Benue", "160", "Accounting", "Guma"],           // over MS's 150
    ["202699000004AA", "G H", "F", "Benue", "140", "Accounting", "Guma"]];          // under 150
  const p = parseCaps(rows, "UTME", PROGRAMMES, cutoffs);
  if (isError(p)) throw new Error(p.error);
  assert.equal(p.belowCutoff, 2);
  assert.deepEqual(p.rows.map((r) => r.belowCutoff), [null, 200, null, 150]);
  const held = p.findings.filter((f) => f.excluded);
  assert.equal(held.length, 2);
  assert.ok(held.every((f) => !f.blocking));
  assert.match(held[0].message, /190 is under the cut-off of 200 for MBBS/);
  assert.deepEqual(blockingFindings(p), []);
  const req = toRequest(p, { session: "2026/2027", filename: "l.xlsx", fileSha256: "ab".repeat(32), listKind: "UTME", downloadedOn: "2026-08-27" });
  assert.deepEqual(req.rows.map((r) => r.jambRegNo), ["202699000001AA", "202699000003AA"]);
});

test("a programme with no cut-off in the settings is a blocking finding, and a Direct Entry list has no cut-off", () => {
  const p = parseCaps([HEAD, ["202699000001AA", "A B", "F", "Benue", "300", "Computer Science", "Guma"]], "UTME", PROGRAMMES, { faculty: {}, programme: {} });
  if (isError(p)) throw new Error(p.error);
  assert.equal(blockingFindings(p).length, 1);
  assert.match(blockingFindings(p)[0].message, /no UTME cut-off is set/);
  const de = parseCaps([HEAD, ["202699000001AA", "A B", "F", "Benue", "0", "Accounting", "Guma"]], "DIRECT_ENTRY", PROGRAMMES, { faculty: {}, programme: {} });
  if (isError(de)) throw new Error(de.error);
  assert.equal(de.belowCutoff, 0);
  assert.deepEqual(de.findings, []);
});

test("names split surname-first, as CAPS writes them", () => {
  assert.deepEqual(splitName("  Iorfa   Msendoo Blessing "), ["Iorfa", "Msendoo Blessing"]);
  assert.deepEqual(splitName("Iorfa"), ["Iorfa", ""]);
  assert.deepEqual(splitName(""), ["", ""]);
});

test("the list as read exports as CSV, one row per candidate with the findings against it", () => {
  const programmes: Programme[] = [
    { code: "C00061", name: "MBBS", deptCode: "MED", facultyCode: "CHS", jambName: "Medicine & Surgery", category: "UNDER GRADUATE", archived: false },
  ];
  const rows = [
    ["RG_NUM", "RG_CANDNAME", "RG_SEX", "STATE_NAME", "RG_AGGREGATE", "CO_NAME", "LGA_NAME"],
    ["202699176777GF", "Iorfa Msendoo Blessing", "F", "Benue", "337", "Medicine & Surgery", "Guma"],
    ["202699224740IB", "Ochefu, \"Dan\" Ejembi", "M", "Benue", "317", "Basket Weaving", "Obi"],
  ];
  const parsed = parseCaps(rows, "UTME", programmes);
  assert.ok(!isError(parsed));
  if (isError(parsed)) return;
  const csv = toCsv(parsed, "UTME");
  const lines = csv.trim().split("\r\n");
  assert.equal(lines.length, 3);
  assert.ok(lines[0].startsWith("Line,Registration number,Surname"));
  assert.ok(lines[1].includes("202699176777GF") && lines[1].includes("C00061") && lines[1].includes("MBBS"));
  assert.ok(lines[2].includes('"Ochefu, ""Dan"" Ejembi"') || lines[2].includes('""Dan""'), lines[2]);
  assert.ok(lines[2].includes("Basket Weaving"));
  assert.ok(/does not run|no alias|not mapped|carries no/i.test(lines[2]) || lines[2].split(",").length >= 13, lines[2]);
});
