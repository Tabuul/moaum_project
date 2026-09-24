"use client";
/** Programme structure: what a programme offers at each level and semester (catalogue.course_offer), the
 *  units each semester carries against the level's limits, and — for the programme's own department —
 *  the binding of a course into the structure and its removal. Registration reads these rows, so a
 *  course missing here is a course no student of the programme sees. */
import { useRef, useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { useQueryNav } from "@/lib/query-nav";
import { notify } from "@/components/proto/Toast";
import { Btn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { SearchSelect } from "@/components/proto/SearchSelect";
import { ProblemNotice } from "@/components/ProblemNotice";

export interface ProgrammeOption { code: string; name: string; dept_code: string | null; department_name: string | null; faculty_name: string; archived: boolean }
export interface StructureRow { level: number; semester: number | null; code: string; title: string; units: number; kind: string; state: string; dept_code: string; dept_name: string | null; basis: string; track: string | null; ca_max: number }
export interface StructureData {
  programme: { code: string; name: string; dept_code: string | null; dept_name: string | null; faculty_code: string };
  rows: StructureRow[];
  limits: { level: number; min_units: number; max_units: number }[];
  tracks: { code: string; name: string }[];
}
interface Found { code: string; title: string; units: number; semester: number | null; level: number; kind: string; dept_code: string; dept_name: string | null }

const BASES = ["Core", "Elective", "Borrowed", "GST"];
const LEVELS = [100, 200, 300, 400, 500, 600];
const semName = (n: number | null) => (n === 1 ? "First semester" : n === 2 ? "Second semester" : n === 3 ? "Third semester" : "Semester not set");

export function Structure({ programmes, prog, data, problem, may }: { programmes: ProgrammeOption[]; prog: string; data: StructureData | null; problem: Problem | null; may: boolean }) {
  const router = useRouter();
  const go = useQueryNav();
  const [track, setTrack] = useState("");
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<Problem | null>(null);
  // the picker: a course anywhere in the University, by code or title
  const [q, setQ] = useState("");
  const [found, setFound] = useState<Found[]>([]);
  const [pick, setPick] = useState<Found | null>(null);
  const [f, setF] = useState({ level: "100", basis: "Core", track: "" });
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);

  const rows = data ? data.rows.filter((r) => !track || !r.track || r.track === track) : [];
  const levels = LEVELS.filter((l) => rows.some((r) => r.level === l));
  const limitOf = (level: number) => data?.limits.find((l) => Number(l.level) === level);
  const ownDept = data?.programme.dept_code ?? null;

  function search(text: string) {
    setQ(text);
    setPick(null);
    if (timer.current) clearTimeout(timer.current);
    if (text.trim().length < 2) { setFound([]); return; }
    timer.current = setTimeout(() => {
      void fetch(`/api/bff/api/v1/catalogue/courses/search?q=${encodeURIComponent(text.trim())}`).then(async (r) => {
        if (!r.ok) return;
        const j = (await r.json().catch(() => [])) as Found[];
        setFound(Array.isArray(j) ? j : []);
      });
    }, 250);
  }

  async function call(method: "POST" | "DELETE", path: string, body: unknown, reason: string): Promise<boolean> {
    setBusy(true);
    setErr(null);
    try {
      const r = await fetch(`/api/bff/api/v1/catalogue${path}`, {
        method, headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: method === "DELETE" ? undefined : JSON.stringify(body),
      });
      if (!r.ok) { setErr((await r.json().catch(() => null)) ?? { status: r.status, title: r.statusText }); return false; }
      notify(reason);
      router.refresh();
      return true;
    } finally {
      setBusy(false);
    }
  }

  async function bind() {
    if (!pick || !data) return;
    const ok = await call("POST", "/structure/bind", { programme: data.programme.code, course: pick.code, level: Number(f.level), basis: f.basis, track: f.track || null },
      `${pick.code} bound into ${data.programme.code} at ${f.level} level as ${f.basis}${f.track ? ` (${f.track})` : ""}`);
    if (ok) { setPick(null); setQ(""); setFound([]); }
  }

  function unbind(r: StructureRow) {
    if (!data) return;
    if (!window.confirm(`Remove ${r.code} from ${data.programme.code} at ${r.level} level? Students of the programme at that level will no longer see it at registration.`)) return;
    void call("DELETE", `/structure/bind?programme=${encodeURIComponent(data.programme.code)}&course=${encodeURIComponent(r.code)}&level=${r.level}`, null,
      `${r.code} removed from ${data.programme.code} at ${r.level} level`);
  }

  const total = rows.length;
  const borrowed = rows.filter((r) => ownDept && r.dept_code !== ownDept).length;
  const unplaced = rows.filter((r) => r.semester == null).length;

  return (
    <>
      <div className="scope">
        <div className="scope__f" style={{ flex: "2 1 320px" }}><label htmlFor="st-prog">Programme</label>
          <SearchSelect id="st-prog" value={prog} placeholder="Search a programme…" options={programmes.map((p) => ({ value: p.code, label: `${p.name} · ${p.code}${p.department_name ? ` · ${p.department_name}` : ""}` }))}
            onChange={(v: string) => go(`/catalogue/structure?prog=${encodeURIComponent(v)}`)} /></div>
        <div className="scope__f"><label htmlFor="st-track">Track</label>
          <select id="st-track" className="ws__select" value={track} onChange={(e) => setTrack(e.target.value)}>
            <option value="">Every track</option>
            {(data?.tracks ?? []).map((t) => <option key={t.code} value={t.code}>{t.code} — {t.name}</option>)}
          </select></div>
      </div>
      {problem ? <ProblemNotice problem={problem} /> : null}
      {err ? <ProblemNotice problem={err} /> : null}
      {!data ? (
        <Note kind="info" title="Choose a programme">The structure is one programme&rsquo;s: every course it offers, at each level and semester, and what the structure says the course is to its students.</Note>
      ) : (
        <>
          <Tiles items={[
            ["Courses bound", String(total), null, `${data.programme.name}`],
            ["Levels", String(levels.length), null, levels.length ? levels.join(", ") + " level" : "Nothing bound yet"],
            ["Borrowed", String(borrowed), borrowed ? "var(--chrome)" : null, "Owned by another department"],
            ["Without a semester", String(unplaced), unplaced ? "var(--red-ink)" : null, unplaced ? "Fix the course's semester on its department's desk" : "Every course says which semester"],
          ]} />
          <Note kind="info" title="Registration reads this structure">
            A student of {data.programme.code} at a level sees, at registration, the courses bound here at that level for their track (a course bound for every track is seen by all). A course missing here is a course no student of the programme can register; a course bound as Elective is an elective to them even where it is core in its own department, and a failed elective is not carried over.
          </Note>
          {may ? (
            <Panel title="Bind a course into the structure" right={`${data.programme.name} · ${data.programme.dept_name ?? ""}`}>
              <PBody>
                <div className="row row--end">
                  <div className="field" style={{ flex: "2 1 280px", position: "relative" }}><label htmlFor="st-find">Course — any department, by code or title</label>
                    <input id="st-find" className="ctl" value={pick ? `${pick.code} — ${pick.title}` : q} onChange={(e) => search(e.target.value)} placeholder="e.g. GST 111, or Use of English" autoComplete="off" />
                    {found.length && !pick ? (
                      <div style={{ position: "absolute", zIndex: 5, left: 0, right: 0, top: "100%", background: "var(--bg, #fff)", border: "1px solid var(--line)", borderRadius: 8, maxHeight: 260, overflowY: "auto", boxShadow: "0 8px 24px rgba(0,0,0,.12)" }}>
                        {found.map((c) => (
                          <button key={c.code} type="button" style={{ display: "block", width: "100%", textAlign: "left", padding: "6px 10px", border: 0, background: "transparent", cursor: "pointer" }}
                            onClick={() => { setPick(c); setF({ ...f, level: String(c.level || f.level), basis: c.kind === "GST" ? "GST" : ownDept && c.dept_code !== ownDept ? "Borrowed" : c.kind === "Elective" ? "Elective" : "Core" }); }}>
                            <strong className="tnum">{c.code}</strong> <span>{c.title}</span> <span className="sub2">· {c.units} units · {c.level} level · {semName(c.semester)} · {c.dept_name ?? c.dept_code}</span>
                          </button>
                        ))}
                      </div>
                    ) : null}
                  </div>
                  <div className="field" style={{ width: 110 }}><label htmlFor="st-level">Level</label>
                    <select id="st-level" className="ctl" value={f.level} onChange={(e) => setF({ ...f, level: e.target.value })}>{LEVELS.map((l) => <option key={l} value={String(l)}>{l}</option>)}</select></div>
                  <div className="field" style={{ width: 130 }}><label htmlFor="st-basis">Basis</label>
                    <select id="st-basis" className="ctl" value={f.basis} onChange={(e) => setF({ ...f, basis: e.target.value })}>{BASES.map((b) => <option key={b} value={b}>{b}</option>)}</select></div>
                  <div className="field" style={{ width: 170 }}><label htmlFor="st-btrack">Track</label>
                    <select id="st-btrack" className="ctl" value={f.track} onChange={(e) => setF({ ...f, track: e.target.value })}>
                      <option value="">Every track</option>
                      {data.tracks.map((t) => <option key={t.code} value={t.code}>{t.code}</option>)}
                    </select></div>
                  <Btn kind="primary" disabled={busy || !pick} onClick={() => void bind()}>{busy ? "Binding…" : "Bind the course"}</Btn>
                </div>
                <div className="sub2 mt-2">Basis: <b>Core</b> the programme requires it; <b>Elective</b> the student chooses it and a failure is not carried; <b>Borrowed</b> another department owns it; <b>GST</b> a University requirement. A binding for a track is seen by that track&rsquo;s students only.</div>
              </PBody>
            </Panel>
          ) : null}
          {levels.length === 0 ? (
            <Note kind="bad" title="Nothing is bound to this programme">No student of {data.programme.code} sees any course at registration until courses are bound here — upload the structure on Department courses, or bind them one by one above.</Note>
          ) : levels.map((level) => {
            const lim = limitOf(level);
            const sems = [1, 2, 3, null].filter((s) => rows.some((r) => r.level === level && (r.semester ?? null) === s));
            return (
              <Panel key={level} title={`${level} Level`} right={lim ? `Limits ${lim.min_units}–${lim.max_units} units a semester` : "No unit limit set for this level"}>
                {sems.map((s) => {
                  const list = rows.filter((r) => r.level === level && (r.semester ?? null) === s);
                  const units = list.reduce((n, r) => n + Number(r.units), 0);
                  const coreUnits = list.filter((r) => r.basis === "Core" || r.basis === "GST").reduce((n, r) => n + Number(r.units), 0);
                  const over = lim && coreUnits > lim.max_units;
                  const under = lim && units < lim.min_units;
                  return (
                    <div key={String(s)} style={{ padding: "0 0 8px" }}>
                      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline", padding: "10px 14px 4px", gap: 10, flexWrap: "wrap" }}>
                        <strong>{semName(s)}</strong>
                        <span className="sub2 tnum" style={over || under ? { color: "var(--red-ink)", fontWeight: 600 } : undefined}>
                          {units} units bound · {coreUnits} core/GST{lim ? over ? ` — core alone exceeds the ${lim.max_units}-unit maximum` : under ? ` — under the ${lim.min_units}-unit minimum even with every course` : "" : ""}
                        </span>
                      </div>
                      <DTable cols={["Code|mid", "Title", "Units|mid", "Basis|mid", "Track|mid", "Owner", "State|mid", ...(may ? ["|num"] : [])]} rows={list.map((r) => [
                        <strong className="tnum" key="c">{r.code}</strong>,
                        <span key="t">{r.title}</span>,
                        <span className="tnum" key="u">{r.units}</span>,
                        <Pil key="b" kind={r.basis === "Core" ? "info" : r.basis === "GST" ? "ok" : "grey"}>{r.basis}</Pil>,
                        <span className="sub2 tnum" key="tr">{r.track ?? "every track"}</span>,
                        <span className="sub2" key="o" style={ownDept && r.dept_code !== ownDept ? { color: "var(--chrome)" } : undefined}>{r.dept_name ?? r.dept_code}</span>,
                        <Pil key="s" kind={r.state === "LIVE" ? "ok" : r.state === "ENDED" ? "bad" : "warn"}>{r.state === "LIVE" ? "Live" : r.state === "BOARD" ? "At the Board" : r.state === "SENATE" ? "At Senate" : r.state}</Pil>,
                        ...(may ? [<Btn key="x" kind="ghost" disabled={busy} onClick={() => unbind(r)}>Remove</Btn>] : []),
                      ])} texts={list.map((r) => `${r.code} ${r.title} ${r.basis} ${r.track ?? ""} ${r.dept_name ?? ""}`)} />
                    </div>
                  );
                })}
              </Panel>
            );
          })}
        </>
      )}
    </>
  );
}
