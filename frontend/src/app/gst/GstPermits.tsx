"use client";
/** The GST & EPS examination permits on the GST or EPS office's desk (V492): the students a submitted registration of the
 *  office's courses concerns for a session and semester (V589: the permit is issued on the examination card's own terms), each with their permit (generated, downloaded, printed, withdrawn), the
 *  examination schedule of the office's courses, a permit found by its reference, and a student's permit as the student sees it,
 *  withdrawn or restored with a reason. The office never changes a registration here. */
import { useState } from "react";
import { useQueryNav } from "@/lib/query-nav";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, KvGrid, LinkBtn, Note, Panel, PBody, Pil, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { semesterName } from "@/lib/student-portal";
import {
  ROSTER_STATUSES, courseSchedule, permitSections, permitStatusLabel, rosterStatusLabel, slotDate, slotTime, slotVenue,
  type PermitState, type RosterPage, type RosterRow,
} from "@/lib/gst-eps-permit";

type Detail = PermitState & { studentId: string; permitId: string | null; events: { action: string; courses: string | null; reason: string | null; actor_office: string | null; at: string; actor: string | null }[] };

const EVENT_WORD: Record<string, string> = {
  GST_EPS_PERMIT_GENERATED: "Generated", GST_EPS_PERMIT_VIEWED: "Viewed", GST_EPS_PERMIT_DOWNLOADED: "Downloaded",
  GST_EPS_PERMIT_PRINTED: "Printed", GST_EPS_PERMIT_REVOKED: "Withdrawn", GST_EPS_PERMIT_RESTORED: "Restored",
};
const at = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleString("en-GB", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" }) : "—");

async function bff<T>(path: string, init?: RequestInit): Promise<T | null> {
  const r = await fetch(`/api/bff${path}`, { cache: "no-store", ...init, headers: { "content-type": "application/json", ...(init?.headers ?? {}) } }).catch(() => null);
  const j = r ? await r.json().catch(() => null) : null;
  if (!r || !r.ok) { notifyProblem(j ?? { status: 503, title: "The desk could not be reached just now." }); return null; }
  return j as T;
}

export function GstPermits({ data, base, filters }: { data: RosterPage; base: string; filters: { status?: string; course?: string; q?: string } }) {
  const go = useQueryNav();
  const o = data.office;
  const [q, setQ] = useState(filters.q ?? "");
  const [ref, setRef] = useState("");
  const [open, setOpen] = useState<Detail | null>(null);
  const [reason, setReason] = useState("");
  const query = (extra: Record<string, string | number | undefined>) => {
    const p = new URLSearchParams();
    const all: Record<string, string | number | undefined> = { session: data.session, semester: data.semester, status: filters.status, course: filters.course, q: filters.q, ...extra };
    for (const [k, v] of Object.entries(all)) if (v !== undefined && v !== "" && v !== null) p.set(k, String(v));
    return `${base}/permits?${p.toString()}`;
  };
  const pages = Math.max(1, Math.ceil(data.total / data.size));
  const f = data.figures;

  async function show(studentId: string) {
    const d = await bff<Detail>(`/api/v1/gst/${o}/permits/students/${studentId}?session=${encodeURIComponent(data.session)}&semester=${data.semester}`);
    if (d) { setOpen(d); setReason(""); }
  }
  async function find() {
    const r = ref.trim();
    if (!r) return;
    const hit = await bff<{ student_id: string; session: string; semester: number }>(`/api/v1/gst/${o}/permits/lookup?reference=${encodeURIComponent(r)}`);
    if (!hit) return;
    const d = await bff<Detail>(`/api/v1/gst/${o}/permits/students/${hit.student_id}?session=${encodeURIComponent(hit.session)}&semester=${hit.semester}`);
    if (d) { setOpen(d); setReason(""); }
  }
  async function decide(restore: boolean) {
    if (!open?.permitId) return;
    const d = await bff<PermitState>(`/api/v1/gst/${o}/permits/${open.permitId}/${restore ? "restore" : "revoke"}`, { method: "POST", body: JSON.stringify({ reason: reason.trim() }) });
    if (!d) return;
    notify(restore ? "The permit is restored; the student is told." : "The permit is withdrawn; the student is told.", "ok");
    await show(open.studentId);
    go(query({}));
  }

  const statusPil = (r: RosterRow) => {
    const s = r.permit_status ?? "NOT_GENERATED";
    return <Pil kind={s === "REVOKED" ? "bad" : s === "PRINTED" ? "ok" : s === "NOT_GENERATED" ? "grey" : "info"}>{rosterStatusLabel(s)}</Pil>;
  };

  return (
    <>
      <Panel title={`${o} examination permits · ${data.session} · ${semesterName(data.semester)} semester`} right={`${data.total.toLocaleString()} shown`}>
        <PBody>
          <form className="row row--inline" style={{ gap: 8, flexWrap: "wrap", alignItems: "flex-end" }} onSubmit={(e) => { e.preventDefault(); go(query({ q: q.trim() || undefined, page: undefined })); }}>
            <Field id="pm-session" label="Session">
              <input id="pm-session" defaultValue={data.session} pattern="\d{4}/\d{4}" style={{ width: 110 }} onBlur={(e) => { if (/^\d{4}\/\d{4}$/.test(e.target.value) && e.target.value !== data.session) go(query({ session: e.target.value, page: undefined })); }} />
            </Field>
            <Field id="pm-sem" label="Semester">
              <select id="pm-sem" value={data.semester} onChange={(e) => go(query({ semester: e.target.value, page: undefined }))}>
                {[1, 2, 3].map((n) => <option key={n} value={n}>{semesterName(n)}</option>)}
              </select>
            </Field>
            <Field id="pm-status" label="Permit">
              <select id="pm-status" value={filters.status ?? "ALL"} onChange={(e) => go(query({ status: e.target.value === "ALL" ? undefined : e.target.value, page: undefined }))}>
                {ROSTER_STATUSES.map(([k, label]) => <option key={k} value={k}>{label}</option>)}
              </select>
            </Field>
            <Field id="pm-course" label="Course">
              <select id="pm-course" value={filters.course ?? ""} onChange={(e) => go(query({ course: e.target.value || undefined, page: undefined }))}>
                <option value="">Every course</option>
                {[...new Set(data.courses.map((c) => c.course_code))].map((c) => <option key={c} value={c}>{c}</option>)}
              </select>
            </Field>
            <Field id="pm-q" label="Search">
              <input id="pm-q" value={q} onChange={(e) => setQ(e.target.value)} placeholder="Matric number or name" style={{ width: 200 }} />
            </Field>
            <Btn kind="secondary" type="submit">SEARCH</Btn>
          </form>
          <div className="mt-2">
            <Tiles cls="grid--3" items={[
              ["Students", f.students.toLocaleString(), null, "a submitted registration carries the office's course", query({ status: undefined, page: undefined })],
              ["Generated", f.generated.toLocaleString(), null, "viewed at least once", query({ status: "GENERATED", page: undefined })],
              ["Not generated", f.not_generated.toLocaleString(), null, "not yet viewed", query({ status: "NOT_GENERATED", page: undefined })],
              ["Downloaded", f.downloaded.toLocaleString(), null, undefined, query({ status: "DOWNLOADED", page: undefined })],
              ["Printed", f.printed.toLocaleString(), "var(--green-ink)", undefined, query({ status: "PRINTED", page: undefined })],
              ["Withdrawn", f.revoked.toLocaleString(), f.revoked ? "var(--red-deep)" : null, undefined, query({ status: "REVOKED", page: undefined })],
            ]} />
          </div>
        </PBody>
      </Panel>

      <Panel title="Examination schedule" right="From the examination timetable and the CBT engine">
        {data.courses.length ? (
          <DTable cols={["Course", "Type|mid", "Registered|num", "Examination"]} rows={data.courses.map((c) => [
            <Two key="c" a={`${c.course_code}${c.stream && c.stream !== "REGULAR" ? ` (${c.stream})` : ""}`} b={c.title} />,
            <Pil key="t" kind="info">{c.course_type}</Pil>,
            <span key="r" className="tnum">{c.registered.toLocaleString()}</span>,
            <span key="e" className="sub2">{courseSchedule(c)}</span>,
          ])} />
        ) : <PBody><Note kind="info" title={`No ${o} course runs in ${data.session} ${semesterName(data.semester).toLowerCase()} semester`} /></PBody>}
      </Panel>

      <Panel title="Verify a permit" right="By its permit number">
        <PBody>
          <form className="row row--inline" style={{ gap: 8, flexWrap: "wrap", alignItems: "flex-end" }} onSubmit={(e) => { e.preventDefault(); void find(); }}>
            <Field id="pm-ref" label="Permit number"><input id="pm-ref" value={ref} onChange={(e) => setRef(e.target.value)} placeholder="GST-EPS/2026/000001" style={{ width: 220 }} /></Field>
            <Btn kind="secondary" type="submit" busyLabel="Finding permit...">FIND PERMIT</Btn>
          </form>
          <div className="sub2 mt-1">A printed permit&rsquo;s QR opens the public verification page; this finds the permit and shows it as the student sees it now.</div>
        </PBody>
      </Panel>

      <Panel title="Students" right={pages > 1 ? `page ${data.page + 1} of ${pages}` : undefined}>
        {data.rows.length ? (
          <DTable cols={["S/N|num", "Student", "Programme", "Level|num", `${o} courses`, "Permit", "Last issued", "Viewed · downloaded · printed|num", ""]} rows={data.rows.map((r, i) => [
            <span key="n" className="tnum">{data.page * data.size + i + 1}</span>,
            <Two key="s" a={r.name} b={r.number} />,
            <span key="p" className="sub2">{r.programme ?? r.programme_code ?? "—"}</span>,
            <span key="l" className="tnum">{r.level ?? "—"}</span>,
            <span key="c">{r.courses}</span>,
            <span key="pm">{statusPil(r)}{r.reference ? <div className="sub2 tnum">{r.reference}</div> : null}</span>,
            <span key="li" className="sub2">{at(r.last_issued_at)}</span>,
            <span key="v" className="tnum">{r.viewed} · {r.downloaded} · {r.printed}</span>,
            <Btn key="b" kind="ghost" busyLabel="Loading permit..." onClick={() => show(r.student_id)}>VIEW</Btn>,
          ])} />
        ) : <PBody><Note kind="info" title="No student matches">A submitted registration carrying one of the office&rsquo;s courses puts a student here.</Note></PBody>}
        {pages > 1 ? (
          <PBody>
            <div className="row row--inline" style={{ gap: 8 }}>
              {data.page > 0 ? <LinkBtn href={query({ page: data.page - 1 })}>PREVIOUS</LinkBtn> : null}
              {data.page + 1 < pages ? <LinkBtn href={query({ page: data.page + 1 })}>NEXT</LinkBtn> : null}
            </div>
          </PBody>
        ) : null}
      </Panel>

      {open ? (
        <Modal wide title={`GST & EPS permit · ${open.student.name}`} sub={`${open.student.matricNo ?? open.student.number ?? ""} · ${open.session} · ${semesterName(open.semester)} semester`} onClose={() => setOpen(null)}
          foot={open.permitId ? (
            <div className="row row--inline" style={{ gap: 8, flexWrap: "wrap", alignItems: "flex-end", width: "100%" }}>
              <Field id="pm-reason" label={open.permit?.status === "REVOKED" ? "Why it is restored" : "Why it is withdrawn"} hint="At least ten characters; the student is told the permit was withdrawn, not why.">
                <input id="pm-reason" value={reason} onChange={(e) => setReason(e.target.value)} style={{ width: 320 }} />
              </Field>
              {open.permit?.status === "REVOKED"
                ? <Btn kind="primary" busyLabel="Restoring permit..." disabled={reason.trim().length < 10} onClick={() => decide(true)}>RESTORE PERMIT</Btn>
                : <Btn kind="urgent" busyLabel="Withdrawing permit..." disabled={reason.trim().length < 10} onClick={() => decide(false)}>WITHDRAW PERMIT</Btn>}
            </div>
          ) : undefined}>
          <Note kind={open.available ? "ok" : open.permit?.status === "REVOKED" ? "bad" : "info"} title={permitStatusLabel(open)}>
            {open.available ? "The permit may be issued: a submitted registration with GST or EPS courses, the school fees paid and the GST fee in order." : open.reason}
          </Note>
          <KvGrid cls="grid--3" pairs={[
            ["Permit number", open.permit?.reference ?? "Not generated"],
            ["Programme", open.student.programme ?? "—"],
            ["Level", `${open.registration?.level ?? open.student.level ?? "—"} Level`],
            ["Registration", open.registration?.status ?? "None"],
            ["Viewed · downloaded · printed", open.permit ? `${open.permit.viewed} · ${open.permit.downloaded} · ${open.permit.printed}` : "—"],
            ["Withdrawn", open.permit?.revokedAt ? `${at(open.permit.revokedAt)} by ${open.permit.revokedOffice}: ${open.permit.revokedReason}` : "—"],
          ]} />
          {permitSections(open.courses).map((sec) => (
            <div key={sec.type} className="mt-2">
              <div className="eyebrow mb-1">{sec.title}</div>
              <DTable cols={["Course", "Unit|num", "Date", "Time", "Venue"]} rows={sec.courses.map((c) => [
                <Two key="c" a={c.course_code} b={c.title} />, <span key="u" className="tnum">{c.units}</span>,
                <span key="d" className="tnum">{slotDate(c)}</span>, <span key="t" className="tnum">{slotTime(c)}</span>, <span key="v">{slotVenue(c)}</span>,
              ])} />
            </div>
          ))}
          {open.events.length ? (
            <div className="mt-2">
              <div className="eyebrow mb-1">What was done with it</div>
              <DTable cols={["When", "Act", "By", "Note"]} rows={open.events.map((e) => [
                <span key="w" className="sub2">{at(e.at)}</span>, <span key="a">{EVENT_WORD[e.action] ?? e.action}</span>,
                <span key="b" className="sub2">{e.actor ?? e.actor_office ?? "—"}</span>, <span key="n" className="sub2">{e.reason ?? ""}</span>,
              ])} />
            </div>
          ) : null}
        </Modal>
      ) : null}
    </>
  );
}
