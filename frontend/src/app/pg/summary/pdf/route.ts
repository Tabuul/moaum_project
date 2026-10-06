import { NextResponse } from "next/server";
import { api, API_URL } from "@/lib/api";
import { sessionToken } from "@/lib/session";
import { A4, Page, jpegSize, textWidth } from "@/lib/pdf-write";
import { docLabel } from "@/lib/pg-documents";
import { crestImage } from "@/lib/pdf-crest";

import { loadInstitution } from "@/lib/document/institution-server";
import { finishPdf } from "@/lib/document/pdf";

export const dynamic = "force-dynamic";

interface Deg { kind: string; institution: string | null; award: string | null; field?: string | null; class_of_degree: string | null; cgpa: number | null; year: number | null }
interface Ref { name: string; email: string | null; phone?: string | null; institution: string | null; position: string | null; submitted_at?: string | null }
interface Doc { kind: string; filename: string }
interface PgMe {
  applicationNo: string; session: string; name: string; surname: string; otherNames: string;
  email: string; phone: string | null; entryLevel: number; programme: string; award: string | null;
  faculty: string; department: string; submittedAt: string | null; feeConfirmedAt: string | null;
  biodata: { sex: string | null; dateOfBirth: string | null; stateOfOrigin: string | null; lga: string | null; nationality?: string | null; contactAddress?: string | null };
  prior: { institution: string | null; award: string | null; classOfDegree: string | null; cgpa: number | null; year: number | null };
  proposal: { title: string | null; text: string | null };
  referees: Ref[]; priorDegrees: Deg[]; documents: Doc[];
}

const clean = (s: string | null | undefined) => (s ?? "").replace(/[^\x20-\x7E]/g, " ").replace(/\s+/g, " ").trim();
const day = (iso: string | null) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" }) : "—");
const QUAL: Record<string, string> = { FIRST: "First degree", MASTERS: "Master's degree", PGD: "Postgraduate Diploma", HND: "Higher National Diploma", ND: "National Diploma", NCE: "NCE", PHD: "Doctorate", OTHER: "Other qualification" };
const LEVEL: Record<number, string> = { 700: "Postgraduate Diploma", 800: "Master", 900: "MPhil / PhD" };

