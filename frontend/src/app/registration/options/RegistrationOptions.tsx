"use client";

/**
 * Course registration options (V504): whether students add courses beside their recommended list (ON by default), how wide — their
 * programme's other levels and electives with the University GST/EPS courses, or their department's or faculty's courses too — and
 * whether a course of a higher level than the student's may be added (OFF by default). Set with a reason, on the audit trail. The
 * engine judges every course a student adds (already passed, result pending, not offered this semester, prerequisites, the GST
 * fee…) whatever is set here, and the automatic approval judges it again. V590: whether every curriculum's courses (BMAS, CCMAS) are
 * open to every student whatever the cohort's track — ON from V590 — set with a reason the same way.
 */
import { useState } from "react";
import { useRouter } from "next/navigation";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, Note, Panel, PBody, Pil } from "@/components/proto/ui";
import { Field } from "@/components/proto/blocks";

export interface FlexState {
  allow_other_courses: boolean; other_scope: "PROGRAMME" | "DEPARTMENT" | "FACULTY"; allow_higher_levels: boolean;
  /** V590: every curriculum's courses open to every student, whatever the cohort's track */
  curriculum_open: boolean;
  reason: string | null; set_at: string | null; set_by: string | null; set_office: string | null;
}

const SCOPE: Record<FlexState["other_scope"], string> = {
  PROGRAMME: "The student's programme (other levels, electives) and the University GST/EPS courses",
  DEPARTMENT: "Also the courses of the student's department",
  FACULTY: "Also the courses of the student's faculty",
};

const when = (iso: string | null) => (iso ? new Date(iso).toLocaleString("en-GB", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" }) : "—");

export function RegistrationOptions({ flex, mayChange }: { flex: FlexState; mayChange: boolean }) {
  const router = useRouter();
  const [form, setForm] = useState({ allow: flex.allow_other_courses, scope: flex.other_scope, higher: flex.allow_higher_levels, open: flex.curriculum_open, reason: "" });
  const flexChanged = form.allow !== flex.allow_other_courses || form.scope !== flex.other_scope || form.higher !== flex.allow_higher_levels;
  const openChanged = form.open !== flex.curriculum_open;
  const changed = flexChanged || openChanged;

  async function put(path: string, body: unknown) {
    const r = await fetch(`/api/bff/api/v1/registration/flex${path}`, {
      method: "PUT",
      headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Course registration options set: ${form.reason.trim()}`) },
      body: JSON.stringify(body),
    });
    const j = await r.json().catch(() => null);
    if (!r.ok) { notifyProblem(j ?? { status: r.status, title: r.statusText }); return false; }
    return true;
  }

  async function save() {
    if (flexChanged && !(await put("", { allowOtherCourses: form.allow, otherScope: form.scope, allowHigherLevels: form.higher, reason: form.reason.trim() }))) return;
    if (openChanged && !(await put("/curriculum", { open: form.open, reason: form.reason.trim() }))) return;
    notify("Saved");
    setForm({ ...form, reason: "" });
    router.refresh();
  }

  return (
    <>
      <Panel title="In force" right={<Pil kind={flex.allow_other_courses ? "ok" : "grey"}>{flex.allow_other_courses ? "Students add other courses" : "Recommended list only"}</Pil>}>
        <PBody>
          <div className="grid grid--2">
            <div className="kv"><span className="k">Allow students to add other courses</span><span className="v">{flex.allow_other_courses ? "On" : "Off"}</span></div>
            <div className="kv"><span className="k">Courses they may add</span><span className="v">{SCOPE[flex.other_scope]}</span></div>
            <div className="kv"><span className="k">Allow a course of a higher level</span><span className="v">{flex.allow_higher_levels ? "On" : "Off"}</span></div>
            <div className="kv"><span className="k">Every curriculum&rsquo;s courses open to every student</span><span className="v">{flex.curriculum_open
              ? "On — every student sees and registers the programme’s courses at their level, BMAS or CCMAS, whatever their cohort"
              : "Off — each student sees their own cohort’s curriculum only"}</span></div>
            <div className="kv"><span className="k">Set</span><span className="v">{flex.set_by ?? "—"}{flex.set_office ? ` (${flex.set_office})` : ""} · {when(flex.set_at)}<div className="sub2">{flex.reason}</div></span></div>
          </div>
          <div className="sub2 mt-2">Whatever is set, the registration engine judges every course a student adds: one already passed, one whose result is
            still pending, one not offered in the semester, one registered in another semester of the session, one of another curriculum while the
            curricula are kept apart, one of the other BSU-/MOAU- code family, a postgraduate course for an undergraduate, and an unmet prerequisite where they are enforced are refused with the reason, and
            a GST fee owed holds every course, as it holds the recommended list. Carry-overs come only from published results. The minimum and maximum units, the registration window,
            the school fees and the approval rule apply as before.</div>
        </PBody>
      </Panel>
      {mayChange ? (
        <Panel title="Change the options">
          <PBody>
            <div className="stack" style={{ maxWidth: 640 }}>
              <label className="row row--inline row--tight"><input type="checkbox" className="chk" checked={form.allow} onChange={(e) => setForm({ ...form, allow: e.target.checked })} /> ALLOW STUDENT TO ADD OTHER COURSES</label>
              <Field id="ro-scope" label="Courses a student may add">
                <select id="ro-scope" className="ctl" value={form.scope} disabled={!form.allow} onChange={(e) => setForm({ ...form, scope: e.target.value as FlexState["other_scope"] })}>
                  {(Object.keys(SCOPE) as FlexState["other_scope"][]).map((k) => <option key={k} value={k}>{SCOPE[k]}</option>)}
                </select>
              </Field>
              <label className="row row--inline row--tight"><input type="checkbox" className="chk" checked={form.higher} disabled={!form.allow} onChange={(e) => setForm({ ...form, higher: e.target.checked })} /> ALLOW A COURSE OF A HIGHER LEVEL THAN THE STUDENT&rsquo;S</label>
              <label className="row row--inline row--tight"><input type="checkbox" className="chk" checked={form.open} onChange={(e) => setForm({ ...form, open: e.target.checked })} /> OPEN EVERY CURRICULUM&rsquo;S COURSES (BMAS AND CCMAS) TO EVERY STUDENT, WHATEVER THEIR COHORT</label>
              <Field id="ro-reason" label="Reason" required hint="Ten characters or more; kept on the audit trail">
                <input id="ro-reason" className="ctl" value={form.reason} maxLength={500} onChange={(e) => setForm({ ...form, reason: e.target.value })} placeholder="e.g. Senate allowed students to register outstanding lower-level courses" />
              </Field>
              <div><Btn kind="primary" disabled={!changed || form.reason.trim().length < 10} busyLabel="SAVING..." onClick={() => save()}>Save the options</Btn></div>
            </div>
          </PBody>
        </Panel>
      ) : <Note kind="info" title="Set by the Academic Office, the Registry or the Directorate of ICT" />}
    </>
  );
}
