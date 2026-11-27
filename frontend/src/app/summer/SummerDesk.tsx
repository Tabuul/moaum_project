"use client";

/** V735 · the Summer Semester desk, V779 · open to every final-year and spillover student. The Academic Office (and the Registrar, the
 *  Deputy Registrar, the Super Administrator) set the Summer of a session — a third period of its own — identify the eligible,
 *  authorise a student for an approved academic reason, tell the students, verify what the students selected against the record, and
 *  open the examinations. Everyone who reads it sees the students (a Head of Department their department's, a Dean their faculty's),
 *  the verification queue, the classes and the reports. One route; the view is in the address, and the server reads only the view
 *  that is shown. */
import { useState } from "react";
import { Btn, Note, Pil, Tabs } from "@/components/proto/ui";
import { useQueryNav } from "@/lib/query-nav";
import { DESK_VIEWS, deskHref, periodForWord, periodWords, type DeskView, type SummerIssue, type SummerPeriod, type SummerReportView, type SummerRosterView, type SummerSelectionsView } from "@/lib/summer";
import { day } from "@/lib/format";
import type { OrgOptions } from "@/lib/summer-org";
import { SummerCourses, type SummerCourseRow } from "./SummerCourses";
import { SummerPeriodActs, type SummerAuthorisationToReview } from "./SummerPeriodActs";
import { SummerQueue } from "./SummerQueue";
import { SummerReports } from "./SummerReports";
import { SummerRoster } from "./SummerRoster";

/** what the server read for the view shown */
export type DeskData =
  | { view: "review"; filters: Record<string, string>; page: number; data: SummerSelectionsView }
  | { view: "students"; filters: Record<string, string>; page: number; org: OrgOptions; data: SummerRosterView }
  | { view: "reports"; filters: Record<string, string>; org: OrgOptions; data: SummerReportView }
  | { view: "courses"; data: SummerCourseRow[] }
  | { view: "period"; period: SummerPeriod | null; issues: SummerIssue[]; toReview: SummerAuthorisationToReview[] };

export function SummerDesk({ periods, session, sessions, view, maySet, actingOffice, desk }: {
  periods: SummerPeriod[]; session: string | null; sessions: string[]; view: DeskView; maySet: boolean; actingOffice: string | null; desk: DeskData | null;
}) {
  const go = useQueryNav();
  const [newSession, setNewSession] = useState("");
  const period = (desk?.view === "period" ? desk.period : null) ?? periods.find((p) => p.session === session) ?? null;
  const unset = sessions.filter((s) => !periods.some((p) => p.session === s));
  return (
    <>
      <div className="row" style={{ flexWrap: "wrap", gap: "var(--s-2)", alignItems: "center" }}>
        <span className="sub2">Session</span>
        {periods.map((p) => (
          <Btn key={p.session} kind={p.session === session ? "primary" : "ghost"} size="sm" onClick={() => go(deskHref(p.session, view))}>{p.session}</Btn>
        ))}
        {maySet && unset.length ? (
          <>
            <select aria-label="A session without a Summer" className="ctl" style={{ width: "auto" }} value={newSession} onChange={(e) => setNewSession(e.target.value)}>
              <option value="">Set a new Summer…</option>
              {unset.map((x) => <option key={x} value={x}>{x}</option>)}
            </select>
            <Btn kind="ghost" size="sm" disabled={!newSession} onClick={() => go(deskHref(newSession, "period"))}>Open</Btn>
          </>
        ) : null}
      </div>

      {!session ? (
        <Note kind="info" title="No Summer Semester is set">{maySet ? "Choose a session above to set its Summer Semester." : "The Academic Office sets the Summer Semester of a session."}</Note>
      ) : (
        <>
          {period && view !== "period" ? (
            <div className="row" style={{ flexWrap: "wrap", gap: "var(--s-2)", alignItems: "center" }}>
              <b>Summer Semester {session}</b>
              <Pil kind={periodWords(period)[1]}>{periodWords(period)[0].toUpperCase()}</Pil>
              <span className="sub2">Registration {period.registration_opens ? `${day(period.registration_opens)} – ${day(period.registration_closes)}` : "not dated"} · for {periodForWord(period.categories)}</span>
            </div>
          ) : null}
          <Tabs label="What to show" value={view} onChange={(v) => go(deskHref(session, v))} items={DESK_VIEWS.map((v) => ({ id: v.id, label: v.label }))} />
          {!period && (view !== "period" || !maySet) ? (
            <Note kind="info" title="This session has no Summer Semester yet">{maySet ? "Set it on the Period and acts tab." : "The Academic Office sets the Summer Semester of a session."}</Note>
          ) : desk?.view === "review" ? (
            <SummerQueue key={`${session}-${JSON.stringify(desk.filters)}`} session={session} view={desk.data} filters={desk.filters} page={desk.page} maySet={maySet} />
          ) : desk?.view === "students" ? (
            <SummerRoster session={session} view={desk.data} filters={desk.filters} page={desk.page} org={desk.org} />
          ) : desk?.view === "reports" ? (
            <SummerReports session={session} view={desk.data} filters={desk.filters} org={desk.org} />
          ) : desk?.view === "courses" ? (
            <SummerCourses session={session} courses={desk.data} actingOffice={actingOffice} />
          ) : desk?.view === "period" ? (
            <SummerPeriodActs session={session} period={period} maySet={maySet} issues={desk.issues} toReview={desk.toReview} />
          ) : null}
        </>
      )}
    </>
  );
}
