"use client";
/** The GST or EPS office's courses (V314): the catalogue it owns, the session's offerings with their lecturers, registrations and
 *  score sheets, and the acts — a new course, an edit, a deactivation, the programmes it is offered to, the offering for a session,
 *  the lecturer. Score entry is on the sheet itself, which the office reaches for its own courses alone.
 *  V366: where each course is offered — faculty, department, programme, level — is the mapping a student's GST/EPS requirement is
 *  read from; it is shown whole, and a programme taken off is ended through the catalogue and kept on its history. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { useQueryNav } from "@/lib/query-nav";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, LinkBtn, Note, PageHead, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { STAGE_WORD, dayOf, num, type GstCourseRow, type GstOffice } from "@/lib/gst";

export interface CatalogueCourse { code: string; title: string; units: number; level: number; semester: number; dept_code: string; department: string; state: string; ended_on: string | null; general_office: string; ca_max: number | null; programmes: number; offers: string | null; offered_this_session: boolean }
export interface GstCoursesData {
  office: GstOffice; session: string; semester: number | null; sessions: { name: string; state: string }[]; catalogue: CatalogueCourse[]; offerings: GstCourseRow[];
  departments: { code: string; name: string; faculty_code: string }[]; programmes: { code: string; name: string; dept_code: string; faculty_code: string }[]; lecturers: { id: string; name: string; staff_number: string | null }[];
  /** V366: every programme each course is offered to, at which level — the mapping the requirement is read from — and the ended ones */
  offers?: { course_code: string; level: number; basis: string; track: string | null; programme_code: string; programme: string; dept_code: string | null; department: string | null;
    faculty_code: string | null; faculty: string | null; added_at: string | null; source: string | null; upper_level: boolean }[];
  offerHistory?: { course_code: string; programme_code: string; programme: string | null; level: number; ended_at: string; reason: string | null; registrations_carried: number }[];
}

type Act = { kind: "new" } | { kind: "edit"; course: CatalogueCourse } | { kind: "offers"; course: CatalogueCourse } | { kind: "offer"; course: CatalogueCourse } | { kind: "lecturer"; offering: GstCourseRow };

