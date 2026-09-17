import { NextResponse } from "next/server";
import { api, API_URL } from "@/lib/api";
import { sessionToken } from "@/lib/session";
import { BODY, type Application } from "@/lib/applicant";
import { A4, Page, pdf, jpegSize } from "@/lib/pdf-write";
import { brandHeader } from "@/lib/pdf-crest";

export const dynamic = "force-dynamic";

const day = (iso: string | null) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" }) : "—");
const clean = (s: string | null | undefined) => (s ?? "").replace(/[^\x20-\x7E]/g, " ").replace(/\s+/g, " ").trim();
const cut = (s: string, n: number) => (s.length > n ? s.slice(0, n - 1).trimEnd() + "..." : s);

/** decode a base64 data URL to raw bytes, or null */
function fromDataUrl(url: string | null | undefined): Uint8Array | null {
  if (!url) return null;
  const c = url.indexOf(",");
  if (c < 0) return null;
  try { return new Uint8Array(Buffer.from(url.slice(c + 1), "base64")); } catch { return null; }
}

/** the applicant's application form as a clean PDF, with the passport JAMB sent or the one uploaded */
export async function GET() {
  const mine = await api<Application>("/api/v1/applicant/me");
  if (!mine.ok) return NextResponse.json(mine.problem, { status: mine.problem.status });
  const a = mine.data;

  // the passport: the uploaded document if any, else JAMB's downloaded one (a data URL)
  let photo: { width: number; height: number; data: Uint8Array } | null = null;
  const doc = a.documents?.find((d) => d.kind === "PASSPORT");
  try {
    let buf: Uint8Array | null = null;
    if (doc) {
      const tok = await sessionToken();
      const res = await fetch(`${API_URL}/api/v1/applicant/me/documents/${doc.id}/content`, { headers: tok ? { Authorization: `Bearer ${tok}` } : {}, cache: "no-store" });
      if (res.ok) buf = new Uint8Array(await res.arrayBuffer());
    } else {
      buf = fromDataUrl(a.jambPassport);
    }
    if (buf) { const dim = jpegSize(buf); if (dim) photo = { width: dim.width, height: dim.height, data: buf }; }
  } catch { /* leave the box blank */ }

  const p = new Page();
  const L = 64;
  let y = brandHeader(p, L, "Application Form");

  // passport top-right
  const pw = 62, ph = 76, px = A4.w - L - pw, ptop = y + 6;
  if (photo) p.jpeg(px, ptop - ph, pw, ph, photo);
  else { p.rule(px, ptop, px + pw, ptop, 0.6, 0.7); p.rule(px, ptop - ph, px + pw, ptop - ph, 0.6, 0.7); p.rule(px, ptop, px, ptop - ph, 0.6, 0.7); p.rule(px + pw, ptop, px + pw, ptop - ph, 0.6, 0.7); p.text(px + 12, ptop - ph / 2, "PHOTO", 7.5, false, [0.6, 0.6, 0.6]); }

  const rows: [string, string][] = [
    ["Application number", clean(a.applicationNo)],
    ["Name", clean(a.name)],
    ["JAMB registration", clean(a.jambKey)],
    ["Date of birth", day(a.biodata.dateOfBirth)],
    ["Sex", a.biodata.sex === "F" ? "Female" : a.biodata.sex === "M" ? "Male" : "—"],
    ["State / LGA of origin", `${clean(a.biodata.stateOfOrigin) || "—"} · ${clean(a.biodata.lga) || "—"}`],
    ["Programme", `${clean(a.programme) || "—"}${a.faculty ? ` · Faculty of ${clean(a.faculty)}` : ""}`],
    ["Entry", a.entryMode === "UTME" ? `UTME · score ${a.biodata.utme ?? "—"}` : "Direct Entry"],
    ["Email / phone", `${clean(a.email) || "—"} · ${clean(a.phone) || "—"}`],
    ["Next of kin", clean(a.biodata.nextOfKin) || "—"],
    ["Session", clean(a.session)],
  ];
  for (const [k, val] of rows) {
    p.text(L, y, k.toUpperCase(), 7.5, false, [0.4, 0.4, 0.4]);
    p.text(L + 150, y, cut(val, 60), 10.5);
    y -= 17;
  }
  y = Math.min(y, ptop - ph) - 12;

  // ── O'Level, as JAMB sent it ──
  p.fill(L, y - 4, A4.w - 2 * L, 18, 0.2);
  p.text(L + 8, y, "O’LEVEL RESULTS", 8, true, [1, 1, 1]);
  y -= 22;
  if (a.olevel.length) {
    for (const s of a.olevel) {
      p.text(L + 8, y, `${BODY[s.body] ?? s.body}${s.year ? ` · ${s.year}` : ""}`, 9, true);
      y -= 14;
      const line = s.subjects.map((g) => `${clean(g.subject)} ${clean(g.grade)}`).join("   ");
      y = p.paragraph(L + 16, y, line || "No subjects recorded", A4.w - 2 * L - 16, 9);
      y -= 8;
    }
  } else {
    p.text(L + 8, y, "No O’Level result has reached the University from JAMB yet.", 9, false, [0.3, 0.3, 0.3]);
    y -= 16;
  }

  y -= 10;
  p.text(L, y, a.submittedAt ? `Submitted on ${day(a.submittedAt)}` : "Not yet submitted", 10, true,
    a.submittedAt ? [0.1, 0.4, 0.2] : [0.72, 0.11, 0.11]);
  y -= 24;
  y = p.paragraph(L, y, "This form is a view of the application record held by the University. The biodata, programme and O’Level results are as JAMB sent them; the programme choice comes from JAMB and cannot be changed on the portal. If anything on it is wrong, write to the Registry quoting the application number — do not create a second account.", A4.w - 2 * L, 9);
  p.text(L, 50, `Issued by the portal on ${day(new Date().toISOString())} · ${clean(a.applicationNo)}`, 7.5, false, [0.4, 0.4, 0.4]);

  const bytes = pdf([p], `Application form ${a.applicationNo}`);
  return new NextResponse(Buffer.from(bytes), { status: 200, headers: { "content-type": "application/pdf", "content-disposition": `inline; filename="application-form-${a.applicationNo.replace(/\//g, "-")}.pdf"` } });
}
