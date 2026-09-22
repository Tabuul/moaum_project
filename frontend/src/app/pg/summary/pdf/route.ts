import { NextResponse } from "next/server";
import { api, API_URL } from "@/lib/api";
import { sessionToken } from "@/lib/session";
import { A4, Page, pdf, jpegSize } from "@/lib/pdf-write";
import { crestImage } from "@/lib/pdf-crest";

export const dynamic = "force-dynamic";

interface Deg { kind: string; institution: string | null; award: string | null; field?: string | null; class_of_degree: string | null; cgpa: number | null; year: number | null }
interface Ref { name: string; email: string | null; institution: string | null; position: string | null }
interface Doc { kind: string; filename: string }
interface PgMe {
  applicationNo: string; session: string; name: string; surname: string; otherNames: string;
  email: string; phone: string | null; entryLevel: number; programme: string; award: string | null;
  faculty: string; department: string; submittedAt: string | null; feeConfirmedAt: string | null;
  biodata: { sex: string | null; dateOfBirth: string | null; stateOfOrigin: string | null; lga: string | null };
  prior: { institution: string | null; award: string | null; classOfDegree: string | null; cgpa: number | null; year: number | null };
  proposal: { title: string | null; text: string | null };
  referees: Ref[]; priorDegrees: Deg[]; documents: Doc[];
}

const clean = (s: string | null | undefined) => (s ?? "").replace(/[^\x20-\x7E]/g, " ").replace(/\s+/g, " ").trim();
const day = (iso: string | null) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" }) : "—");
const QUAL: Record<string, string> = { FIRST: "First degree", MASTERS: "Master's degree", PGD: "Postgraduate Diploma", HND: "Higher National Diploma", ND: "National Diploma", NCE: "NCE", PHD: "Doctorate", OTHER: "Other qualification" };
const LEVEL: Record<number, string> = { 700: "Postgraduate Diploma", 800: "Master's", 900: "MPhil / PhD" };

