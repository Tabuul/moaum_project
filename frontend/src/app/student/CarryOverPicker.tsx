"use client";

/**
 * V663: ADD CARRY-OVER COURSES — every earlier course of the student, as the server reads it (registration.carry_over_candidates):
 * those a published result shows failed, those registered before with no result on the portal, those of the programme below the
 * student's level with no record here, and, under All previous courses, those cleared or already registered. Grouped by level and
 * semester, searched and filtered here (the student's own list, never the whole catalogue), ticked, and added at once: each course is
 * judged again and added on the server, by its id, and each is answered.
 */
import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify } from "@/components/proto/Toast";
import { Btn, Note, Pil, Tabs } from "@/components/proto/ui";
import { Field, Modal } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import {
  NO_FILTER, OWED, STATUS_KIND, STATUS_WORD, filterRows, groupRows, levelsOf, openingView, outcomeWords, selection, semesterWord,
  type CarryFilter, type CarryList, type CarryResult,
} from "@/lib/carry-over";

export function CarryOverPicker({ session, semester, onAdded, onClose, onViewRegistered, spillover = false }: {
  session: string; semester: number;
  /** V674: a spillover student: the courses of their own level are listed with the earlier ones, and every course they add is a carry-over */
  spillover?: boolean;
  /** the classes the courses were added by: the draft's selection keeps them */
  onAdded: (offerings: string[]) => void;
  onClose: () => void;
  onViewRegistered: () => void;
}) {
  const router = useRouter();
  const [list, setList] = useState<CarryList | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [f, setF] = useState<CarryFilter>(NO_FILTER);
  const [picked, setPicked] = useState<Set<string>>(new Set());
  const [closed, setClosed] = useState<Set<number>>(new Set());
  const [busy, setBusy] = useState(false);
  const [results, setResults] = useState<CarryResult[] | null>(null);

  useEffect(() => {
    let live = true;
    fetch(`/api/bff/api/v1/me/registration/carry-overs?session=${encodeURIComponent(session)}&semester=${semester}`, { cache: "no-store" })
      .then(async (r) => {
        const j = await r.json().catch(() => null);
        if (!live) return;
        if (!r.ok) { setProblem(j ?? { status: r.status, title: "Your earlier courses could not be read" }); return; }
        const data = j as CarryList;
        setList(data);
        setF((x) => ({ ...x, view: openingView(data.rows) }));
      })
      .catch(() => { if (live) setProblem({ status: 0, title: "Your earlier courses could not be read", detail: "Check your connection and open it again." }); });
    return () => { live = false; };
  }, [session, semester]);

  const rows = useMemo(() => list?.rows ?? [], [list]);
  const shown = useMemo(() => filterRows(rows, f), [rows, f]);
  const groups = useMemo(() => groupRows(shown), [shown]);
  const sel = selection(rows, picked);
  const owedCount = rows.filter((r) => OWED.includes(r.status)).length;
  const toggle = (id: string) => setPicked((s) => { const x = new Set(s); if (x.has(id)) x.delete(id); else x.add(id); return x; });

  async function add() {
    if (!sel.count || busy) return;
    setBusy(true);
    setProblem(null);
    try {
      const courses = rows.filter((r) => picked.has(r.course_id) && r.selectable).map((r) => r.course_id);
      const r = await fetch("/api/bff/api/v1/me/registration/carry-overs", {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`${courses.length} carry-over course${courses.length === 1 ? "" : "s"} added by the student`) },
        body: JSON.stringify({ session, semester, courses }),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) {
        setProblem(j ?? { status: r.status, title: "The carry-overs could not be added" });
        return;
      }
      const res = (j?.results ?? []) as CarryResult[];
      setResults(res);
      const offerings = res.filter((x) => x.added && x.offering).map((x) => String(x.offering));
      if (offerings.length) onAdded(offerings);
      const w = outcomeWords(res);
      notify(w.title, w.kind === "ok" ? undefined : "bad");
      router.refresh();
    } finally {
      setBusy(false);
    }
  }

  const sub = list ? `${list.student.name} · ${list.student.matricNo ?? ""} · ${list.student.programme ?? ""} · ${list.student.level} Level · ${list.session} · ${semesterWord(list.semester)} Semester` : undefined;

  if (results) {
    const w = outcomeWords(results);
    return (
      <Modal title="ADD CARRY-OVER COURSES" sub={sub} wide onClose={onClose}
        foot={<><Btn kind="ghost" onClick={onClose}>CLOSE</Btn><Btn kind="primary" onClick={() => { onClose(); onViewRegistered(); }}>VIEW REGISTERED COURSES</Btn></>}>
        <Note kind={w.kind === "ok" ? "ok" : "bad"} title={w.kind === "ok" ? "Carry-over courses added successfully." : w.title}>
          {w.kind === "ok" ? w.title : "The courses added are on your registration; the others are listed with the reason."}
        </Note>
        <div className="mt-2">
          {results.map((x) => (
            <div key={x.courseId} className="row" style={{ gap: 10, padding: "8px 0", borderBottom: "1px solid var(--line)", alignItems: "flex-start", flexWrap: "wrap" }}>
              <Pil kind={x.added ? "ok" : "bad"}>{x.added ? "ADDED" : "NOT ADDED"}</Pil>
              <div className="grow" style={{ minWidth: 200 }}>
                <div className="b600 tnum">{x.courseCode ?? ""} <span className="b400">{x.title ?? ""}</span></div>
                {!x.added ? <div className="sub2" style={{ color: "var(--red-deep)" }}>{x.message ?? "It could not be added."}</div> : null}
              </div>
              {x.units != null ? <span className="tnum b600">{x.units} CU</span> : null}
            </div>
          ))}
        </div>
      </Modal>
    );
  }

  return (
    <Modal title="ADD CARRY-OVER COURSES" sub={sub} wide onClose={() => { if (!busy) onClose(); }}
      foot={
        <>
          <span className="sub2 tnum grow">Selected Carry-Over Courses: <b>{sel.count}</b> · Total Units: <b>{sel.units} CU</b></span>
          <Btn kind="ghost" disabled={busy} onClick={onClose}>CLOSE</Btn>
          <Btn kind="urgent" disabled={!sel.count || busy} busy={busy} busyLabel="ADDING CARRY-OVER COURSES..." onClick={() => void add()}>ADD SELECTED CARRY-OVERS</Btn>
        </>
      }>
      {problem ? <ProblemNotice problem={problem} /> : null}
      {!list && !problem ? <div className="sub2">Reading your earlier courses…</div> : null}
      {list ? (
        <>
          <div className="sub2 mb-2">{spillover
            ? "In spillover you register only the courses you still owe — of your level and the levels before it. Each course you add is registered as a carry-over, and the semester's spillover fee is then owed."
            : "Select courses from previous levels that you have not cleared."}</div>
          <Tabs label="Which courses" value={f.view} onChange={(v) => setF({ ...f, view: v })}
            items={[{ id: "OUTSTANDING", label: "ONLY OUTSTANDING", count: owedCount }, { id: "ALL", label: spillover ? "ALL YOUR COURSES" : "ALL PREVIOUS COURSES", count: rows.length }]} />
          <div className="row mt-2" style={{ flexWrap: "wrap", gap: "var(--s-2)", alignItems: "flex-end" }}>
            <Field id="co-q" label="Search" style={{ flex: "1 1 220px" }}>
              <input id="co-q" className="ctl" value={f.q} maxLength={60} placeholder="Course code, title, level or semester" onChange={(e) => setF({ ...f, q: e.target.value })} />
            </Field>
            <Field id="co-level" label="Level">
              <select id="co-level" className="ctl" value={f.level ?? ""} onChange={(e) => setF({ ...f, level: e.target.value ? Number(e.target.value) : null })}>
                <option value="">All levels</option>
                {levelsOf(rows).map((l) => <option key={l} value={l}>{l} Level</option>)}
              </select>
            </Field>
            <Field id="co-sem" label="Semester">
              <select id="co-sem" className="ctl" value={f.semester ?? ""} onChange={(e) => setF({ ...f, semester: e.target.value ? Number(e.target.value) : null })}>
                <option value="">Both semesters</option><option value="1">First Semester</option><option value="2">Second Semester</option>
              </select>
            </Field>
            <Field id="co-group" label="Type">
              <select id="co-group" className="ctl" value={f.group} onChange={(e) => setF({ ...f, group: e.target.value as CarryFilter["group"] })}>
                <option value="">All courses</option><option value="GST">GST</option><option value="EPS">EPS</option><option value="OTHER">Other</option>
              </select>
            </Field>
          </div>
          {f.view === "OUTSTANDING" && !rows.some((r) => r.status === "OUTSTANDING") && owedCount ? (
            <div className="sub2 mt-2">No published result on the portal shows a course you failed. Your earlier results may be on the old portal: tick a course only if you did not pass it.</div>
          ) : null}
          {groups.length ? groups.map((g) => {
            const open = !closed.has(g.level);
            const owed = g.semesters.reduce((n, s) => n + s.rows.filter((r) => r.selectable).length, 0);
            return (
              <div key={g.level} className="mt-2" style={{ border: "1px solid var(--line)", borderRadius: 8 }}>
                <button type="button" className="row" aria-expanded={open}
                  style={{ width: "100%", padding: "10px 12px", background: "var(--bg)", border: 0, borderRadius: 8, cursor: "pointer", justifyContent: "space-between" }}
                  onClick={() => setClosed((c) => { const x = new Set(c); if (x.has(g.level)) x.delete(g.level); else x.add(g.level); return x; })}>
                  <b>{g.level} LEVEL</b>
                  <span className="sub2">{owed} to add · {g.semesters.reduce((n, s) => n + s.rows.length, 0)} listed {open ? "▲" : "▼"}</span>
                </button>
                {open ? g.semesters.map((s) => (
                  <div key={s.semester} style={{ padding: "4px 12px 8px" }}>
                    <div className="t-xs b700 sub2 mt-1">{semesterWord(s.semester).toUpperCase()} SEMESTER</div>
                    {s.rows.map((r) => {
                      const on = picked.has(r.course_id);
                      return (
                        <label key={r.course_id} className="row" style={{ gap: 10, padding: "8px 0", borderBottom: "1px solid var(--line)", alignItems: "flex-start", flexWrap: "wrap",
                          cursor: r.selectable ? "pointer" : "default", opacity: r.selectable ? 1 : 0.75 }}>
                          <input type="checkbox" checked={on && r.selectable} disabled={!r.selectable || busy} onChange={() => toggle(r.course_id)}
                            aria-label={`Select ${r.shown_code} ${r.title}`} style={{ marginTop: 3, width: 18, height: 18 }} />
                          <div className="grow" style={{ minWidth: 200 }}>
                            <div><b className="tnum">{r.shown_code}</b> — {r.title}</div>
                            <div className="sub2">{r.level} Level · {semesterWord(r.course_semester)} Semester{r.both_semesters ? " (both semesters)" : ""}
                              {r.origin_session ? ` · last registered ${r.origin_session}` : ""}{r.last_grade ? ` · grade ${r.last_grade}` : ""}</div>
                            {r.reason ? <div className="sub2" style={!r.selectable && OWED.includes(r.status) ? { color: "var(--red-deep)" } : undefined}>{r.reason}</div> : null}
                          </div>
                          <Pil kind={STATUS_KIND[r.status]}>{STATUS_WORD[r.status]}</Pil>
                          <span className="tnum b600" style={{ minWidth: 44, textAlign: "right" }}>{r.units} CU</span>
                        </label>
                      );
                    })}
                  </div>
                )) : null}
              </div>
            );
          }) : (
            <div className="sub2 mt-2">
              {f.view === "OUTSTANDING" && rows.length ? "No outstanding course. Choose ALL PREVIOUS COURSES to see every earlier course."
                : rows.length ? "No course matches the search." : "You have no earlier course to carry over."}
            </div>
          )}
        </>
      ) : null}
    </Modal>
  );
}
