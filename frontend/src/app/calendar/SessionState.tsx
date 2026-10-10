"use client";

/**
 * The University's academic state at a glance (V289): the current session
 * and its open semester, the next planned session and how far its fresh
 * students' preparation has gone, the timeline of every session on the
 * calendar, the readiness checks of the transition and the transition
 * itself (the Director of ICT's, the Registrar's or the Super
 * Administrator's), and the log of every transition attempted.
 */
import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import type { Problem } from "@/lib/api";
import type { CalendarData, ReadinessCheck, SessionRow, TransitionRow } from "@/lib/calendar";
import { d, semesterName, sessionLabel, withThousands } from "@/lib/calendar";
import { useQueryNav } from "@/lib/query-nav";
import { Btn, Note, Panel, PBody, Pil, Tick } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";

/** who may make a planned session current, as the API allows (CalendarController.TRANSITIONERS) */
const TRANSITIONERS = ["ict", "registrar", "dregistrar", "super"];

export function statePill(state: string) {
  const kind = state === "CURRENT" ? "ok" : state === "PLANNED" ? "info" : state === "DRAFT" ? "warn" : state === "ARCHIVED" ? "grey" : "bad";
  return <Pil kind={kind} key="s">{sessionLabel(state)}</Pil>;
}

function whenAt(iso: string | null | undefined) {
  return iso ? new Date(iso).toLocaleString("en-GB", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit", timeZone: "Africa/Lagos" }) : "—";
}

/** the timeline: each session a bar on one shared span of days, current in green, planned in the accent, the rest grey */
function Timeline({ sessions, now }: { sessions: SessionRow[]; now: number }) {
  const rows = [...sessions].sort((a, b) => a.startsOn.localeCompare(b.startsOn));
  if (!rows.length) return null;
  const min = new Date(rows[0].startsOn).getTime();
  const max = Math.max(...rows.map((r) => new Date(r.endsOn).getTime()));
  const span = Math.max(1, max - min);
  const today = now;
  const todayPct = today >= min && today <= max ? ((today - min) / span) * 100 : null;
  return (
    <div className="timeline">
      {rows.map((r) => {
        const left = ((new Date(r.startsOn).getTime() - min) / span) * 100;
        const width = Math.max(1.5, ((new Date(r.endsOn).getTime() - new Date(r.startsOn).getTime()) / span) * 100);
        const tone = r.state === "CURRENT" ? "timeline__bar--current" : r.state === "PLANNED" ? "timeline__bar--planned" : r.state === "DRAFT" ? "timeline__bar--draft" : "timeline__bar--past";
        return (
          <div className="timeline__row" key={r.name}>
            <div className="timeline__label"><b className="tnum">{r.name}</b><span className="sub2">{sessionLabel(r.state)}</span></div>
            <div className="timeline__track">
              <div className={`timeline__bar ${tone}`} style={{ left: `${left.toFixed(2)}%`, width: `${width.toFixed(2)}%` }} title={`${d(r.startsOn)} – ${d(r.endsOn)}`} />
              {todayPct !== null ? <div className="timeline__today" style={{ left: `${todayPct.toFixed(2)}%` }} title="Today" /> : null}
            </div>
          </div>
        );
      })}
    </div>
  );
}

function Checks({ checks }: { checks: ReadinessCheck[] }) {
  return (
    <ul className="checks">
      {checks.map((c) => (
        <li key={c.code} className={`checks__item${c.ok ? " checks__item--ok" : c.blocking ? " checks__item--bad" : " checks__item--warn"}`}>
          <span className="checks__mark">{c.ok ? <Tick size={13} colour="var(--green-ink)" /> : c.blocking ? "✕" : "!"}</span>
          <span className="checks__text">{c.detail}{!c.ok && !c.blocking ? <span className="sub2"> (advisory; blocks the automatic clock)</span> : null}</span>
        </li>
      ))}
    </ul>
  );
}

export function SessionState({ calendar, actingOffice }: { calendar: CalendarData; actingOffice: string | null }) {
  const router = useRouter();
  const go = useQueryNav();
  const sessions = calendar.sessions;
  const current = sessions.find((s) => s.name === calendar.current) ?? null;
  const next = sessions.find((s) => s.name === calendar.next) ?? null;
  const looking = calendar.session;
  const openSem = calendar.semesters.find((s) => s.state === "OPEN") ?? null;
  const canTransition = actingOffice !== null && TRANSITIONERS.includes(actingOffice);
  const [readiness, setReadiness] = useState<{ session: string; ready: boolean; readyForAutomatic: boolean; checks: ReadinessCheck[] } | null>(null);
  const [modal, setModal] = useState<string | null>(null);
  const [confirm, setConfirm] = useState("");
  const [reason, setReason] = useState("");
  const [minute, setMinute] = useState("");
  const [busy, setBusy] = useState(false);
  const [refusal, setRefusal] = useState<Problem | null>(null);
  const [now] = useState(() => Date.now());

  const target = next?.name ?? null;
  useEffect(() => {
    if (!target) return;
    let live = true;
    fetch(`/api/bff/api/v1/calendar/sessions/${target}/readiness`).then((r) => (r.ok ? r.json() : null)).then((j) => { if (live && j) setReadiness(j); }).catch(() => undefined);
    return () => { live = false; };
  }, [target]);

  async function transition() {
    if (!modal) return;
    setBusy(true); setRefusal(null);
    try {
      const r = await fetch(`/api/bff/api/v1/calendar/sessions/${modal}/transition`, {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason || `Transition into ${modal}`) },
        body: JSON.stringify({ confirm: confirm.trim(), reason: reason.trim(), senateMinute: minute.trim() || null }),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) { const p = j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }; setRefusal(p); notifyProblem(p); return; }
      notify(j.outcome === "ALREADY" ? `${modal} was already the current session` : `${modal} is now the current session${j.from ? `; ${j.from} is completed` : ""}`);
      setModal(null); setConfirm(""); setReason(""); setMinute("");
      router.refresh();
    } finally {
      setBusy(false);
    }
  }

  const fresh = next?.freshStudents ?? 0;
  const prep = next ? (fresh > 0 || (readiness?.checks.some((c) => c.code === "FEE_SCHEDULE" && c.ok) ?? false) ? "ACTIVE" : "NOT STARTED") : null;
  const transitions: TransitionRow[] = calendar.transitions ?? [];

  return (
    <>
      <Panel title="Academic state" right={<span className="row row--inline row--tight"><label htmlFor="cal-session" className="sub2">Looking at</label><select id="cal-session" className="ctl" value={looking ?? ""} onChange={(e) => go(`/calendar?session=${encodeURIComponent(e.target.value)}`)}>{sessions.map((s) => <option key={s.name} value={s.name}>{s.name} — {sessionLabel(s.state).toUpperCase()}</option>)}</select></span>}>
        <PBody>
          <div className="grid grid--2">
            <div className="card card--state">
              <div className="sub2">CURRENT SESSION</div>
              {current ? (
                <>
                  <div className="row row--inline row--tight"><span className="kpi tnum">{current.name}</span>{statePill(current.state)}</div>
                  <div className="sub2">Current semester: <b>{calendar.session === current.name ? (openSem ? `${semesterName(openSem.number)} semester` : "none open") : "—"}</b> · {withThousands(current.students)} enrolled · runs {d(current.startsOn)} – {d(current.endsOn)}</div>
                  <div className="sub2">Made current {whenAt(current.madeCurrentAt)}{current.senateMinute ? ` · ${current.senateMinute}` : ""}</div>
                </>
              ) : (
                <div className="sub2">No session is current.</div>
              )}
            </div>
            <div className="card card--state">
              <div className="sub2">NEXT PLANNED SESSION</div>
              {next ? (
                <>
                  <div className="row row--inline row--tight"><span className="kpi tnum">{next.name}</span>{statePill(next.state)}</div>
                  <div className="sub2">Fresh student preparation: <Pil kind={prep === "ACTIVE" ? "ok" : "grey"}>{prep}</Pil> · {withThousands(fresh)} entrant{fresh === 1 ? "" : "s"} on the register</div>
                  <div className="sub2">Transition: <b>{next.transitionMode === "AUTOMATIC" ? "automatic" : "by hand"}</b>{next.transitionsOn ? ` on ${d(next.transitionsOn)}` : next.transitionMode === "AUTOMATIC" ? " — no date set, so the clock will not act" : ""}</div>
                </>
              ) : (
                <div className="sub2">No planned session follows{current ? ` ${current.name}` : ""}.</div>
              )}
            </div>
          </div>
          <Timeline sessions={sessions} now={now} />
        </PBody>
      </Panel>

      {next ? (
        <Panel title={`Transition into ${next.name}`} right={canTransition ? <Btn kind="primary" disabled={busy} onClick={() => setModal(next.name)}>Transition now</Btn> : <span className="sub2">The Director of ICT or the Registrar transitions</span>}>
          <PBody>
            <div className="sub2">
              At the transition {current ? <><b>{current.name}</b> becomes <b>Completed</b> and </> : null}<b>{next.name}</b> becomes <b>Current</b>. No student is moved.
            </div>
            {readiness ? (
              <>
                <div className="row row--inline row--tight mt-2">
                  <Pil kind={readiness.ready ? "ok" : "bad"}>{readiness.ready ? "READY TO TRANSITION" : "BLOCKED"}</Pil>
                  <Pil kind={readiness.readyForAutomatic ? "ok" : "warn"}>{readiness.readyForAutomatic ? "READY FOR THE CLOCK" : "THE CLOCK WOULD WAIT"}</Pil>
                </div>
                <Checks checks={readiness.checks} />
              </>
            ) : <div className="sub2 mt-2">Reading the readiness checks…</div>}
          </PBody>
        </Panel>
      ) : null}

      <Panel title="Session transitions" right="Every attempt, with its outcome">
        {transitions.length === 0 ? (
          <PBody><div className="sub2">No transition has been attempted yet.</div></PBody>
        ) : (
          <DTable
            cols={["When|mid", "From", "To", "Outcome|mid", "Mode|mid", "By", "Reason"]}
            rows={transitions.map((t) => [
              <span className="tnum" key="w">{whenAt(t.at)}</span>,
              <span className="tnum" key="f">{t.from_session ?? "—"}</span>,
              <b className="tnum" key="t">{t.to_session}</b>,
              <Pil kind={t.outcome === "DONE" ? "ok" : t.outcome === "BLOCKED" ? "bad" : "grey"} key="o">{t.outcome === "DONE" ? "Done" : t.outcome === "BLOCKED" ? "Blocked" : "Already current"}</Pil>,
              <span className="sub2" key="m">{t.mode === "AUTOMATIC" ? "Automatic" : "Manual"}</span>,
              <span className="sub2" key="b">{t.actor ?? "—"}{t.actor_office ? ` · ${t.actor_office}` : ""}</span>,
              <span className="sub2" key="r">{t.reason ?? "—"}</span>,
            ])}
          />
        )}
      </Panel>

      {modal ? (
        <Modal title={`Transition into ${modal}`} sub={current ? `${current.name} → Completed · ${modal} → Current` : `${modal} → Current`} onClose={() => { setModal(null); setRefusal(null); }} wide
          foot={<><Btn kind="ghost" onClick={() => { setModal(null); setRefusal(null); }}>Cancel</Btn><span className="grow" /><Btn kind="urgent" disabled={busy || confirm.trim().toUpperCase() !== "TRANSITION" || !reason.trim()} onClick={() => void transition()}>{busy ? "Transitioning…" : "Complete the transition"}</Btn></>}>
          {refusal ? <ProblemNotice problem={refusal} /> : null}
          <Note kind="info" title="This is the University's official session change">
            Logged with your name and reason. Historical records and student accounts are untouched.
          </Note>
          {readiness && readiness.session === modal ? <Checks checks={readiness.checks} /> : null}
          <div className="grid grid--2 rfgrid">
            <Field id="tr_reason" label="Reason, as it will read in the log" full>
              <input id="tr_reason" className="ctl" value={reason} autoComplete="off" placeholder={`Senate resolved to run ${modal}; the ${current?.name ?? "previous"} session has ended`} onChange={(e) => setReason(e.target.value)} />
            </Field>
            <Field id="tr_minute" label="Senate minute" hint="Needed only if none is recorded against the session yet">
              <input id="tr_minute" className="ctl tnum" value={minute} autoComplete="off" placeholder="SEN/2026/…" onChange={(e) => setMinute(e.target.value)} />
            </Field>
            <Field id="tr_confirm" label="Type TRANSITION to confirm">
              <input id="tr_confirm" className="ctl" value={confirm} autoComplete="off" onChange={(e) => setConfirm(e.target.value)} />
            </Field>
          </div>
        </Modal>
      ) : null}
    </>
  );
}
