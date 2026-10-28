import { test } from "node:test";
import assert from "node:assert/strict";
import { carryPayOffer, gstPayState, unpaidGstRegistered } from "./gst-payable.ts";

const owed = { required: true, stated: true, entitled: false, fee: "4000.00" };
const notOwed = { required: false, stated: true, entitled: false, fee: "4000.00" };

test("V643: a student who owes the fee pays it, as before", () => {
  assert.deepEqual(gstPayState(owed, []), { unpaid: true, shown: [], gstShown: false, epsShown: false });
  assert.equal(gstPayState({ ...owed, entitled: true }, []).unpaid, false);
  assert.equal(gstPayState({ ...owed, fee: 0 }, []).unpaid, false);
  assert.equal(gstPayState({ ...owed, stated: false }, []).unpaid, false);
});

test("V643: a student shown a GST/EPS course on the registration page pays the fee though not yet owing it", () => {
  const s = gstPayState(notOwed, [{ course_code: "ENT 412", office: "EPS" }, { course_code: "GST 412", office: "GST" }]);
  assert.deepEqual(s, { unpaid: true, shown: ["ENT 412", "GST 412"], gstShown: true, epsShown: true });
  assert.equal(gstPayState({ ...notOwed, entitled: true }, [{ course_code: "GST 412", office: "GST" }]).unpaid, false);
});

test("V643: a student shown none, owing nothing, has nothing to pay", () => {
  assert.deepEqual(gstPayState(notOwed, []), { unpaid: false, shown: [], gstShown: false, epsShown: false });
  assert.equal(gstPayState(notOwed, undefined).unpaid, false);
});

test("V690: a GST/EPS carry-over is paid for first — offered on the GST page only when nothing else asks for the fee", () => {
  const carry = [{ course_code: "EPS 202", office: "EPS" }, { course_code: "GST 211", office: "GST" }];
  assert.deepEqual(carryPayOffer(notOwed, [], carry), ["EPS 202", "GST 211"]);
  assert.deepEqual(carryPayOffer(owed, [], carry), []);
  assert.deepEqual(carryPayOffer(notOwed, [{ course_code: "GST 412", office: "GST" }], carry), []);
  assert.deepEqual(carryPayOffer({ ...notOwed, entitled: true }, [], carry), []);
  assert.deepEqual(carryPayOffer({ ...notOwed, fee: 0 }, [], carry), []);
});

test("V690: a GST/EPS course registered with the fee unpaid is named; paid, or no fee stated, nothing is", () => {
  const entries = [{ courseCode: "EPS 202", kind: "GST", status: "APPROVED" }, { courseCode: "POL 402", kind: "Core", status: "APPROVED" },
    { courseCode: "GST 211", kind: "GST", status: "DROPPED" }];
  assert.deepEqual(unpaidGstRegistered(entries, owed), ["EPS 202"]);
  assert.deepEqual(unpaidGstRegistered(entries, { ...owed, entitled: true }), []);
  assert.deepEqual(unpaidGstRegistered(entries, { ...owed, stated: false }), []);
  assert.deepEqual(unpaidGstRegistered(entries, null), []);
});
