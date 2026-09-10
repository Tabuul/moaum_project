import { test } from "node:test";
import assert from "node:assert/strict";
import { colName, crc32, sheetXml, xlsx, zipStored } from "./xlsx-write.ts";

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
  // empty cells within a row are now emitted (bordered) so the grid stays complete
  assert.ok(x.includes('<row r="3"><c r="A3" s="2"><v>2</v></c><c r="B3" s="2"/><c r="C3" s="2"/></row>'));
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
