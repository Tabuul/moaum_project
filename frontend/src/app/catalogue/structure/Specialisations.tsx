"use client";
/** V483: a postgraduate programme's specialisations, on its one structure — added, renamed, ended or restored; how many students
 *  read each and how many courses are for it; the programme's students, each given the specialisation they read (one at a
 *  time or many at once). A course bound for no specialisation is for every student of the programme; one named for some is on
 *  those students' registration menus only. A student given none sees the courses for every student. */
import { useState } from "react";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, Note, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";

export interface Specialisation { id: string; code: string; name: string; active: boolean; created_at: string; ended_at: string | null; students: number; courses: number }
export interface SpecStudent { id: string; matric_no: string | null; admission_no: string | null; name: string; level: number; status: string; specialisation_id: string | null }
export interface SpecData { programme: { code: string; name: string }; postgraduate: boolean; specialisations: Specialisation[]; students: SpecStudent[]; may: { change: boolean; ticket: boolean } }

/** one request to the specialisation endpoints, with the ticket and the reason; true when it was saved */
export async function specCall(method: "POST" | "PUT", path: string, body: unknown, reason: string, ticket: string): Promise<boolean> {
  const t = ticket.trim();
  const url = `/api/bff/api/v1/catalogue/structure/specialisations${path}${t ? `${path.includes("?") ? "&" : "?"}ticket=${encodeURIComponent(t)}` : ""}`;
  const r = await fetch(url, { method, headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(t ? `Ticket ${t.toUpperCase()}: ${reason}` : reason) }, body: JSON.stringify(body ?? {}) });
  if (!r.ok) { notifyProblem((await r.json().catch(() => null)) ?? { status: r.status, title: r.statusText }); return false; }
  notify(reason);
  return true;
}

