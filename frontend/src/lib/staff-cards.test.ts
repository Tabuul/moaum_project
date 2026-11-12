import { test } from "node:test";
import assert from "node:assert/strict";
import { issueWords, printAllHref, staffCardsHref } from "./staff-cards.ts";
import { staffCardFace, type LiveStaffCard } from "./staff-card-face.ts";

test("V698: the desk and its print keep the narrowing; the print takes every card in force", () => {
  assert.equal(staffCardsHref({}), "/credentials/idcards/staff");
  assert.equal(staffCardsHref({ faculty: "SC", unit: "MTC", q: "ada", card: "WITHOUT" }), "/credentials/idcards/staff?faculty=SC&unit=MTC&q=ada&card=WITHOUT");
  assert.equal(printAllHref({ faculty: "SC", card: "WITHOUT" }), "/credentials/idcards/staff/pdf?faculty=SC");
  assert.equal(printAllHref({}), "/credentials/idcards/staff/pdf");
});

test("V698: a bulk issue says what it did", () => {
  assert.equal(issueWords({ ISSUED: 312, HAS_CARD: 4, STAFF_CARD_NO_NUMBER: 2 }), "312 cards issued; 4 already had one; 2 refused (2 no staff number on record)");
  assert.equal(issueWords({ ISSUED: 1 }), "1 card issued");
});

const card = (face: Partial<LiveStaffCard["face"]>, offices: LiveStaffCard["offices"] = []): LiveStaffCard => ({
  card_no: "MOAUM/SID/26/00001", valid_to: "2029-12-31", verify_path: "/verify/staffcard?no=x", offices,
  face: { staff_number: "P1234", surname: "ADA", given_names: "Bem", rank: null, department: null, faculty: null, category: null,
          date_first_appointment: null, appointment_date: null, has_photo: false, ...face },
});

test("V698, the layout of 12 November 2026: a member of staff prints rank, category, department, appointment and blood group", () => {
  const f = staffCardFace(card({ rank: "SENIOR EXECUTIVE OFFICER [ADMIN]", department: "Registry", category: "NON_ACADEMIC", blood_group: "O+" }))!;
  assert.deepEqual(f.fields, [["Rank", "Senior Executive Officer [Admin]"], ["Category", "Non-teaching"], ["Department", "Registry"], ["Blood group", "O+"], ["Appointed", "—"]]);
  assert.deepEqual(f.foot, [], "no validity on the staff card");
  // an academic: their department, never the faculty; Teaching
  const lecturer = staffCardFace(card({ department: "Mathematics", faculty: "Science", category: "ACADEMIC" }, [{ office_code: "lecturer", office: "Lecturer" }]))!;
  assert.deepEqual(lecturer.fields.slice(1, 3), [["Category", "Teaching"], ["Department", "Mathematics"]]);
  assert.ok(!lecturer.fields.some(([l]) => ["Unit", "Faculty", "Office"].includes(l)), "no unit, faculty or office");
  // V751: no department from the API: a dash — never the office's title ("Bursar") under DEPARTMENT; the API reads the office's unit
  const officer = staffCardFace(card({ category: null }, [{ office_code: "bursar", office: "Bursar" }]))!;
  assert.deepEqual(officer.fields[2], ["Department", "—"]);
  assert.deepEqual(staffCardFace(card({ category: null, department: "Bursary" }, [{ office_code: "bursar", office: "Bursar" }]))!.fields[2], ["Department", "Bursary"]);
  assert.equal(staffCardFace(card({ staff_number: null })), null);
});
