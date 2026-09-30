import { test } from "node:test";
import assert from "node:assert/strict";
import { firstEmail, firstMobile } from "./contacts.ts";

test("an email is read as people write it", () => {
  assert.equal(firstEmail("John.Doe@Gmail.com"), "john.doe@gmail.com");
  assert.equal(firstEmail("  john@yahoo.com "), "john@yahoo.com");
  assert.equal(firstEmail("mailto:ada@x.ng"), "ada@x.ng");
  assert.equal(firstEmail("Ada Obi <ada.obi@gmail.com>"), "ada.obi@gmail.com");
  assert.equal(firstEmail("a@b.com, c@d.com"), "a@b.com");
  assert.equal(firstEmail("bad@mail.com."), "bad@mail.com");
  assert.equal(firstEmail("x@migrate.moau.local; real@mail.com"), "real@mail.com");
});

test("what is not an email is not taken for one", () => {
  for (const cell of ["nonsense", "john@gmail", "", "with space @x.com", "123@migrate.moau.local", null, undefined]) assert.equal(firstEmail(cell), null, String(cell));
});

test("a Nigerian mobile number is read in every usual form", () => {
  for (const cell of ["08031234567", "8031234567", "+2348031234567", "2348031234567", "+234 803 123 4567", "0803 123 4567", "0803-123-4567",
    "08031234567, 07061234567", "08031234567/07061234567", "08031234567 07061234567", "+234 (0) 803 123 4567", "2340803 123 4567", "+234-0803-123-4567"]) {
    assert.equal(firstMobile(cell), "08031234567", cell);
  }
  assert.equal(firstMobile("Tel: 0706 555 1234 (father)"), "07065551234");
  assert.equal(firstMobile("09112345678"), "09112345678");
  assert.equal(firstMobile("07012345678"), "07012345678");
});

test("what is not a mobile number is not taken for one", () => {
  for (const cell of ["01234567890", "0803123456", "080312345678", "12348031234567", "00000000000", "8.03123E+09", "", null]) assert.equal(firstMobile(cell), null, String(cell));
});