/** the applicant's application summary as a PDF — printable and downloadable once they are signed in */
export async function GET() {
  await loadInstitution();
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

  const pages: Page[] = [new Page()];
  let p = pages[0];
  const L = 56;
  const BOTTOM = 64;
  const crest = crestImage();
  const cx = A4.w / 2;
  let y = A4.h - 44;
  if (crest) p.jpeg(cx - 20, y - 40, 40, 40, crest);
  // the University, the School in bold beneath it, and the heading — each centred on the page by its measured width
  p.textCenter(cx, y - 55, "REV. FR. MOSES ORSHIO ADASU UNIVERSITY, MAKURDI", 12, true);
  p.textCenter(cx, y - 71, "School of Postgraduate Studies", 11.5, true, [0.12, 0.12, 0.12]);
  p.textCenter(cx, y - 89, "APPLICATION SUMMARY", 12, true, [0.1, 0.25, 0.4]);
  y -= 104;
  p.rule(L, y, A4.w - L, y, 1, 0.2);
  y -= 20;

  const W = A4.w - 2 * L;
  const NAVY: [number, number, number] = [0.1, 0.25, 0.4];
  const GREY: [number, number, number] = [0.45, 0.45, 0.45];
  /** a new page when the next block does not fit; the content continues under a slim running head */
  const room = (h: number) => {
    if (y - h >= BOTTOM) return;
    p = new Page();
    pages.push(p);
    y = A4.h - 50;
    p.text(L, y, `Application summary · ${clean(s.applicationNo)} (continued)`, 8, false, GREY);
    y -= 22;
  };
  const row = (k: string, v: string) => { room(15); p.text(L, y, k.toUpperCase(), 7, false, GREY); p.text(L + 120, y, clean(v) || "—", 10, true); y -= 15; };
  // a light heading band with dark-navy text
  const section = (t: string) => { room(48); y -= 8; p.fill(L, y - 4, W, 15, 0.9); p.text(L + 6, y, t, 8, true, NAVY); y -= 20; };

  /** a cell's text in lines that fit its width (Helvetica averages about half the size a character); an unbroken
   *  string longer than the width — an email — is cut across lines rather than run over its neighbour */
  const lines = (text: string, width: number, size: number): string[] => {
    const max = Math.max(4, Math.floor((width - 8) / (size * 0.52)));
    const out: string[] = [];
    let line = "";
    for (const word of clean(text).split(" ").filter(Boolean)) {
      const parts = word.length > max ? word.match(new RegExp(`.{1,${max}}`, "g")) ?? [word] : [word];
      for (const part of parts) {
        if (!line) line = part;
        else if ((line + " " + part).length <= max) line += " " + part;
        else { out.push(line); line = part; }
      }
    }
    if (line) out.push(line);
    return out.length ? out : ["—"];
  };
  /** a labelled value too long for one line (the contact address), wrapped to the measured width beside its label */
  const rowLong = (k: string, v: string) => {
    const words = clean(v).split(" ").filter(Boolean);
    const max = W - 120;
    const out: string[] = [];
    let line = "";
    for (const w of words) {
      const next = line ? `${line} ${w}` : w;
      if (line && textWidth(next, 10, true) > max) { out.push(line); line = w; } else line = next;
    }
    if (line) out.push(line);
    if (!out.length) out.push("—");
    room(15 * out.length);
    p.text(L, y, k.toUpperCase(), 7, false, GREY);
    out.forEach((t, i) => p.text(L + 120, y - i * 13, t, 10, true));
    y -= 15 + (out.length - 1) * 13;
  };
  /** a ruled table: a shaded header, every cell wrapped to its column, S/N first, the header repeated on a new page */
  const table = (cols: { h: string; w: number }[], rows: string[][]) => {
    const size = 8, lead = 10, pad = 5;
    const scale = W / cols.reduce((a, c) => a + c.w, 0);
    const ws = cols.map((c) => c.w * scale);
    const xs = ws.map((_, i) => L + ws.slice(0, i).reduce((a, b) => a + b, 0));
    const header = () => {
      const hh = 16;
      p.fill(L, y - hh + 4, W, hh, 0.88);
      cols.forEach((c, i) => p.text(xs[i] + 4, y - 7, c.h.toUpperCase(), 6.5, true, NAVY));
      p.box(L, y - hh + 4, W, hh, 0.7);
      ws.slice(0, -1).forEach((_, i) => p.rule(xs[i + 1], y + 4, xs[i + 1], y - hh + 4, 0.4, 0.7));
      y -= hh;
    };
    room(16 + lead + 2 * pad);
    header();
    rows.forEach((r, ri) => {
      const cells = r.map((v, i) => lines(v || "—", ws[i], size));
      const h = Math.max(...cells.map((c) => c.length)) * lead + 2 * pad - 2;
      if (y - h < BOTTOM) { room(h + 40); header(); }
      if (ri % 2 === 1) p.fill(L, y - h + 4, W, h, 0.97);
      cells.forEach((c, i) => c.forEach((t, li) => p.text(xs[i] + 4, y - pad - 3 - li * lead, t, size, i === 1)));
      p.box(L, y - h + 4, W, h, 0.7);
      ws.slice(0, -1).forEach((_, i) => p.rule(xs[i + 1], y + 4, xs[i + 1], y - h + 4, 0.4, 0.7));
      y -= h;
    });
    y -= 10;
  };

  section("COURSE DETAILS");
  // the passport photograph, at the top-right of the course details
  if (photo) { const pw = 84, ph = 104; p.jpeg(A4.w - L - pw, y + 11 - ph, pw, ph, photo); }
  row("Application number", s.applicationNo);
  row("Session", s.session);
  row("Programme", s.programme);
  row("Level", LEVEL[s.entryLevel] ?? String(s.entryLevel));
  row("Faculty", s.faculty);
  row("Department", s.department);
  row("Date applied", day(s.submittedAt));
  row("Application fee", s.feeConfirmedAt ? "Paid" : "Not yet paid");

  section("APPLICANT DETAILS");
  row("Name", `${s.surname}, ${s.otherNames}`);
  row("Sex", s.biodata.sex === "F" ? "Female" : s.biodata.sex === "M" ? "Male" : "—");
  row("Date of birth", day(s.biodata.dateOfBirth));
  row("Nationality", s.biodata.nationality ?? "—");
  row("State of origin", s.biodata.stateOfOrigin ?? "—");
  row("LGA", s.biodata.lga ?? "—");
  row("Email", s.email);
  row("Phone", s.phone ?? "—");
  rowLong("Contact address", s.biodata.contactAddress ?? "—");

  const degs: Deg[] = (s.priorDegrees && s.priorDegrees.length)
    ? s.priorDegrees
    : (s.prior && (s.prior.institution || s.prior.award)
      ? [{ kind: "FIRST", institution: s.prior.institution, award: s.prior.award, field: null, class_of_degree: s.prior.classOfDegree, cgpa: s.prior.cgpa, year: s.prior.year }]
      : []);
  if (degs.length) {
    section("QUALIFICATIONS | INSTITUTION ATTENDED");
    table(
      [{ h: "S/N", w: 24 }, { h: "Qualification", w: 96 }, { h: "Award", w: 50 }, { h: "Course of study", w: 92 }, { h: "Institution attended", w: 128 }, { h: "Class / result", w: 80 }, { h: "Year", w: 38 }],
      degs.map((d, i) => [String(i + 1), QUAL[d.kind] ?? d.kind, d.award ?? "", d.field ?? "", d.institution ?? "", d.class_of_degree ?? "", d.year != null ? String(d.year) : ""]),
    );
  }

  if (s.proposal && (s.proposal.title || s.proposal.text)) {
    section("RESEARCH PROPOSAL");
    if (s.proposal.title) row("Topic", s.proposal.title);
    if (s.proposal.text) { y = p.paragraph(L, y, clean(s.proposal.text), A4.w - 2 * L, 9, 1.35) - 4; }
  }

  if (s.referees && s.referees.length) {
    section("REFEREES");
    table(
      [{ h: "S/N", w: 24 }, { h: "Name", w: 96 }, { h: "Position", w: 88 }, { h: "Institution", w: 104 }, { h: "Email", w: 112 }, { h: "Phone number", w: 66 }],
      s.referees.map((r, i) => [String(i + 1), r.name ?? "", r.position ?? "", r.institution ?? "", r.email ?? "", r.phone ?? ""]),
    );
  }

  room(40);
  y -= 10;
  p.rule(L, y, A4.w - L, y, 0.5, 0.6);
  y -= 12;
  // the documents on file by their names, the passport first, wrapped to the page
  const docs = [...(s.documents || [])].sort((a, b) => (a.kind === "PASSPORT" ? -1 : b.kind === "PASSPORT" ? 1 : 0)).map((d) => docLabel(d.kind));
  let note = "";
  for (const w of `Documents on file: ${docs.join(", ") || "none"}.`.split(" ")) {
    const next = note ? `${note} ${w}` : w;
    if (note && textWidth(next, 8) > W) { p.text(L, y, note, 8, false, GREY); y -= 11; note = w; } else note = next;
  }
  if (note) p.text(L, y, note, 8, false, GREY);
  // the standard footer (finishPdf) carries the generation date, the reference and the page numbers

  const bytes = finishPdf(pages, `Application summary ${s.applicationNo}`, "FORM");
  return new NextResponse(Buffer.from(bytes), {
    status: 200,
    headers: {
      "content-type": "application/pdf",
      "content-disposition": `inline; filename="pg-application-${s.applicationNo.replace(/\//g, "-")}.pdf"`,
    },
  });
}
