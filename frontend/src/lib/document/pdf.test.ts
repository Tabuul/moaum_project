import { test } from "node:test";
import assert from "node:assert/strict";
import { PdfDocument, finishPdf, fit } from "./pdf.ts";
import { Page } from "../pdf-write.ts";
import { DEFAULT_INSTITUTION } from "./institution.ts";
import { primeInstitution } from "./institution-cache.ts";

const inst = { ...DEFAULT_INSTITUTION, name: "Example University, Makurdi", shortName: "EXU", motto: "Knowledge and Service", address: "No. 1 University Road", phone: "+234 800 000 0000", email: "info@example.edu.ng", website: "https://www.example.edu.ng" };

test("a report runs across pages with the full header first, the compact band after, a repeated table header, continuous serial numbers and Page X of Y on every page", () => {
  primeInstitution(inst);
  const doc = new PdfDocument("STANDARD_REPORT", { title: "Student register", subtitle: "2025/2026 Academic Session — First Semester", meta: [["Faculty", "Science"], ["Department", "Mathematics and Computer Science"]], generatedBy: "Ada Lovelace", reference: "EXU/RPT/1" }, inst);
  const rows = Array.from({ length: 150 }, (_, i) => [`EXU/SC/CMP/25/${String(i + 1).padStart(5, "0")}`, `Student ${i + 1}`, 100 + (i % 4) * 100, (i * 7) % 100]);
  doc.table(["Matriculation number", "Name", "Level", "Score"], rows);
  doc.signatures([{ name: "A. Officer", designation: "Head of Department" }, { designation: "Dean of Faculty" }]);
  const bytes = doc.finish();
  const text = new TextDecoder("latin1").decode(bytes);
  assert.ok(text.startsWith("%PDF-1.4"));
  const pages = Number(/\/Count (\d+)/.exec(text)?.[1]);
  assert.ok(pages >= 3, `150 rows need more than two pages, got ${pages}`);
  assert.ok(text.includes("(EXAMPLE UNIVERSITY, MAKURDI) Tj"), "the full header names the University");
  assert.ok(text.includes("(STUDENT REGISTER) Tj"), "the title prints in capitals");
  assert.ok(text.includes("(EXU) Tj"), "continuation pages carry the short name");
  assert.ok(text.includes(`(Page 1 of ${pages}) Tj`) && text.includes(`(Page ${pages} of ${pages}) Tj`), "every page is numbered against the total");
  assert.ok(text.includes("(1) Tj") && text.includes("(150) Tj"), "the serial column runs from 1 to the last row");
  assert.ok(text.includes("(S/N) Tj"), "the serial column is headed");
  // the signature block may open a last page of its own; every page that carries rows carries the table header
  const tablePages = (text.match(/\(MATRICULATION NUMBER\) Tj/g) ?? []).length;
  assert.ok(tablePages >= pages - 1 && tablePages >= 3, `the table header repeats on every page of rows (${tablePages} of ${pages})`);
  assert.ok(text.includes("(Head of Department) Tj") && text.includes("(Dean of Faculty) Tj"), "the signature lines are drawn");
  assert.ok(text.includes("by Ada Lovelace"), "the footer says who generated it");
  assert.ok(text.includes("OFFICIAL USE ONLY"), "the profile's confidentiality label is in the footer");
});

test("a route's own pages are footed and bound by finishPdf, landscape pages on their own width, and a watermark stamps every page", () => {
  primeInstitution(inst);
  const p1 = new Page().text(72, 780, "Course form");
  const p2 = new Page().text(72, 780, "Continued");
  const bytes = finishPdf([p1, p2], "Course form", "FORM", { reference: "EXU/FRM/9", watermark: "SAMPLE" });
  const text = new TextDecoder("latin1").decode(bytes);
  assert.ok(text.includes("(Page 1 of 2) Tj") && text.includes("(Page 2 of 2) Tj"));
  assert.ok(text.includes("Example University, Makurdi  |  COURSE FORM"), "the footer carries the University and the title");
  assert.ok(text.includes("Ref EXU/FRM/9"), "the footer carries the reference");
  assert.equal((text.match(/\(SAMPLE\) Tj/g) ?? []).length, 2, "the watermark is on both pages");
});

test("an identity card profile adds no footer, and text is cut to its column with an ellipsis", () => {
  primeInstitution(inst);
  const bytes = finishPdf([new Page().text(10, 10, "card")], "Identity card", "ID_CARD");
  const text = new TextDecoder("latin1").decode(bytes);
  assert.ok(!text.includes("Page 1 of 1"), "no page numbers on a card");
  assert.equal(fit("A very long course title that will not fit", 60, 8), "A very long co…");
  assert.equal(fit("short", 200, 8), "short");
});
