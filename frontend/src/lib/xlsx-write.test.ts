import { test } from "node:test";
import assert from "node:assert/strict";
import { STYLES_XML, colName, crc32, sheetXml, styleExtras, stylesXml, xlsx, zipStored, type Cell, type SheetOpts, type SheetSpec } from "./xlsx-write.ts";
import { zipEntries } from "./xlsx.ts";

test("columns are lettered the way a spreadsheet letters them", () => {
  assert.equal(colName(0), "A");
  assert.equal(colName(25), "Z");
  assert.equal(colName(26), "AA");
  assert.equal(colName(36), "AK");
});

test("a sheet writes strings inline and numbers as values, styled and bordered", () => {
  const x = sheetXml([["SN", "REG_NO", "UTME SCORE"], [1, "202699176777GF", 287], [2, "", null]]);
  // heading row carries the bold header style (s=1); body carries the bordered style (s=2)
  assert.ok(x.includes('<c r="A1" s="1" t="inlineStr"><is><t xml:space="preserve">SN</t></is></c>'));
  assert.ok(x.includes('<c r="C2" s="2"><v>287</v></c>'));
  // empty cells within a row are emitted so the grid stays complete; data rows stripe (s=2 then s=7)
  assert.ok(x.includes('<row r="3"><c r="A3" s="7"><v>2</v></c><c r="B3" s="7"/><c r="C3" s="7"/></row>'));
  // column widths are declared so each column fits its data
  assert.ok(x.includes("<cols>") && x.includes('customWidth="1"'));
  assert.ok(x.includes("&amp;") === false);
  assert.ok(sheetXml([["A & B"]]).includes("A &amp; B"));
});

test("the crc is the standard one", () => {
  assert.equal(crc32(new TextEncoder().encode("123456789")), 0xcbf43926);
});

test("the zip is a stored zip with every entry in the central directory", () => {
  const z = zipStored([["a.txt", "hello"], ["dir/b.xml", "<x/>"]]);
  assert.deepEqual([...z.slice(0, 4)], [0x50, 0x4b, 0x03, 0x04]);
  const end = z.slice(z.length - 22);
  assert.deepEqual([...end.slice(0, 4)], [0x50, 0x4b, 0x05, 0x06]);
  assert.equal(end[10] | (end[11] << 8), 2);
  const text = new TextDecoder("latin1").decode(z);
  assert.ok(text.includes("a.txt") && text.includes("dir/b.xml") && text.includes("hello"));
});

test("a workbook names its sheets in order", () => {
  const w = xlsx([["Admission_Summary", [["SN", "ITEM", "COUNT"]]], ["Merit_List", [["SN"]]]]);
  const text = new TextDecoder("latin1").decode(w);
  assert.ok(text.indexOf('name="Admission_Summary" sheetId="1"') < text.indexOf('name="Merit_List" sheetId="2"'));
  assert.ok(text.includes("xl/worksheets/sheet2.xml"));
});

