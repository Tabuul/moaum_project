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
import { brandedXlsx, brandedPrint, downloadBlob, docSerial } from "@/lib/exportbrand";
import { Btn, IcoBtn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { SearchSelect } from "@/components/proto/SearchSelect";

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

const olevelState = (r: Crit) => (r.olevel_uploaded ? "Uploaded" : "Not uploaded");
const compulsoryState = (r: Crit) =>
  !r.olevel_uploaded ? "—" : r.olevel_meets ? "Met" : s(r.olevel_missing) ? `Missing: ${s(r.olevel_missing)}` : "Not met";

const DETAIL_COLS = ["RegNo", "Name", "Sex", "State of origin", "LGA", "UTME aggregate", "Meets cut-off",
  "O'Level", "O'Level points", "Compulsory (Eng & Maths)"];
const detailCells = (r: Crit, cutoff: number | null): (string | number | null)[] => [
  s(r.jamb_reg_no), `${s(r.surname)} ${s(r.other_names)}`.trim(), s(r.sex), s(r.state_of_origin), s(r.lga),
  num(r.aggregate), meets(r.aggregate, cutoff),
  olevelState(r), r.olevel_uploaded ? num(r.olevel_total) : "", compulsoryState(r),
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
  const [allBusy, setAllBusy] = useState(false);
  const [allProgress, setAllProgress] = useState(0);

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

  async function exportOverviewExcel() {
    const rows = shown.map((r) => [r.faculty_name, r.code, r.name, Number(r.applied), Number(r.screened),
      r.quota == null ? "" : Number(r.quota), r.cutoff == null ? "" : Number(r.cutoff)]);
    const blob = await brandedXlsx("Screened applicants — summary",
      ["Faculty", "Code", "Programme", "Applied", "Screened", "Quota", "Cut-off"], rows,
      { sub: session, serial: docSerial("SCR") });
    downloadBlob(blob, `Screened summary ${session.replace("/", "-")}.xlsx`);
  }
  // the all-programmes O'Level screening report: fetch each shown course and combine into one workbook
  async function exportAllOlevel() {
    setAllBusy(true);
    setAllProgress(0);
    try {
      const all: (string | number | null)[][] = [];
      for (let i = 0; i < shown.length; i++) {
        const p = shown[i];
        setAllProgress(i + 1);
        try {
          const r = await fetch(`/api/bff/api/v1/admissions/sessions/${session}/screened?programme=${encodeURIComponent(p.code)}`, { cache: "no-store" });
          const j = await r.json().catch(() => null);
          if (!r.ok || !j) continue;
          const co = num(j.cutoff);
          for (const row of (j.rows as Crit[]) ?? []) {
            all.push([p.faculty_name, p.name, ...detailCells(row, co)]);
          }
        } catch { /* skip a course that fails, keep going */ }
      }
      const blob = await brandedXlsx("O’Level screening — all programmes",
        ["Faculty", "Programme", ...DETAIL_COLS], all, { sub: session, serial: docSerial("OLS") });
      downloadBlob(blob, `O'Level screening ${session.replace("/", "-")}.xlsx`);
    } finally {
      setAllBusy(false);
    }
  }

  async function exportDetailExcel() {
    if (!open || !detail) return;
    const blob = await brandedXlsx(`Screened applicants — ${open.name}`,
      DETAIL_COLS, detail.map((r) => detailCells(r, cutoff)),
      { sheetName: open.name.slice(0, 28), sub: `${session}${cutoff != null ? ` · cut-off ${cutoff}` : ""}`, serial: docSerial("SCR") });
    downloadBlob(blob, `Screened ${open.code} ${session.replace("/", "-")}.xlsx`);
  }

  // ── the per-course criteria view ──
  if (open) {
    const belowNote = cutoff != null;
    return (
      <>
        <div style={{ display: "flex", gap: 10, alignItems: "center", flexWrap: "wrap", marginBottom: 12 }}>
          <Btn kind="ghost" onClick={() => { setOpen(null); setDetail(null); }}>← All courses</Btn>
          <span style={{ flexGrow: 1 }} />
          <Btn kind="ghost" disabled={!detail?.length} onClick={() => void exportDetailExcel()}>Export Excel</Btn>
          <Btn kind="ghost" disabled={!detail?.length} onClick={() => detail && brandedPrint(
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
                  cols={["RegNo|mid", "Name", "Sex|mid", "State of origin", "UTME|num", "Meets cut-off|mid", "O’Level|mid", "O’Level pts|num", "Compulsory (Eng & Maths)"]}
                  rows={detail.map((r) => [
                    <span className="tnum" key="r">{s(r.jamb_reg_no)}</span>,
                    <span key="n"><strong>{s(r.surname)} {s(r.other_names)}</strong><div className="sub2">{s(r.lga)}{r.lga && r.state_of_origin ? ", " : ""}{s(r.state_of_origin)}</div></span>,
                    <span key="x">{s(r.sex) || "—"}</span>,
                    <span className="sub2" key="st">{s(r.state_of_origin) || "—"}</span>,
                    <strong className="tnum" key="u">{nz(r.aggregate)}</strong>,
                    cutoff == null
                      ? <span className="sub2" key="m">—</span>
                      : <Pil key="m" kind={Number(r.aggregate) >= cutoff ? "ok" : "bad"}>{Number(r.aggregate) >= cutoff ? "Yes" : "No"}</Pil>,
                    r.olevel_uploaded ? <Pil kind="ok" key="o">Uploaded</Pil> : <Pil kind="grey" key="o">Not yet</Pil>,
                    <span className="tnum" key="op">{r.olevel_uploaded ? nz(r.olevel_total) : "—"}</span>,
                    !r.olevel_uploaded
                      ? <span className="sub2" key="cm">—</span>
                      : r.olevel_meets
                        ? <Pil kind="ok" key="cm">Met</Pil>
                        : <span key="cm"><Pil kind="bad">Not met</Pil>{s(r.olevel_missing) ? <div className="sub2">missing {s(r.olevel_missing)}</div> : null}</span>,
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
        <div style={{ minWidth: 260, maxWidth: 340 }}>
          <SearchSelect value={faculty} allLabel="All departments (faculties)" placeholder="Search a faculty…"
            options={faculties.map((f) => ({ value: f.code, label: f.name }))}
            onChange={(v) => setFaculty(v)} />
        </div>
        <span style={{ flexGrow: 1 }} />
        <Btn kind="ghost" disabled={!shown.length} onClick={() => void exportOverviewExcel()}>Export summary (Excel)</Btn>
        <Btn kind="ghost" disabled={!shown.length} onClick={() => brandedPrint(
          `Screened applicants — summary`, `${session}${faculty ? ` · ${faculties.find((f) => f.code === faculty)?.name}` : ""} · ${totalScreened.toLocaleString()} screened`,
          ["Faculty", "Code", "Programme", "Applied", "Screened", "Quota", "Cut-off"],
          shown.map((r) => [r.faculty_name, r.code, r.name, Number(r.applied), Number(r.screened), r.quota ?? "", r.cutoff ?? ""]))}>Print / PDF</Btn>
        <Btn kind="primary" disabled={!shown.length || allBusy} onClick={() => void exportAllOlevel()}>
          {allBusy ? `Building… ${allProgress}/${shown.length}` : "Export all O’Level screening (Excel)"}
        </Btn>
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
