"use client";

/** rGraduation — proto/part9.html: the degree audit, computed, and the list Senate approves. */
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import type { Scope } from "@/lib/scope";
import type { GraduationView } from "@/lib/credentials";
import { ScopeBar, type ScopeStructure } from "@/components/proto/ScopeBar";
import { Btn, LinkBtn, Note, Panel, PBody, RoleLine, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Modal, Field } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Pil } from "@/components/proto/ui";
import { OVERALL_WORD, stateKind } from "@/lib/clearance";

export function Graduation({ scope, structure, sessions, view, actingOffice }: { scope: Scope; structure: ScopeStructure; sessions: string[]; view: GraduationView; actingOffice: string | null }) {
  const router = useRouter();
  const [problem, setProblem] = useState<Problem | null>(null);
  const [busy, setBusy] = useState(false);
  const [minute, setMinute] = useState<string | null>(null);
  const [said, setSaid] = useState<string | null>(null);
  const t = view.tiles;
  const office = ["academic", "registrar", "dregistrar", "records"].includes(actingOffice ?? "");
  // V416: final clearance from the graduation list — the Academic Office and the Registry start it
  const canStart = ["academic", "registrar", "dregistrar"].includes(actingOffice ?? "");
  const finalists = view.finalists ?? [];
  const notStarted = finalists.filter((f) => f.clearanceState === "NOT_STARTED").length;
  const byState = finalists.reduce<Record<string, number>>((a, f) => { a[f.clearanceState] = (a[f.clearanceState] ?? 0) + 1; return a; }, {});
  const [refused, setRefused] = useState<{ number: string; name: string; why: string }[]>([]);

  async function startFinal() {
    setBusy(true);
    setProblem(null);
    try {
      const body: Record<string, string> = { session: scope.session };
      if (scope.fac) body.fac = scope.fac;
      if (scope.dept) body.dept = scope.dept;
      if (scope.prog) body.prog = scope.prog;
      const r = await fetch("/api/bff/api/v1/clearance/start-graduands", { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Final clearance started for the ${scope.session} graduands`) }, body: JSON.stringify(body) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { const p = j ?? { status: r.status, title: r.statusText }; setProblem(p); notifyProblem(p); return; }
      setRefused(j.refused ?? []);
      notify(`Final clearance started for ${j.started} graduand${j.started === 1 ? "" : "s"}${j.refused?.length ? `; ${j.refused.length} refused` : ""} — each is told`);
      router.refresh();
    } finally {
      setBusy(false);
    }
  }

  async function post(path: string, body: unknown, reason: string) {
    setBusy(true);
    setProblem(null);
    try {
      const r = await fetch(path, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body ?? {}) });
      const j = await r.json().catch(() => null);
      if (!r.ok) {
        setProblem(j ?? { status: r.status, title: r.statusText }); notifyProblem(j ?? { status: r.status, title: r.statusText });
        return;
      }
      if (j && "audited" in j) setSaid(`${j.audited} finalists audited: ${j.passed} passed, ${j.outstanding} with an unmet requirement.`);
      if (j && "approved" in j) setSaid(`${j.approved} awards approved under ${j.senateMinute}.`);
      setMinute(null);
      notify(reason);
      router.refresh();
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      <RoleLine allowed={["academic", "registrar", "dregistrar", "records"]} actingOffice={actingOffice} canAct={office}
        action="Confirming graduands and the Senate list" />
      <ScopeBar scope={scope} structure={structure} sessions={sessions} what="candidates" count={t.finalists} of={t.finalists} />
      {t.outstanding ? (
        <Note kind="bad" title={`${t.outstanding} finalist${t.outstanding === 1 ? " has" : "s have"} an unmet requirement`} action={<LinkBtn href="#exceptions" kind="urgent">Open the exception list</LinkBtn>}>
          They cannot be presented to Senate until each gap is closed or waived.
        </Note>
      ) : t.finalists ? (
        <Note kind="ok" title="Every finalist audited has met the requirements">Nothing stands between the list and Senate but the clearance of those still held.</Note>
      ) : (
        <Note kind="info" title={`No degree audit has been run for ${scope.session}`} />
      )}
      {problem ? <ProblemNotice problem={problem} /> : null}
      {said ? <Note kind="info" title="Done">{said}</Note> : null}
      <Tiles items={[
        ["Finalists", t.finalists.toLocaleString(), null, `${scope.session} session`],
        ["Audit passed", t.auditPassed.toLocaleString(), "var(--green-ink)", "All requirements met"],
        ["Outstanding requirement", t.outstanding.toLocaleString(), "var(--red-ink)", "Cannot graduate yet"],
        ["Awaiting clearance", t.awaitingClearance.toLocaleString(), "var(--red-ink)", "Library, Bursary or hostel"],
      ]} />
      <div id="exceptions">
        <Panel title="Degree audit exceptions" right="Computed, not compiled by hand">
          <DTable
            cols={["Student", "Programme", "Unmet requirement", "CGPA|mid", "Action|num"]}
            rows={view.exceptions.map((x) => [
              <Two key="s" a={`${x.surname}, ${x.otherNames}`} b={x.number} />, <span key="p">{x.programmeName}</span>,
              <span key="u" className="ink-red">{x.unmet}</span>,
              <span className="tnum" key="c">{x.cgpa == null ? "—" : Number(x.cgpa).toFixed(2)}</span>,
              <LinkBtn key="a" href={`/students/${x.studentId}`} kind="ghost">Review</LinkBtn>,
            ])}
            texts={view.exceptions.map((x) => `${x.number} ${x.surname} ${x.otherNames} ${x.programmeName} ${x.unmet}`)}
          />
          {!view.exceptions.length ? <PBody><div className="sub2">No exception on the list.</div></PBody> : null}
        </Panel>
      </div>
      <Panel title="Final clearance" right={canStart && notStarted ? <Btn kind="go" disabled={busy} onClick={() => void startFinal()}>{busy ? "Starting…" : `Start final clearance for ${notStarted} graduand${notStarted === 1 ? "" : "s"}`}</Btn> : <LinkBtn href={`/clearance?${new URLSearchParams({ wf: "FINAL", session: scope.session }).toString()}`}>Open the clearance desk</LinkBtn>}>
        <PBody>
          <div className="row row--tight" style={{ flexWrap: "wrap", gap: "var(--s-2)" }}>
            {(["NOT_STARTED", "IN_PROGRESS", "PARTIALLY_CLEARED", "PENDING_ACTION", "NOT_CLEARED", "REJECTED", "COMPLETED"] as const).filter((k) => byState[k]).map((k) => (
              <Pil key={k} kind={k === "NOT_STARTED" ? "grey" : stateKind(k)}>{byState[k]} {(OVERALL_WORD[k] ?? k).toLowerCase()}</Pil>
            ))}
            {!finalists.length ? <span className="sub2">No graduand on the list for {scope.session} yet.</span> : null}
          </div>
          {refused.length ? (
            <Note kind="bad" title={`${refused.length} not started — the record says why`} action={<Btn kind="ghost" onClick={() => setRefused([])}>Done</Btn>}>
              {refused.slice(0, 10).map((x) => `${x.name} (${x.number}): ${x.why}`).join(" · ")}
            </Note>
          ) : null}
        </PBody>
        {finalists.length ? (
          <DTable
            cols={["Student", "Programme", "CGPA|mid", "Clearance", "Final clearance|mid", "|num"]}
            rows={finalists.map((f) => [
              <Two key="s" a={`${f.surname}, ${f.otherNames}`} b={f.number} />, <span key="p">{f.programmeName}</span>,
              <span className="tnum" key="c">{f.cgpa == null ? "—" : Number(f.cgpa).toFixed(2)}</span>,
              <span className="tnum sub2" key="r">{f.clearanceRef ?? "—"}</span>,
              <Pil key="st" kind={f.clearanceState === "NOT_STARTED" ? "grey" : stateKind(f.clearanceState)}>{OVERALL_WORD[f.clearanceState] ?? f.clearanceState}</Pil>,
              f.clearanceProcess ? <LinkBtn key="o" kind="ghost" href={`/clearance?${new URLSearchParams({ wf: "FINAL", session: scope.session, process: f.clearanceProcess }).toString()}`}>Open</LinkBtn> : <span key="o" />,
            ])}
            texts={finalists.map((f) => `${f.number} ${f.surname} ${f.otherNames} ${f.programmeName} ${f.clearanceRef ?? ""} ${OVERALL_WORD[f.clearanceState] ?? f.clearanceState}`)}
          />
        ) : null}
      </Panel>
      <Panel title="Classification summary" right="Computed from the versioned classification table in force at each student's entry">
        <DTable
          cols={["Class", "Students|mid", "Share|mid", "CGPA range|num"]}
          rows={view.classification.map((c) => [
            <span key="c">{c.clazz}</span>, <span className="tnum" key="n">{c.students.toLocaleString()}</span>,
            <span className="tnum" key="s">{c.share}%</span>,
            <span className="tnum sub2" key="r">{c.low == null ? "—" : Number(c.low).toFixed(2)} – {c.high == null ? "—" : Number(c.high).toFixed(2)}</span>,
          ])}
        />
      </Panel>
      <div className="row">
        <Btn kind="primary" disabled={busy || !office} onClick={() => void post(`/api/bff/api/v1/graduation/sessions/${scope.session}/audit`, {}, `Degree audit run for ${scope.session}`)}>{busy ? "Working…" : `Run the degree audit for ${scope.session}`}</Btn>
        <Btn kind="go" disabled={busy || !t.auditPassed || !["academic", "registrar", "dregistrar"].includes(actingOffice ?? "")} onClick={() => setMinute("")}>Send the list to Senate</Btn>
        <span className="sub2">{t.approved ? `${t.approved} award${t.approved === 1 ? "" : "s"} already approved by Senate` : "Nothing approved yet"}</span>
      </div>
      {minute !== null ? (
        <Modal title="Approve the graduation list" sub="On the Senate minute" onClose={() => setMinute(null)}
          foot={<><Btn kind="ghost" onClick={() => setMinute(null)}>Cancel</Btn><span className="grow" /><Btn kind="go" disabled={busy || !minute.trim()} onClick={() => void post(`/api/bff/api/v1/graduation/sessions/${scope.session}/approve`, { senateMinute: minute }, `Graduation list ${scope.session} approved under ${minute}`)}>Approve the awards</Btn></>}>
          <Field id="g-minute" label="Senate minute" hint="Every graduand who passed the audit becomes GRADUATED on this minute; the exceptions stay where they are."><input id="g-minute" className="ctl" value={minute} onChange={(e) => setMinute(e.target.value)} placeholder="SEN/2027/…" autoComplete="off" /></Field>
        </Modal>
      ) : null}
    </>
  );
}
