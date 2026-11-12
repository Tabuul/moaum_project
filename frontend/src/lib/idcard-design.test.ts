import { test } from "node:test";
import assert from "node:assert/strict";
import { Page, pdf } from "./pdf-write.ts";
import { PdfSurface, SvgSurface, measure, type Font, type Rgb, type Surface, type TextOptions } from "./card-surface.ts";
import { LAND, PORT, c128Runs, cardSvg, drawCardBack, drawStaffFront, drawStudentFront, type CardBack, type CardFace } from "./idcard-design.ts";

/** a surface that only records the text it is asked to set, and where */
class Recorder implements Surface {
  texts: { x: number; y: number; s: string; size: number; right: number }[] = [];
  fill(): void {}
  stroke(): void {}
  text(x: number, y: number, s: string, size: number, font: Font, _c: Rgb, o: TextOptions = {}): void {
    this.texts.push({ x, y, s, size, right: x + measure(s, size, font, o.spacing ?? 0, o.hscale ?? 1) });
  }
  image(): boolean { return false; }
  has(): boolean { return false; }
  clip(): void {}
  restore(): void {}
}

const student = (over: Partial<CardFace> = {}): CardFace => ({
  kind: "student", name: "Aaga, Doowuese Edith", number: "MOAU/SS/LIS/25/83810",
  fields: [["Faculty", "Social Sciences"], ["Blood group", "—"], ["Programme", "B.Sc. LIBRARY AND INFORMATION SCIENCE"], ["Admitted", "2025"]],
  foot: [["Valid until", "12 November 2030"]], serial: "MOAUM/ID/26/00004", ...over,
});
const staff = (over: Partial<CardFace> = {}): CardFace => ({
  kind: "staff", name: "Okeme, Friday Achile", number: "P2369",
  fields: [["Rank", "Senior Assistant Registrar"], ["Category", "Non-teaching"], ["Department", "Registry"], ["Blood group", "—"], ["Appointed", "04 May 2016"]],
  foot: [], serial: "MOAUM/SID/26/00001", ...over,
});
const sBack: CardBack = { kind: "student", barcode: "MOAU/SS/LIS/25/83810", serial: "MOAUM/ID/26/00004", aside: ["In an emergency", "08031234567"], signatory: { title: "Chief Security Officer", name: "Gbehe, Simon Ingbian" } };
const fBack: CardBack = { kind: "staff", barcode: "P2369", serial: "MOAUM/SID/26/00001", place: "Km 1 Gboko Road, Makurdi", signatory: { title: "Chief Security Officer", name: "Gbehe, Simon Ingbian" } };
const q = { size: 21, dark: Array.from({ length: 441 }, (_, i) => i % 3 === 0) };

/** every text inside the card, left to right and top to bottom */
function within(r: Recorder, W: number, H: number) {
  for (const t of r.texts) {
    assert.ok(t.x >= 0 && t.right <= W + 0.5, `"${t.s}" runs from ${t.x.toFixed(1)} to ${t.right.toFixed(1)} on a card ${W} wide`);
    assert.ok(t.y - t.size * 0.75 >= 0 && t.y <= H, `"${t.s}" sits at ${t.y.toFixed(1)} on a card ${H} tall`);
  }
}

test("the four faces set every word inside the card, with ordinary and very long particulars", () => {
  const long = "Ter-Ayatse Mnenga-Iorhemba, Doowuese Edith Mwuese Terkimbi";
  for (const f of [student(), student({ name: long, fields: [["Faculty", "Agriculture and Environmental Sciences"], ["Blood group", "AB+"], ["Programme", "B.Sc. (Ed.) Industrial Technical Education (Woodwork Technology)"], ["Admitted", "2021"]] })]) {
    const r = new Recorder(); drawStudentFront(r, f); within(r, LAND.w, LAND.h);
    assert.ok(r.texts.some((t) => t.s === "MOAU/SS/LIS/25/83810"), "the matriculation number is on the pill");
    assert.ok(r.texts.some((t) => t.s === "STUDENT") && r.texts.some((t) => t.s === "IDENTITY CARD"), "the tab names the card");
    for (const label of ["FACULTY", "PROGRAMME", "ADMITTED", "BLOOD GROUP", "VALID UNTIL", "ID NO."]) {
      assert.ok(r.texts.some((t) => t.s === label), `${label} is printed`);
    }
    // the University's layout of 12 November 2026: no level, session or graduation year on the student card
    for (const label of ["LEVEL", "SESSION", "GRADUATES"]) assert.ok(!r.texts.some((t) => t.s === label), `${label} is not printed`);
  }
  for (const f of [staff(), staff({ name: "Iorhemba-Mnenga, Friday Achile Terhemen Aondona", fields: [["Rank", "Principal Assistant Registrar (Academic Planning)"], ["Category", "Non-teaching"], ["Department", "Centre for Entrepreneurship and Technology Development"], ["Blood group", "O+"], ["Appointed", "04 May 2016"]] })]) {
    const r = new Recorder(); drawStaffFront(r, f); within(r, PORT.w, PORT.h);
    assert.ok(r.texts.some((t) => t.s === "STAFF IDENTITY CARD"));
  }
  const b1 = new Recorder(); drawCardBack(b1, sBack, true, q); within(b1, LAND.w, LAND.h);
  const b2 = new Recorder(); drawCardBack(b2, fBack, false, q); within(b2, PORT.w, PORT.h);
  assert.ok(b2.texts.some((t) => t.s === "Km 1 Gboko Road, Makurdi"), "the staff card says where a found card goes");
  assert.ok(b1.texts.some((t) => t.s === "MOAU/SS/LIS/25/83810"), "the number prints under the bars as the barcode carries it");
  assert.equal(b1.texts.filter((t) => /^(This ID card|Any alteration|Loss must)/.test(t.s)).length, 3, "the three conditions, each begun on its own line");
});

