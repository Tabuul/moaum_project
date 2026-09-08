"use client";

/**
 * Session and semester setup — proto/part33.html tSession, with the calendar
 * the University actually keeps behind it: the sessions are
 * policy.academic_session with the number of people enrolled in each, the
 * semesters are policy.semester, and the unit limits policy.level_limit.
 * The two rules that matter are the database's — one session current, none
 * overlapping — so this screen lets them refuse and shows the refusal.
 */
import { reasonHeader } from "@/lib/reason";
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import type { CalendarData, LevelLimitRow, SemesterRow, SessionRow } from "@/lib/calendar";
import { SEMESTER_NAMES, d, daysBetween, semesterName, span, withThousands, within } from "@/lib/calendar";
import { Btn, Note, Panel, Pil, Tick, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { ProblemNotice } from "@/components/ProblemNotice";
import { SessionModal, type Draft } from "./CalendarForms";
import { LevelModal, SemesterModal } from "./SemesterLevelForms";

type Open =
  | { kind: "session"; row: SessionRow | null }
  | { kind: "semester"; row: SemesterRow | null }
  | { kind: "level"; row: LevelLimitRow | null }
  | null;

function sessPill(state: string) {
  return state === "CURRENT" ? (
    <Pil kind="ok" key="s">Current</Pil>
  ) : state === "PLANNED" ? (
    <Pil kind="info" key="s">Planned</Pil>
  ) : (
    <Pil kind="bad" key="s">Closed</Pil>
  );
}

const SEM_STATE: Record<string, string> = { Open: "OPEN", "Not yet open": "NOT_YET_OPEN", Closed: "CLOSED" };

export function SessionSetup({
  calendar,
  problem,
  actingOffice,
}: {
  calendar: CalendarData | null;
  problem: Problem | null;
  actingOffice: string | null;
}) {
  const router = useRouter();
  const [open, setOpen] = useState<Open>(null);
  const [busy, setBusy] = useState(false);
  const [refusal, setRefusal] = useState<Problem | null>(null);

  const isSuper = actingOffice === "super";
  const sessions = calendar?.sessions ?? [];
  const current = calendar?.current ?? null;
  const currentRow = sessions.find((s) => s.name === current) ?? null;
  const looking = calendar?.session ?? current;
  const semesters = calendar?.semesters ?? [];
  const limits = calendar?.levelLimits ?? [];
  const openSem = semesters.find((s) => s.state === "OPEN") ?? null;
  const watch = openSem ?? semesters[0] ?? null;

  async function send(method: "PUT" | "POST", path: string, body: unknown, reason: string): Promise<boolean> {
    setBusy(true);
    setRefusal(null);
    try {
      const response = await fetch(`/api/bff${path}`, {
        method,
        headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) },
        body: body === undefined ? undefined : JSON.stringify(body),
      });
      if (response.ok) {
        setOpen(null);
        router.refresh();
        return true;
      }
      const json = await response.json().catch(() => null);
      setRefusal(json && typeof json === "object" && "status" in json ? (json as Problem) : { status: response.status, title: response.statusText });
      return false;
    } finally {
      setBusy(false);
    }
  }

  async function saveSession(row: SessionRow | null, draft: Draft) {
    const name = (row?.name ?? draft.n).trim();
    if (!/^\d{4}\/\d{4}$/.test(name)) {
      setRefusal({
        status: 422,
        title: "The session has to be named as the University names one",
        detail: `“${name}” is not a session. A session is written 2027/2028 — four digits, an oblique, four digits.`,
        remedy: { message: "Name it as the two calendar years it spans, e.g. 2027/2028.", office: "Academic Office" },
      });
      return;
    }
    const wanted = draft.state === "Current" ? null : draft.state.toUpperCase();
    const ok = await send(
      "PUT",
      `/api/v1/calendar/sessions/${name}`,
      {
        startsOn: draft.opens || null,
        endsOn: draft.closes || null,
        semesters: draft.sems.startsWith("3") ? 3 : 2,
        senateMinute: draft.minute.trim() || null,
        state: wanted,
      },
      `${name} recorded on the calendar`,
    );
    if (ok && draft.state === "Current") {
      await send("POST", `/api/v1/calendar/sessions/${name}/make-current`, { senateMinute: draft.minute.trim() }, `${name} made the current session`);
    }
  }

  async function saveSemester(draft: Draft) {
    const n = SEMESTER_NAMES.indexOf(draft.n) + 1 || 1;
    await send(
      "PUT",
      `/api/v1/calendar/sessions/${looking}/semesters/${n}`,
      {
        lecturesFrom: draft.lectFrom || null,
        lecturesTo: draft.lectTo || null,
        registrationOpens: draft.ropen || null,
        registrationCloses: draft.rclose || null,
        lateRegistrationCloses: draft.late || null,
        examsFrom: draft.examsFrom || null,
        examsTo: draft.examsTo || null,
        resultsDue: draft.due || null,
        queryWindow: draft.query.trim() || null,
        state: SEM_STATE[draft.state] ?? "NOT_YET_OPEN",
      },
      `${draft.n} semester windows of ${looking} recorded`,
    );
  }

  async function saveLevel(draft: Draft) {
    await send(
      "PUT",
      `/api/v1/calendar/levels/${draft.n}`,
      {
        appliesTo: draft.who,
        minUnits: Number(draft.min || 0),
        maxUnits: Number(draft.max || 0),
        carryoverCounts: draft.carry === "Yes",
        instrument: draft.instrument.trim() || null,
      },
      `Unit limits for level ${draft.n} recorded`,
    );
  }

  const reg = watch
    ? within(watch.registrationOpens, watch.registrationCloses)
      ? (["Open", "var(--green-ink)", `Closes ${d(watch.registrationCloses)}`] as const)
      : watch.registrationCloses
        ? (["Closed", "var(--red-ink)", `Closed ${d(watch.registrationCloses)}`] as const)
        : (["—", null, "No registration window is set"] as const)
    : (["—", null, "No registration window is set"] as const);
  const due = watch?.resultsDue ? daysBetween(watch.lecturesFrom, watch.resultsDue) : null;

  return (
    <>
      {problem ? <ProblemNotice problem={problem} /> : null}
      {refusal && !open ? <ProblemNotice problem={refusal} /> : null}

      <Note kind="info" title="The session is the spine everything else hangs on">
        Registration windows, fee schedules, grading schemes, examination sessions, result sets and the publication embargo
        are all bounded by a session and a semester. Exactly one session is current at a time, and the portal will not let
        two overlap &mdash; that is an exclusion constraint in the database, not a check on this form.
        {isSuper ? (
          <>
            {" "}
            You are here as the <b>Super Administrator</b>. The Academic Office runs this calendar day to day; you can reach
            it so the platform is configurable when the Registry is not at its desk, and the log records which of you made
            each change.
          </>
        ) : null}
      </Note>

      <Tiles
        items={[
          [
            "Current session",
            current ?? "—",
            current ? "var(--green-ink)" : null,
            currentRow ? `Opened ${d(currentRow.startsOn)}` : "None is current until a Senate minute is recorded",
          ],
          [
            "Current semester",
            openSem ? semesterName(openSem.number) : "—",
            null,
            openSem
              ? openSem.lecturesTo
                ? `Ends ${d(openSem.lecturesTo)}`
                : "No end of lectures recorded"
              : semesters.length
                ? `No semester of ${looking} is open`
                : `No semester windows are recorded for ${looking ?? "any session"}`,
          ],
          ["Registration", reg[0], reg[1], reg[2]],
          [
            "Score sheets due",
            watch?.resultsDue ? d(watch.resultsDue, false) : "—",
            watch?.resultsDue ? "var(--chrome)" : null,
            due === null ? "No date the score sheets are due is set" : `${due} days from opening`,
          ],
        ]}
      />

      <Panel title="Academic sessions" right="One current, the rest closed or planned">
        {sessions.length === 0 ? (
          <div className="card__body">
            <Note kind="info" title="No session has been recorded yet">
              Nothing can be registered, examined or classified until a session exists and Senate&rsquo;s minute opening it is
              recorded against it.
            </Note>
          </div>
        ) : (
          <DTable
            cols={["Session|mid", "Opens|mid", "Closes|mid", "Senate minute", "Students|mid", "State|mid", "Action|num"]}
            texts={sessions.map((s) => `${s.name} ${s.state} ${s.senateMinute ?? ""}`)}
            rows={sessions.map((s) => [
              <b className="tnum" key="n">{s.name}</b>,
              <span className="tnum" key="o">{d(s.startsOn)}</span>,
              <span className="tnum" key="c">{d(s.endsOn)}</span>,
              s.senateMinute ? <span className="sub2 tnum" key="m">{s.senateMinute}</span> : <span className="sub2" key="m">&mdash;</span>,
              s.students ? <span className="tnum" key="s">{withThousands(s.students)}</span> : <span className="sub2" key="s">&mdash;</span>,
              sessPill(s.state),
              <Btn kind="ghost" key="a" onClick={() => setOpen({ kind: "session", row: s })}>
                {s.state === "CLOSED" ? "Reopen" : "Edit"}
              </Btn>,
            ])}
          />
        )}
        <div className="rfbar">
          <Btn kind="primary" onClick={() => setOpen({ kind: "session", row: null })}>
            + New session
          </Btn>
          <span className="sub2">It is held as planned until its Senate minute is recorded against it.</span>
        </div>
      </Panel>

      <Panel title={`Semesters of ${looking ?? "no session"}`} right="Each with its own windows">
        {semesters.length === 0 ? (
          <div className="card__body">
            <Note kind="info" title={`No semester windows are recorded for ${looking ?? "any session"}`}>
              Registration, examinations and the results due date all read these dates, and each of them refuses while the
              date it depends on is unset. Nothing is assumed on their behalf.
            </Note>
          </div>
        ) : (
          <DTable
            cols={["Semester", "Lectures|mid", "Registration closes|mid", "Examinations|mid", "Results due|mid", "State|mid", "Action|num"]}
            rows={semesters.map((w) => [
              <strong key="n">{semesterName(w.number)}</strong>,
              <span className="tnum" key="l">{span(w.lecturesFrom, w.lecturesTo)}</span>,
              <span className="tnum" key="r">{d(w.registrationCloses)}</span>,
              <span className="tnum" key="e">{span(w.examsFrom, w.examsTo)}</span>,
              <span className="tnum" key="d">{d(w.resultsDue)}</span>,
              w.state === "OPEN" ? (
                <Pil kind="ok" key="s">Open</Pil>
              ) : w.state === "CLOSED" ? (
                <Pil kind="bad" key="s">Closed</Pil>
              ) : (
                <Pil kind="info" key="s">Not yet open</Pil>
              ),
              <Btn kind="ghost" key="a" onClick={() => setOpen({ kind: "semester", row: w })}>
                Edit windows
              </Btn>,
            ])}
          />
        )}
        <div className="rfbar">
          <Btn kind="primary" disabled={!looking} onClick={() => setOpen({ kind: "semester", row: null })}>
            + New semester
          </Btn>
          <span className="sub2">Every date on that form changes what a student can do today.</span>
        </div>
      </Panel>

      <Panel title="Levels and unit limits" right="Per level, per semester">
        {limits.length === 0 ? (
          <div className="card__body">
            <Note kind="info" title="No unit limits are recorded">
              Until they are, a registration has no ceiling to be measured against, and the course form refuses rather than
              accepting whatever fits.
            </Note>
          </div>
        ) : (
          <DTable
            cols={["Level|mid", "Applies to", "Minimum units|mid", "Maximum units|mid", "Carryover counts toward the maximum|mid", "Action|num"]}
            rows={limits.map((l) => [
              <b className="tnum" key="l">{l.level}</b>,
              <span className="sub2" key="w">{l.appliesTo}</span>,
              <span className="tnum" key="min">{l.minUnits}</span>,
              <span className="tnum" key="max">{l.maxUnits}</span>,
              l.carryoverCounts ? <Tick size={15} colour="var(--green-ink)" key="c" /> : <span className="sub2" key="c">No</span>,
              <Btn kind="ghost" key="a" onClick={() => setOpen({ kind: "level", row: l })}>
                Edit
              </Btn>,
            ])}
          />
        )}
        <div className="rfbar">
          <Btn kind="primary" onClick={() => setOpen({ kind: "level", row: null })}>
            + New level
          </Btn>
        </div>
      </Panel>

      {open?.kind === "session" ? (
        <SessionModal
          row={open.row}
          busy={busy}
          problem={refusal}
          onClose={() => {
            setOpen(null);
            setRefusal(null);
          }}
          onSave={(draft) => void saveSession(open.row, draft)}
          onEnd={(reason) =>
            void send("POST", `/api/v1/calendar/sessions/${open.row?.name}/close`, undefined, reason || `${open.row?.name} closed`)
          }
        />
      ) : null}

      {open?.kind === "semester" && looking ? (
        <SemesterModal
          session={looking}
          row={open.row}
          next={semesters.length + 1}
          busy={busy}
          problem={refusal}
          onClose={() => {
            setOpen(null);
            setRefusal(null);
          }}
          onSave={(draft) => void saveSemester(draft)}
        />
      ) : null}

      {open?.kind === "level" ? (
        <LevelModal
          row={open.row}
          busy={busy}
          problem={refusal}
          onClose={() => {
            setOpen(null);
            setRefusal(null);
          }}
          onSave={(draft) => void saveLevel(draft)}
        />
      ) : null}
    </>
  );
}
