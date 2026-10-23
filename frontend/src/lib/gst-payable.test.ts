import { test } from "node:test";
import assert from "node:assert/strict";
import { gstPayState } from "./gst-payable.ts";

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