test("a two-line name on the staff card stays clear of the photograph and of the number", () => {
  const r = new Recorder();
  drawStaffFront(r, staff({ name: "Iorhemba-Mnenga, Friday Achile Terhemen Aondona" }));
  const names = r.texts.filter((t) => /IORHEMBA|FRIDAY|ACHILE|AONDONA/.test(t.s));
  assert.equal(names.length, 2);
  const pill = r.texts.find((t) => t.s === "P2369")!;
  assert.ok(names[1].y < pill.y - pill.size, "the second line ends above the number's pill");
});

test("the barcode is Code 128-B of the number as printed: start, the characters, the check and the stop", () => {
  const runs = c128Runs("MOAU/SS/LIS/25/83810");
  assert.equal(runs.reduce((a, b) => a + b, 0), 11 * (20 + 2) + 13);
  assert.deepEqual(runs.slice(0, 6), [2, 1, 1, 2, 1, 4]);   // START B
});

test("the PDF carries the gradients and the condensed serif, and nothing unset", () => {
  const p = new Page();
  for (const [draw, w, h, top] of [
    [(s: Surface) => drawStudentFront(s, student()), LAND.w, LAND.h, 800],
    [(s: Surface) => drawCardBack(s, sBack, true, q), LAND.w, LAND.h, 560],
    [(s: Surface) => drawStaffFront(s, staff()), PORT.w, PORT.h, 800],
  ] as [(s: Surface) => void, number, number, number][]) {
    const s = new PdfSurface(p, 40, top, 300 / w, {}).begin(); draw(s); s.end(); void h;
  }
  const ops = p.ops.join("\n");
  assert.ok(!/NaN|undefined|Infinity/.test(ops), "every number is set");
  assert.ok(/ 93 Tz /.test(ops), "the University's name in the serif at the design's width");
  assert.ok(/ re /.test(ops) && !/NaN/.test(ops), "the QR's modules and the barcode's bars are rectangles");
  assert.ok(p.shadings.size > 3 && /sh Q/.test(ops), "the bands and the swooshes are gradients");
  const text = new TextDecoder("latin1").decode(pdf([p], "cards"));
  assert.ok(/\/Shading << \/Sh1 \d+ 0 R/.test(text) && text.includes("<< /ShadingType 2"), "each gradient one object, referred to by the page");
  assert.ok(/\/ExtGState << \/GSW .*\/A\d+ << \/ca/.test(text), "the faint watermark's opacity is a resource of the page");
  // every q has its Q
  const opens = (ops.match(/(?<=^|\s)q(?=\s|$)/g) ?? []).length, closes = (ops.match(/(?<=^|\s)Q(?=\s|$)/g) ?? []).length;
  assert.equal(opens, closes);
});

