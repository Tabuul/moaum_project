"use client";
/** The postings desk (V245): choose the session and the level, then a block's posting; tick the College's
 *  students at that level and allocate them to it with a rotation group, a supervisor and dates. The
 *  posting's roll shows who is on it and where each stands; an allocation made in error is withdrawn
 *  while it is merely allocated, and marked incomplete once it has begun. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { useQueryNav } from "@/lib/query-nav";
import { notify } from "@/components/proto/Toast";
import { Btn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { SearchSelect } from "@/components/proto/SearchSelect";
import { Field } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";

export interface CollegeStructure {
  blocks: { id: string; code: string; name: string; dept_code: string | null; total_weeks: number | null; weeks_note: string | null; note: string | null; ordinal: number }[];
  postings: { id: string; block_id: string; code: string; name: string; tier: string; level: number | null; level_note: string | null; duration_weeks: number | null; ordinal: number; min_cases: number | null; note: string | null; courses: string | null; procedures: number; slots: number }[];
  groups: { id: string; posting_id: string; label: string }[];
  levels: { level: number; phase: string; clinical_year: number | null; enrolment: string }[];
}
export interface AllocationBrief { id: string; posting_id: string; posting: string; block: string; group: string | null; supervisor: string | null; starts_on: string | null; ends_on: string | null; state: string }
export interface CollegeStudent { id: string; number: string; surname: string; other_names: string; programme_code: string; programme: string; current_level: number; entry_mode: string; status: string; allocations: string }
export interface Allocation { id: string; student_id: string; number: string; surname: string; other_names: string; programme_code: string; group_id: string | null; group_label: string | null; supervisor_id: string | null; supervisor: string | null; starts_on: string | null; ends_on: string | null; state: string; allocated_at: string }
export interface Supervisor { id: string; surname: string; given_names: string; staff_number: string | null; dept_code: string; dept_name: string }

const STATE: Record<string, ["ok" | "info" | "bad" | "grey" | "warn", string]> = {
  ALLOCATED: ["info", "Allocated"], IN_PROGRESS: ["warn", "In progress"], COMPLETED: ["ok", "Completed"], INCOMPLETE: ["bad", "Incomplete"],
};
const TIER: Record<string, string> = { INTRO: "Introductory", JUNIOR: "Junior", INTERMEDIATE: "Intermediate", SENIOR: "Senior", REVISION: "Revision", LECTURES: "Lectures" };
const day = (iso: string | null) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" }) : "—");
const parseAlloc = (s: string): AllocationBrief[] => { try { const j = JSON.parse(s); return Array.isArray(j) ? j : []; } catch { return []; } };

export function Postings({ structure, sessions, session, level, posting, students, allocations, supervisors, problem }: {
  structure: CollegeStructure; sessions: string[]; session: string; level: number; posting: string;
  students: CollegeStudent[]; allocations: Allocation[]; supervisors: Supervisor[]; problem: Problem | null;
}) {
  const router = useRouter();
  const go = useQueryNav();
  const [picked, setPicked] = useState<Set<string>>(new Set());
  const [group, setGroup] = useState("");
  const [supervisor, setSupervisor] = useState("");
  const [from, setFrom] = useState("");
  const [to, setTo] = useState("");
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<Problem | null>(null);
  const [q, setQ] = useState("");

  const nav = (patch: Partial<{ session: string; level: number; posting: string }>) => {
    const s = patch.session ?? session; const l = patch.level ?? level; const p = patch.posting ?? posting;
    go(`/college/postings?session=${encodeURIComponent(s)}&level=${l}${p ? `&posting=${encodeURIComponent(p)}` : ""}`);
  };
  const postingsAtLevel = structure.postings.filter((p) => p.level === level || (p.level == null && (p.level_note ?? "").includes(String(level))));
  const chosen = structure.postings.find((p) => p.id === posting) ?? null;
  const chosenBlock = chosen ? structure.blocks.find((b) => b.id === chosen.block_id) : null;
  const groups = chosen ? structure.groups.filter((g) => g.posting_id === chosen.id) : [];
  const onIt = new Set(allocations.map((a) => a.student_id));
  const terms = q.toLowerCase().trim().split(/\s+/).filter(Boolean);
  const shown = students.filter((s) => !terms.length || terms.every((t) => `${s.number} ${s.surname} ${s.other_names} ${s.programme}`.toLowerCase().includes(t)));
  const notYet = shown.filter((s) => !onIt.has(s.id));

  async function call(method: "POST" | "PUT" | "DELETE", path: string, body: unknown, reason: string): Promise<boolean> {
    setBusy(true); setErr(null);
    try {
      const r = await fetch(`/api/bff/api/v1/college${path}`, {
        method, headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: method === "DELETE" ? undefined : JSON.stringify(body),
      });
      if (!r.ok) { setErr((await r.json().catch(() => null)) ?? { status: r.status, title: r.statusText }); return false; }
      notify(reason);
      router.refresh();
      return true;
    } finally { setBusy(false); }
  }

  async function allocate() {
    if (!chosen || !picked.size) return;
    const ok = await call("POST", "/allocations", {
      session, postingId: chosen.id, studentIds: [...picked], groupId: group || null, supervisorId: supervisor || null, startsOn: from || null, endsOn: to || null,
    }, `${picked.size} student${picked.size === 1 ? "" : "s"} allocated to ${chosenBlock?.code ?? ""} ${chosen.code} for ${session}`);
    if (ok) setPicked(new Set());
  }

  const toggleAll = (on: boolean) => setPicked(on ? new Set(notYet.map((s) => s.id)) : new Set());

  return (
    <>
      <div className="scope">
        <div className="scope__f"><label htmlFor="po-session">Session</label>
          <select id="po-session" className="ws__select" value={session} onChange={(e) => nav({ session: e.target.value, posting: "" })}>
            {sessions.map((s) => <option key={s} value={s}>{s}</option>)}
          </select></div>
        <div className="scope__f"><label htmlFor="po-level">Level</label>
          <select id="po-level" className="ws__select" value={String(level)} onChange={(e) => nav({ level: Number(e.target.value), posting: "" })}>
            {structure.levels.filter((l) => l.level >= 300).map((l) => <option key={l.level} value={String(l.level)}>{l.level} · {l.phase === "CLINICAL" ? `Clinical year ${l.clinical_year}` : "Pre-clinical"}</option>)}
          </select></div>
        <div className="scope__f" style={{ flex: "2 1 320px" }}><label htmlFor="po-posting">Posting</label>
          <select id="po-posting" className="ws__select" value={posting} onChange={(e) => nav({ posting: e.target.value })}>
            <option value="">Choose a posting at {level} Level…</option>
            {structure.blocks.map((b) => {
              const ps = postingsAtLevel.filter((p) => p.block_id === b.id);
              return ps.length ? <optgroup key={b.id} label={`${b.name}${b.total_weeks ? ` · ${b.total_weeks} weeks` : ""}`}>{ps.map((p) => <option key={p.id} value={p.id}>{p.code} — {p.name}{p.duration_weeks ? ` · ${p.duration_weeks} wk` : ""}</option>)}</optgroup> : null;
            })}
          </select></div>
      </div>
      {problem ? <ProblemNotice problem={problem} /> : null}
      {err ? <ProblemNotice problem={err} /> : null}

      <Tiles items={[
        ["Students at this level", String(students.length), null, `${level} Level · the College's register`],
        ["Postings at this level", String(postingsAtLevel.length), null, `${new Set(postingsAtLevel.map((p) => p.block_id)).size} block${new Set(postingsAtLevel.map((p) => p.block_id)).size === 1 ? "" : "s"}`],
        ["On the chosen posting", chosen ? String(allocations.length) : "—", null, chosen ? `${chosenBlock?.name ?? ""} · ${chosen.code}` : "Choose a posting"],
        ["Not yet allocated to it", chosen ? String(students.length - allocations.length) : "—", chosen && students.length - allocations.length > 0 ? "var(--red-ink)" : null, chosen ? "At this level, this session" : ""],
      ]} />

      {!chosen ? (
        <Note kind="info" title="Choose a posting">
          Postings are the College&rsquo;s way of enrolling a clinical student: not a course registered, but a Block&rsquo;s posting allocated for a stretch of weeks, with a supervisor and, where the department names them, a rotation group. Choose the session, the level and the posting; then tick the students and allocate.
        </Note>
      ) : (
        <>
          <Panel title={`${chosenBlock?.name ?? ""} · ${chosen.code} — ${chosen.name}`} right={`${TIER[chosen.tier] ?? chosen.tier}${chosen.duration_weeks ? ` · ${chosen.duration_weeks} weeks` : ""}${chosen.level_note ? ` · ${chosen.level_note}` : ""}`}>
            <PBody>
              {chosen.courses ? <div className="sub2 tnum mb-2">{chosen.courses}</div> : null}
              <div className="sub2">{chosen.min_cases ? `${chosen.min_cases} cases to clerk · ` : ""}{chosen.procedures ? `${chosen.procedures} procedure requirements · ` : ""}{chosen.slots ? `${chosen.slots} timetable slots` : "no timetable in the prospectus"}{chosen.note ? ` · ${chosen.note}` : ""}</div>
            </PBody>
          </Panel>

          <div className="grid grid--2">
            <Panel title="Students at this level not yet on it" right={`${notYet.length} of ${shown.length} shown`}>
              <PBody>
                <div className="row mb-2">
                  <input className="ctl" type="search" value={q} onChange={(e) => setQ(e.target.value)} placeholder="Search by number, name or programme…" aria-label="Search students" style={{ flex: "1 1 220px" }} />
                  <Btn kind="ghost" onClick={() => toggleAll(true)} disabled={!notYet.length}>Tick all {notYet.length}</Btn>
                  <Btn kind="ghost" onClick={() => toggleAll(false)} disabled={!picked.size}>Clear</Btn>
                </div>
                {notYet.length ? (
                  <div style={{ maxHeight: 420, overflowY: "auto", border: "1px solid var(--line)", borderRadius: "var(--r-md)" }}>
                    {notYet.map((s) => {
                      const other = parseAlloc(s.allocations);
                      return (
                        <label key={s.id} className="row row--top" style={{ padding: "6px 10px", borderBottom: "1px solid var(--line-2)", cursor: "pointer" }}>
                          <input type="checkbox" checked={picked.has(s.id)} onChange={(e) => { const n = new Set(picked); if (e.target.checked) n.add(s.id); else n.delete(s.id); setPicked(n); }} style={{ marginTop: 3 }} />
                          <span className="grow">
                            <strong>{s.surname}, {s.other_names}</strong> <span className="tnum sub2">{s.number}</span>
                            <div className="sub2">{s.programme} · {s.entry_mode === "DIRECT_ENTRY" ? "Direct Entry" : "UTME"}{other.length ? ` · this session: ${other.map((a) => `${a.block} ${a.posting}`).join(", ")}` : ""}</div>
                          </span>
                        </label>
                      );
                    })}
                  </div>
                ) : <div className="sub2">{students.length ? "Every student at this level is on this posting." : `No student of the College is at ${level} Level.`}</div>}
              </PBody>
            </Panel>

            <Panel title="Allocate the ticked students" right={`${picked.size} ticked`}>
              <PBody>
                <div className="stack">
                  {groups.length ? (
                    <Field id="po-group" label="Rotation group">
                      <select id="po-group" className="ctl" value={group} onChange={(e) => setGroup(e.target.value)}>
                        <option value="">No group</option>
                        {groups.map((g) => <option key={g.id} value={g.id}>Group {g.label}</option>)}
                      </select></Field>
                  ) : null}
                  <Field id="po-sup" label="Supervisor">
                    <SearchSelect id="po-sup" value={supervisor} allLabel="Not yet assigned" placeholder="Search the College's staff…"
                      options={supervisors.map((s) => ({ value: s.id, label: `${s.surname}, ${s.given_names} · ${s.dept_name}` }))} onChange={setSupervisor} /></Field>
                  <div className="row">
                    <div className="field" style={{ flex: "1 1 140px" }}><label htmlFor="po-from">Starts</label><input id="po-from" className="ctl" type="date" value={from} onChange={(e) => setFrom(e.target.value)} /></div>
                    <div className="field" style={{ flex: "1 1 140px" }}><label htmlFor="po-to">Ends</label><input id="po-to" className="ctl" type="date" value={to} onChange={(e) => setTo(e.target.value)} /></div>
                  </div>
                  <div className="sub2">The prospectus gives durations, never dates: {chosen.duration_weeks ? `this posting runs ${chosen.duration_weeks} weeks; ` : ""}the College dates it. A student already on the posting keeps their group, supervisor and dates unless these are filled.</div>
                  <Btn kind="primary" disabled={busy || !picked.size} onClick={() => void allocate()}>{busy ? "Allocating…" : `Allocate ${picked.size || ""} student${picked.size === 1 ? "" : "s"}`}</Btn>
                </div>
              </PBody>
            </Panel>
          </div>

          <Panel title={`On ${chosen.code} in ${session}`} right={`${allocations.length} allocated`}>
            {allocations.length ? (
              <DTable cols={["Matriculation number", "Name", "Group|mid", "Supervisor", "Starts|mid", "Ends|mid", "Standing|mid", "|num"]} rows={allocations.map((a) => [
                <span className="tnum" key="n">{a.number}</span>,
                <strong key="nm">{a.surname}, {a.other_names}</strong>,
                <span className="tnum" key="g">{a.group_label ?? "—"}</span>,
                <span className="sub2" key="s">{a.supervisor ?? "Not yet assigned"}</span>,
                <span className="tnum" key="f">{day(a.starts_on)}</span>,
                <span className="tnum" key="t">{day(a.ends_on)}</span>,
                <Pil key="st" kind={STATE[a.state]?.[0] ?? "grey"}>{STATE[a.state]?.[1] ?? a.state}</Pil>,
                <div key="a" className="row row--inline row--tight row--right">
                  {a.state === "ALLOCATED" ? <Btn kind="ghost" disabled={busy} onClick={() => void call("PUT", `/allocations/${a.id}`, { state: "IN_PROGRESS" }, `${a.number} began ${chosen.code}`)}>Begin</Btn> : null}
                  {a.state === "IN_PROGRESS" ? <Btn kind="go" disabled={busy} onClick={() => void call("PUT", `/allocations/${a.id}`, { state: "COMPLETED" }, `${a.number} completed ${chosen.code}`)}>Complete</Btn> : null}
                  {a.state === "IN_PROGRESS" ? <Btn kind="ghost" disabled={busy} onClick={() => { if (window.confirm(`Mark ${a.number}'s ${chosen.code} incomplete?`)) void call("PUT", `/allocations/${a.id}`, { state: "INCOMPLETE" }, `${a.number}'s ${chosen.code} marked incomplete`); }}>Incomplete</Btn> : null}
                  {a.state === "ALLOCATED" ? <Btn kind="ghost" disabled={busy} onClick={() => { if (window.confirm(`Withdraw ${a.number} from ${chosen.code}? Only an allocation that has not begun is withdrawn.`)) void call("DELETE", `/allocations/${a.id}`, null, `${a.number} withdrawn from ${chosen.code}`); }}>Withdraw</Btn> : null}
                </div>,
              ])} texts={allocations.map((a) => `${a.number} ${a.surname} ${a.other_names} ${a.group_label ?? ""} ${a.supervisor ?? ""} ${a.state}`)} />
            ) : <PBody><div className="sub2">Nobody is on this posting for {session} yet. Tick students on the left and allocate them.</div></PBody>}
          </Panel>
        </>
      )}
    </>
  );
}
