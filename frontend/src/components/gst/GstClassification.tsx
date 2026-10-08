"use client";
/** V367: which courses are the office's. A course is the GST office's when its subject is a General Studies code family, the EPS
 *  office's for an Entrepreneurship family or an entrepreneurship title, and no office's otherwise — such a course was marked general
 *  by a course upload (status G) but is a department's. The office claims a course its families miss, gives back to its department
 *  a course it does not run, and keeps its own families; nothing here touches a registration, a result or a payment. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, Note, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { dayOf, num } from "@/lib/gst";

export interface GstFamily { prefix: string; office: "GST" | "EPS" | string; added_at: string }
export interface UnassignedCourse { code: string; title: string; level: number; semester: number; units: number; dept_code: string | null; department: string | null; programmes: number; offered_this_session: boolean }
/** V368: one move of a course between the offices and its department, read from the record kept of every move */
export interface CourseMove {
  id: string; course_code: string; title: string; kind: string; office_now: string | null; given_back: boolean; department: string | null; programmes: number;
  before_office: string | null; after_office: string | null; before_kind: string | null; after_kind: string;
  cause: "RULE" | "CLAIM" | "RETURN" | "FAMILY" | "UPLOAD" | "EDIT" | "TRANSFER"; reason: string | null; changed_at: string; changed_office: string | null;
  confirmed_at: string | null; confirmed_office: string | null;
  /** V369: the office whose request for the course is waiting, if any */
  requested_by_office?: string | null;
}

const CAUSE_WORD: Record<CourseMove["cause"], string> = {
  RULE: "Classified on deploy (V367)", CLAIM: "Taken by an office", RETURN: "Given back to its department",
  FAMILY: "A code family", UPLOAD: "A course upload", EDIT: "A course edit", TRANSFER: "Passed by request",
};
const where = (office: string | null | undefined, kind: string | null | undefined) => office ? `${office} office` : kind === "GST" ? "General, no office" : kind ? "Its department" : "New course";

