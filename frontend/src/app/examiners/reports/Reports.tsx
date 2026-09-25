"use client";
/** The external examiner reports (V254): real rows from the assignments in the scope chosen, as a table and as a download. */
import { useQueryNav } from "@/lib/query-nav";
import { csv, download } from "@/lib/results";
import { Btn, LinkBtn, PageHead, Panel, PBody } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { RECOMMENDATION, STATUS, dayOf, type AssignmentRow, type ExaminerRow } from "@/lib/examiners";

export interface Report { kind: string; rows: Record<string, unknown>[] }
interface Filters { kind: string; session: string; faculty: string; dept: string; programme: string; examiner: string; status: string; from: string; to: string }
interface Faculty { code: string; name: string; departments: { code: string; name: string; programmes?: { code: string; name: string }[] }[] }
const KINDS: [string, string, string][] = [
  ["examiners", "External Examiner Report", "Each examiner: assigned, submitted, pending, overdue, days to submit, average mark"],
  ["assessments", "Project Assessment Report", "Every assignment with its assessment as it stands"],
  ["workload", "Examiner Workload Report", "Open and finished work per examiner per session, and the next deadline"],
  ["department", "Department Assessment Report", "Assignments and submissions by department"],
  ["programme", "Programme Assessment Report", "Assignments, submissions and recommendations by programme"],
  ["pending", "Pending Review Report", "Assignments not yet submitted"],
  ["overdue", "Overdue Review Report", "Assignments past their deadline"],
  ["submitted", "Submitted Assessment Report", "Assignments submitted or locked"],
];

