"use client";

/**
 * Add Other Course (V504): the student finds a course that is not on the recommended list — a course of the programme at another
 * level, an elective, a University-wide GST/EPS course, or the department's or faculty's where the Academic Office allows it — and
 * adds it. The server finds and judges every course (registration.course_check): the category it would be registered in and why,
 * or why it is not available (already passed, result pending, not offered this semester, a higher level, a prerequisite, not part
 * of the programme…). Opened, it lists the student's own courses (V507: the programme's at every level, the University GST/EPS
 * courses, the carry-overs), a level or category narrowing them; a code or title, or a department, searches every course. Only the
 * page the server returns is loaded.
 */
import { useEffect, useRef, useState } from "react";
import type { CourseSearch, FoundCourse } from "@/lib/student-portal";
import { CATEGORIES, CATEGORY_LABEL, addedAsLabel, courseStatus, refusalText, searchQuery, unitsAfter } from "@/lib/course-order";
import { Btn, LinkBtn, Note, Pil } from "@/components/proto/ui";
import { Field, Modal } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { useAct } from "./common";

interface Dept { code: string; name: string; faculty_code: string | null; faculty: string | null }

const LEVELS = [100, 200, 300, 400, 500, 600, 700, 800, 900];

/** what the list holds: the student's own courses (V507) or every course the search found, and how many */
const OWN: Record<string, string> = {
  "": "Your programme's courses, the University GST/EPS courses and your carry-overs",
  CARRY_OVER: "Your carry-overs — failed on a published result, or registered in an earlier session with no result on the portal",
  GST: "GST and EPS courses — your programme's and the University's",
  CORE: "Core courses of your programme",
  ELECTIVE: "Electives of your programme",
};

function listWords(found: CourseSearch, from: number, to: number, cat: string | null): string {
  const range = `${from}–${to} of ${found.total.toLocaleString("en-GB")}, the ones you can add first`;
  if (found.listed === "YOUR_COURSES") {
    if (found.total) return `${OWN[cat ?? ""] ?? OWN[""]}: ${range}. Type a code or title, or choose a department, to search every course.`;
    return cat === "CARRY_OVER" ? "You have no carry-over to add: no published result shows a course failed and not since passed, and no course of an earlier session waits without a result on the portal."
      : "None of these has a class this session. Type a code or title, or choose a department, to search every course.";
  }
  return found.total ? `Courses ${range}.` : "No course matches the search.";
}