export function GstClassification({ office, may, families, unassigned }: { office: "GST" | "EPS"; may: boolean; families: GstFamily[]; unassigned: UnassignedCourse[] }) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [prefix, setPrefix] = useState("");
  const mine = families.filter((f) => f.office === office);
  const other = families.filter((f) => f.office !== office);

  async function call(path: string, method: string, body: unknown, reason: string, done: string) {
    setBusy(true);
    try {
      const r = await fetch(`/api/bff/api/v1/gst${path}`, { method, headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body ?? {}) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { notifyProblem(j ?? { status: r.status, title: r.statusText }); return; }
      notify(done);
      router.refresh();
    } finally { setBusy(false); }
  }
  const slug = (code: string) => encodeURIComponent(code.replace(/ /g, "_"));

  return (
    <Panel title={`WHICH COURSES ARE THE ${office} OFFICE'S`} right={<span className="sub2">{num(unassigned.length)} marked general, no office&rsquo;s</span>}>
      <PBody>
        <div className="sub2">
          A course is the {office} office&rsquo;s when its subject is one of its code families{office === "EPS" ? " or its title is entrepreneurship" : ""}: {mine.length ? mine.map((f) => f.prefix).join(", ") : "none yet"}
          {other.length ? <> (the {office === "GST" ? "EPS" : "GST"} office&rsquo;s: {other.map((f) => f.prefix).join(", ")})</> : null}. Only those courses are on this desk, owe the GST fee and are examined by this office.
        </div>
        {may ? (
          <form className="row row--inline row--tight mt-1" onSubmit={(e) => { e.preventDefault(); const p = prefix.trim().toUpperCase(); if (!/^[A-Z]{2,5}$/.test(p)) { notifyProblem({ status: 422, title: "A family is the two to five letters of a course code, e.g. GNS." }); return; } void call(`/families/${p}`, "PUT", { office }, `${office} code family ${p} added`, `${p} is now a ${office} family`).then(() => setPrefix("")); }}>
            <Field id="gc-family" label={`Add a ${office} code family`}><input id="gc-family" className="ctl tnum" maxLength={5} value={prefix} onChange={(e) => setPrefix(e.target.value.toUpperCase())} placeholder={office === "GST" ? "GNS" : "ENT"} /></Field>
            <Btn kind="secondary" size="sm" type="submit" disabled={busy}>Add</Btn>
            {mine.map((f) => <Btn key={f.prefix} kind="ghost" size="sm" disabled={busy} onClick={() => { if (window.confirm(`Remove ${f.prefix} from the ${office} families? Courses already filed under the office stay; new ${f.prefix} courses no longer come to it.`)) void call(`/families/${f.prefix}`, "PUT", { office: null }, `${office} code family ${f.prefix} removed`, `${f.prefix} removed`); }}>Remove {f.prefix}</Btn>)}
          </form>
        ) : null}
        {unassigned.length ? (
          <Note kind="info" title="Courses a course upload marked general that no office runs">
            A programme structure gave these courses status G (or a GST/EPS classification), but their subject is in no office&rsquo;s family. They stay with their department: they are not on this desk, owe no GST fee, and the examinations office examines them. Take one this office runs, or give it back to its department as a Core course.
          </Note>
        ) : null}
      </PBody>
      {unassigned.length ? (
        <DTable pageSize={20} cols={["Course", "Level|mid", "Department", "Programmes|num", "This session|mid", "|mid"]} rows={unassigned.map((c) => [
          <span key="c"><b className="tnum">{c.code}</b><div className="sub2">{c.title} · {c.units} units · semester {c.semester}</div></span>,
          <span key="l" className="tnum">{c.level}</span>, <span key="d" className="sub2">{c.department ?? c.dept_code ?? "—"}</span>,
          <span key="p" className="tnum">{num(c.programmes)}</span>,
          <Pil key="o" kind={c.offered_this_session ? "info" : "grey"}>{c.offered_this_session ? "Offered" : "Not offered"}</Pil>,
          may ? <span key="a" className="row row--inline row--tight">
            <Btn kind="secondary" size="sm" disabled={busy} onClick={() => { if (window.confirm(`Take ${c.code} as a ${office} course? Its students then owe the GST fee for it, and this office examines it.`)) void call(`/${office}/courses/${slug(c.code)}/claim`, "POST", {}, `${c.code} taken by the ${office} office`, `${c.code} is now a ${office} course`); }}>This office&rsquo;s</Btn>
            <Btn kind="ghost" size="sm" disabled={busy} onClick={() => { const why = window.prompt(`Give ${c.code} back to its department as a Core course? Say why:`, "A departmental course the structure marked G"); if (why && why.trim()) void call(`/courses/${slug(c.code)}/return`, "POST", { reason: why.trim() }, `${c.code} given back to its department: ${why.trim()}`, `${c.code} is its department's again`); }}>Give back to its department</Btn>
          </span> : <span key="a" />,
        ])} />
      ) : null}
    </Panel>
  );
}

/** V368: every move that touched the office's courses — what the V367 classification did on deploy, a claim, a course given back,
 *  an upload — with where the course stands now. The office confirms a move is right, or takes the course or gives it back instead. */