export function Reports({ report, examiners, sessions, faculties, filters }: { report: Report; examiners: ExaminerRow[]; sessions: string[]; faculties: Faculty[]; filters: Filters }) {
  const go = useQueryNav();
  const nav = (patch: Partial<Filters>) => {
    const next = { ...filters, ...patch };
    const qs = new URLSearchParams();
    for (const [k, v] of Object.entries(next)) if (v && !(k === "kind" && v === "assessments")) qs.set(k, v);
    go(`/examiners/reports${qs.toString() ? "?" + qs.toString() : ""}`);
  };
  const meta = KINDS.find((k) => k[0] === filters.kind) ?? KINDS[1];
  const n = (v: unknown) => (v == null ? "—" : String(v));
  const depts = faculties.find((f) => f.code === filters.faculty)?.departments ?? faculties.flatMap((f) => f.departments);
  const progs = depts.find((d) => d.code === filters.dept)?.programmes ?? [];
  const isRows = ["assessments", "pending", "overdue", "submitted"].includes(filters.kind);
  const rows = report.rows;

  const table = (): { cols: string[]; cells: (r: Record<string, unknown>) => React.ReactNode[]; flat: (r: Record<string, unknown>) => (string | number | null)[] } => {
    switch (filters.kind) {
      case "examiners": return { cols: ["Examiner", "Institution", "Status|mid", "Assigned|mid", "Submitted|mid", "Pending|mid", "Overdue|mid", "Days to submit|mid", "Average %|mid"], cells: (r) => [n(r.examiner), n(r.institution), n(r.status), n(r.assigned), n(r.submitted), n(r.pending), n(r.overdue), n(r.avg_days), n(r.avg_percentage)], flat: (r) => [n(r.examiner), n(r.institution), n(r.status), Number(r.assigned), Number(r.submitted), Number(r.pending), Number(r.overdue), r.avg_days == null ? null : Number(r.avg_days), r.avg_percentage == null ? null : Number(r.avg_percentage)] };
      case "workload": return { cols: ["Examiner", "Institution", "Session|mid", "Assigned|mid", "Open|mid", "Done|mid", "Next deadline|mid"], cells: (r) => [n(r.examiner), n(r.institution), n(r.session), n(r.assigned), n(r.open), n(r.done), dayOf(r.next_deadline as string | null)], flat: (r) => [n(r.examiner), n(r.institution), n(r.session), Number(r.assigned), Number(r.open), Number(r.done), r.next_deadline == null ? null : String(r.next_deadline)] };
      case "department": return { cols: ["Faculty", "Department", "Assigned|mid", "Submitted|mid", "Pending|mid", "Overdue|mid", "Average %|mid"], cells: (r) => [n(r.faculty), n(r.department), n(r.assigned), n(r.submitted), n(r.pending), n(r.overdue), n(r.avg_percentage)], flat: (r) => [n(r.faculty), n(r.department), Number(r.assigned), Number(r.submitted), Number(r.pending), Number(r.overdue), r.avg_percentage == null ? null : Number(r.avg_percentage)] };
      case "programme": return { cols: ["Department", "Programme", "Assigned|mid", "Submitted|mid", "Pending|mid", "Average %|mid", "Pass|mid", "Corrections|mid", "Reassess|mid", "Fail|mid"], cells: (r) => [n(r.department), n(r.programme), n(r.assigned), n(r.submitted), n(r.pending), n(r.avg_percentage), n(r.pass), n(r.pass_corrections), n(r.reassess), n(r.fail)], flat: (r) => [n(r.department), n(r.programme), Number(r.assigned), Number(r.submitted), Number(r.pending), r.avg_percentage == null ? null : Number(r.avg_percentage), Number(r.pass), Number(r.pass_corrections), Number(r.reassess), Number(r.fail)] };
      default: return {
        cols: ["Candidate", "Project", "Programme", "Department", "Examiner", "Session|mid", "Assigned|mid", "Deadline|mid", "Status|mid", "Total|mid", "%|mid", "Grade|mid", "Recommendation", "Submitted|mid"],
        cells: (r) => { const a = r as unknown as AssignmentRow; return [`${a.student} (${a.number})`, a.title, a.programme, a.department, a.examiner, a.session, dayOf(a.assigned_at), dayOf(a.deadline), STATUS[a.status]?.[0] ?? a.status, a.total == null ? "—" : `${a.total}/${a.max_total}`, n(a.percentage), n(a.grade), a.final_recommendation ? RECOMMENDATION[a.final_recommendation]?.[0] ?? a.final_recommendation : "—", dayOf(a.submitted_at)]; },
        flat: (r) => { const a = r as unknown as AssignmentRow; return [a.student, a.number, a.title, a.programme, a.department, a.examiner, a.session, a.assigned_at?.slice(0, 10) ?? null, a.deadline, STATUS[a.status]?.[0] ?? a.status, a.total == null ? null : Number(a.total), a.max_total == null ? null : Number(a.max_total), a.percentage == null ? null : Number(a.percentage), a.grade, a.final_recommendation ? RECOMMENDATION[a.final_recommendation]?.[0] ?? a.final_recommendation : null, a.submitted_at?.slice(0, 10) ?? null]; },
      };
    }
  };
  const t = table();
  function downloadIt() {
    const header = isRows ? ["Candidate", "Number", "Project", "Programme", "Department", "Examiner", "Session", "Assigned", "Deadline", "Status", "Total", "Maximum", "Percentage", "Grade", "Recommendation", "Submitted"] : t.cols.map((c) => c.split("|")[0]);
    download(`${meta[1]} ${filters.session || "all sessions"}`, csv([header, ...rows.map(t.flat)], [["Report", meta[1]], ["Session", filters.session || "Every session"], ["Rows", String(rows.length)]]));
  }

  return (
    <>
      <PageHead title="External Examiner Reports" description="Real figures from the assignments and assessments on record, in the scope you choose."
        actions={<><Btn kind="primary" onClick={downloadIt} disabled={!rows.length}>Download</Btn><LinkBtn href="/examiners">The Register</LinkBtn></>} />
      <div className="row mb-3">{KINDS.map(([k, l]) => <Btn key={k} kind={filters.kind === k ? "primary" : "ghost"} size="sm" onClick={() => nav({ kind: k })}>{l.replace(" Report", "")}</Btn>)}</div>
      <div className="filterbar">
        <div className="row">
          <div className="field" style={{ flex: "1 1 130px" }}><label htmlFor="rp-session">Session</label><select id="rp-session" className="ctl" value={filters.session} onChange={(e) => nav({ session: e.target.value })}><option value="">Every</option>{sessions.map((s) => <option key={s} value={s}>{s}</option>)}</select></div>
          <div className="field" style={{ flex: "1 1 170px" }}><label htmlFor="rp-fac">Faculty</label><select id="rp-fac" className="ctl" value={filters.faculty} onChange={(e) => nav({ faculty: e.target.value, dept: "", programme: "" })}><option value="">Every</option>{faculties.map((f) => <option key={f.code} value={f.code}>{f.name}</option>)}</select></div>
          <div className="field" style={{ flex: "1 1 170px" }}><label htmlFor="rp-dept">Department</label><select id="rp-dept" className="ctl" value={filters.dept} onChange={(e) => nav({ dept: e.target.value, programme: "" })}><option value="">Every</option>{depts.map((d) => <option key={d.code} value={d.code}>{d.name}</option>)}</select></div>
          <div className="field" style={{ flex: "1 1 170px" }}><label htmlFor="rp-prog">Programme</label><select id="rp-prog" className="ctl" value={filters.programme} onChange={(e) => nav({ programme: e.target.value })}><option value="">Every</option>{progs.map((p) => <option key={p.code} value={p.code}>{p.name}</option>)}</select></div>
          <div className="field" style={{ flex: "1 1 170px" }}><label htmlFor="rp-ex">Examiner</label><select id="rp-ex" className="ctl" value={filters.examiner} onChange={(e) => nav({ examiner: e.target.value })}><option value="">Every</option>{examiners.map((e) => <option key={e.id} value={e.id}>{e.name}</option>)}</select></div>
          <div className="field" style={{ flex: "1 1 140px" }}><label htmlFor="rp-status">Status</label><select id="rp-status" className="ctl" value={filters.status} onChange={(e) => nav({ status: e.target.value })}><option value="">Every</option>{Object.entries(STATUS).map(([k, v]) => <option key={k} value={k}>{v[0]}</option>)}</select></div>
          <div className="field" style={{ flex: "1 1 130px" }}><label htmlFor="rp-from">Assigned from</label><input id="rp-from" className="ctl" type="date" defaultValue={filters.from} onBlur={(e) => { if (e.target.value !== filters.from) nav({ from: e.target.value }); }} /></div>
          <div className="field" style={{ flex: "1 1 130px" }}><label htmlFor="rp-to">To</label><input id="rp-to" className="ctl" type="date" defaultValue={filters.to} onBlur={(e) => { if (e.target.value !== filters.to) nav({ to: e.target.value }); }} /></div>
          {Object.entries(filters).some(([k, v]) => k !== "kind" && v) ? <div style={{ alignSelf: "flex-end" }}><Btn kind="ghost" onClick={() => go(`/examiners/reports?kind=${filters.kind}`)}>Clear</Btn></div> : null}
        </div>
      </div>
      <Panel title={meta[1]} right={`${rows.length} row${rows.length === 1 ? "" : "s"} · ${meta[2]}`}>
        {rows.length ? <DTable cols={t.cols} rows={rows.map((r, i) => t.cells(r).map((c, j) => <span key={j + "-" + i} className={typeof c === "string" && /^[\d./%—-]+$/.test(c) ? "tnum" : undefined}>{c}</span>))} texts={rows.map((r) => Object.values(r).join(" "))} /> : <PBody><div className="sub2">Nothing in this scope yet.</div></PBody>}
      </Panel>
    </>
  );
}
