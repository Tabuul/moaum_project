"use client";

/**
 * A student's academic level at the ICT Support Desk (V500) — used on Student Level Management and from the student's support record.
 * The student, the level the record holds, the levels the programme has, what the cohort engine computes and what the registrations
 * carry, every earlier change; then PROGRESS TO NEXT LEVEL or CHANGE/CORRECT LEVEL, each with a reason (and the ticket where there is
 * one), the session's registration named before it is confirmed. The server decides it all again and keeps the record of it.
 * A student past the programme's length is read as the cohort engine reads them — SP1, SP2 … or the limit reached, against the
 * limit the policy allows — with the courses still owed, and a record left below the final level offered its correction.
 */
import { useEffect, useState, type ReactNode } from "react";
import { reasonHeader } from "@/lib/reason";
import { notify } from "@/components/proto/Toast";
import { Btn, Note, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import {
  LEVEL_REASON_MIN, levelBody, levelLabel, levelPath, reasonOk, refusalWords, registrationWarning, ruleWord, spilloverChoiceLabel, spilloverChoiceNote, spilloverOf,
  type LevelAction, type LevelState,
} from "@/lib/level-management";

export interface TicketRef { id: string; number: string; subject?: string }
interface TicketRow { id: string; number: string; subject: string; status: string }

const when = (iso: string | null) => (iso ? new Date(iso).toLocaleString("en-GB", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" }) : "—");
const semWord = (n: number) => (n === 1 ? "First" : n === 2 ? "Second" : "Third");

function Kv({ k, v }: { k: string; v: ReactNode }) {
  return <div className="kv"><span className="k">{k}</span><span className="v">{v}</span></div>;
}

export function LevelManagement({ studentId, ticket, onDone }: { studentId: string; ticket: TicketRef | null; onDone?: () => void }) {
  const [state, setState] = useState<LevelState | null>(null);
  const [loadFailed, setLoadFailed] = useState<string | null>(null);
  const [tickets, setTickets] = useState<TicketRow[]>([]);
  const [reload, setReload] = useState(0);
  const [act, setAct] = useState<LevelAction | null>(null);
  const [level, setLevel] = useState<number | null>(null);
  const [spYear, setSpYear] = useState<number | null>(null);   // V628: a spillover year chosen instead of a level
  const [reason, setReason] = useState("");
  const [chosenTicket, setChosenTicket] = useState("");
  const [ack, setAck] = useState(false);
  const [working, setWorking] = useState(false);
  const [failure, setFailure] = useState("");

  const hasTicket = !!ticket;
  useEffect(() => {
    let alive = true;
    void (async () => {
      const r = await fetch(`/api/bff/api/v1/helpdesk/support/students/${studentId}/level`, { cache: "no-store" });
      const j = await r.json().catch(() => null);
      if (!alive) return;
      if (!r.ok) { setLoadFailed(refusalWords(j?.detail) || j?.title || "The student's level could not be read just now."); return; }
      setState(j as LevelState);
      if (!hasTicket) {
        const t = await fetch(`/api/bff/api/v1/helpdesk/support/students/${studentId}/tickets`, { cache: "no-store" });
        const rows = t.ok ? ((await t.json()) as TicketRow[]) : [];
        if (alive) setTickets(rows.filter((x) => x.status !== "CLOSED"));
      }
    })();
    return () => { alive = false; };
  }, [studentId, hasTicket, reload]);

  if (loadFailed) return <Note kind="bad" title="The student's level could not be read">{loadFailed}</Note>;
  if (!state) return <div className="sub2">Reading the student&rsquo;s level…</div>;

  const s = state.student;
  const o = state.options;
  const ticketId = ticket?.id ?? (chosenTicket || null);
  const choices = o.spilloverChoices ?? [];
  const chosenSp = spYear == null ? null : choices.find((c) => c.year === spYear) ?? null;
  const warning = registrationWarning(state, act, !!chosenSp);
  const target = act === "PROGRESS" ? o.nextLevel : chosenSp ? o.finalLevel : level;
  const ready = !!act && target != null && reasonOk(reason) && (!warning || ack);
  const path = levelPath(state.registrations);

  const sp = spilloverOf(state);
  const owed = state.carryovers ?? [];
  const spState = sp ? state.position?.spillover_state : null;

  function open(a: LevelAction, to?: number) {
    setAct(a);
    setLevel(a === "CORRECTION" ? (to ?? o.otherLevels[0] ?? null) : null);
    setSpYear(a === "CORRECTION" && to == null && !o.otherLevels.length && choices.length ? choices[0].year : null);
    setReason("");
    setAck(false);
    setFailure("");
  }

  async function confirm() {
    if (!act || !ready || working) return;
    setWorking(true);
    setFailure("");
    try {
      const r = await fetch(`/api/bff/api/v1/helpdesk/support/students/${studentId}/level`, {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Student level ${act === "PROGRESS" ? "progressed" : "corrected"} at the ICT Support Desk: ${reason.trim()}`) },
        body: JSON.stringify(levelBody(act, state!, level, reason, ticketId, ack, chosenSp ? chosenSp.year : null)),
      });
      const j = (await r.json().catch(() => null)) as Record<string, unknown> | null;
      if (!r.ok) {
        setFailure(refusalWords(String(j?.detail ?? "")) || String(j?.title ?? "The level could not be changed."));
        return;
      }
      notify(j?.alreadyDone ? "The level was changed moments ago; nothing more was done."
        : chosenSp ? `Set to ${chosenSp.year === 0 ? "the final year" : `SP${chosenSp.year}`} at ${j?.newLevel} Level (expected completion ${j?.expectedCompletion}).`
        : `Level ${act === "PROGRESS" ? "progressed" : "corrected"}: ${j?.previousLevel} → ${j?.newLevel}.`);
      if (j?.view) setState(j.view as LevelState);
      setAct(null);
      setReload((n) => n + 1);
      onDone?.();
    } catch {
      setFailure("The portal could not be reached; nothing was changed. Try again.");
    } finally {
      setWorking(false);
    }
  }

  return (
    <div className="stack">
      <div className="eyebrow">Student information</div>
      <div className="grid grid--3" aria-label="Student information">
        <Kv k="Full name" v={<b>{s.full_name}</b>} />
        <Kv k="Matriculation number" v={<span className="tnum">{s.matric_no ?? "—"}</span>} />
        <Kv k="JAMB number" v={<span className="tnum">{s.jamb_reg_no ?? "—"}</span>} />
        <Kv k="Faculty" v={s.faculty ?? "—"} />
        <Kv k="Department" v={s.department ?? "—"} />
        <Kv k="Programme" v={s.programme ?? "—"} />
        <Kv k="Programme type" v={s.programme_type ?? "—"} />
        <Kv k="Admission session" v={s.admission_session ?? "—"} />
        <Kv k="Current academic session" v={state.session} />
        <Kv k="Student status" v={<Pil kind={["ACTIVE", "ADMITTED", "PROBATION"].includes(s.status) ? "ok" : "warn"}>{s.status.replace(/_/g, " ")}</Pil>} />
        <Kv k="Study mode" v={s.study_mode ? s.study_mode.replace(/_/g, " ") : "—"} />
        <Kv k="Admission route" v={s.admission_route ? s.admission_route.replace(/_/g, " ") : "—"} />
      </div>

      <div className="eyebrow">Academic level</div>
      <div className="grid grid--3" aria-label="Academic level">
        <Kv k="Current level" v={<><b className="t-lg">{o.currentLevel}</b>{sp && !sp.behind ? <> <Pil kind={sp.atLimit ? "bad" : "warn"}>{sp.short}</Pil></> : null}</>} />
        <Kv k="Academic session" v={state.session} />
        <Kv k="Semester" v={`${semWord(state.semester)} Semester`} />
        <Kv k="The programme's levels" v={o.postgraduate ? `${o.finalLevel} (postgraduate)` : `${o.levels[0]} to ${o.finalLevel}`} />
        <Kv k="Level the cohort engine computes" v={state.position?.computed_level ?? "—"} />
        <Kv k="Spillover" v={sp ? <Pil kind={sp.atLimit ? "bad" : "warn"}>{sp.long}</Pil> : o.postgraduate ? "Not applicable (postgraduate)" : "Within the programme's length"} />
        <Kv k="Expected completion" v={state.position?.expected_completion ?? "—"} />
        <Kv k="Graduation" v={state.position?.graduation_state ? state.position.graduation_state.replace(/_/g, " ").toLowerCase() : "—"} />
      </div>
      {/* V595: the final year is the one the register shows (the first session at the final level), so the sessions are counted past it */}
      {sp ? (
        <Note kind={sp.atLimit || sp.behind ? "bad" : "info"} title={`${sp.long}${sp.years != null ? ` — ${sp.years} session${sp.years === 1 ? "" : "s"} past the final year${state.position?.expected_completion ? ` (${state.position.expected_completion})` : ` of the programme's ${state.position?.duration_years ?? "?"}`}` : ""}${sp.limit != null ? `; the policy allows ${sp.limit}` : ""}`}
          action={sp.behind && state.mayCorrect && o.otherLevels.includes(sp.final)
            ? <Btn kind="primary" onClick={() => open("CORRECTION", sp.final)}>{`CORRECT TO ${sp.final} LEVEL (${sp.short})`}</Btn> : undefined}>
          {sp.behind
            ? <>The record reads {o.currentLevel} Level, but a spillover student is at the programme&rsquo;s final level, <b>{sp.final} ({sp.short})</b>. Correct it here, or for many at once on Student Cohorts &rarr; Level corrections. </>
            : <>A spillover student is not moved to a higher level: the record stays at <b>{sp.final} ({sp.short})</b> and each new session counts as the next spillover year. </>}
          {sp.atLimit
            ? <>The limit the policy allows is reached: the Registry decides on Student Cohorts &rarr; Reconciliation whether the student stays active (flagged), or becomes dormant or withdrawn. </>
            : <>The way out is passing the courses still owed; once they are passed and published the student is a graduation candidate on Student Cohorts &rarr; Reconciliation. </>}
          {state.position?.last_session ? <>Last session on record: {state.position.last_session}.</> : null}
        </Note>
      ) : null}
      {sp ? (owed.length ? (
        <DTable pageSize={0} noPrint title={`Courses still owed (${owed.length})`} cols={["Course", "Title", "Units|num", "Failed in"]} rows={owed.map((c) => [
          <b key="c" className="tnum">{c.course_code}</b>, <span key="t">{c.title ?? "—"}</span>, <span key="u" className="tnum">{c.units ?? "—"}</span>,
          <span key="f" className="sub2">{c.failed_in ?? "—"}</span>,
        ])} />
      ) : <div className="sub2">No course is owed on the published results: if the student is in the final year&rsquo;s courses too, they are a graduation candidate once those are published.</div>) : null}
      {path.length ? (
        <div className="sub2" aria-label="Levels on the record">
          Levels on the record: {path.map((p) => `${p.level} Level (${p.session})`).join(" → ")} → <b>Current {o.currentLevel} Level</b>
        </div>
      ) : <div className="sub2">No course registration on the record yet.</div>}

      <div className="row row--inline" style={{ gap: 8, flexWrap: "wrap" }}>
        {/* a spillover student is not moved one level at a time: the record is put at the final level, by the correction above */}
        <Btn kind="primary" disabled={!state.mayProgress || !!o.progressRefusal || !!sp} onClick={() => open("PROGRESS")}
          title={sp ? `A spillover student is not progressed one level at a time; the record is put at ${sp.final} Level (${sp.short}).` : o.progressRefusal ? refusalWords(o.progressRefusal) : undefined}>
          {o.nextLevel ? `PROGRESS TO ${o.nextLevel} LEVEL` : "PROGRESS TO NEXT LEVEL"}
        </Btn>
        <Btn kind="secondary" disabled={!state.mayCorrect || !!o.correctRefusal || (!o.otherLevels.length && !choices.length)} onClick={() => open("CORRECTION")}>CHANGE/CORRECT LEVEL</Btn>
      </div>
      {!state.mayProgress && !state.mayCorrect ? <Note kind="info" title="You can read this student's level but not change it">Your posting does not carry level changes for this student. The Head of the ICT Support Desk grants them.</Note> : null}
      {o.correctRefusal ? <Note kind="bad" title="The level cannot be changed">{refusalWords(o.correctRefusal)}</Note>
        : o.progressRefusal && !sp ? <div className="sub2">{refusalWords(o.progressRefusal)}</div> : null}

      <div className="eyebrow">Level history</div>
      {state.history.length ? (
        <DTable pageSize={0} cols={["Date/time", "Previous|num", "New|num", "How", "By", "Reason", "Ticket|mid"]} rows={state.history.map((h) => [
          <span key="d" className="sub2 tnum">{when(h.decided_at)}</span>,
          <span key="p" className="tnum">{h.previous_level ?? "—"}</span>,
          <b key="n" className="tnum">{h.new_level}</b>,
          <span key="r">{ruleWord(h.rule)}</span>,
          <span key="b">{h.officer ?? "—"}<div className="sub2">{h.actor_office ?? ""}</div></span>,
          <span key="w" className="sub2">{h.reason}</span>,
          <span key="t" className="tnum sub2">{h.ticket_number ?? "—"}</span>,
        ])} />
      ) : <div className="sub2">No level change is on the record.</div>}

      {act ? (
        <Modal title={act === "PROGRESS" ? "PROGRESS LEVEL" : "CHANGE/CORRECT LEVEL"} sub={`${s.full_name} · ${s.matric_no ?? s.application_no ?? ""}`} onClose={() => { if (!working) setAct(null); }}
          foot={<>
            <Btn kind="ghost" disabled={working} onClick={() => setAct(null)}>CANCEL</Btn>
            <Btn kind="primary" disabled={!ready} busy={working} busyLabel={act === "PROGRESS" ? "Updating level..." : "Saving level change..."} onClick={() => confirm()}>
              {act === "PROGRESS" ? "PROGRESS LEVEL" : "SAVE LEVEL CHANGE"}
            </Btn>
          </>}>
          <div className="stack">
            <div className="grid grid--2">
              <Kv k="Current level" v={<b>{o.currentLevel}</b>} />
              {act === "PROGRESS" ? <Kv k="Next level" v={<b>{o.nextLevel}</b>} /> : (
                <Field id="lv-to" label="Change to" required>
                  <select id="lv-to" className="ctl" value={chosenSp ? `sp${chosenSp.year}` : String(level ?? "")}
                    onChange={(e) => {
                      const v = e.target.value;
                      if (v.startsWith("sp")) { setSpYear(Number(v.slice(2))); setLevel(null); } else { setSpYear(null); setLevel(Number(v)); }
                    }}>
                    {choices.length ? (
                      <>
                        <optgroup label="Levels">
                          {o.otherLevels.map((l) => <option key={l} value={l}>{levelLabel(l, spState, sp?.final)}</option>)}
                        </optgroup>
                        <optgroup label="Spillover years (past the final level)">
                          {choices.map((c) => <option key={`sp${c.year}`} value={`sp${c.year}`}>{spilloverChoiceLabel(c, o.finalLevel)}</option>)}
                        </optgroup>
                      </>
                    ) : o.otherLevels.map((l) => <option key={l} value={l}>{levelLabel(l, spState, sp?.final)}</option>)}
                  </select>
                </Field>
              )}
            </div>
            {act === "CORRECTION" && chosenSp ? <Note kind="info" title={spilloverChoiceLabel(chosenSp, o.finalLevel)}>{spilloverChoiceNote(chosenSp, o.finalLevel, o.currentSession ?? state.session)}</Note>
              : act === "CORRECTION" ? <div className="sub2">Only the levels of the student&rsquo;s programme are offered{choices.length ? ", and the spillover years past its final level" : ""}. A correction puts right a data problem or records an authorised academic adjustment; it is recorded as a correction, apart from a progression.</div> : null}
            <Field id="lv-reason" label="Reason" required hint={`At least ${LEVEL_REASON_MIN} characters: what was checked, and why the level changes.`}>
              <textarea id="lv-reason" className="ctl" rows={3} maxLength={2000} value={reason} onChange={(e) => setReason(e.target.value)}
                placeholder="e.g. Student was incorrectly left at 300 Level after academic progression; 2025/2026 results checked." />
            </Field>
            {ticket ? <div className="sub2">On ticket <b className="tnum">{ticket.number}</b>{ticket.subject ? ` — ${ticket.subject}` : ""}</div> : tickets.length ? (
              <Field id="lv-ticket" label="Support ticket (optional)">
                <select id="lv-ticket" className="ctl" value={chosenTicket} onChange={(e) => setChosenTicket(e.target.value)}>
                  <option value="">No ticket</option>
                  {tickets.map((t) => <option key={t.id} value={t.id}>{t.number} — {t.subject}</option>)}
                </select>
              </Field>
            ) : null}
            {warning ? (
              <Note kind="bad" title="WARNING">
                {warning}
                <label className="row row--inline row--tight mt-1"><input type="checkbox" checked={ack} onChange={(e) => setAck(e.target.checked)} /> I have read this; continue</label>
              </Note>
            ) : null}
            {failure ? <Note kind="bad" title="The level was not changed">{failure}</Note> : null}
          </div>
        </Modal>
      ) : null}
    </div>
  );
}
