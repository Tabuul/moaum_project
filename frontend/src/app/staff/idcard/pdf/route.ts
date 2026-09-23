import { NextResponse } from "next/server";
import { api, API_URL } from "@/lib/api";
import { sessionToken } from "@/lib/session";
import { A4, Page, pdf, jpegSize, type Image } from "@/lib/pdf-write";
import { crestImage } from "@/lib/pdf-crest";
import { qrMatrix } from "@/lib/qr";
import { cookies } from "next/headers";

export const dynamic = "force-dynamic";

/**
 * The staff identity card as a printable PDF — portrait (vertical), unlike the student card, as the
 * University issues it: the crest and name across the top, the photograph large beneath, the holder's
 * name, staff number, rank and unit, and on the back the barcode, the conditions, the verification QR
 * and the signature lines. Without ?id the card is the signed-in person's own; with ?id it is the
 * named member of staff's, for the offices that read the staff register.
 */

const day = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "2-digit", month: "short", year: "numeric" }) : "—");
const clean = (s: string | null | undefined) => (s ?? "").replace(/[^\x20-\x7E]/g, " ").replace(/\s+/g, " ").trim();
const textWidth = (s: string, size: number, bold = false) => s.length * size * (bold ? 0.54 : 0.5);
const rankCase = (r: string | null) => (r ? r.toLowerCase().replace(/\b[a-z]/g, (c) => c.toUpperCase()).replace(/\bIi\b/g, "II") : "");

/* Code 128-B, as on the student card */
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

interface Person {
  id: string; staff_number: string | null; surname: string; given_names: string; rank: string | null; department: string | null;
  faculty: string | null; category: string | null; date_first_appointment: string | null; appointment_date: string | null;
  status: string; has_photo: boolean; phone: string | null; email: string | null;
}
interface Office { office: string; office_code: string; live: boolean }
interface StaffRecord { person: Person; offices: Office[] }

interface CardFields { name: string; staffNo: string; barcode: string; serial: string; rank: string; unit: string; faculty: string; category: string; office: string; appointed: string; expires: string; phone: string }

const DARK: [number, number, number] = [0.07, 0.13, 0.24];
const RED: [number, number, number] = [0.72, 0.12, 0.16];
const GREEN: [number, number, number] = [0.13, 0.5, 0.24];
const GREY: [number, number, number] = [0.42, 0.42, 0.42];

/** the front, portrait: header, stripe, the photograph, the holder */
function drawFront(p: Page, x0: number, y0: number, W: number, H: number, f: CardFields, photo: Image | null, crest: Image | null) {
  const top = y0 + H;
  p.fill(x0, y0, W, H, 0.985);
  p.box(x0, y0, W, H, 0.7);
  const hb = 46;
  p.fillRgb(x0, top - hb, W, hb, DARK);
  if (crest) p.jpeg(x0 + W / 2 - 11, top - 24, 22, 22, crest);
  p.textCenter(x0 + W / 2, top - 33, "REV. FR. MOSES ORSHIO ADASU UNIVERSITY", 6.4, true, [1, 1, 1]);
  p.textCenter(x0 + W / 2, top - 41.5, "MAKURDI · BENUE STATE · NIGERIA", 5, false, [0.75, 0.8, 0.86]);
  p.fillRgb(x0, top - hb - 3, W * 0.55, 3, RED);
  p.fillRgb(x0 + W * 0.55, top - hb - 3, W * 0.45, 3, GREEN);
  // the photograph, centred and large
  const pw = 96, ph = 118, px = x0 + (W - pw) / 2, py = top - hb - 14 - ph;
  if (photo) p.jpeg(px, py, pw, ph, photo); else { p.fill(px, py, pw, ph, 0.85); p.box(px, py, pw, ph, 0.7); }
  p.fillRgb(px, py, 40, 13, RED); p.text(px + 8, py + 3.5, "STAFF", 6.4, true, [1, 1, 1]);
  // the holder
  let y = py - 16;
  const name = clean(f.name).toUpperCase();
  const nameSize = textWidth(name, 10.5, true) > W - 20 ? 8.6 : 10.5;
  p.textCenter(x0 + W / 2, y, name, nameSize, true, DARK); y -= 12;
  p.textCenter(x0 + W / 2, y, f.staffNo, 8.6, true, RED); y -= 16;
  const row = (label: string, value: string) => {
    p.text(x0 + 14, y, label.toUpperCase(), 5.2, false, GREY);
    const v = clean(value) || "—";
    const size = textWidth(v, 7.8, true) > W - 28 ? 6.6 : 7.8;
    p.text(x0 + 14, y - 9, v, size, true, DARK);
    y -= 20;
  };
  row("Rank / designation", f.rank || f.office);
  row(f.faculty ? "Department" : "Unit", f.unit);
  if (f.faculty) row("Faculty", f.faculty);
  row("Category", f.category);
  row("Appointed", f.appointed);
  // foot
  p.rule(x0 + 12, y0 + 20, x0 + W - 12, y0 + 20, 0.5, 0.8);
  p.text(x0 + 12, y0 + 9, `Valid to ${f.expires}`, 6.2, false, DARK);
  p.text(x0 + W - 12 - textWidth(f.serial, 6.2, true), y0 + 9, f.serial, 6.2, true, GREY);
}

