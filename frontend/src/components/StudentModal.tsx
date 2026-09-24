"use client";

import { notifyProblem } from "@/components/proto/Toast";
/**
 * A student's whole record in a pop-up, opened from any list that names them — the Students desk, the
 * Search desk, the Student register. The photograph, the register line, the figures the student
 * themselves see (fees, GPA, CGPA, standing, this session's registration), and beneath them every
 * part of the record the Registry holds: bio-data by section, enrolments and registrations, results
 * by semester and carryovers, fees and receipts, documents, status history and clearance. Read-only;
 * the full page (Open full record) is where the Registry edits.
 */
import { useEffect, useState, type ReactNode } from "react";
import { Btn, KvGrid, LinkBtn, Note, Pil, Tabs, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Modal, Passport, day } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { Problem } from "@/lib/api";
import type { StudentRecord } from "@/lib/student";
import { fullName, statusLabel, statusPill } from "@/lib/student";
import type { Me as Portal } from "@/lib/student-portal";
import { money } from "@/lib/format";

type Tab = "overview" | "biodata" | "academic" | "fees" | "documents" | "history";
const TABS: [Tab, string][] = [
  ["overview", "Overview"], ["biodata", "Bio-data"], ["academic", "Academic"], ["fees", "Fees"], ["documents", "Documents"], ["history", "History"],
];
const SECTION: Record<string, string> = {
  identity: "Identity", contact: "Contact", origin: "Origin", family: "Next of kin & family", academic: "Academic", health: "Health", other: "Other",
};
const words = (s: string | null | undefined) => (s ?? "").split("_").map((w) => (w ? w.charAt(0) + w.slice(1).toLowerCase() : w)).join(" ");

