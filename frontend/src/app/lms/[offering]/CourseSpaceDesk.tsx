"use client";

/** tLms and rUpload — proto/part12, part17: the space, the upload, the assignments, the gradebook promoted into the score sheet, the students at risk. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { KINDS, fileBase64, size, type Desk, type Submission } from "@/lib/lms";
import { Btn, Ico, Note, Panel, PBody, Pil, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal, day } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";

export function CourseSpaceDesk({ d, upload }: { d: Desk; upload: boolean }) {
  const router = useRouter();
  const [problem, setProblem] = useState<Problem | null>(null);
  const [busy, setBusy] = useState(false);
  const [said, setSaid] = useState<string | null>(null);
  const [m, setM] = useState({ title: "", week: "", kind: "NOTES", description: "", link: "", publish: true });
  const [file, setFile] = useState<File | null>(null);
  const [a, setA] = useState({ title: "", brief: "", kind: "INDIVIDUAL", closesAt: "", weight: "10", outOf: "100", lateHours: "48", latePenalty: "10" });
  const [marking, setMarking] = useState<{ assignment: string; title: string; rows: Submission[] } | null>(null);
  const [marks, setMarks] = useState<Record<string, { mark: string; feedback: string }>>({});
  const [now] = useState(() => Date.now());
  const never = d.engagement.filter((e) => e.materials_read === 0 && !e.last_read).length;
  const open = d.assignments.filter((x) => now >= new Date(x.opens_at).getTime() && now <= new Date(x.closes_at).getTime());

  async function send(path: string, body: unknown, reason: string): Promise<Record<string, unknown> | null> {
    setBusy(true);
    setProblem(null);
    try {
      const r = await fetch(`/api/bff/api/v1/lms/offerings/${d.offering_id}${path}`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body ?? {}) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j ?? { status: r.status, title: r.statusText }); notifyProblem(j ?? { status: r.status, title: r.statusText }); return null; }
      notify(reason);
      router.refresh();
      return j;
    } finally {
      setBusy(false);
    }
  }

  async function publishMaterial() {
    const body: Record<string, unknown> = { title: m.title, week: m.week ? Number(m.week) : null, kind: m.kind, description: m.description || null, link: m.link || null, publish: m.publish };
    if (file) {
      if (file.size > 5 * 1024 * 1024) { setProblem({ status: 422, title: "The file is larger than 5 MB", detail: "Publish it by address and link it here instead." }); notifyProblem({ status: 422, title: "The file is larger than 5 MB", detail: "Publish it by address and link it here instead." }); return; }
      body.filename = file.name;
      body.contentType = file.type || "application/octet-stream";
      body.contentBase64 = await fileBase64(file);
    }
    const j = await send("/materials", body, `${d.course_code}: ${m.title} ${m.publish ? "published" : "saved as a draft"}`);
    if (j) { setSaid(`${m.title} ${m.publish ? "published to the space" : "saved as a draft"}`); setM({ ...m, title: "", description: "", link: "" }); setFile(null); }
  }

  const uploadPanel = (
    <Panel title="Upload course material" right={`${d.course_code} — ${d.title}`}>
      <PBody>
        <Field id="um-title" label="Title"><input id="um-title" className="ctl" value={m.title} onChange={(e) => setM({ ...m, title: e.target.value })} placeholder="Week 5 — Dynamic programming" autoComplete="off" /></Field>
        <div className="grid grid--2">
          <Field id="um-week" label="Week"><input id="um-week" className="ctl tnum" value={m.week} onChange={(e) => setM({ ...m, week: e.target.value.replace(/[^0-9]/g, "") })} /></Field>
          <Field id="um-kind" label="Kind"><select id="um-kind" className="ctl" value={m.kind} onChange={(e) => setM({ ...m, kind: e.target.value })}>{KINDS.map(([k, l]) => <option key={k} value={k}>{l}</option>)}</select></Field>
        </div>
        <Field id="um-desc" label="Description shown to students"><input id="um-desc" className="ctl" value={m.description} onChange={(e) => setM({ ...m, description: e.target.value })} autoComplete="off" /></Field>
        <div style={{ border: "2px dashed var(--field)", borderRadius: "var(--r-md)", padding: "var(--s-6)", textAlign: "center", background: "var(--bg)" }}>
          <Ico name="box" size={26} stroke="var(--faint)" w={1.7} />
          <div className="b600 mt-2">{file ? file.name : "Choose a file"}</div>
          <div className="sub2">PDF, slides, documents, images, audio or video · up to 5 MB here; larger material is linked by address below</div>
          <div className="mt-3"><input type="file" onChange={(e) => setFile(e.target.files?.[0] ?? null)} /></div>
          {file ? <div className="sub2 tnum mt-2">{file.name} · {size(file.size)}</div> : null}
        </div>
        <Field id="um-link" label="Or an address" hint="A video or a large file published elsewhere."><input id="um-link" className="ctl" value={m.link} onChange={(e) => setM({ ...m, link: e.target.value })} placeholder="https://…" autoComplete="off" /></Field>
        <label className="row row--top ink-muted" style={{ fontSize: 13.5 }}><input type="checkbox" className="chk" checked={m.publish} onChange={(e) => setM({ ...m, publish: e.target.checked })} /><span>Publish to the {d.enrolled} registered students now; unticked, it is saved as a draft.</span></label>
        <div className="row"><Btn kind="primary" disabled={busy || !m.title.trim() || (!file && !m.link.trim())} onClick={() => void publishMaterial()}>{m.publish ? "Publish to the course space" : "Save as a draft"}</Btn></div>
      </PBody>
    </Panel>
  );

  return (
    <>
      <Panel title={`${d.course_code} — course space`} right={`${d.enrolled} students enrolled automatically from approved registrations`}>
        <PBody>
          <Tiles items={[
            ["Materials published", String(d.materials.filter((x) => x.published_at).length), null, d.materials.some((x) => !x.published_at) ? `${d.materials.filter((x) => !x.published_at).length} draft${d.materials.filter((x) => !x.published_at).length === 1 ? "" : "s"}` : "No draft"],
            ["Assignments", String(d.assignments.length), null, `${open.length} open`],
            ["Submissions", String(d.assignments.reduce((n, x) => n + x.submitted, 0)), null, `of ${d.assignments.length * d.enrolled} possible`],
            ["Never opened the space", String(never), never ? "var(--red-ink)" : null, "Since material was published"],
          ]} />
        </PBody>
      </Panel>
      {problem ? <ProblemNotice problem={problem} /> : null}
      {said ? <Note kind="ok" title={said}>On the record, in your name.</Note> : null}
      {upload ? uploadPanel : null}
      <Panel title="Published material" right={`${d.materials.length} item${d.materials.length === 1 ? "" : "s"}`}>
        {d.materials.length ? (
          <DTable cols={["Item", "Week|mid", "Size|mid", "Read by|mid", "Published|mid", "Action|num"]} rows={d.materials.map((x) => [
            <Two key="t" a={x.title} b={`${KINDS.find((k) => k[0] === x.kind)?.[1] ?? x.kind}${x.description ? ` · ${x.description}` : ""}`} />,
            <span className="tnum" key="w">{x.week ?? "—"}</span>, <span className="tnum" key="s">{x.filename ? size(x.bytes) : "Link"}</span>,
            <span className="tnum" key="r">{x.readers} of {d.enrolled}</span>,
            x.published_at ? <span className="sub2 tnum" key="p">{day(x.published_at)}</span> : <Pil kind="grey" key="p">Draft</Pil>,
            <span key="a">{x.filename ? <a className="btn btn--ghost btn--sm" href={`/api/bff/api/v1/lms/offerings/${d.offering_id}/materials/${x.id}/content`} target="_blank" rel="noreferrer">Download</a> : <a className="btn btn--ghost btn--sm" href={x.link ?? "#"} target="_blank" rel="noreferrer noopener">Open link</a>}{" "}
              {!x.published_at ? <Btn kind="primary" disabled={busy} onClick={async () => { if (await send(`/materials/${x.id}/publish`, {}, `${d.course_code}: ${x.title} published`)) setSaid("Published"); }}>Publish</Btn> : null}{" "}
              <Btn kind="ghost" disabled={busy} onClick={async () => { if (await send(`/materials/${x.id}/end`, {}, `${d.course_code}: ${x.title} withdrawn`)) setSaid("Withdrawn from the space"); }}>Withdraw</Btn></span>,
          ])} />
        ) : <PBody><div className="sub2">Nothing published yet.</div></PBody>}
        {!upload ? <PBody><div><Btn kind="ghost" onClick={() => router.push(`/lms/${d.offering_id}?tab=upload`)}>Upload material</Btn></div></PBody> : null}
      </Panel>
      <Panel title="Assignments" right="Similarity check is not on the portal">
        {d.assignments.length ? (
          <DTable cols={["Assignment", "Opens|mid", "Closes|mid", "Submitted|mid", "Marked|mid", "Weight|mid", "Action|num"]} rows={d.assignments.map((x) => [
            <Two key="t" a={x.title} b={x.kind.charAt(0) + x.kind.slice(1).toLowerCase()} />,
            <span className="tnum sub2" key="o">{day(x.opens_at)}</span>, <span className="tnum sub2" key="c">{day(x.closes_at)}</span>,
            <span className="tnum" key="s">{x.submitted}</span>, <span className="tnum" key="m">{x.marked}</span>, <span className="tnum" key="w">{x.weight}%</span>,
            <Btn key="a" kind={x.submitted > x.marked ? "primary" : "ghost"} disabled={busy} onClick={async () => { const r = await fetch(`/api/bff/api/v1/lms/offerings/${d.offering_id}/assignments/${x.id}/submissions`); const rows = (await r.json().catch(() => [])) as Submission[]; setMarking({ assignment: x.id, title: x.title, rows }); setMarks(Object.fromEntries(rows.map((s) => [s.id, { mark: s.mark === null ? "" : String(s.mark), feedback: s.feedback ?? "" }]))); }}>{x.submitted > x.marked ? "Mark" : "Review"}</Btn>,
          ])} />
        ) : <PBody><div className="sub2">No assignment set.</div></PBody>}
        <PBody>
          <div className="grid grid--4">
            <Field id="as-title" label="New assignment"><input id="as-title" className="ctl" value={a.title} onChange={(e) => setA({ ...a, title: e.target.value })} placeholder="Problem set 3" /></Field>
            <Field id="as-closes" label="Closes"><input id="as-closes" className="ctl" type="datetime-local" value={a.closesAt} onChange={(e) => setA({ ...a, closesAt: e.target.value })} /></Field>
            <Field id="as-weight" label="Weight, % of CA"><input id="as-weight" className="ctl tnum" value={a.weight} onChange={(e) => setA({ ...a, weight: e.target.value })} /></Field>
            <Field id="as-kind" label="Kind"><select id="as-kind" className="ctl" value={a.kind} onChange={(e) => setA({ ...a, kind: e.target.value })}><option value="INDIVIDUAL">Individual</option><option value="PAIRS">Pairs</option><option value="GROUP">Group</option></select></Field>
          </div>
          <Field id="as-brief" label="Brief"><input id="as-brief" className="ctl" value={a.brief} onChange={(e) => setA({ ...a, brief: e.target.value })} /></Field>
          <div className="grid grid--3">
            <Field id="as-outof" label="Marked out of"><input id="as-outof" className="ctl tnum" value={a.outOf} onChange={(e) => setA({ ...a, outOf: e.target.value })} /></Field>
            <Field id="as-late" label="Late window, hours"><input id="as-late" className="ctl tnum" value={a.lateHours} onChange={(e) => setA({ ...a, lateHours: e.target.value })} /></Field>
            <Field id="as-pen" label="Late penalty, %"><input id="as-pen" className="ctl tnum" value={a.latePenalty} onChange={(e) => setA({ ...a, latePenalty: e.target.value })} /></Field>
          </div>
          <div><Btn kind="ghost" disabled={busy || !a.title.trim() || !a.closesAt || !Number(a.weight)} onClick={async () => { if (await send("/assignments", { title: a.title, brief: a.brief || null, kind: a.kind, closesAt: new Date(a.closesAt).toISOString(), weight: Number(a.weight), outOf: Number(a.outOf) || 100, lateHours: Number(a.lateHours), latePenalty: Number(a.latePenalty) }, `${d.course_code}: assignment ${a.title} set`)) { setSaid(`${a.title} set`); setA({ ...a, title: "", brief: "" }); } }}>Set the assignment</Btn></div>
        </PBody>
      </Panel>
      <Note kind="info" title="The gradebook total becomes the continuous assessment mark" action={<Btn kind="primary" disabled={busy || d.sheet_stage !== "ENTRY"} onClick={async () => { const j = await send("/promote", {}, `${d.course_code}: gradebook promoted to the score sheet`); if (j) setSaid(`${j.written} CA mark${Number(j.written) === 1 ? "" : "s"} written to the score sheet`); }}>Promote CA total to the score sheet</Btn>}>
        When you promote it, the weighted total (capped at 40) lands in the CA column of the score sheet as a new version with its reason — where it still goes through verification, departmental, faculty and Senate approval like any other mark. {d.sheet_stage ? (d.sheet_stage === "ENTRY" ? "The sheet is with you." : `The sheet has left the lecturer (${d.sheet_stage.toLowerCase().replace("_", " ")}); nothing is promoted into it now.`) : "No score sheet exists yet: it is generated when the examination session is opened."}
      </Note>
      <Panel title="Engagement — students at risk" right="Counted from the record, feeds the early-warning report">
        {d.engagement.length ? (
          <DTable cols={["Student", "Last opened", "Materials|mid", "Submissions|mid", "Attendance|mid", "CA so far|mid", "Flag|num"]} rows={d.engagement.map((e) => {
            const rate = e.held ? Math.round((100 * e.attended) / e.held) : null;
            const risk = (!e.last_read && d.materials.some((x) => x.published_at)) || (rate !== null && rate < 50) || (e.assignments > 0 && e.submitted === 0 && open.length < d.assignments.length);
            const watch = !risk && ((rate !== null && rate < 75) || (e.assignments > 0 && e.submitted < e.assignments));
            return [
              <Two key="s" a={e.name} b={e.number} />,
              <span className="sub2 tnum" key="l">{e.last_read ? day(e.last_read) : "Never"}</span>,
              <span className="tnum" key="m">{e.materials ? `${Math.round((100 * e.materials_read) / e.materials)}%` : "—"}</span>,
              <span className="tnum" key="u">{e.submitted} of {e.assignments}</span>,
              <span className="tnum" key="a">{rate === null ? "—" : `${rate}%`}</span>,
              <span className="tnum" key="c">{Number(e.total).toFixed(1)} / {e.weight_marked}</span>,
              risk ? <Pil kind="bad" key="f">High risk</Pil> : watch ? <Pil kind="info" key="f">Watch</Pil> : <Pil kind="ok" key="f">On track</Pil>,
            ];
          })} texts={d.engagement.map((e) => `${e.name} ${e.number}`)} />
        ) : <PBody><div className="sub2">Nobody is registered and approved for this offering yet.</div></PBody>}
      </Panel>
      {marking ? (
        <Modal title={`Mark — ${marking.title}`} sub={`${marking.rows.length} submission${marking.rows.length === 1 ? "" : "s"}`} onClose={() => setMarking(null)}
          foot={<><Btn kind="ghost" onClick={() => setMarking(null)}>Close</Btn></>}>
          {marking.rows.length ? marking.rows.map((s) => (
            <div key={s.id} style={{ padding: "var(--s-3) 0", borderTop: "1px solid var(--line-2)" }}>
              <div className="row row--between row--top">
                <Two a={s.name} b={`${s.number} · ${day(s.submitted_at)}${s.late ? " · late" : ""}`} />
                {s.filename ? <a className="btn btn--ghost btn--sm" href={`/api/bff/api/v1/lms/offerings/${d.offering_id}/submissions/${s.id}/content`} target="_blank" rel="noreferrer">{s.filename} · {size(s.bytes)}</a> : null}
              </div>
              {s.text ? <div className="sub2 mt-2" style={{ whiteSpace: "pre-wrap" }}>{s.text}</div> : null}
              <div className="row mt-2">
                <input className="ctl tnum" style={{ width: 90 }} placeholder="Mark" value={marks[s.id]?.mark ?? ""} onChange={(e) => setMarks({ ...marks, [s.id]: { mark: e.target.value, feedback: marks[s.id]?.feedback ?? "" } })} />
                <input className="ctl grow" style={{ minWidth: 200 }} placeholder="Feedback" value={marks[s.id]?.feedback ?? ""} onChange={(e) => setMarks({ ...marks, [s.id]: { mark: marks[s.id]?.mark ?? "", feedback: e.target.value } })} />
                <Btn kind="go" disabled={busy || marks[s.id]?.mark === ""} onClick={async () => { if (await send(`/assignments/${marking.assignment}/submissions/${s.id}/mark`, { mark: Number(marks[s.id].mark), feedback: marks[s.id].feedback || null }, `${d.course_code}: ${marking.title} marked for ${s.number}`)) setSaid(`Marked ${s.number}`); }}>{s.mark !== null ? "Re-mark" : "Mark"}</Btn>
              </div>
            </div>
          )) : <div className="sub2">No submission yet.</div>}
        </Modal>
      ) : null}
    </>
  );
}