export function AddOtherCourse({ session, semester, level, total, max, addDrop, onAdded, onClose, initialCategory }: {
  session: string; semester: number; level: number; total: number; max: number;
  /** the registration is submitted or approved: the course is added by add and drop */
  addDrop: boolean;
  onAdded: (offeringId: string) => void; onClose: () => void;
  /** V611: opened from Carry-over courses — the student's carry-overs first (the category can still be changed) */
  initialCategory?: string | null;
}) {
  const { act, busy, problem } = useAct();
  const [q, setQ] = useState("");
  const [lvl, setLvl] = useState<number | null>(null);
  const [dept, setDept] = useState<string | null>(null);
  const [cat, setCat] = useState<string | null>(initialCategory ?? null);
  const carryMode = initialCategory === "CARRY_OVER";
  const [page, setPage] = useState(0);
  const [found, setFound] = useState<CourseSearch | null>(null);
  const [loading, setLoading] = useState(false);
  const [failed, setFailed] = useState<string | null>(null);
  const [depts, setDepts] = useState<Dept[]>([]);
  const [units, setUnits] = useState(total);
  const asked = useRef(0);

  useEffect(() => {
    let live = true;
    fetch("/api/bff/api/v1/me/registration/courses/filters", { cache: "no-store" })
      .then((r) => (r.ok ? r.json() : null)).then((j) => { if (live && j) setDepts(j.departments ?? []); }).catch(() => undefined);
    return () => { live = false; };
  }, []);

  async function search(p: number) {
    const n = ++asked.current;
    setLoading(true);
    setFailed(null);
    try {
      const r = await fetch(`/api/bff/api/v1/me/registration/courses?${searchQuery({ session, semester, q, level: lvl, dept, category: cat, page: p })}`, { cache: "no-store" });
      const j = await r.json().catch(() => null);
      if (n !== asked.current) return;   // a later search has been asked for
      if (!r.ok) { setFailed((j && (j.detail || j.title)) || "The search did not go through"); return; }
      setFound(j as CourseSearch);
    } catch {
      if (n === asked.current) setFailed("The search did not go through; try again.");
    } finally {
      if (n === asked.current) setLoading(false);
    }
  }

  // the search runs as the student types (a pause of a third of a second), and at once when a filter changes
  useEffect(() => {
    const t = window.setTimeout(() => { setPage(0); void search(0); }, 350);
    return () => window.clearTimeout(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [q, lvl, dept, cat]);

  async function add(c: FoundCourse) {
    if (!c.offering_id) return;
    const j = await act(`addother-${c.offering_id}`, "POST", "/me/registration/courses", { session, semester, offering: c.offering_id },
      `Course ${c.course_code} added by the student beside the recommended list`, `${c.course_code} added`);
    if (j) {
      onAdded(c.offering_id);
      setUnits((u) => u + Number(c.units || 0));
      void search(page);
    }
  }

  const rows = found?.results ?? [];
  const from = found && found.total ? found.page * found.size + 1 : 0;
  const to = found ? Math.min(found.total, (found.page + 1) * found.size) : 0;
  const closed = found && !found.flex.allow_other_courses;

  return (
    <Modal wide title={carryMode ? "ADD CARRY-OVER COURSE" : "ADD OTHER COURSE"} onClose={onClose}
      sub={carryMode
        ? `Your courses to carry over into ${session}, ${semester === 1 ? "first" : semester === 2 ? "second" : "third"} semester: those a published result shows failed, and those you registered in an earlier session whose result is not on the portal (the old portal's). Add only a course you failed — it is marked as a carry-over you declared, and your department sees it.`
        : `Find a course beside your recommended list for ${session}, ${semester === 1 ? "first" : semester === 2 ? "second" : "third"} semester. The University's rules decide whether it can be added.`}
      foot={<Btn kind="ghost" onClick={onClose}>Done</Btn>}>
      <form className="row row--inline" style={{ gap: 8, flexWrap: "wrap", alignItems: "flex-end" }} onSubmit={(e) => { e.preventDefault(); setPage(0); void search(0); }}>
        <div style={{ flex: "2 1 260px" }}>
          <Field id="aoc-q" label="Search by course code or title">
            <input id="aoc-q" className="ctl" value={q} maxLength={60} autoFocus onChange={(e) => setQ(e.target.value)} placeholder="e.g. ECO 211 or Statistics" />
          </Field>
        </div>
        <div style={{ flex: "1 1 110px" }}>
          <Field id="aoc-l" label="Level">
            <select id="aoc-l" className="ctl" value={lvl ?? ""} onChange={(e) => setLvl(e.target.value ? Number(e.target.value) : null)}>
              <option value="">Any level</option>
              {LEVELS.map((l) => <option key={l} value={l}>{l} Level{l === level ? " (yours)" : ""}</option>)}
            </select>
          </Field>
        </div>
        <div style={{ flex: "1 1 200px" }}>
          <Field id="aoc-d" label="Department">
            <select id="aoc-d" className="ctl" value={dept ?? ""} onChange={(e) => setDept(e.target.value || null)}>
              <option value="">Any department</option>
              {depts.map((d) => <option key={d.code} value={d.code}>{d.name}{d.faculty ? ` — ${d.faculty}` : ""}</option>)}
            </select>
          </Field>
        </div>
        <div style={{ flex: "1 1 130px" }}>
          <Field id="aoc-c" label="Category">
            <select id="aoc-c" className="ctl" value={cat ?? ""} onChange={(e) => setCat(e.target.value || null)}>
              <option value="">Any category</option>
              {CATEGORIES.map((c) => <option key={c} value={c}>{CATEGORY_LABEL[c]}</option>)}
            </select>
          </Field>
        </div>
      </form>
      {closed && cat !== "CARRY_OVER" ? <div className="mt-2"><Note kind="info" title="Adding other courses is closed for now">The Academic Office has closed adding courses beside the recommended list. Your carry-overs and the courses listed for your level are registered as before; ask your department about any other course.</Note></div> : null}
      {problem && problem.code === "GST_PAYMENT_REQUIRED" ? (
        <div className="mt-2"><Note kind="bad" title="GST/EPS PAYMENT REQUIRED" action={<LinkBtn kind="primary" href={`/student/gst?session=${encodeURIComponent(session)}`}>PAY GST/EPS FEE</LinkBtn>}>
          {problem.detail} Once the payment is confirmed, come back here and register the course — no ICT Support needed.</Note></div>
      ) : problem ? <div className="mt-2"><ProblemNotice problem={problem} /></div> : null}
      {rows.some((c) => c.gstHeld && !c.refusal) && !(problem && problem.code === "GST_PAYMENT_REQUIRED") ? (
        <div className="mt-2"><Note kind="bad" title="GST/EPS PAYMENT REQUIRED" action={<LinkBtn kind="primary" href={`/student/gst?session=${encodeURIComponent(session)}`}>PAY GST/EPS FEE</LinkBtn>}>
          A GST or EPS course — a carry-over too — is registered only once your GST/EPS fee is paid and confirmed. One payment covers GST and EPS.</Note></div>
      ) : null}
      {failed ? <div className="mt-2"><Note kind="bad" title={failed} /></div> : null}
      <div className="sub2 mt-2" aria-live="polite">
        {loading ? "Searching..." : found ? listWords(found, from, to, cat) : null}
        {` Your registration: ${units} unit${units === 1 ? "" : "s"}, maximum ${max}.`}{addDrop ? " Your registration is submitted: a course is added by add and drop." : ""}
      </div>
      {rows.length ? (
        <div className="tablewrap mt-2" tabIndex={0}><table className="tbl--data" style={{ minWidth: 760 }}>
          <thead><tr>
            <th>Course code</th><th>Course title</th><th className="mid">Units</th><th className="mid">Level</th><th className="mid">Semester</th>
            <th>Department</th><th>Category</th><th>Status</th><th className="num" />
          </tr></thead>
          <tbody>
            {rows.map((c) => {
              const st = courseStatus(c);
              const after = unitsAfter(units, Number(c.units || 0), max);
              const key = `addother-${c.offering_id}`;
              return (
                <tr key={c.course_code}>
                  <td className="tnum b600">{c.course_code}</td>
                  <td>{c.title}
                    <div className="sub2">{c.refusal ? refusalText(c.refusal) : [c.why, c.added_as === "CARRY_OVER_DECLARED" ? null : addedAsLabel(c.added_as)].filter(Boolean).join(" · ")}{c.recommended ? " · on your recommended list" : ""}</div>
                    {st.ok && after.over ? <div className="sub2 ink-red">Adding it takes you to {after.total} units, over the maximum of {max}.</div> : null}
                  </td>
                  <td className="mid tnum">{c.units}</td>
                  <td className="mid tnum">{c.level}</td>
                  <td className="mid tnum">{c.course_semester === 1 ? "First" : c.course_semester === 2 ? "Second" : c.course_semester ?? "—"}</td>
                  <td className="sub2">{c.department ?? c.dept_code ?? "—"}</td>
                  <td>{c.category ? <Pil kind={c.category === "CARRY_OVER" ? "bad" : c.category === "GST" ? "info" : "grey"}>{CATEGORY_LABEL[c.category]}</Pil> : "—"}</td>
                  <td><Pil kind={st.ok ? "ok" : st.label === "Already added" || st.label === "Added automatically" ? "info" : "warn"}>{st.label}</Pil></td>
                  <td className="num">
                    <Btn kind="primary" size="sm" disabled={!st.ok || after.over || !c.offering_id || busy !== null} busy={busy === key} busyLabel="Adding..."
                      onClick={() => void add(c)}>ADD COURSE</Btn>
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table></div>
      ) : null}
      {found && found.total > found.size ? (
        <div className="row mt-2" style={{ gap: 8 }}>
          <Btn kind="ghost" size="sm" disabled={loading || page === 0} onClick={() => { const p = page - 1; setPage(p); void search(p); }}>Previous</Btn>
          <Btn kind="ghost" size="sm" disabled={loading || to >= found.total} onClick={() => { const p = page + 1; setPage(p); void search(p); }}>Next</Btn>
        </div>
      ) : null}
    </Modal>
  );
}
