"use client";
/** The level's score sheet (V250): downloaded as a workbook for the cohort — a row per candidate, per subject the CA, the
 *  examination, the clinical mark where the subject has one, and the attendance — filled offline and uploaded. The upload is
 *  previewed with its red flags before anything is saved; then every mark is judged by the rule as it goes in and the rule's
 *  decision applied provisionally. The marked sheet comes back down with pass, fail, barred, distinction and the summary. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { useQueryNav } from "@/lib/query-nav";
import { notify } from "@/components/proto/Toast";
import { Btn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { ProblemNotice } from "@/components/ProblemNotice";
import { buildXlsx, csvRows, loadCrest, xlsxRows } from "@/lib/xlsx";
import type { Candidates, Result, Decision } from "../examinations/Examinations";

const UNI = "Moshood Abiola University of Science and Technology, Abeokuta";
const word = (s: string) => s.charAt(0) + s.slice(1).toLowerCase().replace(/_/g, " ");
const parse = <T,>(s: string | null, fallback: T): T => { try { return s ? (JSON.parse(s) as T) : fallback; } catch { return fallback; } };
interface Row { number: string; name: string; line: number; marks: { subjectId: string; subject: string; ca: string; exam: string; clinical: string; attendance: string }[]; flags: string[] }

export function ScoreSheets({ sessions, session, level, exams, data, problem, coordinator }: {
  sessions: string[]; session: string; level: number; exams: { code: string; name: string; level: number; min_attendance_pct: number | null }[]; data: Candidates | null; problem: Problem | null; coordinator: boolean;
}) {
  const router = useRouter();
  const go = useQueryNav();
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<Problem | null>(null);
  const [preview, setPreview] = useState<{ file: string; rows: Row[]; unread: string[] } | null>(null);
  const [done, setDone] = useState<{ saved: { number: string; outcome: string; registered: boolean }[]; problems: { number: string; problem: string }[] } | null>(null);
  const exam = exams.find((e) => e.level === level) ?? null;
  const subjects = data?.subjects ?? [];
  const rows = data?.candidates ?? [];
  const nav = (patch: Partial<{ session: string; level: number }>) => go(`/college/scoresheets?session=${encodeURIComponent(patch.session ?? session)}&level=${patch.level ?? level}`);

  /* the template: the cohort as it stands, with any marks already saved, per subject CA · Exam · (Clinical) · Attendance */
  const columns = () => {
    const cols: { subjectId: string; subject: string; field: "ca" | "exam" | "clinical" | "attendance"; label: string; max: number }[] = [];
    for (const s of subjects) {
      cols.push({ subjectId: s.id, subject: s.name, field: "ca", label: `${s.name} · CA (0-${s.ca_weight})`, max: Number(s.ca_weight) });
      cols.push({ subjectId: s.id, subject: s.name, field: "exam", label: `${s.name} · Exam (0-${s.exam_weight})`, max: Number(s.exam_weight) });
      if (s.clinical_component_min != null) cols.push({ subjectId: s.id, subject: s.name, field: "clinical", label: `${s.name} · Clinical (0-100)`, max: 100 });
      cols.push({ subjectId: s.id, subject: s.name, field: "attendance", label: `${s.name} · Attendance % (0-100)`, max: 100 });
    }
    return cols;
  };
  async function downloadTemplate() {
    if (!exam) return;
    const cols = columns();
    const headers = ["S/N", "Matriculation number", "Name", "Registered", ...cols.map((c) => c.label)];
    const body = rows.map((c, i) => {
      const results = parse<Result[]>(c.results, []);
      const at = c.attempt || "FIRST";
      return [i + 1, c.number, `${c.surname}, ${c.other_names}`, c.fully_registered ? "Yes" : `No (${c.semesters_registered} of ${c.semesters})`,
        ...cols.map((col) => { const r = results.find((x) => x.subject_id === col.subjectId && x.attempt === at); const v = r ? (col.field === "ca" ? r.ca : col.field === "exam" ? r.exam : col.field === "clinical" ? r.clinical : r.attendance) : null; return v ?? ""; })];
    });
    const logo = await loadCrest();
    const blob = buildXlsx(headers, body, "Score sheet", {
      school: UNI, title: `${exam.name} · score sheet`, date: new Date().toLocaleDateString("en-GB", { day: "2-digit", month: "long", year: "numeric" }), logo: logo ?? undefined,
      meta: [["Examination", `${exam.code} — ${exam.name}`], ["Level", `${level} Level`], ["Cohort", `${session} · the year begun in ${session}`], ["Attendance minimum", exam.min_attendance_pct != null ? `${exam.min_attendance_pct}%` : "Not stated"], ["Pass", "50 or more per subject; 70 or more a distinction"]],
      validations: cols.map((c, i) => ({ col: 4 + i, min: 0, max: c.max, title: `Over ${c.max}`, message: `${c.label}: enter 0 to ${c.max}.` })),
    });
    const a = document.createElement("a"); a.href = URL.createObjectURL(blob); a.download = `Score sheet ${exam.code} ${level} Level ${session.replace("/", "-")}.xlsx`; a.click();
  }

  /* the upload: read, matched to the cohort by number, flagged, previewed — nothing saved until the preview is accepted */
  async function readFile(f: File) {
    setErr(null); setDone(null);
    const buf = await f.arrayBuffer();
    const head = new Uint8Array(buf.slice(0, 2));
    const isWorkbook = (head[0] === 0x50 && head[1] === 0x4b) || /\.xlsx$/i.test(f.name);
    let cells: string[][];
    try { cells = (isWorkbook ? await xlsxRows(buf) : csvRows(new TextDecoder("utf-8").decode(buf))).map((row) => row.map((c) => String(c ?? "").trim())); }
    catch { setErr({ status: 400, title: `${f.name} could not be read`, detail: "Upload the template as downloaded, filled in, or a CSV with the same columns." } as Problem); return; }
    const cols = columns();
    const byNumber = Object.fromEntries(rows.map((r) => [r.number.toUpperCase(), r]));
    const out: Row[] = []; const unread: string[] = [];
    let started = false; let off = 0;
    for (const [i, row] of cells.entries()) {
      if (!started) { const h = row.findIndex((c) => /matric/i.test(c)); if (h >= 0) { started = true; off = h; } continue; }
      if (row.every((c) => c === "")) continue;
      const number = (row[off] ?? "").toUpperCase();
      if (!number) { unread.push(`Line ${i + 1}: no matriculation number`); continue; }
      const c = byNumber[number];
      const flags: string[] = [];
      if (!c) flags.push(`not in the ${level} Level cohort for ${session}`);
      else if (!c.fully_registered) flags.push(`not fully registered (${c.semesters_registered} of ${c.semesters} semesters)`);
      const marks: Row["marks"] = [];
      for (const s of subjects) {
        const get = (field: string) => { const k = cols.findIndex((x) => x.subjectId === s.id && x.field === field); return k < 0 ? "" : (row[off + 3 + k] ?? "").trim(); };
        const m = { subjectId: s.id, subject: s.name, ca: get("ca"), exam: get("exam"), clinical: get("clinical"), attendance: get("attendance") };
        const num = (v: string, max: number, what: string) => { if (v === "") return; const n = Number(v); if (!Number.isFinite(n)) flags.push(`${s.name} ${what}: not a number (${v})`); else if (n < 0 || n > max) flags.push(`${s.name} ${what}: ${n} is over ${max}`); };
        num(m.ca, Number(s.ca_weight), "CA"); num(m.exam, Number(s.exam_weight), "exam"); num(m.clinical, 100, "clinical"); num(m.attendance, 100, "attendance");
        if ((m.ca !== "" || m.exam !== "") && exam?.min_attendance_pct != null && m.attendance === "") flags.push(`${s.name}: attendance missing`);
        if ((m.ca !== "" || m.exam !== "") && s.clinical_component_min != null && m.clinical === "") flags.push(`${s.name}: clinical mark missing`);
        if (m.attendance !== "" && exam?.min_attendance_pct != null && Number(m.attendance) < exam.min_attendance_pct) flags.push(`${s.name}: barred at ${m.attendance}% attendance`);
        marks.push(m);
      }
      if (marks.every((m) => m.ca === "" && m.exam === "")) flags.push("no marks on the row");
      out.push({ number, name: c ? `${c.surname}, ${c.other_names}` : (row[off + 1] ?? ""), line: i + 1, marks, flags });
    }
    if (!started) { setErr({ status: 400, title: "No header row", detail: "The sheet has no row with a 'Matriculation number' heading; upload the template as downloaded." } as Problem); return; }
    setPreview({ file: f.name, rows: out, unread });
  }
  async function save() {
    if (!preview || !exam) return;
    const good = preview.rows.filter((r) => !r.flags.some((f) => /not in the|not a number|is over|missing|no marks/.test(f)));
    if (!good.length) return;
    setBusy(true); setErr(null);
    try {
      const r = await fetch(`/api/bff/api/v1/college/exams/${encodeURIComponent(exam.code)}/results/bulk`, {
        method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`${exam.code} ${session}: the ${level} Level score sheet uploaded (${good.length} rows)`) },
        body: JSON.stringify({ session, rows: good.map((x) => ({ number: x.number, marks: x.marks.filter((m) => m.ca !== "" || m.exam !== "").map((m) => ({ subjectId: m.subjectId, caScore: m.ca === "" ? null : Number(m.ca), examScore: m.exam === "" ? null : Number(m.exam), clinicalScore: m.clinical === "" ? null : Number(m.clinical), attendancePct: m.attendance === "" ? null : Number(m.attendance) })) })) }),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setErr((j as Problem) ?? { status: r.status, title: r.statusText }); return; }
      setDone(j); setPreview(null);
      notify(`${(j.saved as unknown[]).length} rows saved`);
      router.refresh();
    } finally { setBusy(false); }
  }

  /* the marked sheet: what stands after the upload, judged, with the summary */
  async function downloadMarked() {
    if (!exam) return;
    const headers = ["S/N", "Matriculation number", "Name", ...subjects.flatMap((s) => [`${s.name} · Total`, `${s.name} · Remark`]), "Decision"];
    let pass = 0, fail = 0, barred = 0, dist = 0, absent = 0;
    const body = rows.map((c, i) => {
      const results = parse<Result[]>(c.results, []); const d = parse<Decision | null>(c.decision, null);
      const cells: (string | number)[] = [i + 1, c.number, `${c.surname}, ${c.other_names}`];
      for (const s of subjects) {
        const rs = results.filter((x) => x.subject_id === s.id); const latest = rs[rs.length - 1];
        if (!latest || latest.passed == null) { cells.push("", "No result"); absent++; continue; }
        const remark = latest.passed ? (Number(latest.total) >= 70 ? "Pass · Distinction" : "Pass") : latest.barred ? "Barred" : "Fail";
        if (latest.passed) { pass++; if (Number(latest.total) >= 70) dist++; } else if (latest.barred) barred++; else fail++;
        cells.push(latest.total ?? "", `${remark}${latest.attempt !== "FIRST" ? ` (${word(latest.attempt)})` : ""}`);
      }
      cells.push(d ? `${word(d.outcome)}${d.state === "CONFIRMED" ? "" : " (provisional)"}` : "");
      return cells;
    });
    const summary: (string | number)[][] = [[], ["Summary"], ["Candidates", rows.length], ["Subject passes", pass], ["Distinctions", dist], ["Subject fails", fail], ["Barred by attendance", barred], ["Subjects without a result", absent]];
    const logo = await loadCrest();
    const blob = buildXlsx(headers, [...body, ...summary], "Marked sheet", {
      school: UNI, title: `${exam.name} · marked sheet`, date: new Date().toLocaleDateString("en-GB", { day: "2-digit", month: "long", year: "numeric" }), logo: logo ?? undefined,
      meta: [["Examination", `${exam.code} — ${exam.name}`], ["Level", `${level} Level`], ["Cohort", session], ["Judged by", "The prospectus's rule: 50 or more per subject, the clinical component where there is one, attendance at the minimum"]],
    });
    const a = document.createElement("a"); a.href = URL.createObjectURL(blob); a.download = `Marked sheet ${exam.code} ${level} Level ${session.replace("/", "-")}.xlsx`; a.click();
  }

  const withResults = rows.filter((c) => parse<Result[]>(c.results, []).some((r) => r.passed != null)).length;
  return (
    <>
      <div className="scope">
        <div className="scope__f"><label htmlFor="ss-session">Cohort (session the year began in)</label>
          <select id="ss-session" className="ws__select" value={session} onChange={(e) => nav({ session: e.target.value })}>{sessions.map((s) => <option key={s} value={s}>{s}</option>)}</select></div>
        {!coordinator ? (
          <div className="scope__f"><label htmlFor="ss-level">Level</label>
            <select id="ss-level" className="ws__select" value={level} onChange={(e) => nav({ level: Number(e.target.value) })}>{[200, 300, 400, 500, 600].map((l) => <option key={l} value={l}>{l} Level</option>)}</select></div>
        ) : null}
      </div>
      {problem ? <ProblemNotice problem={problem} /> : null}
      {err ? <ProblemNotice problem={err} /> : null}
      {!exam ? <Note kind="info" title="No examination at this level">The Professional examinations run from 200 Level.</Note> : (
        <>
          <Tiles items={[
            ["Cohort", String(rows.length), null, `${level} Level year begun in ${session}`],
            ["Registered", String(rows.filter((c) => c.fully_registered).length), null, "Every semester of the year registered"],
            ["With results", String(withResults), withResults === rows.length && rows.length ? "var(--green-ink)" : null, `${exam.code} · ${subjects.length} subjects`],
            ["Year", data?.yearReached ? "At its end" : "Running", data?.yearReached ? "var(--green-ink)" : "var(--red-ink)", data?.yearReached ? "Results may be entered" : "Results open when the final semester begins"],
          ]} />
          <Panel title={`${exam.code} — ${exam.name} · ${level} Level · ${session}`} right="Download, fill, upload">
            <PBody>
              <div style={{ display: "flex", gap: 8, flexWrap: "wrap", alignItems: "center" }}>
                <Btn kind="primary" disabled={!rows.length} onClick={() => void downloadTemplate()}>Download the score sheet</Btn>
                <label className="btn btn--ghost" style={{ cursor: "pointer" }}>Upload the filled sheet<input type="file" accept=".xlsx,.csv" style={{ display: "none" }} onChange={(e) => { const f = e.target.files?.[0]; if (f) void readFile(f); e.target.value = ""; }} /></label>
                <Btn kind="ghost" disabled={!withResults} onClick={() => void downloadMarked()}>Download the marked sheet</Btn>
              </div>
              <div className="sub2" style={{ marginTop: 8 }}>The sheet is a workbook with the cohort as it stands: a row per candidate, and per subject the CA out of {subjects[0]?.ca_weight ?? 30}, the examination out of {subjects[0]?.exam_weight ?? 70}{subjects.some((s) => s.clinical_component_min != null) ? ", the clinical mark out of 100" : ""} and the attendance percentage{exam.min_attendance_pct != null ? ` (minimum ${exam.min_attendance_pct}%, or the candidate is barred)` : ""}. Fill it and upload it; the preview names every problem before anything is saved. Each mark is judged by the rule as it goes in, and once a candidate&rsquo;s subjects are all resulted the rule&rsquo;s decision is applied provisionally for the Board to confirm.</div>
            </PBody>
          </Panel>
          {preview ? (
            <Panel title={`Preview: ${preview.file}`} right={`${preview.rows.length} rows · ${preview.rows.filter((r) => r.flags.length).length} flagged`}>
              {preview.unread.length ? <PBody><div style={{ color: "var(--red-ink)" }}>{preview.unread.join(" · ")}</div></PBody> : null}
              <DTable cols={["Line|mid", "Matriculation number", "Name", ...subjects.map((s) => `${s.name}|mid`), "Flags"]} rows={preview.rows.map((r) => [
                <span className="tnum" key="l">{r.line}</span>, <span className="tnum" key="n">{r.number}</span>, <span key="nm">{r.name}</span>,
                ...r.marks.map((m) => <span className="tnum" key={m.subjectId}>{m.ca === "" && m.exam === "" ? "—" : `${m.ca || "?"} + ${m.exam || "?"}${m.clinical ? ` · cl ${m.clinical}` : ""}${m.attendance ? ` · ${m.attendance}%` : ""}`}</span>),
                <span key="f" style={{ color: r.flags.length ? "var(--red-ink)" : undefined }}>{r.flags.length ? r.flags.join("; ") : "OK"}</span>,
              ])} />
              <PBody>
                <div style={{ display: "flex", gap: 8, flexWrap: "wrap", alignItems: "center" }}>
                  <Btn kind="go" disabled={busy || !preview.rows.some((r) => !r.flags.some((f) => /not in the|not a number|is over|missing|no marks/.test(f)))} onClick={() => void save()}>{busy ? "Saving…" : `Save ${preview.rows.filter((r) => !r.flags.some((f) => /not in the|not a number|is over|missing|no marks/.test(f))).length} rows`}</Btn>
                  <Btn kind="ghost" onClick={() => setPreview(null)}>Discard</Btn>
                  <span className="sub2">Rows flagged as not in the cohort, over range, missing a required mark or empty are left out; a barred or unregistered candidate is saved and shown as such.</span>
                </div>
              </PBody>
            </Panel>
          ) : null}
          {done ? (
            <Note kind={done.problems.length ? "bad" : "ok"} title={`${done.saved.length} rows saved${done.problems.length ? ` · ${done.problems.length} refused` : ""}`}>
              {done.saved.length ? `Decisions applied provisionally: ${done.saved.filter((s) => s.outcome).map((s) => `${s.number} ${word(s.outcome)}`).slice(0, 12).join(" · ")}${done.saved.filter((s) => s.outcome).length > 12 ? " · …" : ""}. ` : ""}
              {done.problems.length ? `Refused: ${done.problems.map((p) => `${p.number} — ${p.problem}`).join(" · ")}` : ""}
            </Note>
          ) : null}
          <Panel title="The cohort as it stands" right={`${rows.length} candidates`}>
            <DTable cols={["Matriculation number", "Name", "Registered|mid", ...subjects.map((s) => `${s.name}|mid`), "Decision|mid"]} rows={rows.map((c) => {
              const results = parse<Result[]>(c.results, []); const d = parse<Decision | null>(c.decision, null);
              return [
                <span className="tnum" key="n">{c.number}</span>, <strong key="nm">{c.surname}, {c.other_names}</strong>,
                <span key="r">{c.fully_registered ? <Pil kind="ok">Yes</Pil> : <Pil kind="bad">{c.semesters ? `${c.semesters_registered} of ${c.semesters}` : "No"}</Pil>}</span>,
                ...subjects.map((s) => { const rs = results.filter((x) => x.subject_id === s.id); const l = rs[rs.length - 1]; return <span key={s.id}>{l && l.passed != null ? <><span className="tnum">{l.total}</span> <Pil kind={l.passed ? "ok" : "bad"}>{l.passed ? (Number(l.total) >= 70 ? "Dist." : "Pass") : l.barred ? "Barred" : "Fail"}</Pil></> : <span className="sub2">—</span>}</span>; }),
                <span key="d">{d ? <Pil kind={d.outcome === "PROMOTE" || d.outcome === "GRADUATE" ? "ok" : d.outcome.startsWith("WITHDRAW") ? "bad" : "info"}>{word(d.outcome)}{d.state === "CONFIRMED" ? "" : " · provisional"}</Pil> : <span className="sub2">—</span>}</span>,
              ];
            })} texts={rows.map((c) => `${c.number} ${c.surname} ${c.other_names}`)} />
          </Panel>
        </>
      )}
    </>
  );
}
