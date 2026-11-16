"use client";

/**
 * The old portal's course registration and past results, one confirmed upload at a time: each has its reference (PRU-YYYY-NNNNN),
 * the reason it was loaded, the officer and office, and a ledger of every change it made to a student's record with what was there
 * before. One upload's report reconciles it — the students whose CGPA moved (before and after), the Senate-approved graduates,
 * whose approved CGPA and class of degree stay as approved, listed for the Registry, and every row of the file that did not load
 * or was left as it was. The officer who opened an upload closes one left running; the Directorate of ICT (or a Database Operator
 * granted over the University) rolls a confirmed upload back from its ledger, with a reason.
 */
import Link from "next/link";
import { useState } from "react";
import { useJson } from "@/lib/use-json";
import { reasonHeader } from "@/lib/reason";
import { Btn, KvGrid, LinkBtn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { Field, Modal } from "@/components/proto/blocks";
import { DTable } from "@/components/proto/DTable";
import { ProblemNotice } from "@/components/ProblemNotice";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { roleLabel } from "@/lib/offices";
import { semesterName } from "@/lib/student-portal";
import { when } from "@/lib/old-fees-history";
import { MATCH_WORD, lineTone, lineWord, plainDetail, type LegacyLine } from "@/lib/legacy-merge";
import type { Problem } from "@/lib/api";

type Counts = { changes?: number; students?: number; graduates?: number; byKind?: Record<string, number>; rows?: number; byStatus?: Record<string, number> };
type RevertCounts = { undone?: number; left?: number; heldDropped?: number; earlierUndone?: number };
interface Upload {
  id: string; ref: string; kind: "RESULTS" | "REGISTRATION" | string; fileName: string | null; rows: number; reason: string;
  state: "RUNNING" | "COMPLETE" | "INCOMPLETE" | "REVERTED" | string; counts: Counts | string | null; createdAt: string; createdBy?: string | null;
  createdByName?: string | null; createdOffice?: string | null; finishedAt: string | null;
  revertedAt?: string | null; revertedByName?: string | null; revertReason?: string | null; revertCounts?: RevertCounts | string | null;
}
interface Student {
  studentId: string; matric: string; name: string; programme: string | null; cgpaBefore: number | string | null; cgpaAfter: number | string | null;
  tcrBefore: number | null; tcrAfter: number | null; graduate: boolean; changes: number;
}
interface Change {
  seq: number; kind: string; matric: string | null; courseCode: string | null; session: string | null; semester: number | null; line: string | null;
  wasUnits: number | null; nowUnits: number | null; wasCode: string | null; nowCode: string | null; wasTitle: string | null; nowTitle: string | null;
  wasEntryType: string | null; nowEntryType: string | null; wasStatus: string | null; nowStatus: string | null; graduate: boolean; changedAt: string;
  /** the category the record read on each side (CORE, ELECTIVE, GST, CARRY_OVER): the programme's basis first, a GST course always GST */
  wasCategory?: string | null; nowCategory?: string | null;
  /** the level of a registration or session enrolment the upload made */
  level?: number | null;
  revertedAt?: string | null; revertNote?: string | null;
}
/** a row of the file that did not load, or was left as it was, with what the loader read of it (the line it answered) */
interface UploadRow {
  session: string; semester: number; line: string | null; matric: string; course: string; status: string; detail: string | null;
  facts: Partial<LegacyLine> | string | null;
}
interface Report {
  upload: Upload; byKind: Record<string, number>; students: Student[]; graduates: Student[]; changes: Change[]; changesTotal: number;
  rows: UploadRow[]; rowsTotal: number; byStatus: Record<string, number>;
  /** what became of the course on the registration, where it is not what the row's status says (a result posted on a course kept as on
   *  the portal or corrected) */
  byEntryStatus: Record<string, number>;
}
/** what a rollback answered: the changes undone, those left as they were with why, and the results it was holding that were dropped */
interface Reverted {
  ref: string; state: string; undone: number; left: number; heldDropped: number;
  /** changes an earlier rollback had to leave because this upload's stood on them, undone now */
  earlierUndone: number;
  leftChanges: { kind: string; courseCode: string | null; session: string | null; semester: number | null; matric: string | null; note: string | null }[];
}
/** who reads the page: the person (an upload's opener closes it) and the acting office (the Directorate of ICT rolls one back) */
export type Viewer = { actorId: string | null; office: string | null };

const BASE = "/api/bff/api/v1/results/legacy/uploads";
const KIND_WORD: Record<string, string> = { RESULTS: "Past results", REGISTRATION: "Course registration" };
const STATE: Record<string, [string, "ok" | "warn" | "info" | "grey"]> = {
  COMPLETE: ["Complete", "ok"], INCOMPLETE: ["Stopped part way", "warn"], RUNNING: ["Running", "info"], REVERTED: ["Rolled back", "grey"],
};
/** a confirmed upload is rolled back by the Directorate of ICT or a Database Operator granted over the University (the API and the
 *  database say; a Database Operator granted over less is refused there) */
const MAY_REVERT = ["ict", "dbops", "super"];
/** each kind of change an upload makes, in the order the report counts them */
const CHANGE_WORD: [string, string][] = [
  ["ENTRY_ADDED", "Course added"], ["UNITS_CORRECTED", "Units corrected"], ["AS_TAKEN_CORRECTED", "Code or title corrected"],
  ["AS_TAKEN_LINKED", "Recorded as taken"], ["CATEGORY_CORRECTED", "Category corrected"], ["ENTRY_REAPPROVED", "Approved again"],
  ["RESULT_POSTED", "Result posted"], ["RESULT_REPLACED", "Result replaced"], ["CLASS_HEADER_CORRECTED", "Class heading corrected"],
  ["REGISTRATION_ADDED", "Registration made"], ["ENROLMENT_ADDED", "Session enrolment made"],
];
/** "results held … were dropped": the results a rolled-back upload was holding for students not yet on the register */
const heldWords = (n: number) =>
  `${n.toLocaleString()} result${n === 1 ? "" : "s"} held for students not yet on the register ${n === 1 ? "was" : "were"} dropped`;
const changeWord = (k: string) => CHANGE_WORD.find(([x]) => x === k)?.[1] ?? k;
/** a student's course as its category reads on the record; an older report without it falls back to the entry's type */
const CATEGORY_WORD: Record<string, string> = {
  CORE: "core", ELECTIVE: "elective", GST: "GST", CARRY_OVER: "carry-over", CURRENT: "core", CARRYOVER: "carry-over", DEFERRED: "carry-over", REPEAT: "carry-over",
};
const category = (cat: string | null | undefined, type?: string | null) => {
  const k = cat ?? type ?? null;
  return k ? CATEGORY_WORD[k] ?? k.toLowerCase().replace(/_/g, "-") : "";
};
const wasCategory = (c: Change) => category(c.wasCategory, c.wasEntryType);
const nowCategory = (c: Change) => category(c.nowCategory, c.nowEntryType);
/** "N changes of other rolled-back uploads were undone too": what an earlier rollback had to leave because of this upload, and a
 *  first result that went with the course this upload had put there */
const earlierWords = (n: number) =>
  `${n.toLocaleString()} change${n === 1 ? "" : "s"} of other rolled-back uploads that stood on this one ${n === 1 ? "was" : "were"} undone too`;
const figure = (v: number | string | null | undefined) => (v == null || v === "" || !Number.isFinite(Number(v)) ? "—" : Number(v).toFixed(2));
/** a JSON column the API may hand over as text */
function objectOf<T extends object>(v: T | string | null | undefined): Partial<T> {
  if (v && typeof v === "object") return v;
  if (typeof v === "string") { try { return JSON.parse(v) as Partial<T>; } catch { return {}; } }
  return {};
}
const countsOf = (u: Upload): Counts => objectOf<Counts>(u.counts);
/** a CGPA the upload left as it found it: no figure after (never "moved"), or the same figure */
const cgpaAfter = (s: Student) => (s.cgpaAfter == null || s.cgpaAfter === "" ? s.cgpaBefore : s.cgpaAfter);
const cgpaMoved = (s: Student) => s.cgpaAfter != null && s.cgpaAfter !== "" && figure(s.cgpaBefore) !== figure(s.cgpaAfter);
const sameId = (a: string | null | undefined, b: string | null | undefined) => !!a && !!b && a.toLowerCase() === b.toLowerCase();

/** a course as one side of a change has it: code and title, units, category (in words), status */
function side(code: string | null, title: string | null, units: number | null, cat: string | null, status: string | null): string {
  return [code && title ? `${code} “${title}”` : code || (title ? `“${title}”` : ""), units != null ? `${units} unit${units === 1 ? "" : "s"}` : "",
    cat ?? "", status ? status.toLowerCase() : ""].filter(Boolean).join(", ");
}

/** what a change found and what it left: the course in full where it was added, otherwise only what moved */
function wasNow(c: Change): [string, string] {
  if (c.kind === "ENTRY_ADDED") return ["—", side(c.nowCode, c.nowTitle, c.nowUnits, nowCategory(c), c.nowStatus)];
  if (c.kind === "RESULT_POSTED") return ["no result from an upload", "the file's result posted"];
  if (c.kind === "RESULT_REPLACED") return ["an earlier upload's result", "the file's result"];
  const at = c.level ? ` at ${c.level} Level` : "";
  if (c.kind === "REGISTRATION_ADDED") return ["no registration for the semester", `a registration made${at}, approved`];
  if (c.kind === "ENROLMENT_ADDED") return ["not enrolled for the session", `enrolled${at}`];
  const ident = c.wasCode !== c.nowCode || c.wasTitle !== c.nowTitle;
  const units = c.wasUnits !== c.nowUnits;
  const type = wasCategory(c) !== nowCategory(c);
  const status = c.wasStatus !== c.nowStatus;
  if (!ident && !units && !type && !status) {
    return ["the same, not yet recorded as taken", side(c.nowCode, c.nowTitle, c.nowUnits, null, null)];
  }
  return [
    side(ident ? c.wasCode : null, ident ? c.wasTitle : null, units ? c.wasUnits : null, type ? wasCategory(c) : null, status ? c.wasStatus : null) || "—",
    side(ident ? c.nowCode : null, ident ? c.nowTitle : null, units ? c.nowUnits : null, type ? nowCategory(c) : null, status ? c.nowStatus : null) || "—",
  ];
}

/** what a rollback did to one change: undone, or left as it was and why; nothing where the upload was not rolled back */
const revertWords = (c: Change) =>
  (c.revertedAt ? `rolled back ${when(c.revertedAt)}${c.revertNote ? ` (${c.revertNote})` : ""}` : c.revertNote ? `left as it was: ${c.revertNote}` : "");

export function Uploads({ id, viewer }: { id: string | null; viewer: Viewer | null }) {
  return id ? <UploadReport id={id} viewer={viewer} /> : <UploadList />;
}

function UploadList() {
  const { data, failed, loading } = useJson<Upload[]>(`${BASE}?limit=50`);
  const rows = Array.isArray(data) ? data : [];
  return (
    <>
      <Note kind="info" title="Each confirmed file is one upload on the record">
        A course registration or past results file from the old portal goes up under its own reference, with the reason it was loaded and
        who loaded it. Its report lists every change it made with what was there before, the students whose CGPA moved, the
        Senate-approved graduates for the Registry, and every row that did not load or was left as it was.
      </Note>
      {failed ? <Note kind="bad" title="Unable to load the uploads">{failed}</Note> : null}
      <Panel title="Confirmed uploads" right={<span className="row row--inline" style={{ gap: 8 }}>
        {loading ? <span className="sub2">Loading…</span> : <span className="sub2">{`the latest ${rows.length.toLocaleString()}, newest first`}</span>}
        <LinkBtn href="/records/migration">Migrate from the old portal</LinkBtn>
      </span>}>
        {rows.length ? (
          <DTable pageSize={25} cols={["Upload", "What", "File", "Rows|num", "State", "Changes|num", "Students|num", "Graduates|num", "Reason", "Loaded by", "Started", "Finished"]}
            texts={rows.map((u) => `${u.ref} ${u.fileName ?? ""} ${KIND_WORD[u.kind] ?? u.kind} ${u.reason} ${u.createdByName ?? ""} ${(STATE[u.state] ?? [u.state])[0]}`)}
            rows={rows.map((u) => {
              const c = countsOf(u);
              const [word, tone] = STATE[u.state] ?? [u.state, "info"];
              return [
                <Link key="r" href={`/records/migration/uploads?id=${encodeURIComponent(u.id)}`} className="tnum"><b>{u.ref}</b></Link>,
                KIND_WORD[u.kind] ?? u.kind, u.fileName ?? "—", Number(u.rows ?? 0).toLocaleString(),
                <span key="s"><Pil kind={tone}>{word}</Pil>{u.state === "REVERTED" && u.revertedAt ? <span className="sub2" style={{ display: "block" }}>{when(u.revertedAt)}</span> : null}</span>,
                c.changes != null ? Number(c.changes).toLocaleString() : "—", c.students != null ? Number(c.students).toLocaleString() : "—",
                c.graduates != null ? Number(c.graduates).toLocaleString() : "—",
                <span key="w" className="sub2">{u.reason}</span>,
                <span key="b">{u.createdByName ?? "—"}<span className="sub2" style={{ display: "block" }}>{roleLabel(u.createdOffice)}</span></span>,
                when(u.createdAt), when(u.finishedAt),
              ];
            })} />
        ) : !loading && !failed ? (
          <PBody><Note kind="ok" title="No upload yet">A confirmed course registration or past results file from the old portal is listed here.</Note></PBody>
        ) : null}
      </Panel>
    </>
  );
}

/** the confirmation before an upload is rolled back: what a rollback takes back and what it does not, in plain words, and why it is
 *  rolled back (ten characters or more, on the upload's record with the officer's name). Its own state, so typing in it does not
 *  redraw the report behind it. */
function ConfirmRollback({ upload, changes, busy, problem, onCancel, onConfirm }: {
  upload: Upload; changes: number; busy: boolean; problem: Problem | null; onCancel: () => void; onConfirm: (reason: string) => void;
}) {
  const [reason, setReason] = useState("");
  const ready = reason.trim().length >= 10;
  return (
    <Modal wide title={`Roll back upload ${upload.ref}`}
      sub={`${KIND_WORD[upload.kind] ?? upload.kind} · ${upload.fileName ?? "no file name"} · ${changes.toLocaleString()} change${changes === 1 ? "" : "s"} on its record`} onClose={onCancel}
      foot={<><Btn kind="ghost" onClick={onCancel}>Cancel</Btn><span className="grow" /><Btn kind="urgent" disabled={!ready || busy} busy={busy} onClick={() => onConfirm(reason.trim())}>Roll it back</Btn></>}>
      <p className="sub2">
        Each change the upload made is undone, newest first, wherever it is still the last word on what it changed:
      </p>
      <ul className="sub2" style={{ paddingLeft: 18, margin: "4px 0 8px" }}>
        <li>a course it added to a registration is taken off it, as if it had never been added; a mark it posted on that course stays on its result sheet as history and no longer counts;</li>
        <li>a dropped course it approved again is dropped again, and a result it posted on that course goes with it;</li>
        <li>a course whose credit units, code, title or category it corrected goes back to what it was;</li>
        <li>a result that replaced an earlier upload&rsquo;s gives the earlier result back;</li>
        <li>a class heading it set goes back to what it was;</li>
        <li>a course registration or session enrolment it made is taken off when nothing else is left on it and nothing has been done to it since (a registration reset, decided on or moved to another level stays);</li>
        <li>results it was still holding for students not yet on the register are dropped, or go back to an earlier upload still standing that held them before it;</li>
        <li>an issued transcript or statement of a student whose course is taken off is flagged for review.</li>
      </ul>
      <Note kind="info" title="What a rollback does not take back">
        Anything done to the record since the upload (a later upload still standing, a result amendment, a mark entered on the
        portal, units the Senate set, a Course Registration Correction on the course) is left as it is and listed with why; when the
        later upload is rolled back too, what was left because of it is undone then, so the order uploads are rolled back in does not
        matter. A first result the upload posted on a course that was already on the registration is not taken back here: amend it
        through Result amendments — unless another upload put that course there, when the result goes with the course once that
        upload is rolled back too. A Senate-approved
        graduate&rsquo;s approved CGPA and class of degree stay as approved, as they did when the file went up. The upload stays on the
        record, marked rolled back, with this report; it is not rolled back twice, and the file goes up again only as a new upload.
      </Note>
      {problem ? <ProblemNotice problem={problem} /> : null}
      <Field id="pru-why" label="Why this upload is rolled back" required hint="Ten characters or more; it goes on the upload's record with your name">
        <textarea id="pru-why" className="ctl" rows={3} value={reason} onChange={(e) => setReason(e.target.value)} />
      </Field>
    </Modal>
  );
}

function UploadReport({ id, viewer }: { id: string; viewer: Viewer | null }) {
  const [tick, setTick] = useState(0);
  const { data: answer, failed, loading } = useJson<Report>(`${BASE}/${encodeURIComponent(id)}`, tick);
  // an answer read whole: a list the reader left out is an empty one
  const data: Report | null = answer?.upload ? { ...answer, byKind: answer.byKind ?? {}, students: answer.students ?? [], graduates: answer.graduates ?? [],
    changes: answer.changes ?? [], changesTotal: Number(answer.changesTotal ?? answer.changes?.length ?? 0),
    rows: answer.rows ?? [], rowsTotal: Number(answer.rowsTotal ?? answer.rows?.length ?? 0),
    byStatus: answer.byStatus ?? countsOf(answer.upload).byStatus ?? {}, byEntryStatus: answer.byEntryStatus ?? {} } : null;
  const [exporting, setExporting] = useState<"changes" | "rows" | null>(null);
  const [closing, setClosing] = useState(false);
  const [rollback, setRollback] = useState<{ busy: boolean; problem: Problem | null } | null>(null);
  const [reverted, setReverted] = useState<Reverted | null>(null);

  /** the upload's heading lines on an export */
  function metaOf(r: Report, more: [string, string][]): [string, string][] {
    const u = r.upload;
    return [["Upload", u.ref], ["What", KIND_WORD[u.kind] ?? u.kind], ["File", u.fileName ?? "—"], ["Reason", u.reason],
      ["Loaded by", `${u.createdByName ?? "—"} (${roleLabel(u.createdOffice)})`], ["State", (STATE[u.state] ?? [u.state])[0]],
      ...(u.state === "REVERTED" ? [["Rolled back", `${when(u.revertedAt)} by ${u.revertedByName ?? "—"}: ${u.revertReason ?? ""}`] as [string, string]] : []), ...more];
  }

  async function exportChanges(r: Report) {
    setExporting("changes");
    notify("Export processing…", "ok", 2500);
    try {
      const u = r.upload;
      const rolled = r.changes.some((c) => c.revertedAt || c.revertNote);
      const headers = ["Change", "Matriculation number", "Course", "Session", "Semester", "Row in the file", "Units was", "Units now", "Code was", "Code now",
        "Title was", "Title now", "Category was", "Category now", "Status was", "Status now", "Level made", "Senate-approved graduate", "When", ...(rolled ? ["Rollback"] : [])];
      const rows = r.changes.map((c) => [changeWord(c.kind), c.matric ?? "", c.courseCode ?? "", c.session ?? "", c.semester ? semesterName(Number(c.semester)) : "",
        c.line ?? "", c.wasUnits, c.nowUnits, c.wasCode ?? "", c.nowCode ?? "", c.wasTitle ?? "", c.nowTitle ?? "", wasCategory(c), nowCategory(c),
        c.wasStatus ?? "", c.nowStatus ?? "", c.level ?? "", c.graduate ? "Yes" : "", when(c.changedAt), ...(rolled ? [revertWords(c)] : [])]);
      downloadBlob(await brandedXlsx("Old portal upload changes", headers, rows, { serial: docSerial("PRU"), meta: metaOf(r, r.changesTotal > r.changes.length
        ? [["Listed", `the first ${r.changes.length.toLocaleString()} of ${r.changesTotal.toLocaleString()} changes`]] : []), sheetName: "Changes" }), `${u.ref} changes.xlsx`);
      notify(`Export completed — ${r.changes.length.toLocaleString()} change${r.changes.length === 1 ? "" : "s"}.`);
    } catch (e) {
      notifyProblem(e as Problem, "The export did not complete");
    } finally { setExporting(null); }
  }

  async function exportRows(r: Report) {
    setExporting("rows");
    notify("Export processing…", "ok", 2500);
    try {
      const headers = ["Row in the file", "Matriculation number", "Code in the file", "Title in the file", "Credit units in the file", "Category", "Matched course",
        "Current title", "Current units", "Match", "Session", "Semester", "Status", "The course on the registration", "Detail", "What to do"];
      const rows = r.rows.map((w) => {
        const f = objectOf<Partial<LegacyLine>>(w.facts);
        return [w.line ?? "", w.matric, f.uploadedCode ?? w.course ?? "", f.uploadedTitle ?? "", f.uploadedUnits ?? "", f.category ?? "", f.matchedCourse ?? "",
          f.currentTitle ?? "", f.currentUnits ?? "", f.match ? (MATCH_WORD[f.match] ?? f.match) : "", w.session, w.semester ? semesterName(Number(w.semester)) : "",
          lineWord(w.status, false), f.entryStatus && f.entryStatus !== w.status ? lineWord(f.entryStatus, false) : "", plainDetail(w.detail), f.action ?? ""];
      });
      downloadBlob(await brandedXlsx("Old portal upload rows not loaded or left as they were", headers, rows, { serial: docSerial("PRU"), meta: metaOf(r, r.rowsTotal > r.rows.length
        ? [["Listed", `the first ${r.rows.length.toLocaleString()} of ${r.rowsTotal.toLocaleString()} rows`]] : []), sheetName: "Rows" }), `${r.upload.ref} rows not loaded.xlsx`);
      notify(`Export completed — ${r.rows.length.toLocaleString()} row${r.rows.length === 1 ? "" : "s"}.`);
    } catch (e) {
      notifyProblem(e as Problem, "The export did not complete");
    } finally { setExporting(null); }
  }

  /** an upload left running closed by the person who opened it: what loaded stands and is in its report */
  async function closeStopped(u: Upload) {
    setClosing(true);
    try {
      const r = await fetch(`${BASE}/${encodeURIComponent(u.id)}/finish`, {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Old portal upload ${u.ref} closed incomplete, stopped part way`) },
        body: JSON.stringify({ complete: false }),
      });
      if (r.ok) {
        notify(`Upload ${u.ref} closed as stopped part way — what loaded stands and is in its report`);
        setTick((t) => t + 1);
      } else {
        const j = await r.json().catch(() => null);
        notifyProblem((j ?? { status: r.status, title: "The upload was not closed" }) as Problem, "The upload was not closed");
      }
    } catch {
      notifyProblem({ status: 0, title: "The upload was not closed", detail: "The connection to the portal dropped." });
    } finally { setClosing(false); }
  }

  /** a confirmed upload rolled back from its ledger with the reason given; what it left as it was is listed */
  async function rollBack(u: Upload, reason: string) {
    setRollback({ busy: true, problem: null });
    try {
      const r = await fetch(`${BASE}/${encodeURIComponent(u.id)}/revert`, {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Old portal upload ${u.ref} rolled back: ${reason}`) },
        body: JSON.stringify({ reason }),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) {
        const p = (j ?? { status: r.status, title: "The upload was not rolled back" }) as Problem;
        setRollback({ busy: false, problem: p });
        notifyProblem(p, "The upload was not rolled back");
        return;
      }
      const a = (j ?? {}) as Partial<Reverted>;
      const done: Reverted = { ref: a.ref ?? u.ref, state: a.state ?? "REVERTED", undone: Number(a.undone ?? 0), left: Number(a.left ?? 0),
        heldDropped: Number(a.heldDropped ?? 0), earlierUndone: Number(a.earlierUndone ?? 0), leftChanges: Array.isArray(a.leftChanges) ? a.leftChanges : [] };
      setReverted(done);
      setRollback(null);
      notify(`Upload ${done.ref} rolled back — ${done.undone.toLocaleString()} change${done.undone === 1 ? "" : "s"} undone${done.left ? `, ${done.left.toLocaleString()} left as ${done.left === 1 ? "it was" : "they were"}` : ""}${done.heldDropped ? `, ${done.heldDropped.toLocaleString()} held result${done.heldDropped === 1 ? "" : "s"} dropped` : ""}${done.earlierUndone ? `; ${earlierWords(done.earlierUndone)}` : ""}`);
      setTick((t) => t + 1);
    } catch {
      const p = { status: 0, title: "The upload was not rolled back", detail: "The connection to the portal dropped; open the report again to see whether it went through." };
      setRollback({ busy: false, problem: p });
      notifyProblem(p);
    }
  }

  if (failed) return (
    <>
      <div className="row" style={{ marginBottom: 8 }}><LinkBtn href="/records/migration/uploads">All uploads</LinkBtn></div>
      <Note kind="bad" title="Unable to load the upload">{failed}</Note>
    </>
  );
  if (!data) return loading ? <Note kind="info" title="Loading the upload">One moment…</Note> : <Note kind="bad" title="No such upload">The upload asked for is not on record.</Note>;
  const u = data.upload;
  const [word, tone] = STATE[u.state] ?? [u.state, "info"];
  const kinds = CHANGE_WORD.filter(([k]) => (data.byKind?.[k] ?? 0) > 0);
  const moved = data.students.filter(cgpaMoved);
  const mine = u.state === "RUNNING" && sameId(viewer?.actorId, u.createdBy);
  const mayRollBack = (u.state === "COMPLETE" || u.state === "INCOMPLETE") && MAY_REVERT.includes(viewer?.office ?? "");
  const rc = objectOf<RevertCounts>(u.revertCounts);
  const rolled = data.changes.some((c) => c.revertedAt || c.revertNote);
  const byCount = (m: Record<string, number>) => Object.entries(m).filter(([, n]) => Number(n) > 0).sort((a, b) => Number(b[1]) - Number(a[1]) || a[0].localeCompare(b[0]));
  const statuses = byCount(data.byStatus);
  const entryStatuses = byCount(data.byEntryStatus);
  const fileRows = statuses.reduce((n, [, v]) => n + Number(v), 0);
  const toneColour = (s: string) => { const t = lineTone(s); return t === "bad" ? "var(--red-ink)" : t === "warn" ? "var(--amber-ink)" : null; };
  return (
    <>
      <div className="row" style={{ marginBottom: 8, gap: 8 }}>
        <LinkBtn href="/records/migration/uploads">All uploads</LinkBtn>
        <LinkBtn href="/records/migration">Migrate from the old portal</LinkBtn>
      </div>
      <Panel title={`Upload ${u.ref}`} right={<Pil kind={tone}>{word}</Pil>}>
        <PBody>
          <KvGrid pairs={[["What", KIND_WORD[u.kind] ?? u.kind], ["File", u.fileName ?? "—"], ["Rows", Number(u.rows ?? 0).toLocaleString()],
            ["Loaded by", `${u.createdByName ?? "—"} · ${roleLabel(u.createdOffice)}`], ["Started", when(u.createdAt)], ["Finished", when(u.finishedAt)],
            ["Reason", u.reason],
            ...(u.state === "REVERTED" ? [["Rolled back", `${when(u.revertedAt)} by ${u.revertedByName ?? "—"}`], ["Why it was rolled back", u.revertReason ?? "—"]] as [string, string][] : [])]} />
          {u.state === "RUNNING" ? (
            <Note kind="info" title="This upload is still running"
                  action={mine ? <Btn kind="ghost" disabled={closing} busy={closing} onClick={() => void closeStopped(u)}>Close as stopped part way</Btn> : undefined}>
              Its batches are going up, or it stopped part way and was not closed; what has loaded stands, and is listed below.
              {mine ? " If it is not going on, close it as stopped part way: what loaded stands, and the upload can then be rolled back if it should not have gone up." : " The officer who opened it closes it."}
            </Note>
          ) : u.state === "INCOMPLETE" ? (
            <Note kind="info" title="This upload stopped part way">What loaded stands, and is listed below; the rest of the file was not loaded under it.</Note>
          ) : u.state === "REVERTED" ? (
            <Note kind="info" title="This upload was rolled back">
              {`${(Number(rc.undone ?? 0)).toLocaleString()} change${Number(rc.undone ?? 0) === 1 ? " was" : "s were"} undone`}
              {Number(rc.left ?? 0) ? `; ${Number(rc.left).toLocaleString()} ${Number(rc.left) === 1 ? "was" : "were"} left as ${Number(rc.left) === 1 ? "it was" : "they were"}, each with why below` : ""}
              {Number(rc.heldDropped ?? 0) ? `; ${heldWords(Number(rc.heldDropped))}` : ""}
              {Number(rc.earlierUndone ?? 0) ? `; ${earlierWords(Number(rc.earlierUndone))}` : ""}.
              {" "}The students and changes below are what the upload did when it went up; each change says whether it was rolled back.
            </Note>
          ) : null}
          {mayRollBack ? (
            <div className="row" style={{ marginTop: 8 }}>
              <Btn kind="secondary" onClick={() => setRollback({ busy: false, problem: null })}>Roll back this upload</Btn>
            </div>
          ) : null}
        </PBody>
      </Panel>
      {reverted ? (
        <Panel title="Rolled back" right={`${reverted.undone.toLocaleString()} undone · ${reverted.left.toLocaleString()} left as they were${reverted.heldDropped ? ` · ${reverted.heldDropped.toLocaleString()} held dropped` : ""}`}>
          <PBody>
            {reverted.left > 0 ? (
              <Note kind="info" title={`${reverted.left.toLocaleString()} change${reverted.left === 1 ? " was" : "s were"} left as on record`}>
                The record has changed there since the upload, or the change is put right elsewhere; each is listed with why.
              </Note>
            ) : (
              <Note kind="ok" title="Every change was undone">
                Nothing this upload put on a student&rsquo;s record is left there; a mark it posted on a course it added stays on its result sheet as history and no longer counts.
              </Note>
            )}
            {reverted.heldDropped > 0 ? (
              <Note kind="info" title={heldWords(reverted.heldDropped)}>
                They never post under a rolled-back upload; the rows are listed below as dropped with the rollback. Where an earlier upload
                still standing held the same row before this one, that upload&rsquo;s result is held again and posts when the student is uploaded.
              </Note>
            ) : null}
            {reverted.earlierUndone > 0 ? (
              <Note kind="info" title={earlierWords(reverted.earlierUndone)}>
                A rolled-back upload could not take them back while this upload&rsquo;s changes stood on them (or they were first results on a course this upload had put on the registration); each upload&rsquo;s report now shows them rolled back, with this upload&rsquo;s reference.
              </Note>
            ) : null}
          </PBody>
          {reverted.leftChanges.length ? (
            <DTable pageSize={25} cols={["Change", "Matriculation number", "Course", "Session|mid", "Semester|mid", "Why it was left"]}
              texts={reverted.leftChanges.map((c) => `${changeWord(c.kind)} ${c.matric ?? ""} ${c.courseCode ?? ""} ${c.note ?? ""}`)}
              rows={reverted.leftChanges.map((c, i) => [changeWord(c.kind), <span key={`m${i}`} className="tnum">{c.matric ?? "—"}</span>,
                <span key={`c${i}`} className="tnum">{c.courseCode ?? "—"}</span>, <span key={`s${i}`} className="tnum">{c.session ?? "—"}</span>,
                c.semester ? semesterName(Number(c.semester)) : "—", <span key={`n${i}`} className="sub2">{c.note ?? "—"}</span>])} />
          ) : null}
        </Panel>
      ) : null}
      <Tiles cls="grid--5" items={[
        ["Changes", data.changesTotal.toLocaleString(), null, "to students' records, each with what was there before"],
        ["Students", data.students.length.toLocaleString(), null, `${moved.length.toLocaleString()} whose CGPA moved`],
        ["Senate-approved graduates", data.graduates.length.toLocaleString(), data.graduates.length ? "var(--amber-ink)" : null, "approved CGPA kept — for the Registry"],
        ...kinds.map(([k, label]) => [label, Number(data.byKind[k]).toLocaleString(), null, ""] as [string, string, null, string]),
      ]} />
      <Panel title="Senate-approved graduates" right="for the Registry">
        <PBody>
          {data.graduates.length ? (
            <Note kind="info" title="Their approved CGPA and class of degree stay as approved">
              The upload corrected their courses as the file had them; the CGPA the Senate approved is not changed by it. The CGPA from the
              record now is shown beside it for the Registry to consider.
            </Note>
          ) : <Note kind="ok" title="None">No Senate-approved graduate&rsquo;s record was changed by this upload.</Note>}
        </PBody>
        {data.graduates.length ? (
          <DTable pageSize={25} cols={["Matriculation number", "Name", "Programme", "CGPA before|mid", "CGPA from the record now|mid", "Changes|num"]}
            texts={data.graduates.map((s) => `${s.matric} ${s.name} ${s.programme ?? ""}`)}
            rows={data.graduates.map((s, i) => [<span key={`m${i}`} className="tnum">{s.matric}</span>, s.name, s.programme ?? "—",
              <span key={`b${i}`} className="tnum">{figure(s.cgpaBefore)}</span>, <b key={`a${i}`} className="tnum">{figure(cgpaAfter(s))}</b>, Number(s.changes ?? 0).toLocaleString()])} />
        ) : null}
      </Panel>
      <Panel title="Students" right={`${data.students.length.toLocaleString()} changed · graduates first`}>
        {data.students.length ? (
          <DTable pageSize={25} cols={["Matriculation number", "Name", "Programme", "CGPA|mid", "Units counted|mid", "Changes|num"]}
            texts={data.students.map((s) => `${s.matric} ${s.name} ${s.programme ?? ""}`)}
            rows={data.students.map((s, i) => [<span key={`m${i}`} className="tnum">{s.matric}</span>,
              <span key={`n${i}`}>{s.name}{s.graduate ? <span style={{ display: "block" }}><Pil kind="warn">Senate-approved graduate</Pil></span> : null}</span>,
              s.programme ?? "—",
              <span key={`c${i}`} className="tnum">{cgpaMoved(s) ? <>{figure(s.cgpaBefore)} → <b>{figure(s.cgpaAfter)}</b></> : <>{figure(s.cgpaBefore)} <span className="sub2">unchanged</span></>}</span>,
              <span key={`u${i}`} className="tnum">{s.tcrBefore ?? "—"} → {s.tcrAfter ?? s.tcrBefore ?? "—"}</span>, Number(s.changes ?? 0).toLocaleString()])} />
        ) : <PBody><span className="sub2">No student&rsquo;s record was changed.</span></PBody>}
      </Panel>
      <Panel title="Changes" right={<span className="row row--inline" style={{ gap: 8 }}>
        <span className="sub2">{data.changesTotal > data.changes.length ? `the first ${data.changes.length.toLocaleString()} of ${data.changesTotal.toLocaleString()}` : `${data.changes.length.toLocaleString()}`}</span>
        <Btn kind="ghost" disabled={exporting !== null || !data.changes.length} busy={exporting === "changes"} onClick={() => void exportChanges(data)}>Excel</Btn>
      </span>}>
        {data.changesTotal > data.changes.length ? (
          <PBody><Note kind="info" title={`The first ${data.changes.length.toLocaleString()} changes are listed`}>The upload made {data.changesTotal.toLocaleString()} changes; the list and its Excel show them in the order they were made, up to the first {data.changes.length.toLocaleString()}.</Note></PBody>
        ) : null}
        {data.changes.length ? (
          <DTable pageSize={25} cols={["#|num", "Change", "Matriculation number", "Course", "Session|mid", "Semester|mid", "Row|num", "Was", "Now", ...(rolled ? ["Rollback"] : [])]}
            texts={data.changes.map((c) => `${changeWord(c.kind)} ${c.matric ?? ""} ${c.courseCode ?? ""} ${c.nowCode ?? ""} ${c.nowTitle ?? ""} ${c.session ?? ""} ${c.revertNote ?? ""}`)}
            rows={data.changes.map((c, i) => {
              const [was, now] = wasNow(c);
              return [c.seq, <span key={`k${i}`}>{changeWord(c.kind)}{c.graduate ? <span style={{ display: "block" }}><Pil kind="warn">Graduate</Pil></span> : null}</span>,
                <span key={`m${i}`} className="tnum">{c.matric ?? "—"}</span>, <span key={`c${i}`} className="tnum">{c.courseCode ?? "—"}</span>,
                <span key={`s${i}`} className="tnum">{c.session ?? "—"}</span>, c.semester ? semesterName(Number(c.semester)) : "—", c.line ?? "—",
                <span key={`w${i}`} className="sub2">{was}</span>, <span key={`n${i}`}>{now}</span>,
                ...(rolled ? [c.revertedAt
                  ? <span key={`r${i}`}><Pil kind="grey">Rolled back</Pil><span className="sub2" style={{ display: "block" }}>{when(c.revertedAt)}</span>{c.revertNote ? <span className="sub2" style={{ display: "block" }}>{c.revertNote}</span> : null}</span>
                  : c.revertNote ? <span key={`r${i}`}><Pil kind="warn">Left as it was</Pil><span className="sub2" style={{ display: "block" }}>{c.revertNote}</span></span> : "—"] : [])];
            })} />
        ) : <PBody><span className="sub2">No change was made.</span></PBody>}
      </Panel>
      <Panel title="Rows not loaded or left as they were" right={<span className="row row--inline" style={{ gap: 8 }}>
        <span className="sub2">{data.rowsTotal > data.rows.length ? `the first ${data.rows.length.toLocaleString()} of ${data.rowsTotal.toLocaleString()}` : `${data.rows.length.toLocaleString()}`}</span>
        <Btn kind="ghost" disabled={exporting !== null || !data.rows.length} busy={exporting === "rows"} onClick={() => void exportRows(data)}>Excel</Btn>
      </span>}>
        <PBody>
          {statuses.length ? (
            <>
              <div className="eyebrow">{`The file's ${fileRows.toLocaleString()} row${fileRows === 1 ? "" : "s"} under this upload, by what became of each`}</div>
              <Tiles cls="grid--5" items={statuses.map(([s, n]) => [lineWord(s, false), Number(n).toLocaleString(), toneColour(s), ""] as [string, string, string | null, string])} />
              {entryStatuses.length ? (
                <>
                  <div className="eyebrow" style={{ marginTop: 8 }}>The course on the registration, where the row&rsquo;s status says only its result</div>
                  <Tiles cls="grid--5" items={entryStatuses.map(([s, n]) => [lineWord(s, false), Number(n).toLocaleString(), toneColour(s), ""] as [string, string, string | null, string])} />
                </>
              ) : null}
            </>
          ) : <span className="sub2">No row of the file is recorded under this upload yet.</span>}
          {data.rowsTotal > data.rows.length ? (
            <Note kind="info" title={`The first ${data.rows.length.toLocaleString()} rows are listed`}>{data.rowsTotal.toLocaleString()} rows did not load or were left as they were; the list and its Excel show them by session, semester and row, up to the first {data.rows.length.toLocaleString()}.</Note>
          ) : null}
          {statuses.length && !data.rows.length ? <Note kind="ok" title="Every row loaded as the file had it">No row was refused, set aside or left as it was on record.</Note> : null}
        </PBody>
        {data.rows.length ? (
          <DTable pageSize={25} cols={["Row|num", "Matriculation number", "Course in the file", "Session|mid", "Semester|mid", "Status", "On record", "Detail"]}
            texts={data.rows.map((w) => { const f = objectOf<Partial<LegacyLine>>(w.facts); return `${w.matric} ${w.course} ${f.uploadedCode ?? ""} ${f.uploadedTitle ?? ""} ${lineWord(w.status, false)} ${plainDetail(w.detail)}`; })}
            rows={data.rows.map((w, i) => {
              const f = objectOf<Partial<LegacyLine>>(w.facts);
              const entry = f.entryStatus && f.entryStatus !== w.status ? f.entryStatus : null;
              return [<span key={`r${i}`} className="tnum sub2">{w.line ?? "—"}</span>, <span key={`m${i}`} className="tnum">{w.matric}</span>,
                <span key={`c${i}`}><span className="tnum">{f.uploadedCode || w.course}</span>{f.uploadedTitle || f.uploadedUnits || f.category
                  ? <span className="sub2" style={{ display: "block" }}>{[f.uploadedTitle, f.uploadedUnits ? `${f.uploadedUnits} units` : "", f.category].filter(Boolean).join(" · ")}</span> : null}</span>,
                <span key={`s${i}`} className="tnum">{w.session}</span>, w.semester ? semesterName(Number(w.semester)) : "—",
                <span key={`p${i}`} style={{ display: "grid", gap: 4 }}><Pil kind={lineTone(w.status)}>{lineWord(w.status, false)}</Pil>
                  {entry ? <Pil kind={lineTone(entry)}>{lineWord(entry, false)}</Pil> : null}</span>,
                <span key={`o${i}`} className="sub2">{f.matchedCourse ? <span className="tnum">{f.matchedCourse}</span> : "—"}
                  {f.currentTitle || f.currentUnits != null ? <span style={{ display: "block" }}>{[f.currentTitle, f.currentUnits != null ? `${f.currentUnits} units` : ""].filter(Boolean).join(" · ")}</span> : null}
                  {f.match ? <span style={{ display: "block" }}><Pil kind={f.match === "CODE_ONLY_NEW_TITLE" || f.match === "AMBIGUOUS" ? "bad" : f.match === "CODE_AND_TITLE" ? "ok" : "warn"}>{MATCH_WORD[f.match] ?? f.match}</Pil></span> : null}</span>,
                <span key={`d${i}`} className="sub2">{plainDetail(w.detail)}{f.action ? <b style={{ display: "block" }}>{f.action}</b> : null}</span>];
            })} />
        ) : null}
      </Panel>
      {rollback ? (
        <ConfirmRollback upload={u} changes={data.changesTotal} busy={rollback.busy} problem={rollback.problem}
          onCancel={() => { if (!rollback.busy) setRollback(null); }} onConfirm={(reason) => void rollBack(u, reason)} />
      ) : null}
    </>
  );
}
