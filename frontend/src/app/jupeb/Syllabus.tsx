"use client";

/**
 * The JUPEB syllabus (V353), as the Board's 2027–2031 edition has it: a subject's course units semester by semester, and a
 * unit's syllabus — its objectives, its subject's general objectives and the topics in the order printed (a blank S/N or
 * topic continues the one above). The office, the student and the lecturer read the same view; the server decides whose
 * units each may open.
 */
import { useEffect, useState } from "react";
import { brandedPrint, docSerial } from "@/lib/exportbrand";
import { notifyProblem } from "@/components/proto/Toast";
import { Btn, KvGrid, Note } from "@/components/proto/ui";
import { Modal } from "@/components/proto/blocks";
import { DTable } from "@/components/proto/DTable";
import { jcall } from "@/lib/jupeb";

/** a course unit as the lists give it: units_for rows (unit_id) or the office's syllabus (id) */
export interface UnitRow {
  id?: string; unit_id?: string; code: string; title: string; semester: number | null; credit_units?: number | null; topics?: number;
  subject_id?: string; subject_code?: string; subject_title?: string; board_subject_id?: string | null; board_code?: string | null; board_title?: string | null;
  prefix?: string | null; either?: boolean; chosen?: boolean;
}
interface Topic { ord: number; sn: string | null; topic: string | null; sub_topic: string | null; details: string | null; source_page: number | null }
interface UnitSyllabus {
  id: string; code: string; title: string; semester: number | null; credit_units: number | null; objectives: string | null; source_page: number | null;
  subject_code: string; subject_title: string; board_code: string | null; board_title: string | null; prefix: string | null; subject_objectives: string | null;
  syllabus: string | null; topics: Topic[];
}

export const SEMESTER = (n: number | null | undefined) => (n === 1 ? "First semester" : n === 2 ? "Second semester" : "Semester not set");
const unitId = (u: UnitRow) => u.unit_id ?? u.id ?? "";
const pre: React.CSSProperties = { whiteSpace: "pre-line" };

/** the units of one or more subjects, one table a semester; a unit with topics opens its syllabus */
export function UnitsBySemester({ units, onOpen, showSubject = false }: { units: UnitRow[]; onOpen?: (u: UnitRow) => void; showSubject?: boolean }) {
  if (!units.length) return <Note kind="info" title="No courses listed">The Board&rsquo;s course units are not listed for this subject.</Note>;
  const semesters = [...new Set(units.map((u) => u.semester ?? 0))].sort((a, b) => (a || 9) - (b || 9));
  return (
    <>
      {semesters.map((s) => {
        const rows = units.filter((u) => (u.semester ?? 0) === s);
        return (
          <div key={s} className="mt-2">
            <div className="eyebrow">{SEMESTER(s || null)}</div>
            <DTable noPrint pageSize={0} cols={[...(showSubject ? ["Subject"] : []), "Code", "Course", "Units|num", ...(onOpen ? ["|mid"] : [])]}
              rows={rows.map((u) => [
                ...(showSubject ? [u.either && !u.chosen ? `${u.subject_title ?? ""} — ${u.board_title ?? ""} (if taken)` : u.board_title ?? u.subject_title ?? ""] : []),
                <b key="c">{u.code}</b>, u.title, u.credit_units ?? "—",
                ...(onOpen ? [u.topics ? <Btn key="o" kind="ghost" onClick={() => onOpen(u)}>Syllabus</Btn> : "—"] : [])])} />
          </div>
        );
      })}
    </>
  );
}

/** a unit's syllabus, read from the URL the reader may use (the office's, the student's or the lecturer's) */
export function SyllabusModal({ url, onClose }: { url: string; onClose: () => void }) {
  const [s, setS] = useState<UnitSyllabus | null>(null);
  const [failed, setFailed] = useState(false);
  useEffect(() => {
    let live = true;
    void jcall<UnitSyllabus>(url).then((r) => { if (!live) return; if (r.ok) setS(r.data); else { notifyProblem(r.problem); setFailed(true); } });
    return () => { live = false; };
  }, [url]);
  function print() {
    if (!s) return;
    brandedPrint(`${s.code}: ${s.title}`, `${s.board_title ?? s.subject_title}${s.prefix ? ` (${s.board_code})` : ""} · ${SEMESTER(s.semester)} · ${s.syllabus ?? "JUPEB syllabus"}`,
      ["S/N", "Topic", "Sub-topic", "Details and notes"], s.topics.map((t) => [t.sn ?? "", t.topic ?? "", t.sub_topic ?? "", t.details ?? ""]), docSerial("JUPEBSYL"));
  }
  return (
    <Modal wide title={s ? `${s.code}: ${s.title}` : "Course syllabus"} onClose={onClose}
      foot={<><Btn kind="ghost" onClick={onClose}>Close</Btn>{s?.topics.length ? <Btn kind="secondary" onClick={print}>Print / PDF</Btn> : null}</>}>
      {failed ? <Note kind="bad" title="The syllabus could not be read">Close this and try again.</Note> : !s ? <p className="sub2">Loading…</p> : (
        <>
          <KvGrid pairs={[["Subject", `${s.board_title ?? s.subject_title}${s.board_code ? ` (${s.board_code})` : ""}`], ["Semester", SEMESTER(s.semester)],
            ["Credit units", s.credit_units ?? "—"], ["Syllabus", `${s.syllabus ?? "—"}${s.source_page ? `, page ${s.source_page}` : ""}`]]} />
          {s.objectives ? <><div className="eyebrow mt-3">Objectives of the course</div><p style={pre}>{s.objectives}</p></> : null}
          {s.topics.length ? (
            <>
              <div className="eyebrow mt-3">{`Course content (${s.topics.length} row${s.topics.length === 1 ? "" : "s"})`}</div>
              <DTable noPrint pageSize={0} cols={["S/N|mid", "Topic", "Sub-topic", "Details and notes"]}
                rows={s.topics.map((t) => [t.sn ?? "", t.topic ? <b key="t">{t.topic}</b> : "", t.sub_topic ?? "", <span key="d" style={pre}>{t.details ?? ""}</span>])} />
            </>
          ) : <Note kind="info" title="No topics listed">The syllabus content of this course is not on the record.</Note>}
          {s.subject_objectives ? <details className="mt-3"><summary className="b600">{`General objectives of ${s.board_title ?? s.subject_title}`}</summary><p style={pre}>{s.subject_objectives}</p></details> : null}
        </>
      )}
    </Modal>
  );
}

export { unitId };
