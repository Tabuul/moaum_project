import { NextResponse } from "next/server";
import { api, API_URL } from "@/lib/api";
import { sessionToken } from "@/lib/session";
import type { Me, Card } from "@/lib/student-portal";
import { A4, Page, pdf, jpegSize, type Image } from "@/lib/pdf-write";
import { crestImage } from "@/lib/pdf-crest";
import { qrMatrix } from "@/lib/qr";

export const dynamic = "force-dynamic";

const day = (iso: string | null) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "2-digit", month: "short", year: "numeric" }) : "—");
const clean = (s: string | null | undefined) => (s ?? "").replace(/[^\x20-\x7E]/g, " ").replace(/\s+/g, " ").trim();
const textWidth = (s: string, size: number, bold = false) => s.length * size * (bold ? 0.54 : 0.5);

/* ── Code 128-B run lengths, ported from components/proto/idcard.tsx ── */
const C128 = [
  "212222", "222122", "222221", "121223", "121322", "131222", "122213", "122312", "132212", "221213",
  "221312", "231212", "112232", "122132", "122231", "113222", "123122", "123221", "223211", "221132",
  "221231", "213212", "223112", "312131", "311222", "321122", "321221", "312212", "322112", "322211",
  "212123", "212321", "232121", "111323", "131123", "131321", "112313", "132113", "132311", "211313",
  "231113", "231311", "112133", "112331", "132131", "113123", "113321", "133121", "313121", "211331",
  "231131", "213113", "213311", "213131", "311123", "311321", "331121", "312113", "312311", "332111",
  "314111", "221411", "431111", "111224", "111422", "121124", "121421", "141122", "141221", "112214",
  "112412", "122114", "122411", "142112", "142211", "241211", "221114", "413111", "241112", "134111",
  "111242", "121142", "121241", "114212", "124112", "124211", "411212", "421112", "421211", "212141",
  "214121", "412121", "111143", "111341", "131141", "114113", "114311", "411113", "411311", "113141",
  "114131", "311141", "411131", "211412", "211214", "211232", "2331112",
];
function c128Runs(text: string): number[] {
  const vals: number[] = [104];
  let sum = 104;
  for (let i = 0; i < text.length; i++) {
    let v = text.charCodeAt(i) - 32;
    if (v < 0 || v > 94) v = 63;
    vals.push(v); sum += v * (i + 1);
  }
  vals.push(sum % 103); vals.push(106);
  const runs: number[] = [];
  for (const val of vals) for (const ch of C128[val]) runs.push(Number(ch));
  return runs;
}

interface CardFields { name: string; matric: string; barcode: string; serial: string; faculty: string; prog: string; level: string; session: string; admitted: string; graduates: string; blood: string; expires: string; kinPhone: string }

/* the card's own colours, as on screen: the navy header, the red|green accent stripe, the red holder tag */
const DARK: [number, number, number] = [0.07, 0.13, 0.24];
const RED: [number, number, number] = [0.72, 0.12, 0.16];
const GREEN: [number, number, number] = [0.13, 0.5, 0.24];
const GREY: [number, number, number] = [0.42, 0.42, 0.42];