export function GstMoves({ office, may, moves }: { office: "GST" | "EPS"; may: boolean; moves: CourseMove[] }) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const open = moves.filter((m) => !m.confirmed_at).length;

  async function call(path: string, body: unknown, reason: string, done: string) {
    setBusy(true);
    try {
      const r = await fetch(`/api/bff/api/v1/gst${path}`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body ?? {}) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { notifyProblem(j ?? { status: r.status, title: r.statusText }); return; }
      notify(done);
      router.refresh();
    } finally { setBusy(false); }
  }
  const slug = (code: string) => encodeURIComponent(code.replace(/ /g, "_"));

  if (!moves.length) return null;
  return (
    <Panel title="COURSES MOVED TO OR FROM THIS OFFICE" right={<span className="sub2">{open ? `${num(open)} to confirm` : "all confirmed"}</span>}>
      {open ? (
        <PBody>
          <Note kind="info" title="Check each move">
            These courses came to the {office} office or left it — most when the classification ran on deploy. Confirm a move that is right; take a course
            this office runs but lost, or give back to its department one it does not run. A course given back stays its department&rsquo;s even if a later
            course upload marks it G.
          </Note>
        </PBody>
      ) : null}
      <DTable pageSize={20} cols={["Course", "Moved|mid", "Now|mid", "How", "Confirmed", "|mid"]} rows={moves.map((m) => {
        const ours = m.office_now === office;
        return [
          <span key="c"><b className="tnum">{m.course_code}</b><div className="sub2">{m.title}{m.department ? ` · ${m.department}` : ""} · {num(m.programmes)} programme{m.programmes === 1 ? "" : "s"}</div></span>,
          <span key="m" className="sub2">{where(m.before_office, m.before_kind)} &rarr; {where(m.after_office, m.after_kind)}</span>,
          <Pil key="n" kind={ours ? "ok" : m.office_now ? "info" : "grey"}>{where(m.office_now, m.kind)}{m.given_back ? " (given back)" : ""}</Pil>,
          <span key="h" className="sub2">{CAUSE_WORD[m.cause]}<div>{dayOf(m.changed_at)}{m.changed_office ? ` · ${m.changed_office.toUpperCase()}` : ""}</div>{m.reason ? <div>{m.reason}</div> : null}</span>,
          m.confirmed_at ? <span key="k" className="sub2">{dayOf(m.confirmed_at)}{m.confirmed_office ? ` · ${m.confirmed_office.toUpperCase()}` : ""}</span> : <Pil key="k" kind="warn">To confirm</Pil>,
          may ? <span key="a" className="row row--inline row--tight">
            {!m.confirmed_at ? <Btn kind="secondary" size="sm" disabled={busy} onClick={() => void call(`/${office}/reclassified/${m.id}/confirm`, {}, `${m.course_code} move confirmed by the ${office} office`, `${m.course_code}: move confirmed`)}>Confirm</Btn> : null}
            {!ours && !m.office_now ? <Btn kind="ghost" size="sm" disabled={busy} onClick={() => { if (window.confirm(`Take ${m.course_code} as a ${office} course? Its students then owe the GST fee for it, and this office examines it.`)) void call(`/${office}/courses/${slug(m.course_code)}/claim`, {}, `${m.course_code} taken by the ${office} office`, `${m.course_code} is now a ${office} course`); }}>This office&rsquo;s</Btn> : null}
            {/* V369: the other office's course comes only by its answer to a request */}
            {!ours && m.office_now && m.requested_by_office === office ? <Pil kind="info">Asked</Pil> : null}
            {!ours && m.office_now && !m.requested_by_office ? <Btn kind="ghost" size="sm" disabled={busy} onClick={() => { const why = window.prompt(`Ask the ${m.office_now} office for ${m.course_code}? Say why it should be this office's:`); if (why && why.trim()) void call(`/${office}/courses/${slug(m.course_code)}/request`, { reason: why.trim() }, `${m.course_code} asked of the ${m.office_now} office: ${why.trim()}`, `Request for ${m.course_code} sent to the ${m.office_now} office`); }}>Ask the {m.office_now} office for it</Btn> : null}
            {ours ? <Btn kind="ghost" size="sm" disabled={busy} onClick={() => { const why = window.prompt(`Give ${m.course_code} back to its department as a Core course? Say why:`, "A departmental course, not run by this office"); if (why && why.trim()) void call(`/courses/${slug(m.course_code)}/return`, { reason: why.trim() }, `${m.course_code} given back to its department: ${why.trim()}`, `${m.course_code} is its department's again`); }}>Give back to its department</Btn> : null}
          </span> : <span key="a" />,
        ];
      })} />
    </Panel>
  );
}
