import { test } from "node:test";
import assert from "node:assert/strict";
import { contactRows, missingWord, TEMPLATE_HEAD } from "./contact-upload.ts";

test("the template's header row is found below its crest and title, and its rows read", () => {
  const grid = [
    ["MOUNTAIN TOP UNIVERSITY"], ["Student Contacts — Department of English"], ["Generated 19 Oct 2026 · Serial CONTACT-1"], [],
    ["S/N", ...TEMPLATE_HEAD],
    ["1", "BSU/AR/ENG/15/29043", "DOE, JOHN", "Arts", "English", "B.A. English", "400", "Phone and e-mail", "8031234567", " Jane.Doe@Example.com "],
    ["2", "BSU/AR/ENG/17/42193", "ROE, MARY", "Arts", "English", "B.A. English", "300", "E-mail", "", ""],
    ["", "", "", "", "", "", "", "", "", ""],
  ];
  const { rows, error } = contactRows(grid);
  assert.equal(error, null);
  assert.deepEqual(rows, [
    { number: "BSU/AR/ENG/15/29043", phone: "8031234567", email: "Jane.Doe@Example.com" },
    { number: "BSU/AR/ENG/17/42193", phone: "", email: "" },
  ]);
});

test("a plain sheet with other headings is read; a phone heading is never taken for the number", () => {
  const { rows } = contactRows([["Phone number", "Matric No", "Email address"], ["+234 803 123 4567", "MOAU/SC/CSC/24/1", "a@b.ng"]]);
  assert.deepEqual(rows, [{ number: "MOAU/SC/CSC/24/1", phone: "+234 803 123 4567", email: "a@b.ng" }]);
  const jamb = contactRows([["JAMB Reg", "GSM"], ["202412345678AB", "08031234567"]]);
  assert.deepEqual(jamb.rows, [{ number: "202412345678AB", phone: "08031234567", email: "" }]);
});

test("a phone a spreadsheet wrote in scientific form is read back to its digits", () => {
  const { rows } = contactRows([["Student number", "Phone"], ["X/1", "8.031234567E9"], ["X/2", "2.34803123457E+12"]]);
  assert.equal(rows[0].phone, "8031234567");
  assert.equal(rows[1].phone, "2348031234570");
});

test("a sheet without a number column, or with headings and no rows, is refused in words", () => {
  assert.match(contactRows([["Name", "Phone"], ["DOE", "0803"]]).error ?? "", /student number column/);
  assert.match(contactRows([["Student number", "E-mail"]]).error ?? "", /no rows/);
});

test("what a student is missing, in words", () => {
  assert.equal(missingWord(true, true), "Phone and e-mail");
  assert.equal(missingWord(true, false), "Phone");
  assert.equal(missingWord(false, true), "E-mail");
});