/** draw the card front with its bottom-left corner at (x0,y0) in a W×H box */
function drawFront(p: Page, x0: number, y0: number, W: number, H: number, f: CardFields, photo: Image | null, crest: Image | null) {
  const top = y0 + H;
  p.fill(x0, y0, W, H, 0.985);          // card face
  p.box(x0, y0, W, H, 0.7);
  // header band (dark)
  const hb = 30;
  p.fillRgb(x0, top - hb, W, hb, DARK);
  if (crest) p.jpeg(x0 + 8, top - hb + 5, 20, 20, crest);
  p.text(x0 + 34, top - 13, "REV. FR. MOSES ORSHIO ADASU UNIVERSITY", 7.4, true, [1, 1, 1]);
  p.text(x0 + 34, top - 23, "MAKURDI · BENUE STATE · NIGERIA", 5.6, false, [0.75, 0.8, 0.86]);
  // the red | green accent stripe under the header, as on the screen card
  p.fillRgb(x0, top - hb - 3, W * 0.55, 3, RED);
  p.fillRgb(x0 + W * 0.55, top - hb - 3, W * 0.45, 3, GREEN);
  // photo
  const px = x0 + 12, pw = 74, ph = 92, py = top - hb - 12 - ph;
  if (photo) p.jpeg(px, py, pw, ph, photo); else { p.fill(px, py, pw, ph, 0.85); p.box(px, py, pw, ph, 0.7); }
  p.fillRgb(px, py, 44, 13, RED); p.text(px + 6, py + 3.5, "STUDENT", 6.4, true, [1, 1, 1]);
  // who + grid
  const wx = px + pw + 14;
  let wy = top - hb - 22;
  p.text(wx, wy, clean(f.name).toUpperCase(), 10.5, true, DARK); wy -= 13;
  p.text(wx, wy, clean(f.matric), 9, true, RED); wy -= 16;
  const col2 = wx + 118;
  const row = (lx: number, label: string, value: string, yy: number) => {
    p.text(lx, yy, label.toUpperCase(), 5.4, false, GREY);
    p.text(lx, yy - 9, value || "—", 8, true, DARK);
  };
  row(wx, "Faculty", clean(f.faculty), wy); row(col2, "Level", f.level, wy); wy -= 23;
  row(wx, "Programme", clean(f.prog), wy); row(col2, "Blood group", f.blood, wy); wy -= 23;
  row(wx, "Admitted", f.admitted, wy); row(col2, "Graduates", f.graduates, wy);
  // foot
  p.rule(x0 + 12, y0 + 20, x0 + W - 12, y0 + 20, 0.5, 0.8);
  p.text(x0 + 12, y0 + 9, `Session ${f.session} · valid to ${f.expires}`, 6.6, false, DARK);
  p.text(x0 + W - 12 - textWidth(f.serial, 6.6, true), y0 + 9, f.serial, 6.6, true, GREY);
}

/** draw the card back with its bottom-left corner at (x0,y0) */
function drawBack(p: Page, x0: number, y0: number, W: number, H: number, f: CardFields) {
  const top = y0 + H;
  p.fill(x0, y0, W, H, 0.985);
  p.box(x0, y0, W, H, 0.7);
  // strip
  p.fillRgb(x0, top - 16, W, 16, DARK);
  p.text(x0 + 10, top - 11, "PROPERTY OF THE UNIVERSITY · NOT TRANSFERABLE", 6, true, [1, 1, 1]);
  // barcode
  const runs = c128Runs(f.barcode);
  const totalUnits = runs.reduce((a, b) => a + b, 0);
  const bw = W - 40, unit = bw / totalUnits, by = top - 16 - 8 - 30;
  let bx = x0 + 20; let dark = true;
  for (const r of runs) { if (dark) p.fill(bx, by, r * unit, 30, 0); bx += r * unit; dark = !dark; }
  p.text(x0 + W / 2 - textWidth(f.barcode, 8, true) / 2, by - 11, f.barcode, 8, true, DARK);
  // conditions (left) + verify (right)
  const cy = by - 24;
  const colW = W * 0.62;
  p.text(x0 + 14, cy, "CONDITIONS", 6, true, DARK);
  let ty = cy - 10;
  const terms = [
    "This ID card must always be in the owner's possession for identification at the gates, examination or wherever identification is necessary.",
    "Any alteration or erasure renders this card invalid. Loss must be reported immediately to the Chief Security Officer of the University.",
  ];
  for (const t of terms) { ty = p.paragraph(x0 + 14, ty, t, colW - 14, 5.8, 1.3) - 4; }
  // QR + verify text
  const { size, dark: qd } = qrMatrix(`MOAUM ID ${f.serial}`);
  const cell = 1.7, qDim = size * cell, qx = x0 + colW + 18, qy = cy - qDim - 2;
  for (let rr = 0; rr < size; rr++) for (let cc = 0; cc < size; cc++) if (qd[rr * size + cc]) p.fill(qx + cc * cell, qy + qDim - (rr + 1) * cell, cell, cell, 0);
  p.text(qx, qy - 9, "moaum.edu.ng/verify", 5.6, false, GREY);
  p.text(qx, qy - 17, f.serial, 6, true, DARK);
  p.text(qx, qy - 30, "In an emergency", 5.6, false, GREY);
  p.text(qx, qy - 39, f.kinPhone, 7, true, DARK);
  // signature lines
  p.rule(x0 + 16, y0 + 22, x0 + W * 0.45, y0 + 22, 0.5, 0.7);
  p.text(x0 + 16, y0 + 12, "Holder's signature", 5.6, false, GREY);
  p.rule(x0 + W * 0.55, y0 + 22, x0 + W - 16, y0 + 22, 0.5, 0.7);
  p.text(x0 + W * 0.55, y0 + 12, "Registrar", 5.6, false, GREY);
}

