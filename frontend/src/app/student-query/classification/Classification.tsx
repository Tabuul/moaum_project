"use client";

/**
 * Student classification (V469): the data-quality report of every learner the portal holds — how many are classified, how
 * many require classification (nothing claims them, or their fields disagree), what is missing — and the learners to be
 * decided, with what their fields propose and why. The Academic Office or the Registry decides each, with a reason; the
 * decision is kept, an earlier one superseded, never erased. Nothing here is guessed for them.
 */
import { useState } from "react";
import { useRouter } from "next/navigation";
import { useQueryNav } from "@/lib/query-nav";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, LinkBtn, Note, PageHead, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { reasonHeader } from "@/lib/reason";
import { statusWord } from "@/lib/student-query";

export interface Audit {
  totals: Record<string, number>;
  bySource: { source: string; learners: number; classified: number; requires_classification: number }[];
  byType: { programme_type: string | null; name: string | null; learners: number; decided: number; by_entry_mode: number; by_programme_category: number; by_preliminary_programme: number }[];
}
export interface Review {
  total: number; page: number; size: number;
  rows: { source: string; learner_id: string; student_id: string | null; surname: string; other_names: string; matric_no: string | null; jamb_no: string | null; application_no: string | null;
    proposed_type: string | null; proposed_type_name: string | null; classification_issue: string | null; classification_note: string | null; admission_route: string | null;
    study_mode: string | null; centre_code: string | null; faculty: string | null; department: string | null; programme_code: string | null; programme: string | null;
    programme_category: string | null; level: number | null; admission_session: string | null; status: string }[];
  types: { code: string; name: string; description: string | null }[];
  routes: { code: string; name: string; entry_mode: string | null }[];
  centres: { code: string; name: string }[];
}

const SOURCE_WORD: Record<string, string> = { REGISTER: "Student register", JUPEB: "JUPEB learners", PRELIMINARY: "Preliminary learners" };
const n = (v: number | undefined) => Number(v ?? 0).toLocaleString("en-GB");

