"use client";
/** V375: CBT slips — what a candidate shows at the door of their sitting. Each carries the candidate, the examination, the sitting
 *  and seat, and a QR of the portal's check-in page with the code the API signed for this candidate and this examination: an
 *  invigilator scans it with the phone's own camera (or from the board), sees the candidate's photograph on the portal and checks
 *  them in. The slip itself proves nothing on paper — the check is the portal's. Printed by the candidate, or by the office for a
 *  whole sitting. */
import QRCode from "qrcode";
import { esc, printDocument } from "@/lib/document/html";

export interface SlipCandidate { surname: string; other_names: string; number: string; number_label?: string; level?: number | null; programme?: string | null }
export interface Slip {
  token: string; course_code: string; course_title?: string | null; title: string; reference: string; session?: string | null;
  sitting: string; sitting_venue: string; sitting_starts_at: string; sitting_ends_at: string; seat_no: number; duration_minutes?: number | null;
  late_entry_until?: string | null; candidate: SlipCandidate;
}

const when = (iso: string) => new Date(iso).toLocaleString("en-GB", { weekday: "short", day: "2-digit", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" });
const hhmm = (iso: string) => new Date(iso).toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit" });

/** the page a slip's QR opens: the portal's check-in page, on the portal the slip was printed from */
export function checkInUrl(token: string): string {
  return `${window.location.origin}/cbt/checkin?t=${encodeURIComponent(token)}`;
}

const CSS = `<style>
.slips{display:grid;grid-template-columns:1fr 1fr;gap:10px}
.slip{border:1.4px dashed #555;border-radius:8px;padding:10px 12px;break-inside:avoid;page-break-inside:avoid;display:grid;grid-template-columns:1fr 112px;gap:8px;font-size:11px}
.slip h3{margin:0 0 2px;font-size:12px;letter-spacing:.04em}
.slip .seat{font-size:26px;font-weight:700;line-height:1}
.slip .k{color:#666;font-size:9px;text-transform:uppercase;letter-spacing:.05em;margin-top:5px}
.slip .v{font-weight:600}
.slip img{width:112px;height:112px}
.slip .hint{font-size:8.5px;color:#555;text-align:center;margin-top:2px}
.slips.one{grid-template-columns:1fr;max-width:420px}
</style>`;

async function slipHtml(s: Slip): Promise<string> {
  const qr = await QRCode.toDataURL(checkInUrl(s.token), { margin: 1, width: 224, errorCorrectionLevel: "M" });
  const c = s.candidate;
  return `<div class="slip"><div>
    <h3>CBT SLIP · ${esc(s.course_code)}</h3>
    <div>${esc(s.title)}${s.course_title ? ` — ${esc(s.course_title)}` : ""}</div>
    <div class="k">Candidate</div><div class="v">${esc(c.surname.toUpperCase())}, ${esc(c.other_names)}</div>
    <div>${esc(c.number_label ?? "Number")} ${esc(c.number)}${c.level ? ` · ${esc(c.level)} level` : ""}${c.programme ? ` · ${esc(c.programme)}` : ""}</div>
    <div class="k">Sitting</div><div class="v">${esc(s.sitting)} · ${esc(s.sitting_venue)}</div>
    <div>${esc(when(s.sitting_starts_at))} to ${esc(hhmm(s.sitting_ends_at))}${s.duration_minutes ? ` · ${esc(s.duration_minutes)} minutes once you start` : ""}</div>
    ${s.late_entry_until ? `<div>Start on your own by <b>${esc(hhmm(s.late_entry_until))}</b>; later, only if the invigilator admits you.</div>` : ""}
    <div class="k">Seat</div><div class="seat">${esc(s.seat_no)}</div>
    <div class="k">${esc(s.reference)}${s.session ? ` · ${esc(s.session)}` : ""}</div>
  </div><div><img src="${qr}" alt="Check-in code"><div class="hint">Show this at the door. The invigilator scans it and checks your face against your photograph on the portal.</div></div></div>`;
}

/** print one candidate's slip, or a sitting's slips two to a row */
export async function printSlips(title: string, subtitle: string, slips: Slip[]): Promise<void> {
  const cards = await Promise.all(slips.map(slipHtml));
  await printDocument("FORM", {
    title, subtitle, copy: null, confidentiality: null,
    bodyHtml: `${CSS}<div class="slips${slips.length === 1 ? " one" : ""}">${cards.join("")}</div>`,
    footnote: "Each slip's QR opens the portal's check-in page for that candidate and examination only; the portal checks the code. Keep your slip until you leave the hall.",
  });
}