/** the student identity card as a printable PDF — the front and the back, drawn to the same design as on screen */
export async function GET() {
  const meR = await api<Me>("/api/v1/me");
  if (!meR.ok) return NextResponse.json(meR.problem, { status: meR.problem.status });
  const s = meR.data;
  const cardR = await api<Card>("/api/v1/me/id-card");
  if (!cardR.ok) return NextResponse.json(cardR.problem, { status: cardR.problem.status });
  const live = cardR.data.cards.find((x) => x.state === "ISSUED") ?? null;
  if (!live) {
    return NextResponse.json({ status: 409, title: "No identity card issued", detail: "The Library prints your card after matriculation and clearance; there is nothing to print yet." }, { status: 409 });
  }

  let photo: Image | null = null;
  try {
    const tok = await sessionToken();
    const res = await fetch(`${API_URL}/api/v1/me/passport`, { headers: tok ? { Authorization: `Bearer ${tok}` } : {}, cache: "no-store" });
    if (res.ok) { const buf = new Uint8Array(await res.arrayBuffer()); const dim = jpegSize(buf); if (dim) photo = { data: buf, width: dim.width, height: dim.height }; }
  } catch { /* blank photo box */ }

  const matric = s.matricNo ?? "";
  const f: CardFields = {
    name: s.name, matric, barcode: matric.replace(/[^A-Za-z0-9]/g, ""), serial: live.card_no,
    faculty: s.faculty, prog: s.programme, level: String(s.level), session: s.session,
    admitted: (s.entrySession ?? "").slice(0, 4) || "—", graduates: "—", blood: "—",
    expires: day(live.valid_to), kinPhone: "—",
  };

  const p = new Page();
  const crest = crestImage();
  const W = 360, H = Math.round((W * 54) / 85.6); // ID-1 aspect
  const x0 = (A4.w - W) / 2;
  p.textCenter(A4.w / 2, A4.h - 54, "Rev. Fr. Moses Orshio Adasu University - Student Identity Card", 12, true, DARK);
  p.textCenter(A4.w / 2, A4.h - 70, "A printed copy of your card. The card itself is issued by the Library.", 8.5, false, GREY);
  const frontTop = A4.h - 96;
  drawFront(p, x0, frontTop - H, W, H, f, photo, crest);
  p.textCenter(A4.w / 2, frontTop - H - 16, "FRONT", 7, true, GREY);
  const backTop = frontTop - H - 40;
  drawBack(p, x0, backTop - H, W, H, f);
  p.textCenter(A4.w / 2, backTop - H - 16, "BACK", 7, true, GREY);
  p.text(x0, 46, `${clean(s.name)} · ${matric} · generated ${day(new Date().toISOString())}`, 7, false, [0.5, 0.5, 0.5]);

  const bytes = pdf([p], `Identity card ${matric}`);
  return new NextResponse(Buffer.from(bytes), {
    status: 200,
    headers: { "content-type": "application/pdf", "content-disposition": `inline; filename="identity-card-${matric.replace(/[^A-Za-z0-9]/g, "-")}.pdf"` },
  });
}
