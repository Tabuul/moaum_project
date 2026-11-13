import { test } from "node:test";
import assert from "node:assert/strict";
import { withSummer, withheldLine, withheldNote, withheldOf } from "./results-withheld.ts";

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

test("V756: a withheld Summer semester is named the Summer and held only by a balance from an earlier session", () => {
  const summer = { session: "2025/2026", semester: 3, outstanding: 40000, summer: true };
  const one = withheldNote([summer])!;
  assert.equal(one.title, "Your 2025/2026 Summer semester results are withheld while a balance from an earlier session is owed");
  assert.equal(one.body, "Withheld: 2025/2026 Summer semester (held by a balance owed for an earlier session). They are released the moment the payment is confirmed; the semesters you have paid for are shown.");
  assert.equal(withheldLine(summer), "Withheld while a balance from an earlier session is owed: under the Bursar's rule on arrears, the Summer semester's results are released once that balance is paid.");
  assert.doesNotMatch(withheldLine(summer), /school fees up to/);
  // with a regular semester beside it, the title names neither semester's reason as the other's
  const two = withheldNote([{ session: "2025/2026", semester: 2, outstanding: 14605 }, summer])!;
  assert.equal(two.title, "Results of 2 semesters are withheld until the fees owed are paid");
  assert.match(two.body, /2025\/2026 second semester \(₦14,605\.00 outstanding\); 2025\/2026 Summer semester \(held by a balance owed for an earlier session\)/);
});

test("V756: a CCE or postgraduate semester 3 is the third, worded by its school fees", () => {
  const third = { session: "2025/2026", semester: 3, outstanding: 5000, summer: false };
  assert.equal(withheldNote([third])!.title, "Your 2025/2026 third semester results are withheld until its school fees are paid");
  assert.equal(withheldLine(third), "Withheld until the school fees up to the third semester are paid: ₦5,000.00 outstanding.");
});

test("V756: the Summer flag is the entry's own, else semester 3 of a session among the student's Summer sessions", () => {
  const list = [
    { session: "2024/2025", semester: 3, outstanding: 0 },
    { session: "2025/2026", semester: 3, outstanding: 0 },
    { session: "2025/2026", semester: 1, outstanding: 0 },
    { session: "2023/2024", semester: 3, outstanding: 0, summer: false },
  ];
  assert.deepEqual(withSummer(list, ["2025/2026", "2023/2024"]).map((w) => w.summer), [false, true, false, false]);
  assert.deepEqual(withSummer(list, undefined).map((w) => w.summer), [false, false, false, false]);
  assert.deepEqual(withSummer(undefined, ["2025/2026"]), []);
});
