"use client";

/** one course space from the roll's side: the material, counted when read; the assignments, submitted once (V035). */
import { useState } from "react";
import Link from "next/link";
import { KINDS, fileBase64, size, type Assignment, type Space } from "@/lib/lms";
import { Btn, Note, Panel, PBody, Pil, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { useAct, when } from "../../common";

export function SpaceScreen({ s }: { s: Space }) {
  const { act, busy, problem } = useAct();
  const [open, setOpen] = useState<Assignment | null>(null);
  const [text, setText] = useState("");
  const [file, setFile] = useState<File | null>(null);
  const [said, setSaid] = useState<string | null>(null);
  const [now] = useState(() => Date.now());
  const read = s.materials.filter((m) => m.read_by_me).length;

  async function submit() {
    if (!open) return;
    const body: Record<string, unknown> = { text: text || null };
    if (file) {
      body.filename = file.name;
      body.contentType = file.type || "application/octet-stream";
      body.contentBase64 = await fileBase64(file);
    }
    const r = await act("submit", "POST", `/me/courses/assignments/${open.id}/submit`, body, `${s.course_code}: ${open.title} submitted`);
    if (r) { setOpen(null); setText(""); setFile(null); setSaid(`${open.title} submitted`); }
  }

  return (
    <>
      <Tiles items={[
        ["Course", s.course_code, null, `${s.title} · ${s.units} units`],
        ["Lecturer", s.lecturer ?? "Not allocated", null, `${s.enrolled} on the roll`],
        ["Material read", `${read} of ${s.materials.length}`, null, "Counted when you open it"],
        ["Assignments", String(s.assignments.length), s.assignments.some((a) => !a.my_submission_id && now < new Date(a.closes_at).getTime()) ? "var(--red-ink)" : null, `${s.assignments.filter((a) => a.my_submission_id).length} submitted`],
      ]} />
      {problem ? <ProblemNotice problem={problem} /> : null}
      {said ? <Note kind="ok" title={said}>On the record.</Note> : null}
      <Panel title="Materials" right={s.materials.length ? `${s.materials.length} published` : "Nothing published yet"}>
        {s.materials.length ? (
          <DTable cols={["Week|mid", "Material", "Kind", "Size|num", "|num"]} rows={s.materials.map((m) => [
            <span className="tnum" key="w">{m.week ?? "—"}</span>,
            <Two key="t" a={m.title} b={m.description ?? ""} />,
            <span className="sub2" key="k">{KINDS.find((k) => k[0] === m.kind)?.[1] ?? m.kind}</span>,
            <span className="tnum sub2" key="s">{m.filename ? size(m.bytes) : "Link"}</span>,
            m.filename ? <a key="d" className="btn btn--ghost btn--sm" href={`/api/bff/api/v1/me/courses/materials/${m.id}/content`} target="_blank" rel="noreferrer">{m.read_by_me ? "Open again" : "Open"}</a>
              : <a key="d" className="btn btn--ghost btn--sm" href={m.link ?? "#"} target="_blank" rel="noreferrer noopener" onClick={() => void act(`read-${m.id}`, "POST", `/me/courses/materials/${m.id}/read`, {}, "Material opened")}>{m.read_by_me ? "Open again" : "Open link"}</a>,
          ])} />
        ) : <PBody><div className="sub2">The lecturer has published nothing yet. Material appears here the moment it is published, and only to the students on the roll.</div></PBody>}
      </Panel>
      <div id="assignments" />
      <Panel title="Assignments" right={s.assignments.length ? `${s.assignments.length}` : "none set"}>
        {s.assignments.length ? (
          <DTable cols={["Assignment", "Closes", "Weight|mid", "Your submission", "|num"]} rows={s.assignments.map((a) => {
            const closes = new Date(a.closes_at).getTime();
            const lateUntil = closes + a.late_hours * 36e5;
            const openNow = now >= new Date(a.opens_at).getTime() && now <= lateUntil && a.my_mark === null;
            return [
              <Two key="t" a={a.title} b={`${a.kind.charAt(0) + a.kind.slice(1).toLowerCase()}${a.brief ? ` · ${a.brief}` : ""}`} />,
              <span className="tnum sub2" key="c">{when(a.closes_at)}{now > closes && now <= lateUntil ? ` · late window, −${a.late_penalty}%` : ""}</span>,
              <span className="tnum" key="w">{a.weight}%</span>,
              a.my_submission_id ? <span key="s">{a.my_mark !== null ? <Pil kind="ok">{a.my_mark} of {a.out_of}</Pil> : <Pil kind="info">Submitted{a.my_late ? " late" : ""}</Pil>}{a.my_feedback ? <div className="sub2">{a.my_feedback}</div> : null}</span> : now > lateUntil ? <Pil kind="bad" key="s">Not submitted — closed</Pil> : <span className="sub2" key="s">Not yet</span>,
              openNow ? <Btn kind={a.my_submission_id ? "ghost" : "primary"} key="o" onClick={() => { setOpen(a); setText(a.my_text ?? ""); setFile(null); }}>{a.my_submission_id ? "Replace" : "Submit"}</Btn> : <span className="sub2" key="o">—</span>,
            ];
          })} />
        ) : <PBody><div className="sub2">No assignment set.</div></PBody>}
      </Panel>
      <Note kind="info" title="A course space is built from the approved registrations">You see this space because your registration for {s.course_code} was approved. Every read of the material is counted, and what you submit goes to the lecturer under your name. <Link href="/student/courses">All courses</Link>.</Note>
      {open ? (
        <Modal title={open.title} sub={`${s.course_code} · closes ${when(open.closes_at)} · ${open.weight}% of continuous assessment`} onClose={() => setOpen(null)}
          foot={<><Btn kind="ghost" onClick={() => setOpen(null)}>Cancel</Btn><span className="grow" /><Btn kind="go" disabled={busy !== null || (!text.trim() && !file)} onClick={() => void submit()}>{busy ? "Submitting…" : "Submit"}</Btn></>}>
          {open.brief ? <p className="m-0 mb-2" style={{ lineHeight: 1.6 }}>{open.brief}</p> : null}
          <Field id="sb-text" label="Your answer" hint="Text, a file, or both. A marked submission is not replaced."><textarea id="sb-text" className="ctl" rows={6} value={text} onChange={(e) => setText(e.target.value)} /></Field>
          <Field id="sb-file" label="File" hint="Up to 5 MB."><input id="sb-file" type="file" onChange={(e) => setFile(e.target.files?.[0] ?? null)} /></Field>
        </Modal>
      ) : null}
    </>
  );
}