export function StudentModal({ id, onClose }: { id: string; onClose: () => void }) {
  const [record, setRecord] = useState<StudentRecord | null>(null);
  const [portal, setPortal] = useState<Portal | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [tab, setTab] = useState<Tab>("overview");
  const [photoOk, setPhotoOk] = useState(true);

  useEffect(() => {
    let live = true;
    (async () => {
      const [r, p] = await Promise.all([
        fetch(`/api/bff/api/v1/student/students/${id}`, { cache: "no-store" }),
        fetch(`/api/bff/api/v1/student/students/${id}/portal`, { cache: "no-store" }),
      ]);
      if (!live) return;
      if (!r.ok) { const j = await r.json().catch(() => null); setProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }); notifyProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }); return; }
      setRecord((await r.json()) as StudentRecord);
      if (p.ok) setPortal((await p.json()) as Portal);
    })();
    return () => { live = false; };
  }, [id]);

  const s = record?.student;
  const f = portal?.fees;
  const latestSem = portal?.gpa?.length ? portal.gpa[portal.gpa.length - 1] : null;
  const reg = portal?.registration ?? null;

  const sections = record ? [...new Set(record.biodata.map((b) => b.section))] : [];

  let body: ReactNode;
  if (problem) body = <ProblemNotice problem={problem} />;
  else if (!record || !s) body = <Note kind="info" title="Reading the record…">One moment.</Note>;
  else body = (
    <>
      <div className="row row--top mb-3" style={{ gap: "var(--s-4)" }}>
        <div style={{ width: 96, height: 118, flexShrink: 0 }}>
          {photoOk ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img src={`/api/bff/api/v1/student/students/${s.id}/passport`} alt={`${fullName(s)} — passport photograph`} onError={() => setPhotoOk(false)}
              style={{ width: 96, height: 118, objectFit: "cover", borderRadius: "var(--r)", border: "1px solid var(--line-2)", display: "block" }} />
          ) : <Passport w={96} h={118} radius={6} src={null} />}
        </div>
        <div className="grow" style={{ minWidth: 240 }}>
          <div className="phead__t">{fullName(s)}</div>
          <div className="sub2 tnum mt-1">{s.matricNo ?? s.admissionNo ?? "—"}{s.jambRegNo ? ` · JAMB ${s.jambRegNo}` : ""}</div>
          <div className="sub2 mt-1">{s.programmeName} · {s.deptName}</div>
          <div className="sub2">{s.facultyName}</div>
          <div className="row mt-2">
            <Pil kind={statusPill(s.status)}>{statusLabel(s.status)}</Pil>
            <Pil kind="info">{s.currentLevel} level</Pil>
            <Pil kind="grey">{words(s.entryMode)} · {s.entrySession}</Pil>
            {s.sex ? <Pil kind="grey">{s.sex === "F" ? "Female" : s.sex === "M" ? "Male" : s.sex}</Pil> : null}
          </div>
        </div>
      </div>

      <div className="mb-3"><Tabs look="line" label="Student record" items={TABS.map(([id, label]) => ({ id, label }))} value={tab} onChange={setTab} /></div>

      {tab === "overview" ? (
        <>
          <Tiles items={[
            ["CGPA", portal?.cgpa != null ? Number(portal.cgpa).toFixed(2) : "—", portal?.standing === "PROBATION" ? "var(--red-ink)" : portal?.cgpa != null ? "var(--green-ink)" : null, portal?.standing ? words(portal.standing) : "No published result"],
            ["School fees", f ? (f.balance > 0 ? money(f.balance) : f.paidInFull ? "Settled" : f.due > 0 ? "Paid" : "—") : "—", f && f.balance > 0 ? "var(--red-ink)" : f?.paidInFull ? "var(--green-ink)" : null, f ? (f.balance > 0 ? `outstanding · ${f.session}` : f.session) : "Not read"],
            ["Registration", reg ? words(reg.status) : "None", reg && (reg.status === "APPROVED" || reg.status === "LOCKED") ? "var(--green-ink)" : null, reg ? `${reg.units} units · ${reg.entries?.length ?? 0} courses` : portal?.session ?? ""],
            ["Carryovers", String(portal?.carryovers?.length ?? 0), portal?.carryovers?.length ? "var(--red-ink)" : null, portal?.carryovers?.length ? "outstanding" : "none outstanding"],
          ]} />
          <KvGrid cls="grid--2" pairs={[
            ["Date of birth", s.dateOfBirth ? day(s.dateOfBirth) : "—"],
            ["Entry", `${words(s.entryMode)} · ${s.entrySession} · ${s.entryLevel} level`],
            ["Programme", `${s.programmeName} (${s.programmeCode})`],
            ["Department / faculty", `${s.deptName} · ${s.facultyName}`],
            ["Email", portal?.contact?.email ?? portal?.contact?.reach_email ?? "—"],
            ["Phone", portal?.contact?.phone ?? portal?.contact?.reach_phone ?? "—"],
            ["Address", portal?.contact?.address ?? "—"],
            ["Approved units (this session)", String(record.approvedUnits)],
          ]} />
          {portal?.graduation?.finalist ? (
            <Note kind={portal.graduation.cleared ? "ok" : "info"} title={`Finalist · ${portal.graduation.session ?? ""}`}>
              {portal.graduation.award ? `${portal.graduation.award}. ` : ""}{portal.graduation.cleared ? "Cleared for graduation." : portal.graduation.unmet ? `Unmet: ${portal.graduation.unmet}.` : "Audit pending."}
            </Note>
          ) : null}
        </>
      ) : null}

      {tab === "biodata" ? (
        sections.length ? sections.map((sec) => (
          <div key={sec} className="mb-3">
            <div className="sub2 eyebrow eyebrow--gap">{SECTION[sec] ?? words(sec)}</div>
            <KvGrid cls="grid--2" pairs={record.biodata.filter((b) => b.section === sec).sort((a, b) => a.ord - b.ord).map((b) => [b.label, b.value?.trim() ? b.value : <span className="sub2" key={b.field}>not recorded</span>])} />
          </div>
        )) : <div className="sub2">No bio-data fields are defined.</div>
      ) : null}

      {tab === "academic" ? (
        <>
          <div className="sub2 eyebrow mb-2">Results by semester</div>
          {portal?.gpa?.length ? (
            <DTable cols={["Session", "Semester|mid", "Units|num", "GPA|num", "CGPA|num", "Published|num"]}
              rows={portal.gpa.map((g) => [g.session, String(g.semester), <span key="u" className="tnum">{g.units}</span>, <span key="g" className="tnum">{g.gpa != null ? Number(g.gpa).toFixed(2) : "—"}</span>, <span key="c" className="tnum">{g.cgpa != null ? Number(g.cgpa).toFixed(2) : "—"}</span>, <span key="p" className="tnum">{g.published_count}/{g.registered_count}</span>])}
              texts={portal.gpa.map((g) => `${g.session} ${g.semester}`)} />
          ) : <div className="sub2 mb-3">No result has been published for this student yet.</div>}
          {portal?.carryovers?.length ? (
            <>
              <div className="sub2 eyebrow eyebrow--gap">Carryovers outstanding</div>
              <DTable cols={["Course", "Title", "Units|num", "Failed in"]} rows={portal.carryovers.map((c) => [<span key="c" className="tnum">{c.course_code}</span>, c.title, <span key="u" className="tnum">{c.units}</span>, c.failed_in])} texts={portal.carryovers.map((c) => c.course_code)} />
            </>
          ) : null}
          <div className="sub2 eyebrow eyebrow--gap">Registrations</div>
          {record.registrations.length ? (
            <DTable cols={["Session", "Semester|mid", "Level|num", "Units|num", "Status|mid", "Submitted"]}
              rows={record.registrations.map((r) => [r.session, String(r.semester), <span key="l" className="tnum">{r.level}</span>, <span key="u" className="tnum">{r.units}</span>, <Pil key="s" kind={r.status === "APPROVED" || r.status === "LOCKED" ? "ok" : r.status === "RETURNED" ? "bad" : "info"}>{words(r.status)}</Pil>, <span key="d" className="sub2">{r.submittedAt ? day(r.submittedAt) : "—"}</span>])}
              texts={record.registrations.map((r) => `${r.session} ${r.semester}`)} />
          ) : <div className="sub2">No course registration on record.</div>}
          <div className="sub2 eyebrow eyebrow--gap">Enrolments</div>
          {record.enrolments.length ? (
            <DTable cols={["Session", "Level|num", "Mode", "Fee category", "Enrolled"]}
              rows={record.enrolments.map((e) => [e.session, <span key="l" className="tnum">{e.level}</span>, words(e.mode), e.feeCategory ?? "—", <span key="d" className="sub2">{day(e.enrolledAt)}</span>])}
              texts={record.enrolments.map((e) => e.session)} />
          ) : <div className="sub2">No enrolment on record.</div>}
          {latestSem ? <div className="sub2 mt-2">Latest: {latestSem.session} semester {latestSem.semester} · GPA {latestSem.gpa != null ? Number(latestSem.gpa).toFixed(2) : "—"} · CGPA {latestSem.cgpa != null ? Number(latestSem.cgpa).toFixed(2) : "—"}.</div> : null}
        </>
      ) : null}

      {tab === "fees" ? (
        f ? (
          <>
            <Tiles items={[
              ["Charged", money(f.due), null, f.session],
              ["Paid", money(f.paid), f.paid > 0 ? "var(--green-ink)" : null, f.paidInFull ? "in full" : `${f.instalmentsPaid} instalment${f.instalmentsPaid === 1 ? "" : "s"}`],
              ["Balance", money(f.balance), f.balance > 0 ? "var(--red-ink)" : "var(--green-ink)", f.hasArrears ? "arrears carried" : f.balance > 0 ? "outstanding" : "settled"],
            ]} />
            {f.charges.length ? (
              <DTable cols={["Item", "Amount|num"]} rows={f.charges.map((c) => [c.item, <span key="a" className="tnum">{money(c.amount)}</span>])} texts={f.charges.map((c) => c.item)} />
            ) : <div className="sub2">No charge stated for {f.session}.</div>}
            <div className="sub2 eyebrow eyebrow--gap">Payment references</div>
            {f.references.length ? (
              <DTable cols={["Reference", "Purpose", "Amount|num", "Generated", "Confirmed", "Receipt"]}
                rows={f.references.map((r) => [<span key="r" className="tnum">{r.reference}</span>, r.purpose, <span key="a" className="tnum">{money(r.amount)}</span>, <span key="g" className="sub2">{day(r.generated_at)}</span>, r.confirmed_at ? <Pil key="c" kind="ok">{day(r.confirmed_at)}{r.channel ? ` · ${r.channel}` : ""}</Pil> : <Pil key="c" kind="grey">unpaid</Pil>, <span key="n" className="tnum sub2">{r.receipt_no ?? "—"}</span>])}
                texts={f.references.map((r) => `${r.reference} ${r.purpose}`)} />
            ) : <div className="sub2">No payment reference for {f.session}.</div>}
            {f.sessions.length > 1 ? <div className="sub2 mt-2">Sessions with fees on record: {f.sessions.join(", ")}.</div> : null}
          </>
        ) : <div className="sub2">The Bursary&rsquo;s figures for this student could not be read.</div>
      ) : null}

      {tab === "documents" ? (
        record.documents.length ? (
          <DTable cols={["Document", "Detail", "Source", "Received", "Status|mid"]}
            rows={record.documents.map((d) => [words(d.kind), d.detail ?? "—", words(d.source), <span key="r" className="sub2">{d.receivedOn ? day(d.receivedOn) : "—"}</span>, <Pil key="s" kind={d.status === "VERIFIED" ? "ok" : d.status === "REJECTED" ? "bad" : "info"}>{words(d.status)}</Pil>])}
            texts={record.documents.map((d) => `${d.kind} ${d.detail ?? ""}`)} />
        ) : <div className="sub2">The Registry holds no document for this student.</div>
      ) : null}

      {tab === "history" ? (
        <>
          <div className="sub2 eyebrow mb-2">Status history</div>
          {record.statusHistory.length ? (
            <DTable cols={["From", "To", "Instrument", "Effective", "Reason"]}
              rows={record.statusHistory.map((h) => [words(h.fromStatus), <Pil key="t" kind={statusPill(h.toStatus)}>{statusLabel(h.toStatus)}</Pil>, h.instrument, <span key="d" className="sub2">{day(h.effectiveOn)}</span>, h.reason ?? "—"])}
              texts={record.statusHistory.map((h) => `${h.fromStatus} ${h.toStatus}`)} />
          ) : <div className="sub2">No change of status on record.</div>}
          {record.registrationClearance.length ? (
            <>
              <div className="sub2 eyebrow eyebrow--gap">Registration clearance</div>
              <KvGrid cls="grid--2" pairs={record.registrationClearance.map((c) => [c.label, <span key={c.unit}><Pil kind={c.state === "CLEARED" ? "ok" : c.state === "HELD" ? "bad" : "grey"}>{words(c.state)}</Pil>{c.item ? ` · ${c.item}` : ""}</span>])} />
            </>
          ) : null}
          {record.convocationClearance.length ? (
            <>
              <div className="sub2 eyebrow eyebrow--gap">Convocation clearance</div>
              <KvGrid cls="grid--2" pairs={record.convocationClearance.map((c) => [c.label, <span key={c.unit}><Pil kind={c.state === "CLEARED" ? "ok" : c.state === "HELD" ? "bad" : "grey"}>{words(c.state)}</Pil>{c.item ? ` · ${c.item}` : ""}</span>])} />
            </>
          ) : null}
          {record.pendingChanges.length || record.decidedChanges.length ? (
            <>
              <div className="sub2 eyebrow eyebrow--gap">Bio-data change requests</div>
              <DTable cols={["Field", "From", "To", "Requested", "State|mid"]}
                rows={[...record.pendingChanges, ...record.decidedChanges].map((c) => [c.label, c.fromValue ?? "—", c.toValue, <span key="d" className="sub2">{day(c.requestedAt)}</span>, <Pil key="s" kind={c.state === "APPROVED" ? "ok" : c.state === "REFUSED" ? "bad" : "info"}>{words(c.state)}</Pil>])}
                texts={[...record.pendingChanges, ...record.decidedChanges].map((c) => c.label)} />
            </>
          ) : null}
        </>
      ) : null}
    </>
  );

  return (
    <Modal wide title={s ? fullName(s) : "Student"} sub={s ? `${s.matricNo ?? s.admissionNo ?? ""} · ${s.programmeName}` : "Reading the record"} onClose={onClose}
      foot={<><span className="sub2">Read from the register as it stands now.</span><span className="grow" />{s ? <LinkBtn href={`/students/${s.id}`} kind="ghost">Open full record</LinkBtn> : null}<Btn kind="primary" onClick={onClose}>Close</Btn></>}>
      {body}
    </Modal>
  );
}

/** a button that names a student and opens their record in the pop-up — for any list */
export function StudentOpen({ id, label, kind = "primary", className }: { id: string; label?: ReactNode; kind?: "primary" | "ghost" | "link"; className?: string }) {
  const [open, setOpen] = useState(false);
  return (
    <>
      {kind === "link"
        ? <button type="button" className={className} style={{ background: "none", border: "none", padding: 0, cursor: "pointer", font: "inherit", color: "var(--chrome)", fontWeight: 600, textAlign: "left" }} onClick={() => setOpen(true)}>{label ?? "Details"}</button>
        : <button type="button" className={className ?? `btn btn--${kind} btn--sm`} onClick={() => setOpen(true)}>{label ?? "Details"}</button>}
      {open ? <StudentModal id={id} onClose={() => setOpen(false)} /> : null}
    </>
  );
}
