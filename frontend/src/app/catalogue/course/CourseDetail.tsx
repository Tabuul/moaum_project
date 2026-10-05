"use client";
/** One course and everything that offers it (V332): the record with its stable identity, the owner, the departments and
 *  programmes that carry it, the sessions it was taught, the proposals waiting on other departments, the bindings ended.
 *  Offerings are managed here — a programme of the owner's department bound at once, another department's proposed to
 *  that department — and the course is edited or its code renamed without ever becoming a second course. */
import Link from "next/link";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, LinkBtn, Note, PageHead, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { SearchSelect } from "@/components/proto/SearchSelect";
import { BASES, KINDS, LEVELS, PROPOSAL_STATE, SOURCE, STATE, semName, usageWords, type CourseDetail as Detail, type Directory } from "@/lib/catalogue";

const when = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" }) : "—");

export function CourseDetail({ data, directory }: { data: Detail; directory: Directory | null }) {
  const router = useRouter();
  const c = data.course;
  const [busy, setBusy] = useState(false);
  const [edit, setEdit] = useState<{ title: string; units: string; semester: string; level: string; kind: string } | null>(null);
  const [rename, setRename] = useState<string | null>(null);
  const [adding, setAdding] = useState(false);
  const [fac, setFac] = useState("");
  const [dept, setDept] = useState("");
  const [picked, setPicked] = useState<string[]>([]);
  const [level, setLevel] = useState(String(c.level));
  const [basis, setBasis] = useState("");
  const [track, setTrack] = useState("");
  const [reason, setReason] = useState("");
  const used = usageWords(data.usage);

  async function call(method: "POST" | "PUT" | "DELETE", path: string, body: unknown, reason: string): Promise<Record<string, unknown> | null> {
    setBusy(true);
    try {
      const r = await fetch(`/api/bff/api/v1/catalogue${path}`, { method, headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: method === "DELETE" ? undefined : JSON.stringify(body ?? {}) });
      const j = (await r.json().catch(() => null)) as Record<string, unknown> | null;
      if (!r.ok) { notifyProblem(j ? (j as unknown as Parameters<typeof notifyProblem>[0]) : { status: r.status, title: r.statusText }); return null; }
      notify(reason);
      router.refresh();
      return j;
    } finally { setBusy(false); }
  }

  const depts = (directory?.departments ?? []).filter((d) => !fac || d.faculty_code === fac);
  const progs = (directory?.programmes ?? []).filter((p) => p.dept_code === dept);
  const offered = new Set(data.offers.map((o) => `${o.programme_code}:${o.level}`));
  const pendingTo = new Set(data.proposals.filter((p) => p.state === "PENDING").map((p) => `${p.programme_code}:${p.level}`));
  const ownDept = c.dept_code ?? "";
  const direct = dept && (data.may.central || (directory?.actingDept && directory.actingDept.toUpperCase() === dept.toUpperCase()));
  const defaultBasis = dept === ownDept ? "Core" : "Borrowed";

  async function addOffers() {
    let bound = 0, proposed = 0;
    for (const p of picked) {
      const j = await call("POST", `/courses/${encodeURIComponent(c.code)}/offers`, { programme: p, level: Number(level), basis: basis || defaultBasis, track: track || null, reason: reason.trim() || null }, `${c.code} offered to ${p}`);
      if (!j) break;
      if (j.outcome === "BOUND") bound += 1; else proposed += 1;
    }
    if (bound || proposed) {
      notify(`${bound ? `${bound} bound` : ""}${bound && proposed ? ", " : ""}${proposed ? `${proposed} proposed to the department` : ""}`);
      setPicked([]); setAdding(false); setReason("");
    }
  }

  const pending = data.proposals.filter((p) => p.state === "PENDING");

  return (
    <>
      <PageHead eyebrow={<span className="tnum">{c.dept_name ?? c.dept_code} · {c.faculty_name ?? ""}</span>} title={<><span className="tnum">{c.code}</span> — {c.title}</>}
        description={<>{c.units} units · {c.level} Level · {semName(c.semester)} semester · {c.kind}{c.curriculum ? ` · ${c.curriculum}` : ""}{c.general_office ? ` · ${c.general_office}` : ""} · <Pil kind={STATE[c.state]?.[0] ?? "grey"}>{STATE[c.state]?.[1] ?? c.state}</Pil> <span className="sub2 tnum">Course ID {c.id}</span></>}
        actions={<>
          {data.may.edit && c.state !== "ENDED" ? <Btn kind="secondary" onClick={() => setEdit({ title: c.title, units: String(c.units), semester: String(c.semester), level: String(c.level), kind: c.kind })}>Edit</Btn> : null}
          {data.may.edit ? <Btn kind="ghost" onClick={() => setRename(c.code)}>Rename the code</Btn> : null}
          {data.may.edit && c.state !== "ENDED" ? <Btn kind="ghost" disabled={busy} onClick={() => { if (window.confirm(`End ${c.code}? It leaves next session's registration and stays on every transcript that carries it.`)) void call("POST", `/courses/${encodeURIComponent(c.code)}/end`, {}, `End course ${c.code}`); }}>End</Btn> : null}
          {data.may.edit && c.state === "ENDED" ? <Btn kind="ghost" disabled={busy} onClick={() => { if (window.confirm(`Restore ${c.code}? It returns to Live.`)) void call("POST", `/courses/${encodeURIComponent(c.code)}/restore`, {}, `Restore course ${c.code}`); }}>Restore</Btn> : null}
          <LinkBtn href={`/catalogue?dept=${encodeURIComponent(ownDept)}`}>Department courses</LinkBtn>
          <LinkBtn href="/catalogue/all">All courses</LinkBtn>
        </>} />

      <Tiles items={[
        ["Course owner", c.dept_name ?? c.dept_code ?? "—", null, "Sets the sheet, answers a query on a mark"],
        ["Departments offering", String(data.departments.length), null, data.departments.map((d) => d.name).slice(0, 3).join(", ") + (data.departments.length > 3 ? ` +${data.departments.length - 3} more` : "")],
        ["Programmes offering", String(data.offers.length), null, `${data.offers.filter((o) => o.registered_now > 0).length} with students registered this session`],
        ["Awaiting a department", String(pending.length), pending.length ? "var(--amber-ink)" : null, pending.length ? "Proposals not yet decided" : "No proposal waits"],
      ]} />

      {used ? <Note kind="info" title="What this course carries">{used}. An edit of the code, units, level or semester reaches all of it: the course stays one record, and every registration, result and offering stays on it.</Note> : null}

      <div className="grid grid--2">
        <Panel title="Departments offering this course" right="The owner first">
          <DTable pageSize={0} noPrint cols={["S/N|num", "Department", "Faculty", "Programmes|mid", "|mid"]} rows={data.departments.map((d, i) => [
            <span key="n" className="tnum sub2">{i + 1}</span>, <span key="d"><b>{d.name}</b></span>, <span key="f" className="sub2">{d.faculty ?? ""}</span>,
            <span key="p" className="tnum">{d.programmes}</span>, d.owner ? <Pil key="o" kind="info">Owner</Pil> : <span key="o" />,
          ])} />
        </Panel>
        <Panel title="Sessions offered" right="The offering each session, who taught it, who registered">
          {data.sessions.length ? <DTable pageSize={0} noPrint cols={["Session", "Semester|mid", "Lecturer", "Co-lecturers", "Registered|mid", "Sheet"]} rows={data.sessions.map((s) => [
            <span key="s" className="tnum">{s.session}</span>, <span key="m" className="tnum">{semName(s.semester)}</span>,
            <span key="l">{s.lecturer ?? <span className="sub2 ink-red">Not allocated</span>}{s.second_examiner ? <div className="sub2">2nd examiner {s.second_examiner}</div> : null}</span>,
            <span key="c" className="sub2">{s.co_lecturers.length ? s.co_lecturers.map((t) => `${t.name}${t.programme ? ` (${t.programme})` : ""}`).join("; ") : "—"}</span>,
            <span key="r" className="tnum">{s.registered}</span>, <span key="h" className="sub2">{s.sheet_stage ?? "—"}</span>,
          ])} /> : <PBody><div className="sub2">Not yet offered in any session.</div></PBody>}
        </Panel>
      </div>

      <Panel title="Programmes offering this course" right={<span className="row row--inline row--tight">
        <span className="sub2">{data.offers.length} binding{data.offers.length === 1 ? "" : "s"}</span>
        {data.may.offer && c.state !== "ENDED" ? <Btn kind="primary" size="sm" onClick={() => { setAdding(true); setDept(ownDept); setFac(""); setPicked([]); setLevel(String(c.level)); setBasis(""); setTrack(""); }}>+ Add Department / Programme</Btn> : null}
      </span>}>
        {data.offers.length ? (
          <DTable pageSize={0} cols={["S/N|num", "Programme", "Department", "Level|mid", "Basis|mid", "Track|mid", "Registered now|mid", "Ever|mid", "Bound", "|num"]} rows={data.offers.map((o, i) => [
            <span key="n" className="tnum sub2">{i + 1}</span>,
            <span key="p"><b>{o.programme}</b><div className="sub2 tnum"><Link href={`/catalogue/structure?prog=${encodeURIComponent(o.programme_code)}`} className="lnk">{o.programme_code}</Link></div></span>,
            <span key="d">{o.dept ?? o.dept_code}{o.dept_code === ownDept ? <Pil kind="info" className="ml-1">Owner</Pil> : null}<div className="sub2">{o.faculty ?? ""}</div></span>,
            <span key="l" className="tnum">{o.level}</span>,
            <Pil key="b" kind={o.basis === "Core" ? "info" : o.basis === "GST" ? "ok" : "grey"}>{o.basis}</Pil>,
            <span key="t" className="sub2 tnum">{o.track ?? "every"}</span>,
            <span key="rn" className="tnum">{o.registered_now}</span>, <span key="re" className="tnum sub2">{o.registered_ever}</span>,
            <span key="w" className="sub2">{when(o.added_at)}{o.added_by ? ` · ${o.added_by}` : ""}{o.source ? ` · ${SOURCE[o.source] ?? o.source.toLowerCase()}` : ""}</span>,
            o.may_remove ? <Btn key="x" kind="ghost" size="sm" disabled={busy} onClick={() => { const why = window.prompt(`Remove ${c.code} from ${o.programme_code} at ${o.level} level? Students of that programme and level will no longer see it at registration; what it carried stays on the record. Say why.`); if (why !== null) void call("DELETE", `/courses/${encodeURIComponent(c.code)}/offers?programme=${encodeURIComponent(o.programme_code)}&level=${o.level}&reason=${encodeURIComponent(why.trim())}`, null, `${c.code} removed from ${o.programme_code} at ${o.level} level`); }}>Remove</Btn> : <span key="x" />,
          ])} texts={data.offers.map((o) => `${o.programme} ${o.programme_code} ${o.dept ?? ""} ${o.basis}`)} />
        ) : <PBody><div className="sub2 ink-red">Not bound to any programme — no student sees it at registration.</div></PBody>}
        {adding ? (
          <PBody>
            <div className="stack">
              <div className="row">
                <Field id="of-fac" label="Faculty" style={{ flex: "1 1 200px" }}><SearchSelect id="of-fac" value={fac} onChange={(v) => { setFac(v); setDept(""); setPicked([]); }} allLabel="Any faculty" options={(directory?.faculties ?? []).map((f) => ({ value: f.code, label: f.name }))} /></Field>
                <Field id="of-dept" label="Department" style={{ flex: "2 1 260px" }}><SearchSelect id="of-dept" value={dept} onChange={(v) => { setDept(v); setPicked([]); setBasis(""); }} placeholder="Search a department…" options={depts.map((d) => ({ value: d.code, label: d.name }))} /></Field>
                <Field id="of-level" label="Level" style={{ flex: "0 1 110px" }}><select id="of-level" className="ctl" value={level} onChange={(e) => setLevel(e.target.value)}>{LEVELS.map((l) => <option key={l} value={String(l)}>{l}</option>)}</select></Field>
                <Field id="of-basis" label="Basis" style={{ flex: "0 1 140px" }}><select id="of-basis" className="ctl" value={basis} onChange={(e) => setBasis(e.target.value)}><option value="">{defaultBasis} (usual)</option>{BASES.map((b) => <option key={b} value={b}>{b}</option>)}</select></Field>
                <Field id="of-track" label="Track" style={{ flex: "0 1 160px" }}><select id="of-track" className="ctl" value={track} onChange={(e) => setTrack(e.target.value)}><option value="">Every track</option>{(directory?.tracks ?? []).map((t) => <option key={t.code} value={t.code}>{t.code}</option>)}</select></Field>
              </div>
              {dept ? (
                <div>
                  <div className="eyebrow">Programmes of {depts.find((d) => d.code === dept)?.name ?? dept}</div>
                  {progs.length ? progs.map((p) => {
                    const key = `${p.code}:${level}`;
                    const has = offered.has(key);
                    const waits = pendingTo.has(key);
                    return (
                      <label key={p.code} className="row row--inline row--tight" style={{ marginRight: 16, opacity: has || waits ? 0.6 : 1 }}>
                        <input type="checkbox" disabled={has || waits} checked={picked.includes(p.code)} onChange={(e) => setPicked(e.target.checked ? [...picked, p.code] : picked.filter((x) => x !== p.code))} />
                        {p.name} <span className="sub2 tnum">{p.code}</span>{has ? <Pil kind="ok">offered</Pil> : waits ? <Pil kind="warn">proposed</Pil> : null}
                      </label>
                    );
                  }) : <div className="sub2">No active programme in this department.</div>}
                </div>
              ) : null}
              {dept && !direct ? <Field id="of-reason" label="Why the programme should offer it" hint="Goes to that department's Head, who decides"><input id="of-reason" className="ctl" value={reason} onChange={(e) => setReason(e.target.value)} maxLength={2000} /></Field> : null}
              <div className="row row--tight">
                <Btn kind="primary" disabled={busy || !picked.length} onClick={() => void addOffers()}>{direct ? `Bind ${picked.length || ""} programme${picked.length === 1 ? "" : "s"}` : `Propose to ${picked.length || ""} programme${picked.length === 1 ? "" : "s"}`}</Btn>
                <Btn kind="ghost" onClick={() => setAdding(false)}>Cancel</Btn>
                <span className="sub2">{direct ? "Within your authority: bound at once." : "Another department's programme: its Head, its Dean or the Academic Office approves before students see it."}</span>
              </div>
            </div>
          </PBody>
        ) : null}
      </Panel>

      {data.proposals.length ? (
        <Panel title="Proposals to other departments" right="A course offered to a programme of another department waits for that department">
          <DTable pageSize={0} noPrint cols={["Programme", "Department", "Level|mid", "Basis|mid", "Proposed", "State|mid", "Decision", "|num"]} rows={data.proposals.map((p) => [
            <span key="p"><b>{p.programme}</b><div className="sub2 tnum">{p.programme_code}</div></span>, <span key="d" className="sub2">{p.dept ?? p.dept_code}</span>,
            <span key="l" className="tnum">{p.level}</span>, <span key="b" className="sub2">{p.basis}</span>,
            <span key="w" className="sub2">{when(p.proposed_at)}{p.proposed_by ? ` · ${p.proposed_by}` : ""}{p.reason ? <div>{p.reason}</div> : null}</span>,
            <Pil key="s" kind={PROPOSAL_STATE[p.state]?.[0] ?? "grey"}>{PROPOSAL_STATE[p.state]?.[1] ?? p.state}</Pil>,
            <span key="dc" className="sub2">{p.decided_at ? `${when(p.decided_at)}${p.decided_by ? ` · ${p.decided_by}` : ""}` : ""}{p.decision_note ? <div>{p.decision_note}</div> : null}</span>,
            <span key="a" className="row row--inline row--tight row--right">
              {p.may_decide ? <><Btn kind="primary" size="sm" disabled={busy} onClick={() => void call("POST", `/offer-proposals/${p.id}/approve`, { note: window.prompt("A note for the record (optional)") ?? "" }, `${c.code} approved for ${p.programme_code}`)}>Approve</Btn><Btn kind="ghost" size="sm" disabled={busy} onClick={() => { const n = window.prompt("Why is it rejected?"); if (n !== null) void call("POST", `/offer-proposals/${p.id}/reject`, { note: n }, `${c.code} declined for ${p.programme_code}`); }}>Reject</Btn></> : null}
              {p.may_cancel ? <Btn kind="ghost" size="sm" disabled={busy} onClick={() => { if (window.confirm("Withdraw this proposal?")) void call("POST", `/offer-proposals/${p.id}/cancel`, {}, `Proposal to ${p.programme_code} withdrawn`); }}>Withdraw</Btn> : null}
            </span>,
          ])} />
        </Panel>
      ) : null}

      {data.history.length ? (
        <Panel title="Bindings ended" right="Kept on the record; what they carried stays">
          <DTable pageSize={0} noPrint cols={["Programme", "Level|mid", "Basis|mid", "Bound", "Ended", "Registrations carried|mid", "Reason"]} rows={data.history.map((h, i) => [
            <span key={"p" + i}><b>{h.programme}</b> <span className="sub2 tnum">{h.programme_code}</span><div className="sub2">{h.dept ?? ""}</div></span>,
            <span key={"l" + i} className="tnum">{h.level}</span>, <span key={"b" + i} className="sub2">{h.basis ?? ""}</span>,
            <span key={"a" + i} className="sub2">{when(h.added_at)}{h.source ? ` · ${SOURCE[h.source] ?? h.source.toLowerCase()}` : ""}</span>,
            <span key={"e" + i} className="sub2">{when(h.ended_at)}{h.ended_by ? ` · ${h.ended_by}` : ""}</span>,
            <span key={"r" + i} className={`tnum${Number(h.registrations_carried) ? " b600" : ""}`}>{h.registrations_carried}</span>, <span key={"w" + i} className="sub2">{h.reason ?? ""}</span>,
          ])} />
        </Panel>
      ) : null}

      {edit ? (
        <Modal title={`Edit ${c.code}`} sub={used ? `This course carries ${used}; it stays the same course and all of it follows.` : "Nothing hangs on this course yet."} onClose={() => setEdit(null)}
          foot={<><Btn kind="ghost" onClick={() => setEdit(null)}>Cancel</Btn><Btn kind="primary" disabled={busy || !edit.title.trim()} onClick={async () => {
            const changed = Number(edit.units) !== c.units || Number(edit.level) !== c.level || Number(edit.semester) !== c.semester;
            if (changed && used && !window.confirm(`The units, level or semester change on a course that carries ${used}. Past results keep the marks they carry; registration and fees from now on read the new values. Continue?`)) return;
            if (await call("PUT", `/courses/${encodeURIComponent(c.code)}`, { title: edit.title.trim(), units: Number(edit.units), semester: Number(edit.semester), level: Number(edit.level), kind: edit.kind }, `${c.code} edited`)) setEdit(null);
          }}>Save</Btn></>}>
          <div className="stack">
            <Field id="ed-title" label="Title" required><input id="ed-title" className="ctl" value={edit.title} onChange={(e) => setEdit({ ...edit, title: e.target.value })} maxLength={120} /></Field>
            <div className="grid grid--4">
              <Field id="ed-units" label="Units"><input id="ed-units" className="ctl tnum" inputMode="numeric" value={edit.units} onChange={(e) => setEdit({ ...edit, units: e.target.value })} /></Field>
              <Field id="ed-level" label="Level"><select id="ed-level" className="ctl" value={edit.level} onChange={(e) => setEdit({ ...edit, level: e.target.value })}>{LEVELS.map((l) => <option key={l} value={String(l)}>{l}</option>)}</select></Field>
              <Field id="ed-sem" label="Semester"><select id="ed-sem" className="ctl" value={edit.semester} onChange={(e) => setEdit({ ...edit, semester: e.target.value })}><option value="1">First</option><option value="2">Second</option><option value="3">Third</option></select></Field>
              <Field id="ed-kind" label="Kind"><select id="ed-kind" className="ctl" value={edit.kind} onChange={(e) => setEdit({ ...edit, kind: e.target.value })}>{KINDS.map((k) => <option key={k} value={k}>{k}</option>)}</select></Field>
            </div>
          </div>
        </Modal>
      ) : null}
      {rename !== null ? (
        <Modal title={`Rename ${c.code}`} sub="The same course under a new code: its bindings, offerings, registrations, results, questions and examinations follow it." onClose={() => setRename(null)}
          foot={<><Btn kind="ghost" onClick={() => setRename(null)}>Cancel</Btn><Btn kind="urgent" disabled={busy || !rename.trim() || rename.trim().toUpperCase() === c.code} onClick={async () => {
            if (used && !window.confirm(`${c.code} carries ${used}. Every one of them will read ${rename.trim().toUpperCase()} from now on. Continue?`)) return;
            const j = await call("POST", `/courses/${encodeURIComponent(c.code)}/rename`, { code: rename.trim() }, `${c.code} renamed`);
            if (j) { setRename(null); router.replace(`/catalogue/course?code=${encodeURIComponent(String(j.code))}`); }
          }}>Rename</Btn></>}>
          <Field id="rn-code" label="New code" hint="CSC 201, or a prefix with its hyphen — MOAU-CHM 101"><input id="rn-code" className="ctl tnum" value={rename} onChange={(e) => setRename(e.target.value)} maxLength={20} autoComplete="off" /></Field>
        </Modal>
      ) : null}
    </>
  );
}
