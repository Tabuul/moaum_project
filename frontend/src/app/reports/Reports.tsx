"use client";

import { useRouter } from "next/navigation";
import { Btn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { REPORTS } from "@/lib/report";

export interface FacultyRow { faculty: string; male: number; female: number; total: number }
/** one row of the due register (reports.due_register, V229) */
export interface DueRow {
  slug: string; title: string; owner_office: string; owner_label: string; frequency: string; purpose: string;
  last_due: string | null; last_period: string | null; last_snapshot: string | null; last_taken_at: string | null; last_filed_at: string | null; last_filed_to: string | null;
  next_due: string | null; next_period: string | null; next_snapshot: string | null; next_taken_at: string | null; next_filed_at: string | null;
  latest_snapshot: string | null; latest_taken_at: string | null;
  state: string; days: number | null;
}
/** a kept copy, as the list gives it */
export interface KeptRow {
  id: string; report: string; title: string; period: string; due_on: string | null; row_count: number; taken_at: string; taken_office: string | null;
  verification_code: string; filed_to: string | null; filed_at: string | null; taken_by_name: string | null; filed_by_name: string | null;
}
const FREQ: Record<string, string> = { MONTHLY: "Monthly", PER_SEMESTER: "Per semester", PER_SESSION: "Per session", ON_DEMAND: "On demand" };
const dmy = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" }) : "—");
function statePill(r: DueRow) {
  switch (r.state) {
    case "OVERDUE": return <Pil kind="bad">Overdue · {r.days} days</Pil>;
    case "DUE": return <Pil kind={r.days != null && r.days <= 30 ? "warn" : "info"}>{r.days != null && r.days < 0 ? `Due · ${-r.days} days ago` : r.days === 0 ? "Due today" : `Due in ${r.days ?? "—"} days`}</Pil>;
    case "TAKEN": return <Pil kind="info">Kept · not filed</Pil>;
    case "FILED": return <Pil kind="ok">Filed</Pil>;
    default: return <Pil kind="grey">On demand</Pil>;
  }
}
/** the last due date is what a Run answers while it stands unanswered; otherwise the next */
const pending = (r: DueRow) => r.state === "OVERDUE" || (r.state === "DUE" && !!r.last_due && !r.last_snapshot);

/** The returns desk, as the prototype's Reports & returns screen lays it out: the standard reports the
 *  office may take — each with its owner, its frequency, and a Run that opens it as a branded, printable
 *  document with a CSV beside it — and the session's enrolment by faculty, read off the register. */
export function Reports({ session, sessions, activeOffice, byFaculty, due, kept, trends }: {
  session: string; sessions: { name: string; state: string }[]; activeOffice: string | null; byFaculty: FacultyRow[] | null;
  due: { asAt: string; rows: DueRow[]; overdue: number; dueSoon: number } | null; kept: KeptRow[];
  /** the period-over-period charts, rendered by the page (a server component may pass a node) */
  trends?: React.ReactNode;
}) {
  const router = useRouter();
  const mine = REPORTS.filter((r) => activeOffice != null && r.offices.includes(activeOffice));
  const pick = (name: string) => router.push(`/reports?session=${encodeURIComponent(name)}`);
  const open = (slug: string) => router.push(`/reports/${slug}/view?session=${encodeURIComponent(session)}`);
  const stamp = new Date().toLocaleString("en-GB", { day: "numeric", month: "long", year: "numeric", hour: "2-digit", minute: "2-digit" });
  const grand = byFaculty ? byFaculty.reduce((s, f) => s + f.total, 0) : 0;
  const mayRun = (slug: string) => activeOffice != null && (REPORTS.find((r) => r.slug === slug)?.offices.includes(activeOffice) || slug === "students" || slug === "staff");
  /* run a return for the period a due date answers: the session it falls in, or the desk's session for a monthly one */
  const runFor = (r: DueRow) => {
    if (r.slug === "students" || r.slug === "staff") return router.push(`/reports/${r.slug}`);
    const dueOn = pending(r) ? r.last_due : r.next_due;
    const period = pending(r) ? r.last_period : r.next_period;
    const ses = period && /^\d{4}\/\d{4}$/.test(period) ? period : session;
    router.push(`/reports/${r.slug}/view?session=${encodeURIComponent(ses)}${dueOn ? `&due=${dueOn}` : ""}`);
  };
  const filedCount = kept.filter((k) => k.filed_at).length;

  return (
    <>
      <Note kind="info" title="Every report shows the moment its data was taken">
        A return is read off the register for the session you choose — the crest, the figures, and the footing that says it is verified
        against the record. Run one to read it on screen, print it or save it as a PDF, or take the same rows as a CSV.
      </Note>

      {due ? (
        <>
          <Tiles items={[
            ["Overdue", String(due.overdue), due.overdue ? "var(--red-ink)" : "var(--green-ink)", due.overdue ? "past the due date, nothing kept" : "nothing is past its date"],
            ["Due within 30 days", String(due.dueSoon), due.dueSoon ? "var(--chrome)" : null, "not yet kept"],
            ["Kept copies", String(kept.length), null, "the latest twelve, below"],
            ["Filed", String(filedCount), filedCount ? "var(--green-ink)" : null, "of those kept"],
          ]} />
          <Panel title="Due register" right={`As at ${dmy(due.asAt)} · a return is answered by a kept copy`}>
            <DTable cols={["Return", "Owner", "Frequency|mid", "Last due", "Next due", "State|mid", "|num"]}
              rows={due.rows.map((r) => [
                <span key="t"><span style={{ fontWeight: 600 }}>{r.title}</span><div className="sub2">{r.purpose}{r.owner_office === activeOffice ? " · yours" : ""}</div></span>,
                <span key="o">{r.owner_label}</span>,
                <span key="f" className="sub2">{FREQ[r.frequency] ?? r.frequency}</span>,
                <span key="l" className="sub2">{r.last_due ? <>{dmy(r.last_due)}<div>{r.last_period}{r.last_snapshot ? <> · <a href={`/reports/snapshots/${r.last_snapshot}`}>{r.last_filed_at ? "filed" : "kept"}</a></> : null}</div></> : "—"}</span>,
                <span key="n" className="sub2">{r.next_due ? <>{dmy(r.next_due)}<div>{r.next_period}{r.next_snapshot ? <> · <a href={`/reports/snapshots/${r.next_snapshot}`}>{r.next_filed_at ? "filed" : "kept"}</a></> : null}</div></> : "—"}</span>,
                <span key="s">{statePill(r)}</span>,
                mayRun(r.slug)
                  ? <Btn kind={pending(r) ? "primary" : "ghost"} key="run" onClick={() => runFor(r)}>{r.frequency === "ON_DEMAND" ? "Open" : "Run"}</Btn>
                  : <span key="run" className="sub2">—</span>,
              ])}
              texts={due.rows.map((r) => `${r.title} ${r.owner_label} ${r.state}`)} />
            <PBody><div className="sub2">Run a return and press <b>Keep a copy</b> to answer its due date; then mark the kept copy <b>filed</b> once it has gone to the body it is for. A fortnight&rsquo;s grace runs after each due date before a return shows as overdue.</div></PBody>
          </Panel>
        </>
      ) : null}

      <Panel title="Session" right={sessions.find((s) => s.name === session)?.state ?? ""}>
        <PBody>
          <div style={{ display: "flex", gap: 10, alignItems: "center", flexWrap: "wrap" }}>
            <label htmlFor="rp-session" className="sub2" style={{ fontWeight: 600 }}>Reporting session</label>
            <select id="rp-session" className="ctl" style={{ maxWidth: 260 }} value={session} onChange={(e) => pick(e.target.value)}>
              {sessions.length ? sessions.map((s) => <option key={s.name} value={s.name}>{s.name}{s.state === "CURRENT" ? " · current" : ""}</option>)
                : <option value={session}>{session}</option>}
            </select>
            <span className="sub2">Financial returns read the calendar year the session opens in.</span>
          </div>
        </PBody>
      </Panel>

      <Panel title="Registers — view all" right="Filter, search, print or take to Excel">
        <DTable cols={["Register", "Filter by", "|num"]} rows={[
          [
            <span key="t"><span style={{ fontWeight: 600 }}>Student register</span><div className="sub2">Every student on the books, with a count of what matched</div></span>,
            <span key="f" className="sub2">Faculty · department · programme · level · sex · status · entry mode · entry session · name or number</span>,
            <Btn kind="primary" key="o" onClick={() => router.push("/reports/students")}>Open</Btn>,
          ],
          [
            <span key="t"><span style={{ fontWeight: 600 }}>Staff register</span><div className="sub2">Every member of staff, academic and non-teaching, with rank and offices held</div></span>,
            <span key="f" className="sub2">Faculty · department · rank · category · status · office held · name, staff number or email</span>,
            <Btn kind="primary" key="o" onClick={() => router.push("/reports/staff")}>Open</Btn>,
          ],
        ]} />
      </Panel>

      {kept.length ? (
        <Panel title="Kept copies" right="Returns as they were when kept — each with a verification code">
          <DTable cols={["Return", "Period", "Rows|num", "Taken", "Code|mid", "Filed", "|num"]}
            rows={kept.map((k) => [
              <span key="t" style={{ fontWeight: 600 }}>{k.title}</span>,
              <span key="p">{k.period}</span>,
              <span key="r" className="tnum">{Number(k.row_count).toLocaleString()}</span>,
              <span key="tk" className="sub2">{dmy(k.taken_at)}{k.taken_by_name ? ` · ${k.taken_by_name}` : ""}</span>,
              <span key="c" className="tnum">{k.verification_code}</span>,
              k.filed_at ? <Pil key="f" kind="ok">{k.filed_to}</Pil> : <Pil key="f" kind="grey">Not filed</Pil>,
              <Btn kind="ghost" key="o" onClick={() => router.push(`/reports/snapshots/${k.id}`)}>Open</Btn>,
            ])}
            texts={kept.map((k) => `${k.title} ${k.period} ${k.verification_code} ${k.filed_to ?? ""}`)} />
        </Panel>
      ) : null}

      <Panel title="Standard reports" right="Run against the register, never a copy of it">
        {mine.length ? (
          <DTable cols={["Report", "Owner", "Frequency|mid", "Last run|mid", "|num"]}
            rows={mine.map((r) => [
              <span key="t"><span style={{ fontWeight: 600 }}>{r.title}</span><div className="sub2">{r.purpose}</div></span>,
              <span key="o">{r.owner}</span>,
              <span key="f" className="sub2">{r.frequency}</span>,
              <span key="l" className="sub2">Live · {session}</span>,
              <Btn kind="primary" key="run" onClick={() => open(r.slug)}>Run</Btn>,
            ])}
            texts={mine.map((r) => `${r.title} ${r.owner} ${r.purpose}`)} />
        ) : <PBody><div className="sub2">This office does not take any of the portal&rsquo;s returns.</div></PBody>}
      </Panel>

      {trends ?? null}

      {byFaculty ? (
        <Panel title="Enrolment by faculty" right={`${session} · data as at ${stamp}`}>
          {byFaculty.length ? (
            <DTable cols={["Faculty", "Male|num", "Female|num", "Total|num", "Share|mid"]}
              rows={byFaculty.map((f) => [
                <span key="f" style={{ fontWeight: 600 }}>{f.faculty}</span>,
                <span key="m" className="tnum">{f.male.toLocaleString()}</span>,
                <span key="w" className="tnum">{f.female.toLocaleString()}</span>,
                <span key="t" className="tnum" style={{ fontWeight: 600 }}>{f.total.toLocaleString()}</span>,
                <span key="s" className="tnum">{grand ? `${((f.total / grand) * 100).toFixed(1)}%` : "—"}</span>,
              ])}
              texts={byFaculty.map((f) => f.faculty)} />
          ) : <PBody><div className="sub2">No student was admitted for {session} yet, so there is no enrolment to show.</div></PBody>}
          {byFaculty.length ? (
            <PBody>
              <div className="sub2">{grand.toLocaleString()} students in the {session} cohort across {byFaculty.length} facult{byFaculty.length === 1 ? "y" : "ies"}. Run the <b>Enrolment by programme, level and sex</b> return above for the full NUC table.</div>
            </PBody>
          ) : null}
        </Panel>
      ) : null}
    </>
  );
}