export function Specialisations({ data, ticket, onChanged }: { data: SpecData; ticket: string; onChanged: () => void }) {
  const [busy, setBusy] = useState(false);
  const [nw, setNw] = useState({ code: "", name: "" });
  const [edit, setEdit] = useState<Specialisation | null>(null);
  const [picked, setPicked] = useState<Set<string>>(new Set());
  const [bulk, setBulk] = useState("");
  const [q, setQ] = useState("");
  const may = data.may.change;
  const p = data.programme.code;
  const running = data.specialisations.filter((s) => s.active);
  const nameOf = (id: string | null) => data.specialisations.find((s) => s.id === id);
  const students = data.students.filter((s) => !q.trim() || `${s.name} ${s.matric_no ?? ""} ${s.admission_no ?? ""}`.toLowerCase().includes(q.trim().toLowerCase()));
  const without = data.students.filter((s) => !s.specialisation_id).length;

  async function run(fn: () => Promise<boolean>) {
    setBusy(true);
    try { if (await fn()) onChanged(); } finally { setBusy(false); }
  }

  async function setStudents(ids: string[], spec: string | null) {
    const label = spec ? nameOf(spec)?.code ?? "a specialisation" : "none";
    await run(async () => {
      const ok = await specCall("PUT", "/students", { programme: p, specialisation: spec, students: ids }, `${ids.length} student${ids.length === 1 ? "" : "s"} of ${p}: specialisation ${label}`, ticket);
      if (ok) setPicked(new Set());
      return ok;
    });
  }

  return (
    <>
      <Panel title="Specialisations" right={`${running.length} running · ${without} student${without === 1 ? "" : "s"} without one`}>
        <PBody>
          <div className="sub2">
            One structure for the programme: a course bound for no specialisation is for every student; a course named for some (the <b>For</b> column below) is on those students&rsquo; registration menus only. A student given none sees the courses for every student.
          </div>
          {may ? (
            <div className="row row--end mt-2">
              <Field id="sp-code" label="Code" hint="Letters and digits, e.g. MON"><input id="sp-code" className="ctl tnum" style={{ width: 120 }} maxLength={12} value={nw.code} onChange={(e) => setNw({ ...nw, code: e.target.value.toUpperCase().replace(/[^A-Z0-9-]/g, "") })} /></Field>
              <Field id="sp-name" label="Name" style={{ flex: "2 1 260px" }}><input id="sp-name" className="ctl" maxLength={120} value={nw.name} onChange={(e) => setNw({ ...nw, name: e.target.value })} placeholder="e.g. Monetary Economics" /></Field>
              <Btn kind="primary" disabled={busy || !nw.code.trim() || !nw.name.trim()} busyLabel="Adding…"
                onClick={() => run(async () => { const ok = await specCall("POST", "", { programme: p, code: nw.code, name: nw.name }, `Specialisation ${nw.code} (${nw.name.trim()}) added to ${p}`, ticket); if (ok) setNw({ code: "", name: "" }); return ok; })}>Add specialisation</Btn>
            </div>
          ) : null}
        </PBody>
        {data.specialisations.length ? (
          <DTable pageSize={0} cols={["Code|mid", "Specialisation", "Students|num", "Courses for it|num", "State|mid", ...(may ? ["|num"] : [])]} rows={data.specialisations.map((s) => [
            <b key="c" className="tnum">{s.code}</b>, <span key="n">{s.name}</span>, <span key="s" className="tnum">{s.students}</span>, <span key="k" className="tnum">{s.courses}</span>,
            <Pil key="a" kind={s.active ? "ok" : "grey"}>{s.active ? "Running" : "Ended"}</Pil>,
            ...(may ? [<span key="x" className="row row--tight row--right">
              <Btn kind="ghost" size="sm" disabled={busy} onClick={() => setEdit(s)}>Rename</Btn>
              {s.active
                ? <Btn kind="ghost" size="sm" disabled={busy} onClick={() => { if (window.confirm(`End ${s.code}? It is no longer given to a student or a course; its ${s.students} student${s.students === 1 ? "" : "s"} and ${s.courses} course${s.courses === 1 ? "" : "s"} keep it.`)) void run(() => specCall("POST", `/${s.id}/end`, {}, `Specialisation ${s.code} of ${p} ended`, ticket)); }}>End</Btn>
                : <Btn kind="ghost" size="sm" disabled={busy} onClick={() => void run(() => specCall("POST", `/${s.id}/restore`, {}, `Specialisation ${s.code} of ${p} restored`, ticket))}>Restore</Btn>}
            </span>] : []),
          ])} />
        ) : <PBody><div className="sub2">No specialisation yet: every course of the programme is for every student.</div></PBody>}
      </Panel>

      {data.specialisations.length ? (
        <Panel title="Students' specialisations" right={`${data.students.length} student${data.students.length === 1 ? "" : "s"} of ${p}`}>
          <PBody>
            <div className="row row--end">
              <Field id="sp-q" label="Find a student" style={{ flex: "1 1 220px" }}><input id="sp-q" className="ctl" value={q} onChange={(e) => setQ(e.target.value)} placeholder="Name or number" /></Field>
              {may ? (
                <>
                  <Field id="sp-bulk" label={`${picked.size} chosen`}>
                    <select id="sp-bulk" className="ctl" value={bulk} onChange={(e) => setBulk(e.target.value)}>
                      <option value="">No specialisation</option>
                      {running.map((s) => <option key={s.id} value={s.id}>{s.code} — {s.name}</option>)}
                    </select></Field>
                  <Btn kind="secondary" disabled={busy || !picked.size} busyLabel="Saving…" onClick={() => setStudents([...picked], bulk || null)}>Set for the chosen</Btn>
                </>
              ) : null}
            </div>
            {!running.length ? <div className="mt-2"><Note kind="info" title="No specialisation is running">Restore one, or add one, to give it to students.</Note></div> : null}
          </PBody>
          <DTable cols={[...(may ? ["|mid"] : []), "Student", "Number", "Level|mid", "Specialisation"]} rows={students.map((s) => [
            ...(may ? [<input key="k" type="checkbox" aria-label={`Choose ${s.name}`} checked={picked.has(s.id)} onChange={(e) => { const n = new Set(picked); if (e.target.checked) n.add(s.id); else n.delete(s.id); setPicked(n); }} />] : []),
            <span key="n">{s.name}</span>, <span key="m" className="tnum sub2">{s.matric_no ?? s.admission_no ?? ""}</span>, <span key="l" className="tnum">{s.level}</span>,
            may ? (
              <select key="s" className="ctl" aria-label={`Specialisation of ${s.name}`} disabled={busy} value={s.specialisation_id ?? ""} onChange={(e) => void setStudents([s.id], e.target.value || null)}>
                <option value="">None</option>
                {data.specialisations.filter((x) => x.active || x.id === s.specialisation_id).map((x) => <option key={x.id} value={x.id}>{x.code} — {x.name}{x.active ? "" : " (ended)"}</option>)}
              </select>
            ) : <span key="s" className="sub2">{s.specialisation_id ? `${nameOf(s.specialisation_id)?.code ?? ""} — ${nameOf(s.specialisation_id)?.name ?? ""}` : "None"}</span>,
          ])} texts={students.map((s) => `${s.name} ${s.matric_no ?? ""} ${nameOf(s.specialisation_id)?.code ?? ""}`)} />
        </Panel>
      ) : null}

      {edit ? (
        <Modal title={`Rename ${edit.code}`} sub={`A specialisation of ${data.programme.name}; its students and courses follow`} onClose={() => setEdit(null)}
          foot={<>
            <Btn kind="ghost" onClick={() => setEdit(null)}>Cancel</Btn>
            <Btn kind="primary" disabled={busy || !edit.code.trim() || !edit.name.trim()} busyLabel="Saving…"
              onClick={() => run(async () => { const ok = await specCall("PUT", `/${edit.id}`, { programme: p, code: edit.code, name: edit.name }, `Specialisation of ${p} renamed: ${edit.code} (${edit.name.trim()})`, ticket); if (ok) setEdit(null); return ok; })}>Save</Btn>
          </>}>
          <div className="row row--end">
            <Field id="sp-ecode" label="Code"><input id="sp-ecode" className="ctl tnum" style={{ width: 120 }} maxLength={12} value={edit.code} onChange={(e) => setEdit({ ...edit, code: e.target.value.toUpperCase().replace(/[^A-Z0-9-]/g, "") })} /></Field>
            <Field id="sp-ename" label="Name" style={{ flex: "2 1 240px" }}><input id="sp-ename" className="ctl" maxLength={120} value={edit.name} onChange={(e) => setEdit({ ...edit, name: e.target.value })} /></Field>
          </div>
        </Modal>
      ) : null}
    </>
  );
}

