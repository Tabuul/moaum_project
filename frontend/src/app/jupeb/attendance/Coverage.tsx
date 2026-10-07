"use client";

/**
 * The syllabus covered (V355). In a lecture's register, the topics of its course the lecture covered — ticked by its instructor (or
 * the office), with when an earlier lecture of the session first covered each. And each course's coverage in the session's
 * lectures, for the office before the Board's monitoring of lectures, and for a lecturer's own subjects. The server decides who
 * ticks and what each sees.
 */
import { useEffect, useMemo, useState } from "react";
import { brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, Note, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { day, jcall } from "@/lib/jupeb";

const BASE = "/api/v1/attendance/jupeb";
interface Topic { topic_id: string; unit_id: string; unit_code: string; unit_title: string; ord: number; sn: string | null; topic: string | null; sub_topic: string | null; here: boolean; first_on: string | null }

/** the topics this lecture covered */
export function RegisterTopics({ registerId, heldOn, editable }: { registerId: string; heldOn: string; editable: boolean }) {
  const [rows, setRows] = useState<Topic[] | null>(null);
  const [ticked, setTicked] = useState<Set<string>>(new Set());
  const [busy, setBusy] = useState(false);
  useEffect(() => {
    let live = true;
    void jcall<Topic[]>(`${BASE}/registers/${registerId}/topics`).then((r) => { if (live && r.ok) { setRows(r.data); setTicked(new Set(r.data.filter((x) => x.here).map((x) => x.topic_id))); } });
    return () => { live = false; };
  }, [registerId]);
  const dirty = useMemo(() => !!rows && (rows.some((x) => x.here !== ticked.has(x.topic_id))), [rows, ticked]);
  if (!rows || !rows.length) return null;
  async function save() {
    setBusy(true);
    try {
      const r = await jcall<Topic[]>(`${BASE}/registers/${registerId}/topics`, "PUT", { topicIds: [...ticked] }, "Topics covered in the lecture");
      if (!r.ok) { notifyProblem(r.problem); return; }
      setRows(r.data); setTicked(new Set(r.data.filter((x) => x.here).map((x) => x.topic_id))); notify("The topics covered are saved.");
    } finally { setBusy(false); }
  }
  return (
    <Panel title="Topics covered in this lecture" right={<span className="row"><Pil kind="info">{`${ticked.size} ticked`}</Pil>
      {editable ? <Btn kind="primary" disabled={busy || !dirty} onClick={() => void save()}>{busy ? "Saving…" : "Save the topics"}</Btn> : null}</span>}>
      <PBody>
        <p className="sub2">Tick what this lecture covered of the course&rsquo;s syllabus. It counts to the course&rsquo;s coverage, which the JUPEB Office follows before the Board&rsquo;s monitoring of lectures.</p>
        <DTable noPrint pageSize={0} cols={["|mid", "Course", "Topic", "Sub-topic", "Earlier"]} rows={rows.map((x, i) => {
          const topic = x.topic ?? "";
          /* a topic's name heads only its first sub-topic */
          const before = rows.slice(0, i).reverse().find((y) => y.topic)?.topic ?? "";
          const show = topic && topic !== before ? `${x.sn ? `${x.sn}. ` : ""}${topic}` : "";
          const earlier = x.first_on && !(x.here && x.first_on === heldOn) ? `First ${day(x.first_on)}` : "—";
          return [<input key="t" type="checkbox" aria-label={`Covered: ${x.sub_topic ?? x.topic ?? ""}`} disabled={!editable} checked={ticked.has(x.topic_id)}
            onChange={() => setTicked((s) => { const n = new Set(s); if (n.has(x.topic_id)) n.delete(x.topic_id); else n.add(x.topic_id); return n; })} />,
            x.unit_code, show ? <b key="h">{show}</b> : "", x.sub_topic ?? "", earlier];
        })} />
      </PBody>
    </Panel>
  );
}

interface CoverageRow { unit_id: string; subject_code: string; subject_title: string; code: string; title: string; topics: number; covered: number; last_on: string | null; lectures: number; instructors: string | null }
interface CoverageData { session: string; semester: number; monitoring: { starts_on: string; ends_on: string | null; title: string } | null; rows: CoverageRow[] }

/** each course's coverage of its syllabus in the session's lectures */
export function CoveragePanel({ session }: { session: string }) {
  const [semester, setSemester] = useState("");
  const [d, setD] = useState<CoverageData | null>(null);
  useEffect(() => {
    let live = true;
    void jcall<CoverageData>(`${BASE}/coverage?session=${encodeURIComponent(session)}${semester ? `&semester=${semester}` : ""}`).then((r) => {
      if (!live) return;
      if (r.ok) { setD(r.data); if (!semester) setSemester(String(r.data.semester)); } else notifyProblem(r.problem);
    });
    return () => { live = false; };
  }, [session, semester]);
  if (!d) return <p className="sub2">Loading…</p>;
  const pct = (r: CoverageRow) => (r.topics ? Math.round((100 * r.covered) / r.topics) : 0);
  async function excel() {
    downloadBlob(await brandedXlsx(`JUPEB syllabus coverage — ${d!.session}, semester ${d!.semester}`, ["Subject", "Course", "Title", "Topics", "Covered", "Coverage %", "Lectures recorded", "Last covered", "Lecturers"],
      d!.rows.map((r) => [r.subject_title, r.code, r.title, r.topics, r.covered, pct(r), r.lectures, r.last_on ?? "", r.instructors ?? ""]), { sheetName: "Coverage", serial: docSerial("JUPEBCOV") }),
      `jupeb-coverage-${d!.session.replace("/", "-")}-sem${d!.semester}.xlsx`);
  }
  return (
    <Panel title="Syllabus coverage" right={<span className="row">
      <select className="ctl" style={{ width: 170 }} aria-label="Semester" value={semester} onChange={(e) => setSemester(e.target.value)}><option value="1">First semester</option><option value="2">Second semester</option></select>
      <Btn kind="ghost" disabled={!d.rows.length} onClick={() => void excel()}>Excel</Btn></span>}>
      <PBody>
        {d.monitoring ? <Note kind="info" title={`The Board's monitoring of lectures: ${day(d.monitoring.starts_on)}${d.monitoring.ends_on ? ` – ${day(d.monitoring.ends_on)}` : ""}`}>The coverage below is what the lectures recorded so far have ticked of each course&rsquo;s syllabus.</Note> : null}
        {!d.rows.length ? <p className="sub2">No course with its syllabus on the record for this semester.</p> : (
          <DTable pageSize={50} cols={["Course", "Subject", "Covered", "Coverage|num", "Lectures|num", "Last covered", "Lecturers"]} texts={d.rows.map((r) => `${r.code} ${r.title} ${r.subject_title}`)}
            rows={d.rows.map((r) => [<span key="c"><b>{r.code}</b> {r.title}</span>, r.subject_title, `${r.covered} of ${r.topics}`,
              <Pil key="p" kind={pct(r) >= 75 ? "ok" : pct(r) >= 40 ? "info" : "warn"}>{`${pct(r)}%`}</Pil>, r.lectures, r.last_on ? day(r.last_on) : "—", r.instructors ?? "—"])} />
        )}
      </PBody>
    </Panel>
  );
}