test("the screen's SVG is the same drawing, its words escaped and its ids its own", () => {
  const svg = cardSvg("front", { face: student({ name: "<b>Aaga</b> & Sons" }), back: sBack }, { photo: "/p.jpg?a=1&b=2", crest: "/crest.png" }, "x1");
  assert.ok(svg.startsWith("<svg") && svg.endsWith("</svg>"));
  assert.ok(svg.includes("&lt;B&gt;AAGA&lt;/B&gt; &amp; SONS") && !svg.includes("<b>"), "the name is text, never markup");
  assert.ok(svg.includes(`href="/p.jpg?a=1&amp;b=2"`));
  assert.ok(!/NaN|undefined/.test(svg));
  const ids = [...svg.matchAll(/id="([^"]+)"/g)].map((m) => m[1]);
  assert.ok(ids.length > 0 && ids.every((i) => i.startsWith("x1-")) && new Set(ids).size === ids.length);
  assert.equal((svg.match(/<g /g) ?? []).length, (svg.match(/<\/g>/g) ?? []).length);
  const back = cardSvg("back", { face: staff(), back: fBack }, {}, "x2");
  assert.ok(back.includes("QR ON") && back.includes("THE PRINT"), "a preview marks the QR the print carries");
  const sv = new SvgSurface(10, 10, {}, "t");
  sv.text(1, 2, "A", 5, "serifBold", [0, 0, 0], { hscale: 0.76 });
  assert.ok(sv.toString().includes("scale(0.76 1)"));
});

test("a two-line name prints every word, measured as it is drawn (the review's cases and a thousand more)", () => {
  const given = ["Mwuese", "Terhemen", "Doowuese", "Elizabeth", "Friday", "Nguveren", "Oluwadamilare", "Iorhemba", "Ngodoo", "Nnamdi", "Aondona", "Chukwuemeka", "Sewuese", "Msughter"];
  const sur = ["Ter-Ayatse", "Okonkwo-Adebayo", "Chukwuemeka", "Oluwaseun", "Mnenga-Iorhemba", "Aaga", "Iorhemba-Mnenga", "Tyoakaa"];
  const names = ["Ter-Ayatse, Mwuese Terhemen Doowuese Elizabeth", "Okonkwo-Adebayo, Friday Elizabeth Nguveren Oluwadamilare",
    "Chukwuemeka, Mnenga-Iorhemba Ngodoo Nnamdi", "Oluwaseun, Mnenga-Iorhemba Nnamdi Ngodoo"];
  let seed = 7;
  const rnd = (n: number) => { seed = (seed * 1103515245 + 12345) % 2147483648; return seed % n; };
  for (let i = 0; i < 1000; i++) names.push(`${sur[rnd(sur.length)]}, ${Array.from({ length: 2 + rnd(3) }, () => given[rnd(given.length)]).join(" ")}`);
  for (const name of names) {
    for (const [draw, face] of [[drawStudentFront, student({ name })], [drawStaffFront, staff({ name })]] as [(s: Surface, f: CardFace) => void, CardFace][]) {
      const r = new Recorder(); draw(r, face);
      const printed = r.texts.filter((t) => t.size >= 18 && /[A-Z]/.test(t.s) && name.toUpperCase().includes(t.s.replace(/…$/, ""))).map((t) => t.s);
      assert.equal(printed.join(" "), name.toUpperCase(), `${face.kind} card: ${name}`);
      within(r, face.kind === "student" ? LAND.w : PORT.w, face.kind === "student" ? LAND.h : PORT.h);
    }
  }
});

test("a name with accents or a typographic apostrophe keeps its letters", () => {
  const r = new Recorder();
  drawStudentFront(r, student({ name: "Ọlábísí-Adéọlá, Ñandú O’Brien" }));
  assert.ok(r.texts.some((t) => t.s === "OLABISI-ADEOLA, NANDU O'BRIEN"), r.texts.map((t) => t.s).join(" | "));
});

test("a student without a matriculation number previews as such: no empty pill, no barcode of nothing", () => {
  const f = new Recorder(); drawStudentFront(f, student({ number: "" }));
  assert.ok(f.texts.some((t) => t.s === "NUMBER NOT YET ISSUED"));
  const svg = cardSvg("back", { face: student({ number: "" }), back: { ...sBack, barcode: "" } }, {}, "nb");
  assert.ok(svg.includes("THE BARCODE IS PRINTED WITH THE NUMBER"));
});

test("a card drawn W points wide is W points wide: the scale is written whole", () => {
  const p = new Page();
  const s = new PdfSurface(p, 50, 700, 230 / PORT.w, {}).begin(); drawStaffFront(s, staff()); s.end();
  assert.ok(p.ops[0].startsWith("q 0.425926 0 0 -0.425926 "), p.ops[0]);
});