export function Classification({ audit, review, q: initialQ, decides }: { audit: Audit; review: Review; q: string; decides: boolean }) {
  const router = useRouter();
  const queryNav = useQueryNav();
  const [q, setQ] = useState(initialQ);
  const [open, setOpen] = useState<Review["rows"][number] | null>(null);
  const [type, setType] = useState("");
  const [route, setRoute] = useState("");
  const [centre, setCentre] = useState("");
  const [reason, setReason] = useState("");
  const [err, setErr] = useState<string | null>(null);
  const t = audit.totals;
  const pages = Math.max(1, Math.ceil(review.total / review.size));

  function start(r: Review["rows"][number]) {
    setOpen(r); setType(r.proposed_type ?? ""); setRoute(""); setCentre(""); setReason(""); setErr(null);
  }
  async function decide() {
    if (!open?.student_id) return;
    if (!type) { setErr("Choose the programme type."); return; }
    if (!reason.trim()) { setErr("Say why — the decision is kept with its reason."); return; }
    const words = `${open.surname}, ${open.other_names} classified ${review.types.find((x) => x.code === type)?.name ?? type}: ${reason.trim()}`;
    const r = await fetch(`/api/bff/api/v1/student/classification/${open.student_id}`, {
      method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(words) },
      body: JSON.stringify({ programmeType: type, admissionRoute: route || null, centre: centre || null, reason: reason.trim() }),
    });
    const j = await r.json().catch(() => null);
    if (!r.ok) { notifyProblem(j ?? { status: r.status, title: r.statusText }); setErr((j as { detail?: string; title?: string } | null)?.detail ?? (j as { title?: string } | null)?.title ?? "The decision was not recorded."); return; }
    notify(`${open.surname}, ${open.other_names}: classification recorded`);
    setOpen(null);
    router.refresh();
  }

  return (
    <>
      <PageHead title="Student classification" description="How every learner is classified — from a decision, the entry mode or the programme's category, never from a name or a number — and the learners still to be decided."
        actions={<LinkBtn href="/student-query">Student query</LinkBtn>} />

      <Tiles cls="grid--4" items={[
        ["Learners", n(t.learners), null, "Register, JUPEB and Preliminary"],
        ["Classified", n(t.classified), "var(--green-ink)", `${n(t.decided)} by an office's decision`, "/student-query?classification=CLASSIFIED"],
        ["Require classification", n(t.requires_classification), t.requires_classification ? "var(--amber-ink)" : null, `${n(t.unclassified)} unclassified · ${n(t.conflicting)} conflicting`, "/student-query?classification=REQUIRES_CLASSIFICATION"],
        ["Study mode differs from type", n(t.study_mode_differs), t.study_mode_differs ? "var(--amber-ink)" : null, "The record's mode is not its type's usual one"],
      ]} />
      <Panel title="Data quality" right="Counted over every learner the portal holds">
        <DTable pageSize={0} cols={["Check", "Learners|num"]} rows={[
          ["Classified", t.classified], ["Unclassified — nothing claims the record", t.unclassified], ["Conflicting — the fields disagree", t.conflicting],
          ["Missing programme type", t.missing_programme_type], ["Missing faculty (JUPEB learners have none by design)", t.missing_faculty],
          ["Missing department", t.missing_department], ["Missing programme (or a Preliminary target not yet set)", t.missing_programme],
          ["Missing admission session", t.missing_session], ["Missing admission route", t.missing_admission_route], ["Missing centre", t.missing_centre],
        ].map(([l, v]) => [<span key="l">{l}</span>, <span key="v" className={`tnum${Number(v) && l !== "Classified" ? " b600" : ""}`}>{n(Number(v))}</span>])} />
      </Panel>

      <div>
        <Panel title="By source">
          <DTable pageSize={0} cols={["Source", "Learners|num", "Classified|num", "Require classification|num"]}
            rows={audit.bySource.map((s) => [SOURCE_WORD[s.source] ?? s.source, <span key="a" className="tnum">{n(s.learners)}</span>, <span key="b" className="tnum">{n(s.classified)}</span>, <span key="c" className="tnum">{n(s.requires_classification)}</span>])} />
        </Panel>
        <Panel title="By programme type" right="Where each type came from">
          <DTable pageSize={0} cols={["Programme type", "Learners|num", "Decision|num", "Entry mode|num", "Programme category|num", "Preliminary programme|num"]}
            rows={audit.byType.map((x) => [x.name ?? "Requires classification", <span key="a" className="tnum">{n(x.learners)}</span>, <span key="b" className="tnum">{n(x.decided)}</span>,
              <span key="c" className="tnum">{n(x.by_entry_mode)}</span>, <span key="d" className="tnum">{n(x.by_programme_category)}</span>, <span key="e" className="tnum">{n(x.by_preliminary_programme)}</span>])} />
        </Panel>
      </div>

      <Panel title="To be classified" right={review.total ? `${n(review.total)} learner${review.total === 1 ? "" : "s"}` : "None"}>
        <PBody>
          <form className="row" onSubmit={(e) => { e.preventDefault(); queryNav(`/student-query/classification${q.trim() ? `?q=${encodeURIComponent(q.trim())}` : ""}`); }}>
            <input className="ctl" style={{ maxWidth: 420 }} value={q} onChange={(e) => setQ(e.target.value)} placeholder="Name, matric, JAMB or application number" aria-label="Search the learners to be classified" />
            <Btn kind="primary" type="submit">Search</Btn>
          </form>
        </PBody>
        {review.rows.length ? (
          <DTable pageSize={0} cols={["S/N|num", "Learner", "Programme", "Level|mid", "Status|mid", "Proposed", "Why", "|num"]}
            rows={review.rows.map((r, i) => [
              <span key="sn" className="tnum sub2">{review.page * review.size + i + 1}</span>,
              <span key="s"><b>{r.surname}, {r.other_names}</b><div className="sub2 tnum">{[r.matric_no, r.jamb_no, r.application_no].filter(Boolean).join(" · ") || "—"}</div></span>,
              <span key="p">{r.programme ?? "—"}<div className="sub2">{[r.programme_category, r.department, r.faculty].filter(Boolean).join(" · ")}</div></span>,
              <span key="l" className="tnum">{r.level ?? "—"}</span>,
              <span key="st">{statusWord(r.status)}</span>,
              r.proposed_type_name ? <Pil key="t" kind="warn">{r.proposed_type_name}?</Pil> : <Pil key="t" kind="grey">None</Pil>,
              <span key="w" className="sub2">{r.classification_issue === "CONFLICTING" ? "Conflicting: " : "Unclassified: "}{r.classification_note}</span>,
              decides && r.student_id ? <Btn key="a" kind="primary" size="sm" onClick={() => start(r)}>Decide</Btn>
                : r.student_id ? <LinkBtn key="a" href={`/students/${r.student_id}`} size="sm">Open</LinkBtn> : <span key="a" />,
            ])} />
        ) : <PBody><Note kind="ok" title="Nothing to classify">Every learner the portal holds is classified{initialQ ? " (for this search)" : ""}.</Note></PBody>}
        {pages > 1 ? (
          <PBody>
            <div className="row row--between">
              <Btn kind="ghost" disabled={review.page === 0} onClick={() => queryNav(`/student-query/classification?page=${review.page - 1}${initialQ ? `&q=${encodeURIComponent(initialQ)}` : ""}`)}>Previous</Btn>
              <span className="sub2 tnum">Page {review.page + 1} of {pages}</span>
              <Btn kind="ghost" disabled={review.page + 1 >= pages} onClick={() => queryNav(`/student-query/classification?page=${review.page + 1}${initialQ ? `&q=${encodeURIComponent(initialQ)}` : ""}`)}>Next</Btn>
            </div>
          </PBody>
        ) : null}
      </Panel>

      {open ? (
        <Modal title={`Classify ${open.surname}, ${open.other_names}`} sub={open.classification_note ?? undefined} onClose={() => setOpen(null)}
          foot={<><Btn kind="ghost" onClick={() => setOpen(null)}>Cancel</Btn><Btn kind="primary" onClick={() => decide()}>Record the decision</Btn></>}>
          <Note kind="info" title="Decide from the admission record">
            Read the admission letter or the record of the admission before deciding. The decision is kept with your reason; a later one supersedes it and both stay on the student&rsquo;s history.
          </Note>
          <Field id="cl-type" label="Programme type" required>
            <select id="cl-type" className="ctl" value={type} onChange={(e) => setType(e.target.value)}>
              <option value="">Choose…</option>
              {review.types.map((x) => <option key={x.code} value={x.code}>{x.name}</option>)}
            </select>
          </Field>
          <Field id="cl-route" label="Admission route" hint="Leave as read from the entry mode unless the record says otherwise">
            <select id="cl-route" className="ctl" value={route} onChange={(e) => setRoute(e.target.value)}>
              <option value="">As the entry mode reads</option>
              {review.routes.map((x) => <option key={x.code} value={x.code}>{x.name}</option>)}
            </select>
          </Field>
          <Field id="cl-centre" label="Centre" hint="Leave unset to keep the programme type's centre">
            <select id="cl-centre" className="ctl" value={centre} onChange={(e) => setCentre(e.target.value)}>
              <option value="">The programme type&rsquo;s centre</option>
              {review.centres.map((x) => <option key={x.code} value={x.code}>{x.name}</option>)}
            </select>
          </Field>
          <Field id="cl-reason" label="Reason" required error={err ?? undefined}>
            <textarea id="cl-reason" className="ctl" rows={3} maxLength={1000} value={reason} onChange={(e) => setReason(e.target.value)} placeholder="e.g. The admission letter (ref …) admits the student to B.Sc. Accounting through UTME" />
          </Field>
        </Modal>
      ) : null}
    </>
  );
}
