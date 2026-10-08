"use client";

/** V362: the registrations of a session made without the semester's school fees cleared — read for the Bursary and the
 *  Registry to act on; nothing here changes a registration or a payment */
import { useRouter } from "next/navigation";
import { Note, PageHead, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { day } from "@/components/proto/blocks";
import { money } from "@/lib/format";

export interface UnpaidRow {
  registration_id: string; student_id: string; number: string; name: string; programme: string | null; faculty: string | null; level: number;
  semester: number; status: string; submitted_at: string | null; approved_at: string | null; stated: boolean; due: number | null; paid: number;
}
export interface UnpaidView { session: string; scheduleFrom: string | null; total: number; notStated: number; unpaid: number; rows: UnpaidRow[]; sessions: string[] }

const SEM = (n: number) => (n === 1 ? "First" : n === 2 ? "Second" : n === 3 ? "Third" : String(n));

export function UnpaidRegistrations({ view }: { view: UnpaidView }) {
  const router = useRouter();
  const sessions = view.sessions.includes(view.session) ? view.sessions : [view.session, ...view.sessions];
  return (
    <>
      <PageHead
        description={<>Course registrations of the session made while the semester&rsquo;s school fees were not cleared — the fees not yet stated for the student on Fee Setup, or stated and not paid. From V362 a registration, an examination card, results and an identity card wait on stated and paid fees; these were made before. Nothing here changes a registration or a payment: what is done about each is the Bursary&rsquo;s and the Registry&rsquo;s own act.</>}
        actions={
          <select className="ctl" aria-label="Session" value={view.session} onChange={(e) => router.push(`/finance/unpaid-registrations?session=${encodeURIComponent(e.target.value)}`)}>
            {sessions.map((s) => <option key={s} value={s}>{s}</option>)}
          </select>
        }
      />
      <Tiles
        items={[
          ["Registrations", view.total.toLocaleString(), null, `${view.session} · fees not cleared`],
          ["Fees not stated", view.notStated.toLocaleString(), view.notStated ? "var(--red-ink)" : null, "No fee line applies to the student"],
          ["Stated, not paid", view.unpaid.toLocaleString(), view.unpaid ? "var(--red-ink)" : null, "Short of the semester's fees"],
          ["Fee schedule from", view.scheduleFrom ?? "—", null, "Earlier sessions were the old portal's"],
        ]}
      />
      {view.notStated > 0 ? (
        <Note kind="info" title={`${view.notStated.toLocaleString()} registration${view.notStated === 1 ? "" : "s"} with no fee stated for the student`}>
          The Bursary states the session&rsquo;s fees on Fee Setup and Schedule; each student then owes their line and pays it before the next semester registers. A group the University means to be free is stated as a ₦0 line.
        </Note>
      ) : null}
      <Panel title="Registrations without fees cleared" right={`${view.rows.length.toLocaleString()} shown · ${view.session}`}>
        {view.rows.length === 0 ? (
          <PBody><span className="sub2">Every registration of {view.session} has its semester&rsquo;s fees cleared.</span></PBody>
        ) : (
          <DTable
            cols={["Number", "Name", "Programme", "Level|mid", "Semester|mid", "Registration|mid", "Fees|mid", "Due|num", "Paid|num"]}
            rows={view.rows.map((r) => [
              <span className="tnum" key="n">{r.number}</span>,
              <strong key="m">{r.name}</strong>,
              <span className="sub2" key="p">{r.programme ?? "—"}{r.faculty ? <div>{r.faculty}</div> : null}</span>,
              <span className="tnum" key="l">{r.level}</span>,
              <span key="s">{SEM(r.semester)}</span>,
              <span key="st"><Pil kind={r.status === "SUBMITTED" ? "info" : "ok"}>{r.status.toLowerCase()}</Pil><div className="sub2">{day(r.approved_at ?? r.submitted_at ?? "")}</div></span>,
              r.stated ? <Pil kind="warn" key="f">Not paid</Pil> : <Pil kind="bad" key="f">Not stated</Pil>,
              <span className="tnum" key="d">{r.due == null ? "—" : money(r.due)}</span>,
              <span className="tnum" key="pd">{money(r.paid)}</span>,
            ])}
            texts={view.rows.map((r) => `${r.number} ${r.name} ${r.programme ?? ""} ${r.faculty ?? ""} ${r.stated ? "not paid" : "not stated"}`)}
            title={`Registrations without fees cleared · ${view.session}`}
          />
        )}
      </Panel>
    </>
  );
}