/** V483: the specialisations a bound course is for — none is every student of the programme */
export function ForSpecialisations({ data, course, level, chosen, ticket, onClose, onSaved }: {
  data: SpecData; course: string; level: number; chosen: string[]; ticket: string; onClose: () => void; onSaved: () => void;
}) {
  const [on, setOn] = useState<Set<string>>(new Set(chosen));
  const [busy, setBusy] = useState(false);
  const list = data.specialisations.filter((s) => s.active || chosen.includes(s.id));
  return (
    <Modal title={`${course}: who it is for`} sub={`${data.programme.name} at ${level} level`} onClose={onClose}
      foot={<>
        <Btn kind="ghost" onClick={onClose}>Cancel</Btn>
        <Btn kind="primary" disabled={busy} busyLabel="Saving…" onClick={async () => {
          setBusy(true);
          try {
            const ids = [...on];
            const names = data.specialisations.filter((s) => ids.includes(s.id)).map((s) => s.code).join(", ");
            if (await specCall("PUT", "/binding", { programme: data.programme.code, course, level, specialisations: ids },
              `${course} in ${data.programme.code} at ${level} level for ${names || "every student"}`, ticket)) onSaved();
          } finally { setBusy(false); }
        }}>Save</Btn>
      </>}>
      <div className="sub2">Tick none for every student of the programme.</div>
      <div className="stack mt-2">
        {list.map((s) => (
          <label key={s.id} className="row row--inline row--tight">
            <input type="checkbox" checked={on.has(s.id)} disabled={!s.active && !chosen.includes(s.id)} onChange={(e) => { const n = new Set(on); if (e.target.checked) n.add(s.id); else n.delete(s.id); setOn(n); }} />
            <b className="tnum">{s.code}</b> {s.name}{s.active ? "" : <span className="sub2"> · ended</span>}
          </label>
        ))}
      </div>
    </Modal>
  );
}