// V773: the writer gained options of its own (cell fills, header block fills, widths, no stripe, frozen columns, a stated
// letterhead); a workbook that asks for none of them must come out byte for byte as it did before — every existing caller's file
// (JAMB's UTME and Direct Entry returns, the allocation and migration templates, the staff roll…). Pinned with the writer as it
// stood before V773.
/** a 1×1 PNG, for the crest */
const PNG1 = new Uint8Array(Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==", "base64"));
const LOGO = { png: PNG1, w: 1, h: 1 };
/** F1: the two-sheet fixture above */
const F1: SheetSpec[] = [["Admission_Summary", [["SN", "ITEM", "COUNT"]]], ["Merit_List", [["SN"]]]];
/** F2: one sheet with every option the writer had, a hidden sheet beside it, and the crest */
const F2: SheetSpec[] = [
  ["Course Allocation", [
    [null, "THE UNIVERSITY & ITS <SCHOOL>"], [null, "A \"quoted\" title"], [null, "As at 15 November 2026"], [], [],
    ["S/N", "Code", "Title", "Units", "Lecturer", "Hidden id", "Date of birth"],
    ["", "Section", "", "", "", "", ""],
    [1, "CSC 301", "Data Structures\nand Algorithms", 3, "DOE, John — STF/0012", "c1", "12/09/2003"],
    [2, "CSC 303", "Database Systems", 3, null, "c2", ""],
    [],
    [null, "SECTION BAND"],
    ["SN", "A", "B"],
    [3, "x", 0.5, -2, 1e21, "", undefined],
    [null, "TOTAL", 6],
  ], {
    headerRows: [6], merges: ["A1:B1", "B12:C12"], centre: [0, 3], hiddenCols: [5], freezeBelow: 6, textCols: [6],
    validations: [{ sqref: "E8:E40", range: "'Lecturers'!$C$2:$C$3", prompt: "Choose the lecturer" }, { sqref: "D8:D40", list: ["1", "2", "3"] }],
    protect: { unlocked: [{ cols: [4], fromRow: 7, toRow: 8 }, { cols: [6] }] },
  }],
  ["Lecturers", [["SN", "Name", "Choice"], [1, "DOE, John", "DOE, John — STF/0012"]], { hidden: true }],
];
/** F3: the shape of JAMB's returns (UTME and Direct Entry): the letterhead in the seven rows above "SN", the summary, a section
 *  band, a second table, a total row, the ranked sheet's rows striped — with the crest on each sheet */
const F3: SheetSpec[] = [
  ["Admission_Summary", [
    [null, "REV. FR. MOSES ORSHIO ADASU UNIVERSITY, MAKURDI"], [null, "9764/9765 DIRECT ENTRY MERIT ADMISSION SUMMARY FOR B.Sc. ACCOUNTING"],
    [null, "SUMMARY OF DIRECT ENTRY ADMISSION AS AT 2026-11-15"], [], [], [], [],
    ["SN", "ITEM", "COUNT"], [1, "Total Applicants", 9], [2, "Registered Applicants", 3], [3, "Qualified Cases", null],
    [], [null, "QUOTA DISTRIBUTION"], ["SN", "ADMISSION CRITERIA", "(%)", "QUOTA", "ADMITTED", "S/FALLS", "REMARK"],
    [1, "National Merit", 50, 1, "", 1, "0 of 1"],
    [], [null, "NATIONAL/STATE/LOCAL GOVERNMENT ANALYSIS"], ["SN", "LGA NAME", "ELG", "SM", "NM", "TOTAL"], [1, "Makurdi", 0, 0, 1, 1], [null, "TOTAL", 0, 0, 1, 1],
    [], [null, "RANKING"], [null, "By the points of the qualification that counts: ties by name."],
  ]],
  ["Ranked_sheet", [
    [null, "REV. FR. MOSES ORSHIO ADASU UNIVERSITY, MAKURDI"], [null, "9764/9765 DIRECT ENTRY MERIT ADMISSION SUMMARY"], [null, "RANKED SHEET AS AT 2026-11-15"], [], [], [], [],
    ["SN", "RANK", "REG_NO", "NAME", "DE POINTS", "GENERAL REMARKS", "DE REMARKS"],
    [1, 1, "29764000001", "CHECKV764 D2", 14, "National Merit", "Qualified"],
    [2, 2, "29764000002", "CHECKV764 D1", 12, "Waiting list", "Qualified"],
    [3, 3, "29764000003", "CHECKV764 D3", null, "O'Level result not uploaded", "O'Level result not uploaded"],
  ]],
];

test("V773: a workbook asking for none of the new options is byte for byte the workbook the writer made before them", () => {
  const pin = (w: Uint8Array) => [w.length, crc32(w)];
  assert.deepEqual(pin(xlsx(F1)), [7771, 3456309886], "F1");
  assert.deepEqual(pin(xlsx(F2, { logo: LOGO })), [16183, 334909888], "F2");
  assert.deepEqual(pin(xlsx(F2)), [11913, 1622264357], "F2 without the crest");
  assert.deepEqual(pin(xlsx(F3, { logo: LOGO })), [18466, 2194916481], "F3");
});

/** the text of one part of a stored workbook */
function part(w: Uint8Array, name: string): string {
  return new TextDecoder().decode(zipEntries(w.slice().buffer as ArrayBuffer)[name].bytes);
}

test("V773: the style table is the old one exactly until a sheet asks for more, and grows only at its end", () => {
  assert.equal(stylesXml([]), STYLES_XML);
  assert.equal(part(xlsx(F1), "xl/styles.xml"), STYLES_XML);
  assert.deepEqual(styleExtras([{}, { centre: [1] }]), []);
  // two fills: two fills of their own (5, 6) and two cell styles (15, 16), the old fourteen untouched
  const opts: SheetOpts = { fills: [{ r: 1, c: 1, fill: "e2efda" }, { r: 2, c: 1, fill: "F8CBAD", centre: true }, { r: 2, c: 2, fill: "E2EFDA" }] };
  assert.deepEqual(styleExtras([opts]), ["D|E2EFDA|0|0|0", "D|F8CBAD|0|1|0"]);
  const w = xlsx([["S", [["SN", "GRADE", "NOTE"], [1, "B3", "x"], [2, "F9", "y"]], opts]]);
  const styles = part(w, "xl/styles.xml");
  assert.ok(styles.startsWith(STYLES_XML.slice(0, STYLES_XML.indexOf("<fonts"))));
  assert.ok(styles.includes('<fonts count="6">'), "no bold cell, no new font");
  assert.ok(styles.includes('<fills count="7">'));
  assert.ok(styles.includes('<fill><patternFill patternType="solid"><fgColor rgb="FFE2EFDA"/><bgColor indexed="64"/></patternFill></fill><fill><patternFill patternType="solid"><fgColor rgb="FFF8CBAD"/><bgColor indexed="64"/></patternFill></fill></fills>'));
  assert.ok(styles.includes('<cellXfs count="17">'));
  assert.ok(styles.includes('<xf numFmtId="0" fontId="0" fillId="5" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment vertical="center" wrapText="1"/></xf>'));
  assert.ok(styles.includes('<xf numFmtId="0" fontId="0" fillId="6" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1"/></xf></cellXfs>'));
  const sheet = part(w, "xl/worksheets/sheet1.xml");
  assert.ok(sheet.includes('<c r="B2" s="15" t="inlineStr">'), "the first fill's style");
  assert.ok(sheet.includes('<c r="B3" s="16" t="inlineStr">'), "the second's");
  assert.ok(sheet.includes('<c r="C3" s="15" t="inlineStr">'), "the same look shares its style");
  assert.ok(sheet.includes('<c r="A3" s="7">'), "a cell without a fill keeps the stripe");
});

test("V773: a bold cell adds the bold font; a number shown with two decimals has a style of its own, with no fill", () => {
  const bold = stylesXml(styleExtras([{ fills: [{ r: 1, c: 0, fill: "D9E1F2", bold: true }] }]));
  assert.ok(bold.includes('<fonts count="7">'));
  assert.ok(bold.includes('<font><b/><sz val="11"/><name val="Calibri"/></font></fonts>'));
  assert.ok(bold.includes('<xf numFmtId="0" fontId="6" fillId="5" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1">'));
  const extras = styleExtras([{ fills: [{ r: 1, c: 1, fmt: "0.00", centre: true }] }]);
  assert.deepEqual(extras, ["D|-|0|1|2"]);
  const fmt = stylesXml(extras);
  assert.ok(fmt.includes('<fills count="5">'), "no colour, no fill");
  assert.ok(fmt.includes('<xf numFmtId="2" fontId="0" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyFont="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1"/></xf></cellXfs>'));
  const x = sheetXml([["SN", "SCORE"], [1, 62.5]], false, { fills: [{ r: 1, c: 1, fmt: "0.00", centre: true }] });
  assert.ok(x.includes('<c r="B2" s="15"><v>62.5</v></c>'), "the value stays a number");
});

test("V773: header blocks in their colours, widths stated, no stripe, frozen columns, and a letterhead stated", () => {
  const rows: Cell[][] = [["S/N", "REG NO.", "Name", "Qualification Type", "Grades"], [1, "29773000001", "ZZCHECK A", "JUPEB", "Biology: C"], [2, "29773000002", "ZZCHECK B", "JUPEB", "Biology: B"]];
  const opts: SheetOpts = { headerFills: [{ from: 0, to: 2, fill: "1F3864" }, { from: 3, to: 4, fill: "385723" }], widths: { 2: 28, 4: 34 }, stripe: false, centre: [0] };
  const extras = styleExtras([opts]);
  assert.deepEqual(extras, ["H|1F3864", "H|385723"]);
  const x = sheetXml(rows, false, opts);
  assert.ok(x.includes('<c r="A1" s="15" t="inlineStr">') && x.includes('<c r="C1" s="15" t="inlineStr">'), "the first block");
  assert.ok(x.includes('<c r="D1" s="16" t="inlineStr">') && x.includes('<c r="E1" s="16" t="inlineStr">'), "the second block");
  assert.ok(stylesXml(extras).includes('<xf numFmtId="0" fontId="1" fillId="6" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1"/></xf>'));
  assert.ok(x.includes('<col min="3" max="3" width="28" customWidth="1"/>') && x.includes('<col min="5" max="5" width="34" customWidth="1"/>'));
  assert.ok(x.includes('<col min="2" max="2" width="13" customWidth="1"/>'), "the others read off the data");
  assert.ok(x.includes('<c r="B3" s="2" t="inlineStr">') && x.includes('<c r="A3" s="8"><v>2</v></c>'), "the second data row unstriped");
  assert.ok(sheetXml(rows, false, { freezeCols: 3 }).includes('<sheetViews><sheetView workbookViewId="0"><pane xSplit="3" topLeftCell="D1" activePane="topRight" state="frozen"/></sheetView></sheetViews>'));
  assert.ok(sheetXml(rows, false, { freezeCols: 3, freezeBelow: 4 }).includes('<pane xSplit="3" ySplit="4" topLeftCell="D5" activePane="bottomRight" state="frozen"/>'));
  assert.ok(sheetXml(rows, false, { freezeBelow: 4 }).includes('<pane ySplit="4" topLeftCell="A5" activePane="bottomLeft" state="frozen"/>'));
  // a summary whose header row does not start with S/N: without letterheadRows the title is a section band
  const summary: Cell[][] = [["Summary: ZZ PROGRAMME"], ["As at 2026-11-15."], [], ["ITEM", "COUNT"], ["Total candidates", 3]];
  const plain = sheetXml(summary, false, { headerRows: [3] });
  assert.ok(plain.includes('<c r="A1" s="6" t="inlineStr">'), "today's rule: no letterhead");
  const stated = sheetXml(summary, false, { headerRows: [3], letterheadRows: 3 });
  assert.ok(stated.includes('<row r="1"><c r="A1" s="3" t="inlineStr">') && stated.includes('<row r="2"><c r="A2" s="4" t="inlineStr">'));
  assert.ok(stated.includes('<c r="A4" s="1" t="inlineStr">') && stated.includes('<c r="A5" s="2" t="inlineStr">'));
});