/** the back, portrait: strip, barcode, conditions, QR, signatures */
function drawBack(p: Page, x0: number, y0: number, W: number, H: number, f: CardFields) {
  const top = y0 + H;
  p.fill(x0, y0, W, H, 0.985);
  p.box(x0, y0, W, H, 0.7);
  p.fillRgb(x0, top - 16, W, 16, DARK);
  p.textCenter(x0 + W / 2, top - 11, "PROPERTY OF THE UNIVERSITY · NOT TRANSFERABLE", 5.6, true, [1, 1, 1]);
  const runs = c128Runs(f.barcode);
  const totalUnits = runs.reduce((a, b) => a + b, 0);
  const bw = W - 36, unit = bw / totalUnits, by = top - 16 - 10 - 28;
  let bx = x0 + 18; let dark = true;
  for (const r of runs) { if (dark) p.fill(bx, by, r * unit, 28, 0); bx += r * unit; dark = !dark; }
  p.textCenter(x0 + W / 2, by - 11, f.barcode, 7.6, true, DARK);
  let ty = by - 28;
  p.text(x0 + 14, ty, "CONDITIONS", 6, true, DARK); ty -= 10;
  const terms = [
    "This ID card must always be in the owner's possession for identification at the gates, examination or wherever identification is necessary.",
    "Any alteration or erasure renders this card invalid. Loss must be reported immediately to the Chief Security Officer of the University.",
  ];
  for (const t of terms) { ty = p.paragraph(x0 + 14, ty, t, W - 28, 5.8, 1.3) - 3; }
  // QR beside the verify text
  const { size, dark: qd } = qrMatrix(`MOAUM STAFF ${f.serial}`);
  const cell = 1.6, qDim = size * cell, qx = x0 + 14, qy = ty - qDim - 4;
  for (let rr = 0; rr < size; rr++) for (let cc = 0; cc < size; cc++) if (qd[rr * size + cc]) p.fill(qx + cc * cell, qy + qDim - (rr + 1) * cell, cell, cell, 0);
  const tx = qx + qDim + 10;
  p.text(tx, qy + qDim - 8, "moaum.edu.ng/verify", 5.6, false, GREY);
  p.text(tx, qy + qDim - 17, f.serial, 6, true, DARK);
  p.text(tx, qy + qDim - 30, "If found, return to the Security post,", 5.4, false, GREY);
  p.text(tx, qy + qDim - 38, "Km 1 Gboko Road, Makurdi.", 5.4, false, GREY);
  if (f.phone) { p.text(tx, qy + qDim - 51, "Holder's phone", 5.4, false, GREY); p.text(tx, qy + qDim - 60, f.phone, 6.6, true, DARK); }
  // signatures
  p.rule(x0 + 14, y0 + 44, x0 + W - 14, y0 + 44, 0.5, 0.7);
  p.text(x0 + 14, y0 + 34, "Holder's signature", 5.6, false, GREY);
  p.rule(x0 + 14, y0 + 20, x0 + W - 14, y0 + 20, 0.5, 0.7);
  p.text(x0 + 14, y0 + 10, "Registrar", 5.6, false, GREY);
}