/** the applicant's application summary as a PDF — printable and downloadable once they are signed in */
export async function GET() {
  const me = await api<PgMe>("/api/v1/pg/me");
  if (!me.ok) return NextResponse.json(me.problem, { status: me.problem.status });
  const s = me.data;

  // the applicant's passport, so it shows on the printed summary (JPEG can be embedded directly)
  let photo: { width: number; height: number; data: Uint8Array } | null = null;
  try {
    const tok = await sessionToken();
    const res = await fetch(`${API_URL}/api/v1/pg/passport/image?format=jpeg`, { headers: tok ? { Authorization: `Bearer ${tok}` } : {}, cache: "no-store" });
    if (res.ok && (res.headers.get("content-type") ?? "").includes("jpeg")) {
      const buf = new Uint8Array(await res.arrayBuffer());
      const dim = jpegSize(buf);
      if (dim) photo = { width: dim.width, height: dim.height, data: buf };
    }
  } catch { /* no passport, or not a JPEG — the summary prints without it */ }

  const p = new Page();
  const L = 56;
  const crest = crestImage();
  const cx = A4.w / 2;
  let y = A4.h - 44;
  if (crest) p.jpeg(cx - 21, y - 42, 42, 42, crest);
  if (photo) p.jpeg(A4.w - L - 66, A4.h - 44 - 80, 66, 80, photo);   // passport, top-right
  p.textCenter(cx, y - 55, "REV. FR. MOSES ORSHIO ADASU UNIVERSITY, MAKURDI", 12, true);
  p.textCenter(cx, y - 68, "School of Postgraduate Studies", 9, false, [0.35, 0.35, 0.35]);
  p.textCenter(cx, y - 84, "APPLICATION SUMMARY", 12, true, [0.1, 0.25, 0.4]);
  y -= 96;
  p.rule(L, y, A4.w - L, y, 1, 0.2);
  y -= 20;

  const row = (k: string, v: string) => { p.text(L, y, k.toUpperCase(), 7, false, [0.45, 0.45, 0.45]); p.text(L + 120, y, clean(v) || "—", 10, true); y -= 15; };
  // a light heading band with dark-navy text (was a dark bar with white text)
  const section = (t: string) => { y -= 8; p.fill(L, y - 4, A4.w - 2 * L, 15, 0.9); p.text(L + 6, y, t, 8, true, [0.1, 0.25, 0.4]); y -= 20; };

  section("APPLICATION");
  row("Application number", s.applicationNo);
  row("Session", s.session);
  row("Programme", `${s.programme}${s.award ? ` (${s.award})` : ""}`);
  row("Level", LEVEL[s.entryLevel] ?? String(s.entryLevel));
  row("Faculty", s.faculty);
  row("Department", s.department);
  row("Submitted", day(s.submittedAt));
  row("Application fee", s.feeConfirmedAt ? `Paid — ${day(s.feeConfirmedAt)}` : "Not yet paid");

  section("APPLICANT");
  row("Name", `${s.surname}, ${s.otherNames}`);
  row("Sex", s.biodata.sex === "F" ? "Female" : s.biodata.sex === "M" ? "Male" : "—");
  row("Date of birth", day(s.biodata.dateOfBirth));
  row("State of origin", s.biodata.stateOfOrigin ?? "—");
  row("LGA", s.biodata.lga ?? "—");
  row("Email", s.email);
  row("Phone", s.phone ?? "—");

  const degs: Deg[] = (s.priorDegrees && s.priorDegrees.length)
    ? s.priorDegrees
    : (s.prior && (s.prior.institution || s.prior.award)
      ? [{ kind: "FIRST", institution: s.prior.institution, award: s.prior.award, field: null, class_of_degree: s.prior.classOfDegree, cgpa: s.prior.cgpa, year: s.prior.year }]
      : []);
  if (degs.length) {
    section("QUALIFICATIONS");
    for (const d of degs) {
      p.text(L, y, (QUAL[d.kind] ?? d.kind).toUpperCase(), 7, false, [0.45, 0.45, 0.45]);
      p.text(L + 120, y, clean(`${d.award ?? ""}${d.field ? ` (${d.field})` : ""}`) || "—", 10, true);
      y -= 13;
      p.text(L + 120, y, clean([d.institution, d.class_of_degree, d.cgpa != null ? `CGPA ${d.cgpa}` : null, d.year != null ? String(d.year) : null].filter(Boolean).join(" · ")) || "—", 8, false, [0.45, 0.45, 0.45]);
      y -= 16;
    }
  }

  if (s.proposal && (s.proposal.title || s.proposal.text)) {
    section("RESEARCH PROPOSAL");
    if (s.proposal.title) row("Topic", s.proposal.title);
    if (s.proposal.text) { y = p.paragraph(L, y, clean(s.proposal.text), A4.w - 2 * L, 9, 1.35) - 4; }
  }

  if (s.referees && s.referees.length) {
    section("REFEREES");
    for (const r of s.referees) {
      p.text(L, y, clean(r.name) || "—", 10, true);
      p.text(L + 220, y, clean([r.position, r.institution, r.email].filter(Boolean).join(" · ")), 8, false, [0.4, 0.4, 0.4]);
      y -= 15;
    }
  }

  y -= 10;
  p.rule(L, y, A4.w - L, y, 0.5, 0.6);
  y -= 12;
  p.text(L, y, `Documents on file: ${(s.documents || []).map((d) => d.kind.replace("_", " ").toLowerCase()).join(", ") || "none"}.`, 8, false, [0.45, 0.45, 0.45]);
  p.text(L, 40, `Generated ${day(new Date().toISOString())} · ${clean(s.name)} · ${s.applicationNo}`, 7, false, [0.45, 0.45, 0.45]);

  const bytes = pdf([p], `Application summary ${s.applicationNo}`);
  return new NextResponse(Buffer.from(bytes), {
    status: 200,
    headers: {
      "content-type": "application/pdf",
      "content-disposition": `inline; filename="pg-application-${s.applicationNo.replace(/\//g, "-")}.pdf"`,
    },
  });
}
