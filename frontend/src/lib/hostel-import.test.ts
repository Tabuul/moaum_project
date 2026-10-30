import { test } from "node:test";
import assert from "node:assert/strict";
import { autoMap, cleanRef, guessHeader, hallDetailsFrom, importRecords, isFooter } from "./hostel-import.ts";

// the headings of the old portal's export (Hostel_Rooms.xlsx, 28 September 2026), with made-up rows
const ROOMS_HEAD = ["Room ID (txid)", "Block ID", "Block Name", "Location", "Room No", "Capacity", "Status"];
const BLOCKS_HEAD = ["Block ID", "Block Name", "Location", "Block Class", "Gender", "Capacity", "Reservation", "Available (Capacity − Reservation)"];

test("the old portal's export: a Block is the hostel, named by Block ID and Block Name (V705)", () => {
  const m = autoMap(ROOMS_HEAD);
  assert.equal(m.hall, 2);
  assert.equal(m.hall_ref, 1);
  assert.equal(m.block, undefined);
  assert.equal(m.room, 4);
  assert.equal(m.capacity, 5);
  assert.equal(m.location, 3);
  assert.equal(m.hall_code, undefined);
  assert.equal(guessHeader([["A title"], ROOMS_HEAD, ["x"]]), 1);
});

test("a workbook with a hostel column keeps its blocks as blocks (V290)", () => {
  const m = autoMap(["Hostel", "Block", "Room", "Beds", "Gender", "Category"]);
  assert.equal(m.hall, 0);
  assert.equal(m.block, 1);
  assert.equal(m.room, 2);
  assert.equal(m.capacity, 3);
  assert.equal(m.gender, 4);
  assert.equal(m.hall_ref, undefined);
});

test("total and source rows under the data are not rooms; an ID is read as the number it is", () => {
  assert.equal(isFooter(["Total", "", "", "", "585 rooms", "2520", "2356"]), true);
  assert.equal(isFooter(["Source: Hostelrooms table, bsumpro export (28 Sep 2026)."]), true);
  assert.equal(isFooter(["", "Total"]), true);
  assert.equal(isFooter(["1ComRoom C1", "1", "Comfort Hostel", "Western Wing", "ComRoom C1", "8", "8"]), false);
  assert.equal(cleanRef("1.0"), "1");
  assert.equal(cleanRef(" 14 "), "14");
  assert.equal(cleanRef("H-02"), "H-02");
  assert.equal(cleanRef(undefined), "");
});

test("the hostel's gender and location come from the sheet that names it by the same ID", () => {
  const sheets = [
    { name: "Hostel Rooms", rows: [ROOMS_HEAD, ["1A1", "1", "Invented Hall", "", "Room A1", "4", "4"], ["2B1", "2", "Invented Lodge", "East", "B1", "2", "0"], ["Total", "", "", "", "2 rooms", "6", "4"]] },
    { name: "Hostel Blocks", rows: [BLOCKS_HEAD, ["1", "Invented Hall", "West", "0", "Female", "4", "0", "4"], ["2", "Invented Lodge", "East", "1", "Male", "2", "0", "2"], ["Total", "", "", "", "", "6", "0", "6"],
      ["Block Capacity comes from the blocks table; every other number is calculated.", "", "", "", "", "", "", ""]] },
  ];
  const d = hallDetailsFrom(sheets, 0);
  assert.ok(d);
  assert.equal(d.sheet, "Hostel Blocks");
  assert.deepEqual(d.byRef["1"], { gender: "Female", location: "West" });
  assert.equal(Object.keys(d.byRef).length, 2);
  const m = autoMap(ROOMS_HEAD);
  const body = sheets[0].rows.slice(1).filter((r) => !isFooter(r));
  const recs = importRecords(body, m, d);
  assert.equal(recs.length, 2);
  assert.deepEqual(recs[0], { hall: "Invented Hall", hall_ref: "1", room: "Room A1", capacity: "4", location: "West", hall_sex: "Female" });
  // a location in the rooms sheet itself is kept
  assert.equal(recs[1].location, "East");
  assert.equal(recs[1].hall_sex, "Male");
  // no other sheet names the hostels: nothing is invented
  assert.equal(hallDetailsFrom([sheets[0]], 0), null);
});
