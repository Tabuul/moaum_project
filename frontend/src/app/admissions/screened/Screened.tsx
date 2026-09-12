"use client";

/**
 * The screened pool, reached from the Screened tile. Two ways to look at it:
 * an overview by faculty and course (applied, screened, quota, cut-off), and a
 * per-course drill-in showing every admission criterion the screening applied.
 * Either view exports to Excel and to PDF (print).
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

const DETAIL_COLS = [
  "RegNo", "Name", "Sex", "State", "LGA", "UTME", "English", "Maths", "O'Level pts", "O'Level ratio",
  "Post-UTME", "Aggregate", "Cut-off", "UTME combination", "O'Level remark", "Decision", "Basis", "Admitted",
];
const detailCells = (r: Crit): (string | number | null)[] => [
  s(r.regNo), s(r.name), s(r.gender), s(r.state), s(r.lga), num(r.utmeScore),
  `${s(r.engGrade)} (${s(r.engPoint)})`, `${s(r.mathsGrade)} (${s(r.mathsPoint)})`,
  num(r.olevelTotal), s(r.olevelRatio), num(r.cbtScore), num(r.total), num(r.cutoff),
  s(r.utmeRemark), s(r.olRemark), s(r.decision), s(r.decisionBasis), r.admitted ? "Yes" : "",
];

export function Screened({ session, summary }: { session: string; summary: ScreenedRow[] }) {
  const withApplicants = summary.filter((r) => Number(r.applied) > 0);
  const faculties = Array.from(new Map(withApplicants.map((r) => [r.faculty_code, r.faculty_name])).entries())
    .map(([code, name]) => ({ code, name })).sort((a, b) => a.name.localeCompare(b.name));

  const [faculty, setFaculty] = useState("");
  const [open, setOpen] = useState<ScreenedRow | null>(null);
  const [detail, setDetail] = useState<Crit[] | null>(null);
  const [loading, setLoading] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  const shown = withApplicants.filter((r) => !faculty || r.faculty_code === faculty);
  const totalScreened = shown.reduce((n, r) => n + Number(r.screened), 0);
  const totalApplied = shown.reduce((n, r) => n + Number(r.applied), 0);

  async function drill(row: ScreenedRow) {
    setOpen(row);
    setDetail(null);
    setErr(null);
    setLoading(true);
    try {
      const r = await fetch(`/api/bff/api/v1/admissions/sessions/${session}/jamb-template?programme=${encodeURIComponent(row.code)}`, { cache: "no-store" });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setErr(j?.title ?? "Could not load this course."); return; }
      const rows = ((j.rows as Crit[]) ?? []).filter((x) => num(x.total) != null || num(x.cbtScore) != null || num(x.utmeScore) != null);
      setDetail(rows);
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
    download(buildXlsx(DETAIL_COLS, detail.map(detailCells), open.name.slice(0, 28)),
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
    return (
      <>
        <div style={{ display: "flex", gap: 10, alignItems: "center", flexWrap: "wrap", marginBottom: 12 }}>
          <Btn kind="ghost" onClick={() => { setOpen(null); setDetail(null); }}>← All courses</Btn>
          <span style={{ flexGrow: 1 }} />
          <Btn kind="ghost" disabled={!detail?.length} onClick={exportDetailExcel}>Export Excel</Btn>
          <Btn kind="ghost" disabled={!detail?.length} onClick={() => detail && printReport(
            `${open.name} — screened applicants`, `${session} · ${detail.length} screened · cut-off ${open.cutoff ?? "—"}`,
            DETAIL_COLS, detail.map(detailCells))}>Print / PDF</Btn>
        </div>
        <Panel title={open.name} right={<span className="sub2">{open.faculty_name} · {open.code}</span>}>
          <PBody>
            <div className="sub2" style={{ marginBottom: 10 }}>
              Every screened applicant for this programme with the criteria the screening applied — UTME and its subjects, the
              O&rsquo;Level points and ratio, the Post-UTME score, the weighted aggregate against the cut-off, and the decision.
            </div>
            {err ? <Note kind="bad" title="Could not load">{err}</Note> : null}
            {loading ? <div className="sub2">Loading…</div> : null}
            {detail && !loading ? (
              detail.length ? (
                <DTable
                  cols={["RegNo|mid", "Name", "Sex|mid", "State", "UTME|num", "Eng|mid", "Maths|mid", "O’Level|num", "Post-UTME|num", "Aggregate|num", "Cut-off|num", "UTME combination", "O’Level remark", "Decision|mid"]}
                  rows={detail.map((r) => [
                    <span className="tnum" key="r">{s(r.regNo)}</span>,
                    <span key="n">{s(r.name)}<div className="sub2">{s(r.lga)}{r.lga && r.state ? ", " : ""}{s(r.state)}</div></span>,
                    <span key="x">{s(r.gender)}</span>,
                    <span className="sub2" key="st">{s(r.state)}</span>,
                    <span className="tnum" key="u">{nz(r.utmeScore)}</span>,
                    <span className="tnum" key="e">{s(r.engGrade) || "—"}</span>,
                    <span className="tnum" key="m">{s(r.mathsGrade) || "—"}</span>,
                    <span className="tnum" key="o">{nz(r.olevelTotal)}{r.olevelRatio ? <span className="sub2"> ·{s(r.olevelRatio)}</span> : null}</span>,
                    <span className="tnum" key="c">{nz(r.cbtScore)}</span>,
                    <strong className="tnum" key="t">{num(r.total) == null ? "—" : Number(r.total).toFixed(2)}</strong>,
                    <span className="tnum" key="co">{nz(r.cutoff)}</span>,
                    <span className="sub2" key="uc">{s(r.utmeRemark)}</span>,
                    <span className="sub2" key="ol">{s(r.olRemark)}</span>,
                    r.decision
                      ? <Pil key="d" kind={r.decision === "OFFERED" ? "ok" : r.decision === "WAITING" ? "info" : "bad"}>{s(r.decision)}{r.decisionBasis ? ` · ${s(r.decisionBasis)}` : ""}</Pil>
                      : <span className="sub2" key="d">—</span>,
                  ])}
                  texts={detail.map((r) => `${s(r.regNo)} ${s(r.name)} ${s(r.state)} ${s(r.decision)}`)}
                />
              ) : <Note kind="info" title="No screened applicant">No applicant for this programme carries a screening aggregate yet.</Note>
            ) : null}
          </PBody>
        </Panel>
      </>
    );
  }

  // ── the overview ──
  const byFaculty = Array.from(new Map(faculties.map((f) => [f.code, f.name])).keys())
    .filter((fc) => !faculty || fc === faculty)
    .map((fc) => ({ code: fc, name: faculties.find((f) => f.code === fc)!.name, rows: shown.filter((r) => r.faculty_code === fc) }))
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

      <Note kind="info" title="Click a course to see every criterion">
        The screened pool by department and course. Open any course for the full per-applicant criteria — UTME, O&rsquo;Level,
        Post-UTME, the weighted aggregate against the cut-off, and the decision — and export it to Excel or PDF.
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
              <IcoBtn key="v" icon="eye" label={`View screened applicants for ${r.name}`} onClick={() => void drill(r)} />,
            ])}
            texts={g.rows.map((r) => `${r.name} ${r.code}`)}
          />
        </Panel>
      ))}
      {!byFaculty.length ? <Note kind="info" title="Nothing screened yet">No programme has a screened applicant for {session} yet.</Note> : null}
    </>
  );
}
