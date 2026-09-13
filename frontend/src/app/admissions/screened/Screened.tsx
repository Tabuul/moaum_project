"use client";

/**
 * The screened pool, reached from the Screened tile. Two ways to look at it:
 * an overview by faculty and course (applied, screened, quota, cut-off), and a
 * per-course drill-in of the screened candidates — the same population the
 * overview counts (committed CAPS rows carrying a UTME aggregate), with the
 * criteria known at screening: the UTME aggregate against the cut-off, origin,
 * and whether an O'Level result has been uploaded. Full O'Level/Post-UTME/
 * decision criteria live on the Applicants and Merit desks. Either view exports
 * to Excel and to PDF (print).
 */
import { useState } from "react";
import Link from "next/link";
import { buildXlsx } from "@/lib/xlsx";
import { Btn, IcoBtn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";

export interface ScreenedRow {
  faculty_code: string; faculty_name: string; code: string; name: string;
  applied: number; screened: number; quota: number | null; cutoff: number | null;
}
type Crit = Record<string, unknown>;

const s = (v: unknown) => (v == null ? "" : String(v));
const num = (v: unknown) => (v == null || v === "" ? null : Number(v));
const nz = (v: unknown) => { const n = num(v); return n == null ? "—" : n.toLocaleString(); };
const meets = (agg: unknown, cutoff: number | null) => {
  const a = num(agg);
  if (cutoff == null || a == null) return "";
  return a >= cutoff ? "Yes" : "No";
};

/** open a clean, branded window and print it — the browser's "Save as PDF" does the rest */
function printReport(title: string, sub: string, headers: string[], rows: (string | number | null)[][]) {
  const esc = (x: unknown) => s(x).replace(/[&<>]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;" }[c] ?? c));
  const th = headers.map((h) => `<th>${esc(h)}</th>`).join("");
  const tr = rows.map((r) => `<tr>${r.map((c) => `<td>${esc(c)}</td>`).join("")}</tr>`).join("");
  const html = `<!doctype html><html><head><meta charset="utf-8"><title>${esc(title)}</title>
    <style>
      body{font:12px/1.4 "Segoe UI",system-ui,sans-serif;color:#13242d;margin:24px;}
      h1{font-size:17px;margin:0 0 2px;} .sub{color:#5a6b74;font-size:12px;margin:0 0 14px;}
      table{border-collapse:collapse;width:100%;} th{background:#0e3f55;color:#fff;text-align:left;padding:6px 8px;font-size:10px;text-transform:uppercase;letter-spacing:.3px;}
      td{padding:5px 8px;border-bottom:1px solid #e8eef1;font-size:11px;} tbody tr:nth-child(even){background:#f6f9fa;}
      @media print{@page{size:landscape;margin:12mm;}}
    </style></head><body>
    <h1>${esc(title)}</h1><div class="sub">${esc(sub)}</div>
    <table><thead><tr>${th}</tr></thead><tbody>${tr}</tbody></table>
    <script>window.onload=function(){window.print();}</script></body></html>`;
  const w = window.open("", "_blank");
  if (!w) return;
  w.document.write(html);
  w.document.close();
}

const DETAIL_COLS = ["RegNo", "Name", "Sex", "State of origin", "LGA", "UTME aggregate", "Meets cut-off", "O'Level uploaded"];
const detailCells = (r: Crit, cutoff: number | null): (string | number | null)[] => [
  s(r.jamb_reg_no), `${s(r.surname)} ${s(r.other_names)}`.trim(), s(r.sex), s(r.state_of_origin), s(r.lga),
  num(r.aggregate), meets(r.aggregate, cutoff), r.olevel_uploaded ? "Yes" : "No",
];

export function Screened({ session, summary }: { session: string; summary: ScreenedRow[] }) {
  const withApplicants = summary.filter((r) => Number(r.applied) > 0);
  const faculties = Array.from(new Map(withApplicants.map((r) => [r.faculty_code, r.faculty_name])).entries())
    .map(([code, name]) => ({ code, name })).sort((a, b) => a.name.localeCompare(b.name));

  const [faculty, setFaculty] = useState("");
  const [open, setOpen] = useState<ScreenedRow | null>(null);
  const [detail, setDetail] = useState<Crit[] | null>(null);
  const [cutoff, setCutoff] = useState<number | null>(null);
  const [loading, setLoading] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  const shown = withApplicants.filter((r) => !faculty || r.faculty_code === faculty);
  const totalScreened = shown.reduce((n, r) => n + Number(r.screened), 0);
  const totalApplied = shown.reduce((n, r) => n + Number(r.applied), 0);

  async function drill(row: ScreenedRow) {
    setOpen(row);
    setDetail(null);
    setCutoff(null);
    setErr(null);
    setLoading(true);
    try {
      const r = await fetch(`/api/bff/api/v1/admissions/sessions/${session}/screened?programme=${encodeURIComponent(row.code)}`, { cache: "no-store" });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setErr(j?.title ?? "Could not load this course."); return; }
      setCutoff(num(j.cutoff));
      setDetail((j.rows as Crit[]) ?? []);
    } catch {
      setErr("Could not load this course.");
    } finally {
      setLoading(false);
    }
  }

  function exportOverviewExcel() {
    const rows = shown.map((r) => [r.faculty_name, r.code, r.name, Number(r.applied), Number(r.screened),
      r.quota == null ? "" : Number(r.quota), r.cutoff == null ? "" : Number(r.cutoff)]);
    download(buildXlsx(["Faculty", "Code", "Programme", "Applied", "Screened", "Quota", "Cut-off"], rows,
      `Screened ${session.replace("/", "-")}`), `Screened summary ${session.replace("/", "-")}.xlsx`);
  }
  function exportDetailExcel() {
    if (!open || !detail) return;
    download(buildXlsx(DETAIL_COLS, detail.map((r) => detailCells(r, cutoff)), open.name.slice(0, 28)),
      `Screened ${open.code} ${session.replace("/", "-")}.xlsx`);
  }
  function download(blob: Blob, name: string) {
    const a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = name;
    document.body.appendChild(a); a.click(); a.remove();
    setTimeout(() => URL.revokeObjectURL(a.href), 1000);
  }

  // ── the per-course criteria view ──
  if (open) {
    const belowNote = cutoff != null;
    return (
      <>
        <div style={{ display: "flex", gap: 10, alignItems: "center", flexWrap: "wrap", marginBottom: 12 }}>
          <Btn kind="ghost" onClick={() => { setOpen(null); setDetail(null); }}>← All courses</Btn>
          <span style={{ flexGrow: 1 }} />
          <Btn kind="ghost" disabled={!detail?.length} onClick={exportDetailExcel}>Export Excel</Btn>
          <Btn kind="ghost" disabled={!detail?.length} onClick={() => detail && printReport(
            `${open.name} — screened applicants`,
            `${session} · ${detail.length} screened${cutoff != null ? ` · cut-off ${cutoff}` : ""}`,
            DETAIL_COLS, detail.map((r) => detailCells(r, cutoff)))}>Print / PDF</Btn>
        </div>
        <Panel title={open.name}
               right={<span className="sub2">{open.faculty_name} · {open.code}{cutoff != null ? ` · cut-off ${cutoff}` : ""}</span>}>
          <PBody>
            <div className="sub2" style={{ marginBottom: 10 }}>
              Every screened candidate for this programme — those on the committed CAPS list who carry a UTME aggregate —
              with the criteria known at screening: the UTME aggregate {belowNote ? "against the cut-off" : ""}, origin, and
              whether an O&rsquo;Level result has been uploaded. The full O&rsquo;Level, Post-UTME and decision criteria appear
              on the <Link href={`/admissions/applicants?session=${encodeURIComponent(session)}&programme=${encodeURIComponent(open.code)}`}>Applicants</Link> and
              {" "}<Link href={`/admissions/merit?session=${encodeURIComponent(session)}&programme=${encodeURIComponent(open.code)}`}>Merit</Link> desks once a candidate registers for post-UTME.
            </div>
            {err ? <Note kind="bad" title="Could not load">{err}</Note> : null}
            {loading ? <div className="sub2">Loading…</div> : null}
            {detail && !loading ? (
              detail.length ? (
                <DTable
                  cols={["RegNo|mid", "Name", "Sex|mid", "State of origin", "LGA", "UTME|num", "Meets cut-off|mid", "O’Level|mid"]}
                  rows={detail.map((r) => [
                    <span className="tnum" key="r">{s(r.jamb_reg_no)}</span>,
                    <strong key="n">{s(r.surname)} {s(r.other_names)}</strong>,
                    <span key="x">{s(r.sex) || "—"}</span>,
                    <span className="sub2" key="st">{s(r.state_of_origin) || "—"}</span>,
                    <span className="sub2" key="l">{s(r.lga) || "—"}</span>,
                    <strong className="tnum" key="u">{nz(r.aggregate)}</strong>,
                    cutoff == null
                      ? <span className="sub2" key="m">—</span>
                      : <Pil key="m" kind={Number(r.aggregate) >= cutoff ? "ok" : "bad"}>{Number(r.aggregate) >= cutoff ? "Yes" : "No"}</Pil>,
                    r.olevel_uploaded ? <Pil kind="ok" key="o">Uploaded</Pil> : <Pil kind="grey" key="o">Not yet</Pil>,
                  ])}
                  texts={detail.map((r) => `${s(r.jamb_reg_no)} ${s(r.surname)} ${s(r.other_names)} ${s(r.state_of_origin)}`)}
                />
              ) : <Note kind="info" title="No screened applicant">No candidate for this programme carries a UTME aggregate on the committed CAPS list yet.</Note>
            ) : null}
          </PBody>
        </Panel>
      </>
    );
  }

  // ── the overview ──
  const byFaculty = faculties
    .filter((f) => !faculty || f.code === faculty)
    .map((f) => ({ code: f.code, name: f.name, rows: shown.filter((r) => r.faculty_code === f.code) }))
    .filter((g) => g.rows.length);

  return (
    <>
      <div style={{ display: "flex", gap: 10, alignItems: "center", flexWrap: "wrap", marginBottom: 12 }}>
        <Link href={`/admissions`} className="btn btn--ghost btn--sm">← Admissions</Link>
        <select className="ctl" style={{ maxWidth: 320 }} value={faculty} onChange={(e) => setFaculty(e.target.value)} aria-label="Filter by faculty">
          <option value="">All departments (faculties)</option>
          {faculties.map((f) => <option key={f.code} value={f.code}>{f.name}</option>)}
        </select>
        <span style={{ flexGrow: 1 }} />
        <Btn kind="ghost" disabled={!shown.length} onClick={exportOverviewExcel}>Export Excel</Btn>
        <Btn kind="ghost" disabled={!shown.length} onClick={() => printReport(
          `Screened applicants — summary`, `${session}${faculty ? ` · ${faculties.find((f) => f.code === faculty)?.name}` : ""} · ${totalScreened.toLocaleString()} screened`,
          ["Faculty", "Code", "Programme", "Applied", "Screened", "Quota", "Cut-off"],
          shown.map((r) => [r.faculty_name, r.code, r.name, Number(r.applied), Number(r.screened), r.quota ?? "", r.cutoff ?? ""]))}>Print / PDF</Btn>
      </div>

      <Tiles items={[
        ["Screened", totalScreened.toLocaleString(), null, faculty ? faculties.find((f) => f.code === faculty)?.name : "All departments"],
        ["Applied", totalApplied.toLocaleString(), null, "On the committed CAPS lists"],
        ["Courses", String(shown.length), null, "With applicants"],
        ["Departments", String(faculties.length), null, "Faculties with applicants"],
      ]} />

      <Note kind="info" title="Click a course to see its screened candidates">
        The screened pool by department and course — candidates on the committed CAPS list who carry a UTME aggregate.
        Open any course for the per-candidate criteria and export it to Excel or PDF.
      </Note>

      {byFaculty.map((g) => (
        <Panel key={g.code} title={g.name} right={`${g.rows.reduce((n, r) => n + Number(r.screened), 0).toLocaleString()} screened · ${g.rows.length} course${g.rows.length === 1 ? "" : "s"}`}>
          <DTable
            cols={["Programme", "Applied|num", "Screened|num", "Quota|num", "Cut-off|num", "View|num"]}
            rows={g.rows.map((r) => [
              <span key="p"><strong>{r.name}</strong><div className="sub2 tnum">{r.code}</div></span>,
              <span className="tnum" key="a">{Number(r.applied).toLocaleString()}</span>,
              <strong className="tnum" key="s">{Number(r.screened).toLocaleString()}</strong>,
              <span className="tnum" key="q">{r.quota == null ? "—" : Number(r.quota).toLocaleString()}</span>,
              <span className="tnum" key="c">{r.cutoff == null ? "—" : r.cutoff}</span>,
              <IcoBtn key="v" icon="eye" label={`View screened candidates for ${r.name}`} onClick={() => void drill(r)} />,
            ])}
            texts={g.rows.map((r) => `${r.name} ${r.code}`)}
          />
        </Panel>
      ))}
      {!byFaculty.length ? <Note kind="info" title="Nothing screened yet">No programme has a screened applicant for {session} yet.</Note> : null}
    </>
  );
}
