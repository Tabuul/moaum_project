"use client";

/**
 * scoreEntry — proto/part28.html: the roll is every approved registration; the lecturer types
 * CA and examination; total, grade and point are computed by the engine, never typed. A mark
 * is never overwritten: a change is a new version with its reason. Bulk upload arrives as the
 * same two columns in a CSV, checked before anything is written, accepted whole or not at all.
 */
import { useRef, useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify } from "@/components/proto/Toast";
import { OUTCOMES, RS_STAGES, STAGE_LABEL, csv, download, type RollRow, type SheetDetail } from "@/lib/results";
import { Btn, Ico, LinkBtn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { Modal, Steps } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { semesterName } from "@/lib/student-portal";
import { csvRows, xlsxRows } from "@/lib/xlsx";

interface Draft { ca: string; exam: string; outcome: string; reason: string }

/** the pass mark under the scheme in force, for the preview only — the record grades from the scheme itself */
const PASS = 40;
/** the grace mark: a total one short of the pass mark is raised to it (V238) */
const graced = (raw: number): number => (raw === PASS - 1 ? PASS : raw);
/** the grade with its weight: A5, B4, C3, D2, E1, F0 */
const gw = (grade: string | null | undefined, points: number | null | undefined) =>
  grade == null ? "" : points == null ? grade : `${grade}${Number.isInteger(Number(points)) ? Number(points) : Number(points).toFixed(2)}`;

function draftOf(r: RollRow): Draft {
  return { ca: r.ca === null ? "" : String(r.ca), exam: r.exam === null ? "" : String(r.exam), outcome: r.outcome ?? "GRADED", reason: "" };
}

function changed(r: RollRow, d: Draft): boolean {
  const ca = d.ca === "" ? null : Number(d.ca);
  const exam = d.exam === "" ? null : Number(d.exam);
  return ca !== r.ca || exam !== r.exam || d.outcome !== (r.outcome ?? "GRADED");
}

export function ScoreEntry({ detail, roll, actingOffice }: { detail: SheetDetail; roll: RollRow[]; actingOffice: string | null }) {
  const router = useRouter();
  const s = detail.sheet;
  // the course's own split of the hundred marks (V239): CA share, examination the rest
  const CA_MAX = typeof s.caMax === "number" ? s.caMax : 40;
  const EXAM_MAX = 100 - CA_MAX;
  const atEntry = s.stage === "ENTRY";
  const [drafts, setDrafts] = useState<Record<string, Draft>>(() => Object.fromEntries(roll.map((r) => [r.studentId, draftOf(r)])));
  const [problem, setProblem] = useState<Problem | null>(null);
  const [busy, setBusy] = useState(false);
  const [saved, setSaved] = useState<string | null>(null);
  const [ask, setAsk] = useState<"submit" | null>(null);
  const [fileNote, setFileNote] = useState<{ kind: "ok" | "bad"; title: string; lines: string[] } | null>(null);
  // lines of an upload whose candidate is not on the roll: offered as held scripts, never held on their own
  const [offRoll, setOffRoll] = useState<{ line: number; number: string; ca: string; exam: string; outcome: string; note: string }[]>([]);
  const [holding, setHolding] = useState(false);
  const file = useRef<HTMLInputElement>(null);

  const dirty = roll.filter((r) => changed(r, drafts[r.studentId]));
  const needReason = dirty.filter((r) => r.version !== null && !drafts[r.studentId].reason.trim());
  const invalid = roll.filter((r) => {
    const d = drafts[r.studentId];
    if (d.outcome !== "GRADED") return false;
    const ca = d.ca === "" ? null : Number(d.ca);
    const ex = d.exam === "" ? null : Number(d.exam);
    return (d.ca !== "" && (Number.isNaN(ca) || ca! < 0 || ca! > CA_MAX)) || (d.exam !== "" && (Number.isNaN(ex) || ex! < 0 || ex! > EXAM_MAX)) || (d.ca === "") !== (d.exam === "");
  });
  const entered = roll.filter((r) => r.outcome !== null).length;
  const blank = roll.length - entered;
  const ready = atEntry && blank === 0 && dirty.length === 0;
  const own = actingOffice === "lecturer" || actingOffice === "exams" || actingOffice === "academic";
  // the sheet is back with the lecturer by a return when its latest decision is one; only then does a saved mark change
  const returned = detail.chain.length > 0 && detail.chain[detail.chain.length - 1].kind === "RETURN";
  const onRecord = (r: RollRow) => r.version !== null;
  const locked = (r: RollRow) => onRecord(r) && !returned;
  const lockedCount = roll.filter(locked).length;

  function set(id: string, patch: Partial<Draft>) {
    setDrafts((d) => ({ ...d, [id]: { ...d[id], ...patch } }));
    setSaved(null);
  }

  async function save(): Promise<boolean> {
    if (!dirty.length) return true;
    setBusy(true);
    setProblem(null);
    try {
      const scores = dirty.map((r) => {
        const d = drafts[r.studentId];
        const graded = d.outcome === "GRADED";
        return { studentId: r.studentId, ca: graded && d.ca !== "" ? Number(d.ca) : null, exam: graded && d.exam !== "" ? Number(d.exam) : null, outcome: d.outcome, reason: d.reason.trim() || null };
      }).filter((x) => x.outcome !== "GRADED" || (x.ca !== null && x.exam !== null));
      const r = await fetch(`/api/bff/api/v1/results/sheets/${s.id}/scores`, { method: "PUT", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`${s.courseCode}: ${scores.length} marks entered`) }, body: JSON.stringify({ scores }) });
      if (!r.ok) {
        setProblem((await r.json().catch(() => null)) ?? { status: r.status, title: r.statusText });
        return false;
      }
      const j = await r.json();
      setSaved(`${j.written} mark${j.written === 1 ? "" : "s"} written`);
      notify(`${j.written} mark${j.written === 1 ? "" : "s"} written`);
      router.refresh();
      return true;
    } finally {
      setBusy(false);
    }
  }

  async function submit() {
    if (!(await save())) return;
    setBusy(true);
    setProblem(null);
    try {
      const r = await fetch(`/api/bff/api/v1/results/sheets/${s.id}/advance`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`${s.courseCode}: submitted and attested by the lecturer`) }, body: "{}" });
      if (!r.ok) {
        setProblem((await r.json().catch(() => null)) ?? { status: r.status, title: r.statusText });
        return;
      }
      setAsk(null);
      notify(`${s.courseCode} submitted`);
      router.refresh();
    } finally {
      setBusy(false);
    }
  }

  function template() {
    download(`${s.courseCode.replace(/[^A-Za-z0-9]+/g, "-")}-score-sheet.xlsx`, csv([
      ["S/N", "Matriculation number", "Name", "Programme", "Level", `CA (0-${CA_MAX})`, `Exam (0-${EXAM_MAX})`, "Outcome (blank = GRADED, or ABSENT / WITHHELD / INCOMPLETE / MALPRACTICE / EXEMPTED)"],
      ...roll.map((r, i) => [i + 1, r.number, `${r.surname}, ${r.otherNames}`, r.programmeName, r.level, r.ca ?? "", r.exam ?? "", r.outcome && r.outcome !== "GRADED" ? r.outcome : ""]),
    ], [
      ["Department", s.deptName],
      ["Programme", ownProgramme?.programmeName ?? ""],
      ["Course", `${s.courseCode} — ${s.courseTitle}`],
      ["Lecturer", s.lecturer ?? "Not allocated"],
      ["Session", `${s.session} · ${semesterName(s.semester)} semester`],
    ], [
      { col: 5, min: 0, max: CA_MAX, title: `More than the ${CA_MAX} CA marks`, message: `${s.courseCode} assesses CA out of ${CA_MAX}. Enter 0 to ${CA_MAX}.` },
      { col: 6, min: 0, max: EXAM_MAX, title: `More than the ${EXAM_MAX} examination marks`, message: `${s.courseCode} examines out of ${EXAM_MAX}. Enter 0 to ${EXAM_MAX}.` },
    ]));
  }

  /* the file is read into the same drafts the keyboard fills; nothing is written until Save */
  async function readFile(f: File) {
    // the template is a workbook; a CSV filled by hand is read too. A workbook is known by its bytes (a zip), not its name.
    const buf = await f.arrayBuffer();
    const head = new Uint8Array(buf.slice(0, 2));
    const isWorkbook = (head[0] === 0x50 && head[1] === 0x4b) || /\.xlsx$/i.test(f.name);
    let cells: string[][];
    try {
      cells = (isWorkbook ? await xlsxRows(buf) : csvRows(new TextDecoder("utf-8").decode(buf))).map((row) => row.map((c) => String(c ?? "").trim()));
    } catch {
      setFileNote({ kind: "bad", title: `${f.name} could not be read`, lines: ["Upload the template as downloaded (an Excel workbook), filled in, or a CSV with the same columns."] });
      return;
    }
    const byNumber = Object.fromEntries(roll.map((r) => [r.number.toUpperCase(), r]));
    const problems: string[] = [];
    const aside: typeof offRoll = [];
    const next: Record<string, Draft> = { ...drafts };
    let matched = 0;
    setOffRoll([]);
    // the header row says where the matriculation number sits (after S/N in the current template, first in
    // the old one); the heading lines above it — department, programme, course, lecturer — are passed over
    const hasHeader = cells.some((row) => row.some((c) => /matric/i.test(c)));
    let started = !hasHeader; let off = 0;
    for (const [i, row] of cells.entries()) {
      if (!started) { const h = row.findIndex((c) => /matric/i.test(c)); if (h >= 0) { started = true; off = h; } continue; }
      if (row.every((c) => c === "")) continue;   // an empty line, or a spacer row a spreadsheet keeps
      const r = byNumber[(row[off] ?? "").toUpperCase()];
      if (!r) {
        const num = (row[off] ?? "").toUpperCase();
        if (!num) { problems.push(`Line ${i + 1}: no matriculation number`); continue; }
        aside.push({ line: i + 1, number: num, ca: (row[off + 4] ?? "").trim(), exam: (row[off + 5] ?? "").trim(), outcome: (row[off + 6] ?? "").trim().toUpperCase() || "GRADED", note: "" });
        continue;
      }
      const ca = (row[off + 4] ?? "").trim();
      const exam = (row[off + 5] ?? "").trim();
      const outcome = (row[off + 6] ?? "").trim().toUpperCase() || "GRADED";
      if (!OUTCOMES.includes(outcome as (typeof OUTCOMES)[number])) { problems.push(`Line ${i + 1}: outcome ${outcome} is not one the register knows`); continue; }
      if (locked(r)) {
        const same = outcome === (r.outcome ?? "GRADED") && (outcome !== "GRADED" || (Number(ca) === r.ca && Number(exam) === r.exam));
        if (same) continue;
        problems.push(`Line ${i + 1}: ${r.number} already has a mark on the record — it changes only after the sheet is returned`); continue;
      }
      if (outcome === "GRADED") {
        if (ca === "" && exam === "") continue;
        const c = Number(ca); const e = Number(exam);
        if (Number.isNaN(c) || c < 0 || c > CA_MAX) { problems.push(`Line ${i + 1}: CA ${ca} is outside 0–${CA_MAX}`); continue; }
        if (Number.isNaN(e) || e < 0 || e > EXAM_MAX) { problems.push(`Line ${i + 1}: exam ${exam} is outside 0–${EXAM_MAX}`); continue; }
      }
      next[r.studentId] = { ...next[r.studentId], ca: outcome === "GRADED" ? ca : "", exam: outcome === "GRADED" ? exam : "", outcome };
      matched++;
    }
    if (problems.length) {
      setFileNote({ kind: "bad", title: `${f.name} was not accepted — ${problems.length} line${problems.length === 1 ? "" : "s"} refused, nothing written`, lines: problems.slice(0, 12) });
      return;
    }
    setDrafts(next);
    setSaved(null);
    setOffRoll(aside);
    setFileNote({ kind: "ok", title: `${f.name} read: ${matched} row${matched === 1 ? "" : "s"} matched the roll${aside.length ? `; ${aside.length} candidate${aside.length === 1 ? " is" : "s are"} not on it` : ""}`,
      lines: ["The marks are on the sheet below as a draft. Check them, then Save — nothing is written until you do.", ...(aside.length ? ["The candidates not on the roll are listed below; hold their scripts with one press if they sat the paper, or leave them."] : [])] });
  }

  /** the lines set aside become held scripts — a deliberate second press, so a typo never becomes one on its own */
  async function holdOffRoll() {
    if (!offRoll.length) return;
    setHolding(true);
    setProblem(null);
    try {
      const r = await fetch(`/api/bff/api/v1/results/sheets/${s.id}/held/bulk`, {
        method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`${s.courseCode}: ${offRoll.length} script${offRoll.length === 1 ? "" : "s"} held from the uploaded sheet`) },
        body: JSON.stringify({ rows: offRoll.map((x) => ({ line: String(x.line), number: x.number, ca: x.ca, exam: x.exam, outcome: x.outcome, note: "From the uploaded score sheet" })) }),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j ?? { status: r.status, title: r.statusText }); return; }
      notify(`${j.held} held script${j.held === 1 ? "" : "s"} from the upload`);
      setOffRoll([]);
      router.refresh();
    } finally {
      setHolding(false);
    }
  }

  const ownCode = [...roll.reduce((m, r) => m.set(r.programmeCode, (m.get(r.programmeCode) ?? 0) + 1), new Map<string, number>()).entries()].sort((a, b) => b[1] - a[1])[0]?.[0];
  const ownProgramme = roll.find((r) => r.programmeCode === ownCode);
  const borrowed = roll.filter((r) => r.programmeCode !== ownCode).length;
  const stageIdx = s.spineStage - 1;

  return (
    <>
      {!atEntry ? (
        <Note kind={s.stage === "PUBLISHED" ? "ok" : "info"} title={s.stage === "PUBLISHED" ? `Published under Senate minute ${detail.senateMinute}` : `This sheet has left the lecturer: ${STAGE_LABEL[s.stage]?.[0] ?? s.stage}`} action={<LinkBtn href={`/results/chain?sheet=${s.id}`} kind="ghost">Open the approval chain</LinkBtn>}>
          {s.stage === "PUBLISHED" ? "Every mark below is what the candidate sees. A correction from here is a result query, answered on the record." : `It is with ${STAGE_LABEL[s.stage]?.[1] ?? "the next desk"}. The marks are readable, not editable; if it comes back, it comes back with the reason.`}
        </Note>
      ) : s.returnedTimes > 0 ? (
        <Note kind="bad" title={`Returned to you ${s.returnedTimes === 1 ? "once" : `${s.returnedTimes} times`}`}>
          {detail.chain.filter((d) => d.kind === "RETURN").map((d) => `${d.actorOffice}: “${d.comment}”`).join(" · ")}. Correct the marks concerned — each correction is a new version with its reason — and submit again.
        </Note>
      ) : null}

      <div className="row">
        <Pil kind={ready ? "ok" : atEntry ? "bad" : "info"}>{!atEntry ? RS_STAGES[stageIdx]?.[0] ?? s.stage : ready ? "Complete — not yet submitted" : blank ? `Draft — ${blank} candidate${blank === 1 ? "" : "s"} without a mark` : "Draft — unsaved changes"}</Pil>
        {saved ? <span className="sk__saved"><Ico name="check" size={14} /> {saved}</span> : dirty.length ? <span className="sub2">{dirty.length} unsaved</span> : null}
        <span className="grow" />
        <Btn kind="ghost" onClick={template}>Download the template</Btn>
        {entered > 0 ? <>
          {/* the marked sheet as it stands — total, grade and point computed by the register, a performance summary at the end */}
          <a className="btn btn--ghost btn--sm" href={`/results/sheets/${s.id}/marked?format=xlsx`} title="The roll with total, grade and point, and a summary of performance — Excel">Marked sheet · Excel</a>
          <a className="btn btn--ghost btn--sm" href={`/results/sheets/${s.id}/marked?format=pdf`} title="The roll with total, grade and point, and a summary of performance — PDF">Marked sheet · PDF</a>
        </> : null}
        {atEntry && own ? <><Btn kind="ghost" onClick={() => file.current?.click()}>Upload a completed sheet</Btn><input ref={file} type="file" accept=".xlsx,.csv,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet,text/csv" hidden onChange={(e) => { const f = e.target.files?.[0]; if (f) void readFile(f); e.target.value = ""; }} /></> : null}
        {atEntry && own ? <Btn kind="primary" disabled={busy || !dirty.length || invalid.length > 0 || needReason.length > 0} onClick={() => void save()}>{busy ? "Saving…" : "Save the draft"}</Btn> : null}
        {atEntry && own ? <Btn kind={ready ? "go" : "ghost"} disabled={busy || !(blank === 0) || invalid.length > 0 || needReason.length > 0} onClick={() => setAsk("submit")}>Submit and attest</Btn> : null}
      </div>

      {problem ? <ProblemNotice problem={problem} /> : null}
      {fileNote ? <Note kind={fileNote.kind} title={fileNote.title}>{fileNote.lines.map((l, i) => <div key={i}>{l}</div>)}</Note> : null}
      {offRoll.length ? (
        <Note kind="info" title={`${offRoll.length} candidate${offRoll.length === 1 ? "" : "s"} on the upload ${offRoll.length === 1 ? "is" : "are"} not on this roll`}
          action={atEntry && own ? <span className="row row--inline row--tight"><Btn kind="primary" disabled={holding} onClick={() => void holdOffRoll()}>{holding ? "Holding…" : `Hold ${offRoll.length === 1 ? "this script" : `these ${offRoll.length} scripts`}`}</Btn><Btn kind="ghost" disabled={holding} onClick={() => setOffRoll([])}>Leave them</Btn></span> : undefined}>
          {offRoll.slice(0, 12).map((x) => <div key={x.line} className="tnum">Line {x.line}: {x.number}{x.outcome === "GRADED" ? ` · CA ${x.ca || "—"} · Exam ${x.exam || "—"}` : ` · ${x.outcome}`}</div>)}
          {offRoll.length > 12 ? <div className="sub2">… and {offRoll.length - 12} more</div> : null}
          <div className="sub2 mt-1">A candidate not on the roll did not register the course. If they sat the paper, hold the scripts: each waits on the candidate&rsquo;s registration and the register releases it into this sheet when that is approved. A number the register does not know is refused by name and nothing is held.</div>
        </Note>
      ) : null}
      {atEntry && own && lockedCount > 0 ? (
        <Note kind="info" title={`${lockedCount} mark${lockedCount === 1 ? " is" : "s are"} on the record and locked`}>
          A mark once saved is not changed by the lecturer. Enter the candidates still without one and submit. If a saved mark is wrong, submit the sheet and ask the Examination Officer or the Head of Department to return it with the reason; every mark then opens for amendment, each change carrying its reason.
        </Note>
      ) : null}
      {atEntry && own && returned ? (
        <Note kind="ok" title="Returned to you — every mark is open for amendment">
          Change what the return asks for, say why on each row, and submit again.
        </Note>
      ) : null}
      {needReason.length ? <Note kind="bad" title="A changed mark carries its reason">{needReason.length} row{needReason.length === 1 ? " is" : "s are"} amendments of a mark already on the record. Say why in the reason box on the row; the old value stays beside the new one.</Note> : null}
      {invalid.length ? <Note kind="bad" title={`${invalid.length} row${invalid.length === 1 ? " is" : "s are"} outside the marks — nothing saves until they are within`}>{s.courseCode} assesses CA out of {CA_MAX} and examines out of {EXAM_MAX}, both entered or neither. A part over its share is marked red on the row.</Note> : null}

      <Tiles items={[
        ["Candidates", String(roll.length), null, "Every approved registration"],
        ["From other programmes", String(borrowed), borrowed ? "var(--chrome)" : null, borrowed ? "They sat the same paper" : "All from the owning programme"],
        ["CA out of", String(CA_MAX), null, `Examination out of ${EXAM_MAX} · set on the department's catalogue`],
        ["Second examiner", detail.secondExaminer ?? "Not yet set", detail.secondExaminer ? null : "var(--red-ink)", "Set when the course was allocated"],
      ]} />

      <Note kind="info" title={borrowed ? "This roll is every registered candidate, not this department’s students" : "This roll is every registered candidate"}>
        {s.courseCode} — {s.courseTitle}, {s.units} units, {s.session} {semesterName(s.semester).toLowerCase()} semester. {roll.length} candidate{roll.length === 1 ? "" : "s"} registered and approved{borrowed ? `; ${borrowed} from ${Array.from(new Set(roll.filter((r) => r.programmeCode !== ownCode).map((r) => r.programmeName))).join(", ")}` : ownProgramme ? `, all ${ownProgramme.programmeName}` : ""}. They registered the course the ordinary way and they sat the same paper. Mark them the same way.
      </Note>

      <Panel title={`${s.deptName} · ${ownProgramme?.programmeName ?? "Programme not on the roll yet"} · ${s.courseCode} — ${s.courseTitle} · ${s.lecturer ?? "No lecturer allocated"}`} right={`${entered} of ${roll.length} entered · Enter or ↓ moves down the column`}>
        {roll.length === 0 ? (
          <div className="card__body sub2">Nobody is registered and approved for this offering, so the sheet has no rows. A student who is not on the roll is not registered, whatever they tell you.</div>
        ) : (
          <div className="tablewrap">
            <table style={{ minWidth: 1020 }}>
              <thead><tr><th className="mid">S/N</th><th>Matriculation number</th><th>Name</th><th>Programme</th><th className="mid">Lv</th><th className="mid">CA — {CA_MAX}</th><th className="mid">Exam — {EXAM_MAX}</th><th className="mid">Total</th><th className="mid">Grade</th><th className="mid">Points</th><th>Outcome</th><th>Reason, if amended</th></tr></thead>
              <tbody>
                {roll.map((r, i) => {
                  const d = drafts[r.studentId];
                  const graded = d.outcome === "GRADED";
                  const ca = d.ca === "" ? null : Number(d.ca);
                  const ex = d.exam === "" ? null : Number(d.exam);
                  // a part over the course's share is flagged on the row as it is typed; no total until it is within
                  const caOver = graded && ca !== null && !Number.isNaN(ca) && ca > CA_MAX;
                  const exOver = graded && ex !== null && !Number.isNaN(ex) && ex > EXAM_MAX;
                  const raw = graded && !caOver && !exOver && ca !== null && ex !== null && !Number.isNaN(ca) && !Number.isNaN(ex) ? ca + ex : null;
                  const overStyle = { width: 64, textAlign: "center" as const, borderColor: "var(--red-ink)", background: "var(--red-bg)", color: "var(--red-ink)", fontWeight: 700 };
                  const overNote = (n: number) => <div className="ink-red t-xs" style={{ lineHeight: 1.2, marginTop: 3, whiteSpace: "nowrap" }}>More than {n}</div>;
                  const total = raw === null ? null : graced(raw);
                  const isChanged = changed(r, d);
                  const editable = atEntry && own && !locked(r);
                  const move = (e: React.KeyboardEvent<HTMLInputElement>, col: string) => {
                    if (e.key === "Enter" || e.key === "ArrowDown") { e.preventDefault(); (document.getElementById(`${col}-${i + 1}`) as HTMLInputElement | null)?.focus(); }
                    if (e.key === "ArrowUp") { e.preventDefault(); (document.getElementById(`${col}-${i - 1}`) as HTMLInputElement | null)?.focus(); }
                  };
                  return (
                    <tr key={r.studentId} style={isChanged ? { background: "var(--amber-wash)" } : undefined}>
                      <td className="mid tnum">{i + 1}</td>
                      <td className="tnum">{r.number}</td>
                      <td><strong>{r.surname}, {r.otherNames}</strong></td>
                      <td className="sub2">{r.programmeName}</td>
                      <td className="mid tnum">{r.level}</td>
                      <td className="mid">{editable ? <><input id={`ca-${i}`} className="ctl tnum" style={caOver ? overStyle : { width: 64, textAlign: "center" }} aria-invalid={caOver || undefined} title={caOver ? `${s.courseCode} assesses CA out of ${CA_MAX}` : undefined} inputMode="numeric" value={d.ca} disabled={!graded} onKeyDown={(e) => move(e, "ca")} onChange={(e) => set(r.studentId, { ca: e.target.value.replace(/[^0-9]/g, "") })} />{caOver ? overNote(CA_MAX) : null}</> : <span className="tnum">{r.ca ?? "—"}</span>}</td>
                      <td className="mid">{editable ? <><input id={`ex-${i}`} className="ctl tnum" style={exOver ? overStyle : { width: 64, textAlign: "center" }} aria-invalid={exOver || undefined} title={exOver ? `${s.courseCode} examines out of ${EXAM_MAX}` : undefined} inputMode="numeric" value={d.exam} disabled={!graded} onKeyDown={(e) => move(e, "ex")} onChange={(e) => set(r.studentId, { exam: e.target.value.replace(/[^0-9]/g, "") })} />{exOver ? overNote(EXAM_MAX) : null}</> : <span className="tnum">{r.exam ?? "—"}</span>}</td>
                      <td className="mid"><b className="tnum" title={isChanged && raw !== null && total !== raw ? `${raw} + 1 grace mark` : r.ca !== null && r.exam !== null && r.total !== null && r.total !== r.ca + r.exam ? `${r.ca + r.exam} + 1 grace mark` : undefined}>{isChanged ? (total ?? "—") : (r.total ?? (r.outcome && r.outcome !== "GRADED" ? r.outcome : "—"))}{(isChanged && raw !== null && total !== raw) || (!isChanged && r.ca !== null && r.exam !== null && r.total !== null && r.total !== r.ca + r.exam) ? <sup style={{ fontWeight: 400, marginLeft: 2 }}>+1</sup> : null}</b></td>
                      <td className="mid">{!isChanged && r.grade ? <Pil kind={(r.points ?? 0) >= 4 ? "ok" : (r.points ?? 0) >= 1 ? "info" : "bad"}>{gw(r.grade, r.points)}</Pil> : <span className="sub2">{isChanged ? "on save" : "—"}</span>}</td>
                      <td className="mid tnum">{!isChanged && r.points !== null ? r.points : "—"}</td>
                      <td>{editable ? (
                        <select className="ctl" value={d.outcome} onChange={(e) => set(r.studentId, { outcome: e.target.value, ...(e.target.value !== "GRADED" ? { ca: "", exam: "" } : {}) })}>
                          {OUTCOMES.map((o) => <option key={o} value={o}>{o === "GRADED" ? "Graded" : o.charAt(0) + o.slice(1).toLowerCase()}</option>)}
                        </select>
                      ) : <span className="sub2">{r.outcome ?? "Not entered"}</span>}</td>
                      <td>{editable && r.version !== null && isChanged ? <input className="ctl" placeholder="Why the mark changes" value={d.reason} onChange={(e) => set(r.studentId, { reason: e.target.value })} /> : atEntry && own && locked(r) ? <span className="sub2">On the record{r.version && r.version > 1 ? ` · version ${r.version}` : ""}</span> : r.version && r.version > 1 ? <span className="sub2">Version {r.version}</span> : <span className="sub2">—</span>}</td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </Panel>

      <Note kind="info" title="You type two numbers; the system does the rest">
        CA plus examination gives a total; a total one short of the pass mark is raised to it by the University&rsquo;s grace mark (39 reads 40) and graded as a pass; the total meets the grading scheme in force for this session; the scheme gives a grade and a point. <b>Nobody types a grade</b>, so nobody can type the wrong one, and a change to the scheme cannot leave behind a grade that no longer follows from the mark. The same three columns are computed identically whether the marks were typed on this screen or read from the template.
      </Note>

      <Panel title="What happens when you attest">
        <PBody>
          <Steps list={[
            [atEntry ? "now" : "done", "The sheet is signed in your name and locked", "You keep read access to it for the rest of the session. A correction after this point is made on the record, and both versions remain."],
            [atEntry ? "todo" : s.spineStage >= 2 ? "done" : "now", `It goes to the second examiner${detail.secondExaminer ? `, ${detail.secondExaminer}` : ""}`, "Set when the course was allocated, not chosen now — the verifier has to exist before the marks do."],
            [s.spineStage >= 3 ? "done" : "todo", "Then the departmental board, then the Faculty, then Senate", "You will see it move. If it is returned, it comes back to you with the reason attached."],
          ]} />
        </PBody>
      </Panel>

      {ask === "submit" ? (
        <Modal title="Submit and attest" sub={`${s.courseCode} · ${roll.length} candidates`} onClose={() => setAsk(null)}
          foot={<><Btn kind="ghost" onClick={() => setAsk(null)}>Not yet</Btn><span className="grow" /><Btn kind="go" disabled={busy} onClick={() => void submit()}>{busy ? "Submitting…" : "I attest these marks"}</Btn></>}>
          <p className="m-0" style={{ lineHeight: 1.6 }}>Every candidate on the roll carries a mark or an outcome. Attesting signs the sheet in your name and sends it to verification; it will not accept a further mark from you unless a desk returns it with a reason.</p>
        </Modal>
      ) : null}
    </>
  );
}