export function GstCourses({ data, base, actingOffice }: { data: GstCoursesData; base: string; actingOffice: string | null }) {
  const router = useRouter();
  const go = useQueryNav();
  const o = data.office;
  const word = o;
  const may = actingOffice === o.toLowerCase() || actingOffice === "super";
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [act, setAct] = useState<Act | null>(null);
  const [form, setForm] = useState<Record<string, string>>({});
  const [picked, setPicked] = useState<Set<string>>(new Set());

  const open = (a: Act) => {
    setProblem(null);
    if (a.kind === "new") setForm({ code: "", title: "", units: "2", level: "100", semester: "1", deptCode: "", caMax: "" });
    if (a.kind === "edit") setForm({ title: a.course.title, units: String(a.course.units), level: String(a.course.level), semester: String(a.course.semester), deptCode: a.course.dept_code, caMax: a.course.ca_max == null ? "" : String(a.course.ca_max) });
    if (a.kind === "offers") { setForm({ level: String(a.course.level) }); setPicked(new Set((a.course.offers ?? "").split(",").filter(Boolean).filter((x) => x.endsWith(`:${a.course.level}`)).map((x) => x.split(":")[0]))); }
    if (a.kind === "offer") setForm({ session: data.session, semester: String(a.course.semester) });
    if (a.kind === "lecturer") setForm({ lecturerId: a.offering.lecturer_id ?? "", secondExaminerId: "" });
    setAct(a);
  };
  const send = async (method: string, path: string, body: unknown, reason: string, done: string) => {
    setBusy(true); setProblem(null);
    try {
      const r = await fetch(`/api/bff/api/v1/gst/${o}${path}`, { method, headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body ?? {}) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { const pr = (j as Problem) ?? { status: r.status, title: r.statusText }; setProblem(pr); notifyProblem(pr); return false; }
      notify(done); setAct(null); router.refresh(); return true;
    } finally { setBusy(false); }
  };
  const submit = async () => {
    if (!act) return;
    const n = (k: string) => Number(form[k] || 0);
    switch (act.kind) {
      case "new": return send("POST", "/courses", { code: form.code, title: form.title, units: n("units"), level: n("level"), semester: n("semester"), deptCode: form.deptCode, caMax: form.caMax ? n("caMax") : null }, `${word} course created: ${form.code}`, `${form.code.toUpperCase()} created and live`);
      case "edit": return send("PUT", `/courses/${encodeURIComponent(act.course.code.replace(/ /g, "_"))}`, { title: form.title, units: n("units"), level: n("level"), semester: n("semester"), deptCode: form.deptCode, caMax: form.caMax ? n("caMax") : null }, `${word} course edited: ${act.course.code}`, `${act.course.code} saved`);
      case "offers": return send("PUT", `/courses/${encodeURIComponent(act.course.code.replace(/ /g, "_"))}/offers`, { programmes: [...picked], level: n("level"), reason: form.reason || null }, `${act.course.code} offered to ${picked.size} programmes`, `${act.course.code}: offered to ${picked.size} programme${picked.size === 1 ? "" : "s"} at ${form.level} level`);
      case "offer": return send("POST", "/offerings", { courseCode: act.course.code, session: form.session, semester: n("semester") }, `${act.course.code} offered in ${form.session}`, `${act.course.code} offered in ${form.session}, semester ${form.semester}`);
      case "lecturer": return send("PUT", `/offerings/${act.offering.offering_id}/lecturer`, { lecturerId: form.lecturerId || null, secondExaminerId: form.secondExaminerId || null }, `${act.offering.course_code}: lecturer assigned`, `${act.offering.course_code}: lecturer ${form.lecturerId ? "assigned" : "cleared"}`);
    }
  };
  const state = async (c: CatalogueCourse) => {
    const action = c.state === "ENDED" ? "activate" : "deactivate";
    if (action === "deactivate" && !window.confirm(`Deactivate ${c.code}? It stops being offered to new registrations; existing registrations and results stand.`)) return;
    await send("POST", `/courses/${encodeURIComponent(c.code.replace(/ /g, "_"))}/${action}`, {}, `${c.code} ${action}d`, `${c.code} ${action}d`);
  };
  const live = data.catalogue.filter((c) => c.state !== "ENDED");
  const pending = data.offerings.filter((x) => !x.stage || x.stage === "ENTRY").length;
  const published = data.offerings.filter((x) => x.stage === "PUBLISHED").length;
  const withSem = (s: string) => `${base}/courses?session=${encodeURIComponent(data.session)}${s ? `&semester=${s}` : ""}`;

  return (
    <>
      <PageHead title={`${word} courses`} description={`The ${word === "GST" ? "General Studies" : "Entrepreneurship Studies"} courses on the catalogue, the programmes they are offered to, the session's offerings with their lecturers, registrations and score sheets. ${may ? "Create, edit, activate and deactivate the office's own courses; assign lecturers; open an offering for a session." : "Read only: the " + word + " office manages these."}`}
        actions={<span className="row row--inline row--tight">
          <label htmlFor="gc-session" className="sub2">Session</label>
          <select id="gc-session" className="ctl" value={data.session} onChange={(e) => go(`${base}/courses?session=${encodeURIComponent(e.target.value)}`)}>{data.sessions.map((x) => <option key={x.name} value={x.name}>{x.name}</option>)}</select>
          <label htmlFor="gc-sem" className="sub2">Semester</label>
          <select id="gc-sem" className="ctl" value={data.semester == null ? "" : String(data.semester)} onChange={(e) => go(withSem(e.target.value))}><option value="">All</option><option value="1">First</option><option value="2">Second</option><option value="3">Third</option></select>
          {may ? <Btn kind="primary" size="sm" onClick={() => open({ kind: "new" })}>New {word} course</Btn> : null}
        </span>} />
      {problem && !act ? <ProblemNotice problem={problem} /> : null}
      <Tiles items={[
        [`${word} COURSES`, num(data.catalogue.length), null, `${num(live.length)} active · ${num(data.catalogue.length - live.length)} deactivated`],
        [`OFFERED IN ${data.session}`, num(data.offerings.length), null, data.semester ? `Semester ${data.semester}` : "Both semesters"],
        ["REGISTRATIONS", num(data.offerings.reduce((n, x) => n + Number(x.registered), 0)), null, `${num(data.offerings.reduce((n, x) => n + Number(x.entitled), 0))} by students with the GST fee paid`],
        ["RESULTS", `${num(pending)} · ${num(published)}`, null, "Pending · published"],
      ]} />

      <Panel title={`OFFERINGS · ${data.session}`} right={<LinkBtn kind="ghost" size="sm" href={`/results/sheets?session=${encodeURIComponent(data.session)}`}>Score sheets</LinkBtn>}>
        {data.offerings.length ? <DTable pageSize={30} cols={["S/N|num", "Course", "Level|mid", "Sem|mid", "Lecturer", "Registered|num", "GST paid|num", "Sheet|mid", "Actions|mid"]} rows={data.offerings.map((x, i) => [
          <span key="n" className="tnum sub2">{i + 1}</span>, <span key="c"><b>{x.course_code}</b><div className="sub2">{x.title} · {x.units} units · {x.department}</div></span>,
          <span key="l" className="tnum">{x.level}</span>, <span key="s" className="tnum">{x.semester}</span>, <span key="t">{x.lecturer ?? <span className="sub2">Not assigned</span>}</span>,
          <span key="r" className="tnum">{num(x.registered)}</span>, <span key="e" className="tnum">{num(x.entitled)}</span>,
          x.sheet_id ? <LinkBtn key="h" kind="ghost" size="sm" href={`/results/sheets/${x.sheet_id}`}>{(STAGE_WORD[x.stage ?? ""] ?? [x.stage ?? "—"])[0]} · {num(x.graded)} graded</LinkBtn> : <Pil key="h" kind="grey">No sheet yet</Pil>,
          may ? <Btn key="a" kind="ghost" size="sm" onClick={() => open({ kind: "lecturer", offering: x })}>Lecturer</Btn> : <span key="a" />,
        ])} /> : <PBody><div className="sub2">No {word} course is offered in {data.session}{data.semester ? `, semester ${data.semester}` : ""}. {may ? "Open an offering from the catalogue below." : ""}</div></PBody>}
      </Panel>

      {data.offers ? (
        <Panel title={`WHERE EACH ${word} COURSE IS OFFERED`} right={<span className="sub2">{num(data.offers.length)} programme binding{data.offers.length === 1 ? "" : "s"}</span>}>
          <PBody>
            <div className="sub2">A student owes a {word} course — and so the GST fee — only where their programme is offered it at their level and it runs in the session, or where they carry it over. {word === "GST" ? "GST is normally taken at 100 and 200 level; a binding at 300 level or above is marked so it can be checked." : "EPS may be offered at 300 level to selected programmes; only those programmes owe it."}</div>
            {word === "GST" && data.offers.some((x) => x.upper_level) ? (
              <Note kind="bad" title={`${num(data.offers.filter((x) => x.upper_level).length)} GST binding${data.offers.filter((x) => x.upper_level).length === 1 ? "" : "s"} at 300 level or above`}>
                The students of these programmes at that level owe the GST course and the fee while it runs. If a binding came from an upload and is not intended, take the programme off the course.
              </Note>
            ) : null}
          </PBody>
          {data.offers.length ? <DTable pageSize={30} cols={["S/N|num", "Course", "Level|mid", "Faculty", "Department", "Programme", "Basis|mid", "Since|mid"]} rows={data.offers.map((x, i) => [
            <span key="n" className="tnum sub2">{i + 1}</span>, <b key="c" className="tnum">{x.course_code}</b>,
            <span key="l" className="tnum">{x.level}{word === "GST" && x.upper_level ? <> <Pil kind="warn">check</Pil></> : null}</span>,
            <span key="f" className="sub2">{x.faculty ?? "—"}</span>, <span key="d" className="sub2">{x.department ?? "—"}</span>,
            <span key="p">{x.programme}<span className="sub2"> · {x.programme_code}</span></span>, <span key="b" className="sub2">{x.basis}{x.track ? ` · ${x.track}` : ""}</span>,
            <span key="a" className="sub2 tnum">{x.added_at ? dayOf(x.added_at) : "—"}</span>,
          ])} /> : <PBody><div className="sub2">No {word} course is offered to any programme yet.</div></PBody>}
          {data.offerHistory?.length ? (
            <PBody>
              <details><summary className="sub2">Bindings ended ({data.offerHistory.length}) — the registrations and results they carried stand</summary>
                <DTable cols={["Course", "Programme", "Level|mid", "Ended|mid", "Reason", "Registrations|num"]} rows={data.offerHistory.map((h) => [
                  <b key="c" className="tnum">{h.course_code}</b>, <span key="p">{h.programme ?? h.programme_code}</span>, <span key="l" className="tnum">{h.level}</span>,
                  <span key="e" className="tnum sub2">{dayOf(h.ended_at)}</span>, <span key="r" className="sub2">{h.reason ?? "—"}</span>, <span key="g" className="tnum">{num(h.registrations_carried)}</span>,
                ])} />
              </details>
            </PBody>
          ) : null}
        </Panel>
      ) : null}

      <Panel title={`${word} CATALOGUE`} right={<span className="sub2">{num(data.catalogue.length)} course{data.catalogue.length === 1 ? "" : "s"}</span>}>
        {data.catalogue.length ? <DTable pageSize={30} cols={["S/N|num", "Course", "Level|mid", "Sem|mid", "Units|num", "Department", "Programmes|num", "Status|mid", "Actions"]} rows={data.catalogue.map((c, i) => [
          <span key="n" className="tnum sub2">{i + 1}</span>, <span key="c"><b>{c.code}</b><div className="sub2">{c.title}</div></span>,
          <span key="l" className="tnum">{c.level}</span>, <span key="s" className="tnum">{c.semester}</span>, <span key="u" className="tnum">{c.units}</span>, <span key="d" className="sub2">{c.department}</span>,
          <span key="p" className="tnum">{num(c.programmes)}</span>,
          <Pil key="t" kind={c.state === "ENDED" ? "bad" : c.offered_this_session ? "ok" : "grey"}>{c.state === "ENDED" ? "Deactivated" : c.offered_this_session ? `Offered ${data.session}` : "Active"}</Pil>,
          may ? <span key="a" className="row row--inline row--tight" style={{ flexWrap: "wrap" }}>
            <Btn kind="ghost" size="sm" onClick={() => open({ kind: "edit", course: c })}>Edit</Btn>
            <Btn kind="ghost" size="sm" onClick={() => open({ kind: "offers", course: c })}>Programmes</Btn>
            {c.state !== "ENDED" && !c.offered_this_session ? <Btn kind="secondary" size="sm" onClick={() => open({ kind: "offer", course: c })}>Offer in {data.session}</Btn> : null}
            <Btn kind={c.state === "ENDED" ? "go" : "urgent"} size="sm" disabled={busy} onClick={() => void state(c)}>{c.state === "ENDED" ? "Activate" : "Deactivate"}</Btn>
          </span> : <span key="a" />,
        ])} /> : <PBody><Note kind="info" title={`No ${word} course on the catalogue yet`}>{may ? `Create the first ${word} course, offer it to the programmes that take it, then open its offering for the session.` : "The office creates its courses here."}</Note></PBody>}
      </Panel>

      {act ? (
        <Modal title={act.kind === "new" ? `New ${word} course` : act.kind === "edit" ? `Edit ${act.course.code}` : act.kind === "offers" ? `${act.course.code} · programmes it is offered to` : act.kind === "offer" ? `Offer ${act.course.code}` : `${act.offering.course_code} · lecturer`}
          sub={act.kind === "lecturer" ? `${data.session} · semester ${act.offering.semester}` : `${word} office`} onClose={() => setAct(null)}
          foot={<><Btn kind="ghost" onClick={() => setAct(null)}>Back</Btn><Btn kind="primary" disabled={busy} onClick={() => void submit()}>{busy ? "Saving…" : "Save"}</Btn></>}>
          {problem ? <ProblemNotice problem={problem} /> : null}
          {act.kind === "new" || act.kind === "edit" ? (
            <div className="grid grid--2">
              {act.kind === "new" ? <Field id="gc-code" label="Course code" required hint="Three letters, a space, three digits — e.g. GST 101 or EPS 201"><input id="gc-code" className="ctl tnum" value={form.code} onChange={(e) => setForm({ ...form, code: e.target.value.toUpperCase() })} /></Field> : null}
              <Field id="gc-title" label="Title" required><input id="gc-title" className="ctl" value={form.title} onChange={(e) => setForm({ ...form, title: e.target.value })} /></Field>
              <Field id="gc-units" label="Units" required><input id="gc-units" type="number" min={0} max={12} className="ctl" value={form.units} onChange={(e) => setForm({ ...form, units: e.target.value })} /></Field>
              <Field id="gc-level" label="Level" required><select id="gc-level" className="ctl" value={form.level} onChange={(e) => setForm({ ...form, level: e.target.value })}>{[100, 200, 300, 400, 500, 600].map((l) => <option key={l} value={l}>{l} Level</option>)}</select></Field>
              <Field id="gc-sem" label="Semester" required><select id="gc-sem" className="ctl" value={form.semester} onChange={(e) => setForm({ ...form, semester: e.target.value })}><option value="1">First</option><option value="2">Second</option><option value="3">Third</option></select></Field>
              <Field id="gc-dept" label="Department" required hint="The department that houses the course on the catalogue"><select id="gc-dept" className="ctl" value={form.deptCode} onChange={(e) => setForm({ ...form, deptCode: e.target.value })}><option value="">Choose</option>{data.departments.map((d) => <option key={d.code} value={d.code}>{d.name}</option>)}</select></Field>
              <Field id="gc-ca" label="CA out of" hint="Blank keeps the catalogue's split"><input id="gc-ca" type="number" min={0} max={100} className="ctl" value={form.caMax} onChange={(e) => setForm({ ...form, caMax: e.target.value })} /></Field>
            </div>
          ) : null}
          {act.kind === "offers" ? (
            <>
              <Field id="gc-olevel" label="At level"><select id="gc-olevel" className="ctl" value={form.level} onChange={(e) => { setForm({ ...form, level: e.target.value }); setPicked(new Set((act.course.offers ?? "").split(",").filter(Boolean).filter((x) => x.endsWith(`:${e.target.value}`)).map((x) => x.split(":")[0]))); }}>{[100, 200, 300, 400, 500, 600].map((l) => <option key={l} value={l}>{l} Level</option>)}</select></Field>
              <div className="sub2 mb-1">The students of the programmes ticked owe {act.course.code} at {form.level} level when it runs. A programme taken off is ended through the catalogue and kept on its history; it is refused while a student of it is registered on the course this session.</div>
              <Field id="gc-oreason" label="Reason for any programme taken off"><input id="gc-oreason" className="ctl" value={form.reason ?? ""} onChange={(e) => setForm({ ...form, reason: e.target.value })} /></Field>
              <div className="row row--inline row--tight mb-1"><Btn kind="ghost" size="sm" onClick={() => setPicked(new Set(data.programmes.map((p) => p.code)))}>Every programme</Btn><Btn kind="ghost" size="sm" onClick={() => setPicked(new Set())}>None</Btn><span className="sub2">{picked.size} chosen</span></div>
              <div style={{ maxHeight: 320, overflow: "auto" }}>
                {data.programmes.map((p) => (
                  <label key={p.code} className="row row--inline row--tight" style={{ padding: "4px 0" }}>
                    <input type="checkbox" checked={picked.has(p.code)} onChange={(e) => { const n = new Set(picked); if (e.target.checked) n.add(p.code); else n.delete(p.code); setPicked(n); }} />
                    <span>{p.name}<span className="sub2"> · {p.code}</span></span>
                  </label>
                ))}
              </div>
            </>
          ) : null}
          {act.kind === "offer" ? (
            <div className="grid grid--2">
              <Field id="gc-osession" label="Session"><select id="gc-osession" className="ctl" value={form.session} onChange={(e) => setForm({ ...form, session: e.target.value })}>{data.sessions.map((x) => <option key={x.name} value={x.name}>{x.name}</option>)}</select></Field>
              <Field id="gc-osem" label="Semester"><select id="gc-osem" className="ctl" value={form.semester} onChange={(e) => setForm({ ...form, semester: e.target.value })}><option value="1">First</option><option value="2">Second</option><option value="3">Third</option></select></Field>
            </div>
          ) : null}
          {act.kind === "lecturer" ? (
            <div className="grid grid--2">
              <Field id="gc-lect" label="Lecturer" hint="Through the catalogue's own allocation; the overload rule is waived for a general course"><select id="gc-lect" className="ctl" value={form.lecturerId} onChange={(e) => setForm({ ...form, lecturerId: e.target.value })}><option value="">Not assigned</option>{data.lecturers.map((l) => <option key={l.id} value={l.id}>{l.name}{l.staff_number ? ` · ${l.staff_number}` : ""}</option>)}</select></Field>
              <Field id="gc-second" label="Second examiner"><select id="gc-second" className="ctl" value={form.secondExaminerId} onChange={(e) => setForm({ ...form, secondExaminerId: e.target.value })}><option value="">None</option>{data.lecturers.map((l) => <option key={l.id} value={l.id}>{l.name}</option>)}</select></Field>
            </div>
          ) : null}
        </Modal>
      ) : null}
    </>
  );
}