export async function GET(req: Request) {
  const id = new URL(req.url).searchParams.get("id");
  const self = !id;
  const r = await api<StaffRecord>(self ? "/api/v1/hr/staff/me" : `/api/v1/hr/staff/${encodeURIComponent(id!)}`);
  if (!r.ok) return NextResponse.json(r.problem, { status: r.problem.status });
  const s = r.data.person;
  if (!s.staff_number) {
    return NextResponse.json({ status: 409, title: "No staff number", detail: "A staff identity card carries the staff number the Registry issued; this person has none on record yet." }, { status: 409 });
  }

  let photo: Image | null = null;
  if (s.has_photo) {
    try {
      const tok = await sessionToken();
      const office = (await cookies()).get("moaum_office")?.value;
      const headers: Record<string, string> = tok ? { Authorization: `Bearer ${tok}` } : {};
      if (office) headers["X-Active-Office"] = office;
      const res = await fetch(`${API_URL}${self ? "/api/v1/hr/staff/me/photo" : `/api/v1/hr/staff/${encodeURIComponent(id!)}/photo`}`, { headers, cache: "no-store" });
      // the writer embeds JPEG; a PNG photograph leaves the frame blank on the print (the screen shows it)
      if (res.ok && (res.headers.get("content-type") ?? "").includes("jpeg")) {
        const buf = new Uint8Array(await res.arrayBuffer()); const dim = jpegSize(buf);
        if (dim) photo = { data: buf, width: dim.width, height: dim.height };
      }
    } catch { /* blank photo box */ }
  }

  const live = r.data.offices.filter((o) => o.live);
  const office = live.find((o) => !["lecturer"].includes(o.office_code))?.office ?? live[0]?.office ?? "";
  const expiresOn = new Date(); expiresOn.setFullYear(expiresOn.getFullYear() + 3); expiresOn.setMonth(11, 31);
  const f: CardFields = {
    name: `${s.surname}, ${s.given_names}`, staffNo: s.staff_number, barcode: s.staff_number.replace(/[^A-Za-z0-9]/g, ""),
    serial: `STF-${s.staff_number.replace(/[^A-Za-z0-9]/g, "").slice(-8)}-${new Date().getFullYear()}`,
    rank: rankCase(s.rank), unit: s.department ?? office, faculty: s.faculty ?? "",
    category: s.category === "ACADEMIC" ? "Academic staff" : s.category === "NON_ACADEMIC" ? "Non-teaching staff" : (live.some((o) => ["lecturer", "hod", "dean"].includes(o.office_code)) ? "Academic staff" : "Staff"),
    office, appointed: day(s.date_first_appointment ?? s.appointment_date), expires: day(expiresOn.toISOString()), phone: clean(s.phone),
  };

  const p = new Page();
  const crest = crestImage();
  const W = 230, H = Math.round((W * 85.6) / 54); // ID-1 aspect, portrait
  const gap = 40;
  const x1 = A4.w / 2 - W - gap / 2, x2 = A4.w / 2 + gap / 2;
  p.textCenter(A4.w / 2, A4.h - 54, "Rev. Fr. Moses Orshio Adasu University - Staff Identity Card", 12, true, DARK);
  p.textCenter(A4.w / 2, A4.h - 70, self ? "A printed copy of your card. The card itself is issued by the Registry." : `Printed for ${clean(f.name)} by the office signed in.`, 8.5, false, GREY);
  const top = A4.h - 100;
  drawFront(p, x1, top - H, W, H, f, photo, crest);
  p.textCenter(x1 + W / 2, top - H - 16, "FRONT", 7, true, GREY);
  drawBack(p, x2, top - H, W, H, f);
  p.textCenter(x2 + W / 2, top - H - 16, "BACK", 7, true, GREY);
  p.text(x1, 46, `${clean(f.name)} · ${f.staffNo} · generated ${day(new Date().toISOString())}`, 7, false, [0.5, 0.5, 0.5]);

  const bytes = pdf([p], `Staff identity card ${f.staffNo}`);
  return new NextResponse(Buffer.from(bytes), {
    status: 200,
    headers: { "content-type": "application/pdf", "content-disposition": `inline; filename="staff-id-${f.staffNo.replace(/[^A-Za-z0-9]/g, "-")}.pdf"` },
  });
}
