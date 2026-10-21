import { test } from "node:test";
import assert from "node:assert/strict";
import { fileTally, filtersInWords, historyRow, historyUrl, HISTORY_HEADERS, HISTORY_STATE, KIND_STATES, partRows, paymentRow, PAYMENT_HEADERS,
  rowsWord, skipped, when, type HistoryRow } from "./old-fees-history.ts";

const row = (o: Partial<HistoryRow> = {}): HistoryRow => ({
  id: "1", ref: "OFL-2026-00004", kind: "DIRECT", rebuilt: false, state: "LOADED", file_name: "export.xlsx", by_person: "p", by_name: "Akile, Terna",
  office: "bursar", at: "2026-10-21T09:15:00Z", finished_at: "2026-10-21T09:18:00Z", parts: 3, file_rows: 1200, rows_read: 1200, recorded: 1100,
  already: 80, no_student: 15, no_due: 5, separate: 2, taken_over: 0, corrected: 1, undated: 0, deleted: 0, students: 410, sessions: "2019/2020, 2020/2021",
  file_amount: "55000000", amount: "51000000.50", decided_by: null, decided_by_name: null, decided_at: null, note: null, ...o,
});

test("a file states its rows, students by number, sessions and the amount stated (blank is cleared in full)", () => {
  const t = fileTally([
    { matric: "bsu/ss/19/1", session: "2019/2020", amount: "₦85,000" },
    { matric: "BSU/SS/19/1", session: "2020/2021", amount: "" },
    { matric: "BSU/SS/19/2", session: "2019/2020", amount: "1,500.50" },
    { matric: "", session: "", amount: "n/a" },
  ]);
  assert.deepEqual(t, { rows: 4, students: 2, sessions: "2019/2020, 2020/2021", amount: 86500.5 });
});

test("the history's address carries only the filters given", () => {
  assert.equal(historyUrl({}, 10, 1), "/api/bff/api/v1/finance/legacy-fees/history?size=10&page=1");
  const u = historyUrl({ from: "2026-10-01", kind: "DIRECT", q: " export ", session: "", person: "abc" }, 25, 3);
  assert.equal(u, "/api/bff/api/v1/finance/legacy-fees/history?size=25&page=3&from=2026-10-01&kind=DIRECT&person=abc&q=export");
});

test("the filters in words name the person and the range", () => {
  assert.equal(filtersInWords({}), "Every upload");
  assert.equal(filtersInWords({ from: "2026-10-01", to: "2026-10-21", kind: "RESET", person: "p1", session: "2019/2020" }, [{ id: "p1", name: "Akile, Terna" }]),
    "2026-10-01 to 2026-10-21 · Start over · by Akile, Terna · session 2019/2020");
});

test("what was skipped adds up, and a rebuilt upload cannot say", () => {
  assert.equal(skipped(row()), 100);
  assert.equal(skipped(row({ already: null, no_student: null, no_due: null })), null);
});

test("an upload part-way says how far it got", () => {
  assert.equal(rowsWord(row({ state: "STOPPED", rows_read: 500 })), "500 of 1,200");
  assert.equal(rowsWord(row()), "1,200");
  assert.equal(rowsWord(row({ file_rows: null, rows_read: null })), "—");
  assert.equal(rowsWord(row({ kind: "RESET" })), "—");
});

test("every state has words and every kind its states", () => {
  for (const states of Object.values(KIND_STATES)) for (const s of states) assert.ok(HISTORY_STATE[s][0]);
  assert.equal(HISTORY_STATE.PENDING[0], "Waiting for the Bursar");
});

test("an upload's Excel row has a cell for every heading", () => {
  const r = historyRow(row({ rebuilt: true, already: null, no_student: null, no_due: null }));
  assert.equal(r.length, HISTORY_HEADERS.length);
  assert.equal(r[3], "Loaded by the Bursary (rebuilt from the records)");
  assert.equal(r[12], "");
  assert.equal(r[23], 51000000.5);
  const reset = historyRow(row({ kind: "RESET", state: "DONE", recorded: 0, deleted: 284058 }));
  assert.equal(reset[11], "");
  assert.equal(reset[19], 284058);
  assert.equal(paymentRow({ part: 2, at: "", number: "BSU/SS/19/1", name: "A, B", session: "2019/2020", purpose: "School fees", amount: "85000",
    paid_on: "2019-11-04T00:00:00Z", reference: "MOAUM-LEG-1", receipt_no: "LEG-1", payref: null }).length, PAYMENT_HEADERS.length);
});

test("a part names its rows; a moment reads in Lagos", () => {
  assert.equal(partRows({ from_row: 500, rows_read: 500 }), "501–1,000");
  assert.equal(partRows({ from_row: null, rows_read: 500 }), "—");
  assert.equal(when("2026-10-16T15:21:18Z"), "16 Oct 2026, 16:21");
  assert.equal(when(null), "—");
});
