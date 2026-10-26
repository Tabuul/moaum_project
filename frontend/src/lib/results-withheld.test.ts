import { test } from "node:test";
import assert from "node:assert/strict";
import { withheldLine, withheldNote, withheldOf } from "./results-withheld.ts";

test("V667: one semester withheld is named with what is outstanding; the others are shown", () => {
  const list = [{ session: "2025/2026", semester: 2, outstanding: 14605 }];
  const n = withheldNote(list)!;
  assert.equal(n.title, "Your 2025/2026 second semester results are withheld until its school fees are paid");
  assert.equal(n.body, "Withheld: 2025/2026 second semester (₦14,605.00 outstanding). They are released the moment the payment is confirmed; the semesters you have paid for are shown.");
  assert.deepEqual(withheldOf(list, "2025/2026", 2), list[0]);
  assert.equal(withheldOf(list, "2025/2026", 1), null);
  assert.equal(withheldLine(list[0]), "Withheld until the school fees up to the second semester are paid: ₦14,605.00 outstanding.");
});

test("V667: nothing withheld says nothing; several are listed", () => {
  assert.equal(withheldNote([]), null);
  assert.equal(withheldNote(undefined), null);
  const n = withheldNote([{ session: "2025/2026", semester: 1, outstanding: 66745 }, { session: "2025/2026", semester: 2, outstanding: "95350.00" }])!;
  assert.equal(n.title, "Results of 2 semesters are withheld until their school fees are paid");
  assert.match(n.body, /2025\/2026 first semester \(₦66,745\.00 outstanding\); 2025\/2026 second semester \(₦95,350\.00 outstanding\)/);
});
