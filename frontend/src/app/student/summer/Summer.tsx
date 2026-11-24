"use client";

/** studentSummer — V735, V779: the Summer Semester. The student sees whether they may take it and why; the courses of their
 *  programme and their record, both semesters together, to search and select (the courses they believe they still owe: nothing
 *  here says they owe nothing); the itemised fee and one payment for what is owed; the Academic Office's verification of each
 *  selection with its reason; and the registration the payment makes, which they print. */
import { useEffect } from "react";
import { useRouter } from "next/navigation";
import { Btn, KvGrid, LinkBtn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { onDay, when } from "../common";
import { reasonHeader } from "@/lib/reason";
import {
  categoryPill, courseSemesterWord, failedInWord, incompleteResultsNote, naira, nextStep, notEligibleWord, num, periodForSentence, periodWords, plural,
  registrationCategoryWord, verificationTone, verificationWord, type MySummer,
} from "@/lib/summer";
import { Breakdown } from "./Breakdown";
import { Picker } from "./Picker";
import { Selections } from "./Selections";

function Period({ d }: { d: MySummer }) {
  const p = d.period;
  if (!p) return null;
  const [word, tone] = periodWords(p);
  return (
    <Panel title={`Summer Semester ${p.session}`} right={<Pil kind={tone}>{word.toUpperCase()}</Pil>}>
      <PBody>
        <KvGrid pairs={[
          ["Registration opens", onDay(p.registration_opens)],
          ["Registration closes", onDay(p.registration_closes)],
          ["Examinations", p.exams_from ? `${onDay(p.exams_from)} – ${onDay(p.exams_to)}` : "Not yet dated"],
          ["Results expected", onDay(p.results_due)],
        ]} />
        <div className="sub2 mt-1">{periodForSentence(p.categories)}{p.max_courses ? ` At most ${p.max_courses} courses a student.` : ""}</div>
      </PBody>
    </Panel>
  );
}

/** the Summer registration the payment made — printable, with the Academic Office's verification of each course beside it */
function Registered({ d, name, number, printHref }: { d: MySummer; name: string; number: string; printHref: string | null }) {
  const rows = d.registered ?? [];
  if (!rows.length) return null;
  const units = rows.reduce((s, r) => s + (r.units ?? 0), 0);
  return (
    <Panel title="Summer Semester registration" right={<span className="row row--inline row--tight">
      <Pil kind="ok">{(rows[0].registration_status ?? "APPROVED").toUpperCase()}</Pil>
      {printHref ? <a className="btn btn--primary btn--sm" href={printHref} target="_blank" rel="noopener">Print confirmation</a> : null}
    </span>}>
      <PBody>
        <div className="sub2">{name} · <span className="tnum">{number}</span> · {d.session} Summer Semester · {plural(rows.length, "course")}, {units} units</div>
        <div className="sub2 mt-1">A course marked pending verification is registered at your request; the Academic Office verifies each against your record. A course found not outstanding or rejected is taken off your registration and its fee is held for you as a Summer credit.</div>
      </PBody>
      <DTable title={`Summer Semester ${d.session} · ${name} · ${number}`} cols={["Course", "Title", "Units|num", "Course's semester", "Owed in", "Registration category", "Verification", "Lecturer", "Paid by"]} rows={rows.map((r) => [
        <b key={`c${r.course_code}`} className="tnum">{r.course_code}</b>,
        <span key={`n${r.course_code}`}>{r.title ?? "—"}</span>,
        <span key={`u${r.course_code}`} className="tnum">{r.units ?? "—"}</span>,
        <span key={`s${r.course_code}`}>{courseSemesterWord({ both_semesters: false, course_semester: r.course_semester })}</span>,
        <span key={`f${r.course_code}`} className="sub2">{failedInWord({ original_session: r.original_session, original_semester: r.original_semester, basis: r.basis ?? "STUDENT_SELECTED" })}</span>,
        <span key={`g${r.course_code}`}>{r.basis ? registrationCategoryWord(r.basis) : r.category_label ?? "—"}</span>,
        r.verification ? <Pil key={`v${r.course_code}`} kind={verificationTone(r.verification)}>{verificationWord(r.verification)}</Pil> : <span key={`v${r.course_code}`} className="sub2">—</span>,
        <span key={`l${r.course_code}`}>{r.lecturer ?? "Not yet allocated"}</span>,
        r.paid_reference ? <LinkBtn key={`p${r.course_code}`} kind="ghost" href={`/student/receipt/${encodeURIComponent(r.paid_reference)}`}>{r.receipt_no ?? "Receipt"}</LinkBtn>
          : <span key={`p${r.course_code}`} className="tnum t-xs">—</span>,
      ])} />
    </Panel>
  );
}

/** the page asks the server, once after it renders, to read the student's selections against the published results (a selection a
 *  published pass has overtaken is taken back or flagged); it reads itself again only when something changed. A page read never
 *  writes: this is its own request, and ICT Support's read-only view of the portal is refused it and goes on. */
function useReconcile(session: string | null, reconcilable: boolean) {
  const router = useRouter();
  useEffect(() => {
    if (!session || !reconcilable) return;
    let live = true;
    void fetch("/api/bff/api/v1/me/summer/reconcile", {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-Reason": reasonHeader("Summer Semester selections read against the published results"), "X-Background": "1" },
      body: JSON.stringify({ session }),
    })
      .then((r) => (r.ok ? r.json() : null))
      .then((j: { changed?: number } | null) => { if (live && j && Number(j.changed ?? 0) > 0) router.refresh(); })
      .catch(() => undefined);
    return () => { live = false; };
  }, [session, reconcilable, router]);
}

export function Summer({ d, paid = null, name, number, sessions = [] }: { d: MySummer; paid?: string | null; name: string; number: string; sessions?: string[] }) {
  const a = d.account;
  const payments = d.payments ?? [];
  useReconcile(d.session, !!d.summary?.reconcilable);
  const back = paid ? payments.find((p) => p.reference === paid) ?? null : null;
  const confirmed = !!back?.confirmed_at;
  const confirming = !!paid && !confirmed && !!back;
  if (!d.period) {
    return <Note kind="info" title="No Summer Semester is set">The Academic Office sets the Summer Semester of a session; you will be told when it opens.</Note>;
  }
  const e = d.eligibility;
  const s = d.summary;
  const due = num(s?.due ?? a?.due);
  const paidSum = num(s?.paid ?? a?.paid);
  const took = due > 0 || paidSum > 0 || (s?.selected ?? 0) > 0 || (s?.notOutstanding ?? 0) + (s?.rejected ?? 0) > 0;
  const incomplete = incompleteResultsNote(d);
  const printHref = d.session && (s?.selected ?? 0) > 0 ? `/student/summer/confirmation/pdf?session=${encodeURIComponent(d.session)}` : null;
  const selectedCount = s?.selected ?? 0;
  return (
    <>
      {confirming ? (
        <div className="card"><div className="card__body" style={{ alignItems: "center", textAlign: "center", gap: "var(--s-4)", padding: "var(--s-6) var(--s-5)" }}>
          <div><div className="t-lg b700" style={{ letterSpacing: "-.3px" }}>Confirming your payment</div>
            <p className="sub2" style={{ margin: "6px auto 0", maxWidth: "44ch", lineHeight: 1.55 }}>Reference {paid}. Your courses are registered when it is confirmed.</p></div>
          <Btn kind="ghost" onClick={() => window.location.reload()}>Check again</Btn>
        </div></div>
      ) : null}
      {confirmed && back ? (
        <Note kind="ok" title="Summer Semester payment confirmed">Reference {back.reference} · {naira(back.amount)}{back.receipt_no ? ` · receipt ${back.receipt_no}` : ""}. Your courses are registered below; the Academic Office verifies each against your record.</Note>
      ) : null}
      <Tiles items={[
        ["Summer Semester", d.period.session, null, periodWords(d.period)[0]],
        ["You", e?.eligible ? <Pil key="cat" kind="ok">{categoryPill(e.category)}</Pil> : took ? "Registered" : "Not eligible", null,
          e?.eligible ? "Eligible for the Summer Semester" : took ? "" : notEligibleWord(e?.reason)],
        ["Selected", String(selectedCount), null, `${selectedCount === 1 ? "course" : "courses"} · ${s?.units ?? 0} unit${(s?.units ?? 0) === 1 ? "" : "s"}`],
        ["Owed now", naira(due), null, `${naira(paidSum)} paid`],
      ]} />
      <Note kind={e?.eligible || took ? "info" : "bad"} title={nextStep(d)}>
        {e?.eligible
          ? "Select the courses you believe you still owe, from the first and second semesters together. A course is registered once its fee is paid; you may add more while registration is open."
          : took ? "What you paid for stays registered." : "If you believe this is wrong, ask your department or the Academic Office."}
      </Note>
      {incomplete ? <Note kind="info" title="Your earlier results">{incomplete}</Note> : null}
      {(s?.clarifications ?? 0) > 0 ? <Note kind="info" title={`${plural(s?.clarifications ?? 0, "course")} the Academic Office asked you about`}>Answer in My selections below.</Note> : null}
      {(s?.notOutstanding ?? 0) + (s?.rejected ?? 0) > 0 ? (
        <Note kind="info" title={`${plural((s?.notOutstanding ?? 0) + (s?.rejected ?? 0), "selection")} found not outstanding or rejected`}>See the reasons in My selections below. A course taken off your registration has its fee held for you as a Summer credit; the Bursary applies it to your next Summer or refunds it.</Note>
      ) : null}
      <Period d={d} />
      {e?.eligible || took ? <Breakdown d={d} /> : null}
      {e?.eligible && d.period.open_now ? <Picker d={d} sessions={sessions} /> : null}
      {e?.eligible || took ? <Selections d={d} printHref={printHref} /> : null}
      <Registered d={d} name={name} number={number} printHref={printHref} />
      {payments.length ? (
        <Panel title="Summer Semester payments" right={String(payments.length)}>
          <DTable cols={["Reference", "For", "Amount|num", "Drawn", "Status"]} rows={payments.map((p) => [
            <span key={`r${p.reference}`} className="tnum t-xs">{p.reference}</span>,
            <span key={`f${p.reference}`} className="sub2">{p.purpose.replace(/^Summer semester fees, [^:]+: /, "")}</span>,
            <span key={`a${p.reference}`} className="tnum">{naira(p.amount)}</span>,
            <span key={`d${p.reference}`} className="sub2">{when(p.generated_at)}</span>,
            p.confirmed_at ? <span key={`s${p.reference}`} className="row" style={{ gap: "var(--s-1)" }}><Pil kind="ok">PAID</Pil><LinkBtn kind="ghost" href={`/student/receipt/${encodeURIComponent(p.reference)}`}>Receipt{p.receipt_no ? ` ${p.receipt_no}` : ""}</LinkBtn></span>
              : <Pil key={`s${p.reference}`} kind="warn">AWAITING PAYMENT</Pil>,
          ])} />
        </Panel>
      ) : null}
    </>
  );
}
