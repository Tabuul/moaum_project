/** A kept return as a PDF, built on the server from the rows as they were kept (V229): the
 *  crest and the University's name, the title, period and verification code, then the table
 *  across as many landscape pages as it takes, each page footed with the code and its number.
 *  The browser's print gives the same document on screen; this is the one that goes by email. */
import { A4, Page, pdf } from "@/lib/pdf-write";
import { crestImage } from "@/lib/pdf-crest";

export interface KeptReport {
  title: string; subtitle?: string | null; period: string; verification_code: string;
  taken_at: string; taken_office?: string | null; taken_by_name?: string | null;
  filed_to?: string | null; filed_at?: string | null; note?: string | null;
  headers: string[]; rows: (string | number | null)[][];
}

const W = A4.h, H = A4.w;           // landscape
const L = 36, R = 36, TOP = 36, BOTTOM = 40;
const INK: [number, number, number] = [0.09, 0.15, 0.23];
const MUTED: [number, number, number] = [0.42, 0.47, 0.53];

const isNum = (v: unknown) => typeof v === "number" || (typeof v === "string" && /^-?[\d,]+(\.\d+)?%?$/.test(v.trim()) && v.trim() !== "");
const fmt = (v: string | number | null) => (v == null ? "—" : typeof v === "number" ? v.toLocaleString("en-NG") : String(v));
const day = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" }) : "—");

/** column widths in points: proportional to the longest cell (capped), never narrower than the header allows */
function widths(headers: string[], rows: (string | number | null)[][], avail: number, size: number): number[] {
  const cw = size * 0.52;
  const want = headers.map((h, i) => {
    let m = h.length;
    for (const r of rows.slice(0, 400)) m = Math.max(m, Math.min(48, fmt(r[i] ?? null).length));
    return Math.max(6, m) * cw + 10;
  });
  const sum = want.reduce((a, b) => a + b, 0);
  const k = sum > avail ? avail / sum : 1;
  return want.map((w) => w * k);
}

/** text cut to what fits a column, with an ellipsis */
function clip(s: string, width: number, size: number): string {
  const max = Math.max(3, Math.floor((width - 6) / (size * 0.52)));
  return s.length <= max ? s : s.slice(0, max - 1) + "…";
}

export function keptReportPdf(k: KeptReport): Uint8Array {
  const pages: Page[] = [];
  const size = k.headers.length > 10 ? 7 : k.headers.length > 7 ? 7.5 : 8.5;
  const rowH = size * 1.9;
  const cols = widths(k.headers, k.rows, W - L - R, size);
  const numeric = k.headers.map((_, i) => k.rows.length > 0 && k.rows.every((r) => r[i] == null || r[i] === "" || isNum(r[i])) && k.rows.some((r) => r[i] != null && r[i] !== ""));
  const crest = crestImage();
  const total = Math.max(1, Math.ceil(k.rows.length / Math.floor((H - TOP - 118 - BOTTOM) / rowH)) );

  let idx = 0;
  let pageNo = 0;
  do {
    pageNo++;
    const p = new Page();
    p.size = { w: W, h: H };
    // header
    let y = H - TOP;
    if (crest) p.jpeg(L, y - 40, 40, 40, crest);
    const tx = crest ? L + 50 : L;
    p.text(tx, y - 14, "REV. FR. MOSES ORSHIO ADASU UNIVERSITY, MAKURDI", 11, true, INK);
    p.text(tx, y - 27, "Makurdi, Benue State · Unified University Portal", 8, false, MUTED);
    p.text(W - R - 200, y - 14, `Kept copy · ${k.verification_code}`, 8, true, INK);
    p.text(W - R - 200, y - 27, `Page ${pageNo} of ${total}`, 8, false, MUTED);
    y -= 48;
    p.rule(L, y, W - R, y, 1, 0.2);
    y -= 18;
    p.text(L, y, k.title, 14, true, INK);
    y -= 14;
    p.text(L, y, `${k.subtitle ? k.subtitle + " · " : ""}${k.period}`, 8.5, false, MUTED);
    y -= 16;

    // table header
    p.fill(L, y - rowH + 4, W - L - R, rowH, 0.93);
    let x = L;
    k.headers.forEach((h, i) => {
      const s = clip(h, cols[i], size);
      if (numeric[i]) p.text(x + cols[i] - 3 - s.length * size * 0.52, y - rowH + 4 + size * 0.55, s, size, true, INK);
      else p.text(x + 3, y - rowH + 4 + size * 0.55, s, size, true, INK);
      x += cols[i];
    });
    y -= rowH;

    // rows
    while (idx < k.rows.length && y - rowH > BOTTOM + 14) {
      const r = k.rows[idx];
      if (idx % 2 === 1) p.fill(L, y - rowH + 4, W - L - R, rowH, 0.975);
      x = L;
      k.headers.forEach((_, i) => {
        const s = clip(fmt(r[i] ?? null), cols[i], size);
        if (numeric[i]) p.text(x + cols[i] - 3 - s.length * size * 0.52, y - rowH + 4 + size * 0.55, s, size, false, INK);
        else p.text(x + 3, y - rowH + 4 + size * 0.55, s, size, false, INK);
        x += cols[i];
      });
      p.rule(L, y - rowH + 4, W - R, y - rowH + 4, 0.3, 0.85);
      y -= rowH;
      idx++;
    }
    if (k.rows.length === 0) p.text(L + 3, y - 12, "Nothing to return for this period.", size, false, MUTED);

    // footer
    const fy = BOTTOM - 6;
    p.rule(L, fy + 14, W - R, fy + 14, 0.6, 0.6);
    p.text(L, fy, `Kept ${day(k.taken_at)}${k.taken_by_name ? ` by ${k.taken_by_name}` : ""}${k.taken_office ? ` (${k.taken_office})` : ""}`
      + `${k.filed_at ? ` · filed with ${k.filed_to} on ${day(k.filed_at)}` : " · not yet filed"}. Verify at /verify/report/${k.verification_code}. A return is a view of the register, verified against it — not by its appearance.`, 6.8, false, MUTED);
    pages.push(p);
  } while (idx < k.rows.length);

  return pdf(pages, `${k.title} · ${k.period}`);
}