test("the University's layout of 12 November 2026: the staff card prints DEPARTMENT, and no unit, faculty, office or validity", () => {
  const r = new Recorder(); drawStaffFront(r, staff()); within(r, PORT.w, PORT.h);
  for (const label of ["RANK", "CATEGORY", "DEPARTMENT", "APPOINTED", "BLOOD GROUP", "ID NO."]) assert.ok(r.texts.some((t) => t.s === label), `${label} is printed`);
  for (const label of ["UNIT", "FACULTY", "OFFICE", "VALID UNTIL"]) assert.ok(!r.texts.some((t) => t.s === label), `${label} is not printed`);
  assert.ok(r.texts.some((t) => t.s === "Registry"), "the department's value is printed");
  // the card number alone on the foot is centred on the band, from its icon's left edge (the icon, 31 wide, centred 48 in from the
  // fact's edge; the text 80 in) to the end of its text
  const no = r.texts.find((t) => t.s === "ID NO.")!, serial = r.texts.find((t) => t.s === "MOAUM/SID/26/00001")!;
  const iconLeft = no.x - 80 + 48 - 31 / 2;
  const mid = (iconLeft + Math.max(no.right, serial.right)) / 2;
  assert.ok(Math.abs(mid - PORT.w / 2) < 1.5, `the card number's icon and text sit centred on the foot (${mid.toFixed(1)} of ${PORT.w})`);
});

test("fewer particulars fill the room the removed fields left, one size for both columns", () => {
  // the student card: the particulars reach down towards the foot, the two columns set at one size
  const r = new Recorder(); drawStudentFront(r, student());
  const labels = r.texts.filter((t) => ["FACULTY", "PROGRAMME", "BLOOD GROUP", "ADMITTED"].includes(t.s));
  assert.equal(new Set(labels.map((t) => t.size.toFixed(2))).size, 1, "one label size in both columns");
  const values = r.texts.filter((t) => ["Social Sciences", "2025"].includes(t.s));
  assert.ok(Math.max(...values.map((t) => t.y)) > 340, "the last row sits well down the card, not under the name");
  // the staff card: the third row's date sits well down the card; the rows keep level although the rank wraps to two lines
  const s = new Recorder(); drawStaffFront(s, staff());
  const ys = ["RANK", "DEPARTMENT", "APPOINTED"].map((l) => s.texts.find((t) => t.s === l)!.y);
  assert.ok(ys[0] < ys[1] && ys[1] < ys[2] && ys[2] > 660, `the left column reaches down the card (${ys.map((y) => y.toFixed(0)).join(", ")})`);
  const right = ["CATEGORY", "BLOOD GROUP"].map((l) => s.texts.find((t) => t.s === l)!.y);
  assert.ok(Math.abs(right[0] - ys[0]) < 0.01 && Math.abs(right[1] - ys[1]) < 0.01, `the right column's rows keep level with the left's (${right.map((y) => y.toFixed(1)).join(", ")} against ${ys.map((y) => y.toFixed(1)).join(", ")})`);
  // the student card likewise, a two-line faculty beside the blood group
  const t = new Recorder(); drawStudentFront(t, student({ fields: [["Faculty", "Agriculture and Environmental Sciences"], ["Blood group", "AB+"], ["Programme", "B.Sc. Economics"], ["Admitted", "2021"]] }));
  const at = (l: string) => t.texts.find((x) => x.s === l)!.y;
  assert.ok(Math.abs(at("PROGRAMME") - at("ADMITTED")) < 0.01, "the second row keeps level after a wrapped faculty");
});

test("growing the particulars never cuts short a value that prints in full at the usual size; a date stays on one line", () => {
  // the review of V748: a one-line rank let the size grow until the 61-character CEID lost its end
  for (const rank of ["Professor", "Lecturer I", "Deputy Director (Information and Communication Technology Services)"]) {
    const r = new Recorder();
    drawStaffFront(r, staff({ fields: [["Rank", rank], ["Category", "Non-teaching"], ["Department", "Centre for Entrepreneurship and Innovation Development (CEID)"],
      ["Blood group", "O+"], ["Appointed", "28 September 2016"]] }));
    assert.ok(!r.texts.some((t) => t.s.endsWith("…")), `nothing is cut short beside the rank ${rank}`);
    assert.ok(r.texts.some((t) => t.s.includes("(CEID)")), "the department prints to its end");
  }
  for (const month of ["January", "February", "September", "October", "November", "December"]) {
    const r = new Recorder(); drawStaffFront(r, staff({ fields: [["Rank", "Professor"], ["Category", "Teaching"], ["Department", "Accounting"], ["Blood group", "A+"], ["Appointed", `28 ${month} 2016`]] }));
    assert.ok(r.texts.some((t) => t.s === `28 ${month} 2016`), `28 ${month} 2016 prints on one line`);
  }
});
