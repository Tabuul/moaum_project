"use client";

/** rAdmissions — proto/part9.html: the cycle as the register shows it. */
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import type { AdmissionCycle } from "@/lib/matriculation";
import { Btn, LinkBtn, Note, Panel, PBody, Pil, RoleLine, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { ProblemNotice } from "@/components/ProblemNotice";

/** V722: how many admitted candidates one call of the intake run brings onto the register (about 300 × 8 ms on the live-shaped copy) */
const TRANCHE = 300;

/** V729: a programme the merit recording refused, with the rule's words and what to do */
interface Refusal { code: string; name: string; reason: string; remedy: string | null }

export function Admissions({ cycle, actingOffice }: { cycle: AdmissionCycle; actingOffice: string | null }) {
  const router = useRouter();
  const [problem, setProblem] = useState<Problem | null>(null);
  const [busy, setBusy] = useState(false);
  const [said, setSaid] = useState<string | null>(null);
  const [brought, setBrought] = useState(0);
  const [recording, setRecording] = useState(false);
  const [recorded, setRecorded] = useState<string | null>(null);
  const [refused, setRefused] = useState<Refusal[]>([]);
  const [recordedCount, setRecordedCount] = useState<string | null>(null);
  const may = ["academic", "registrar", "dregistrar"].includes(actingOffice ?? "");
  const pct = (a: number, b: number) => (b ? `${Math.round((1000 * a) / b) / 10}%` : "—");

  // V729: every programme recorded in its own request, counted off, so one programme's refusal never undoes the others (in one
  // request the first refused decision undid every programme); each refusal is listed with its reason
  async function recordAll() {
    if (!window.confirm("Record the merit list for every programme with applicants this session? Offers, waiting and not-offered decisions are entered for all of them; released decisions are left untouched. Decisions are not released yet.")) return;
    setRecording(true);
    setProblem(null);
    setRecorded(null);
    setRefused([]);
    setRecordedCount(null);
    let done = 0;
    try {
      const lr = await fetch(`/api/bff/api/v1/admissions/merit/programmes?session=${encodeURIComponent(cycle.session)}`, { cache: "no-store" });
      const lj = await lr.json().catch(() => null);
      if (!lr.ok) { const p: Problem = lj ?? { status: lr.status, title: lr.statusText }; setProblem(p); notifyProblem(p); return; }
      const codes: string[] = lj?.programmes ?? [];
      const names = new Map(cycle.programmes.map((x) => [x.code, x.name] as const));
      const totals = { offered: 0, waited: 0, notOffered: 0, skipped: 0, awaiting: 0, unscored: 0 };
      const refusals: Refusal[] = [];
      for (const [i, code] of codes.entries()) {
        setRecordedCount(`${(i + 1).toLocaleString()} of ${codes.length.toLocaleString()}`);
        let r: Response;
        try {
          r = await fetch("/api/bff/api/v1/admissions/merit/record", {
            method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Merit list recorded for ${code}, ${cycle.session}`) },
            body: JSON.stringify({ session: cycle.session, programme: code }),
          });
        } catch {
          refusals.push({ code, name: names.get(code) ?? code, reason: "The portal could not be reached", remedy: "Record all programmes again: the programmes recorded are recorded again, the same way." });
          continue;
        }
        const j = await r.json().catch(() => null);
        if (!r.ok) {
          const p: Problem | null = j;
          refusals.push({ code, name: names.get(code) ?? code, reason: p?.detail ?? p?.title ?? r.statusText, remedy: p?.remedy?.message ?? null });
          continue;
        }
        done += 1;
        totals.offered += Number(j?.offered ?? 0);
        totals.waited += Number(j?.waited ?? 0);
        totals.notOffered += Number(j?.notOffered ?? 0);
        totals.skipped += Number(j?.skipped ?? 0);
        totals.awaiting += Number(j?.awaitingRelease ?? 0);
        totals.unscored += Number(j?.awaitingScore ?? 0);
      }
      setRefused(refusals);
      setRecorded(`${done.toLocaleString()} of ${codes.length.toLocaleString()} programme${codes.length === 1 ? "" : "s"} recorded — ${totals.offered.toLocaleString()} offered, ${totals.waited.toLocaleString()} waiting, ${totals.notOffered.toLocaleString()} not offered${totals.skipped ? `, ${totals.skipped.toLocaleString()} left untouched (already released)` : ""}.${totals.awaiting ? ` ${totals.awaiting.toLocaleString()} applicant${totals.awaiting === 1 ? " awaits" : "s await"} a released screening score and ${totals.awaiting === 1 ? "is" : "are"} not on the merit list yet: release the screening results, then record again.` : ""}${totals.unscored ? ` ${totals.unscored.toLocaleString()} applicant${totals.unscored === 1 ? "" : "s"} of programmes screened by the Post-UTME examination ${totals.unscored === 1 ? "has" : "have"} no screening score: upload ${totals.unscored === 1 ? "it" : "them"} or score the remainder as zero, release, then record again.` : ""} Release the decisions from the Applicants desk when the Board is ready.`);
      if (refusals.length) {
        notify(`${done.toLocaleString()} programme${done === 1 ? "" : "s"} recorded; ${refusals.length.toLocaleString()} refused — see the list`, "bad");
      } else {
        notify(`${done.toLocaleString()} programme${done === 1 ? "" : "s"} recorded`);
      }
    } finally {
      setRecording(false);
      setRecordedCount(null);
      if (done) router.refresh();
    }
  }

  // V722: the admitted candidates are brought onto the register in tranches — one call brings at most TRANCHE of them and says how
  // many remain — so no single request outlasts what a screen is allowed, however long the list (2,359 waited on 11 November 2026).
  // Each tranche is its own transaction: what a tranche brought on stays whatever happens to the next, so the page is re-read after
  // any run that brought somebody on, and a refusal mid-run says how many came on before it.
  async function intake() {
    setBusy(true);
    setProblem(null);
    setSaid(null);
    setBrought(0);
    let total = 0;
    try {
      let remaining = cycle.notYetOnRegister;
      for (let round = 0; round < 1000 && remaining > 0; round++) {
        const r = await fetch(`/api/bff/api/v1/student/intake/${cycle.session}?limit=${TRANCHE}`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Admitted candidates of ${cycle.session} brought onto the register`) }, body: "{}" });
        const j = await r.json().catch(() => null);
        if (!r.ok) {
          const refusal: Problem = r.status === 404 ? { status: 404, title: "The student register is not yet served", detail: "The intake endpoint has not arrived on the portal; the admission numbers are issued the moment it does." } : j ?? { status: r.status, title: r.statusText };
          setProblem(refusal);
          if (total) {
            // the tranches before this one are on the register; a refusal's "nothing was saved" would be untrue of them
            setSaid(`${total.toLocaleString()} candidate${total === 1 ? "" : "s"} brought onto the register before the run stopped; the rest wait for another press.`);
            notify(`The run stopped after ${total.toLocaleString()} candidate${total === 1 ? " was" : "s were"} brought onto the register; press the button again for the rest`, "bad");
          } else {
            notifyProblem(refusal);
          }
          return;
        }
        const n = Number(j?.broughtOnto ?? 0);
        total += n;
        remaining = Number(j?.remaining ?? 0);
        setBrought(total);
        if (!n) break;   // nothing more could be taken; the server's count says what is left
      }
      setSaid(`${total.toLocaleString()} candidate${total === 1 ? "" : "s"} brought onto the register, each with an admission number.${remaining > 0 ? ` ${remaining.toLocaleString()} remain; press the button again.` : ""}`);
      notify(`${total.toLocaleString()} candidate${total === 1 ? "" : "s"} brought onto the register`);
    } finally {
      if (total) router.refresh();
      setBusy(false);
    }
  }

  return (
    <>
      <RoleLine allowed={["academic", "registrar", "dregistrar"]} actingOffice={actingOffice}
        action="Recording merit lists and bringing candidates onto the register" />
      <Tiles items={[
        ["Applications", cycle.applications.toLocaleString(), null, `${cycle.session} cycle · on the CAPS lists`],
        ["Screened", cycle.screened.toLocaleString(), null,
          <>{pct(cycle.screened, cycle.applications)} carry a screening aggregate · <span className="b600" style={{ color: "var(--link)" }}>View all →</span></>,
          `/admissions/screened?session=${encodeURIComponent(cycle.session)}`],
        ["Offers issued", cycle.offers.toLocaleString(), "var(--chrome)", cycle.capacity ? `Against ${cycle.capacity.toLocaleString()} capacity` : "No NUC capacity in force"],
        ["Accepted", cycle.accepted.toLocaleString(), "var(--green-ink)", `${pct(cycle.accepted, cycle.offers)} conversion`],
      ]} />
      {problem ? <ProblemNotice problem={problem} /> : null}
      {said ? <Note kind="ok" title="On the register">{said}</Note> : null}
      {cycle.notYetOnRegister ? (
        <Note kind="bad" title={`${cycle.notYetOnRegister.toLocaleString()} admitted candidate${cycle.notYetOnRegister === 1 ? " is" : "s are"} not yet on the register`}
          action={<Btn kind="urgent" disabled={busy || !may} onClick={() => void intake()}>{busy ? (brought ? `Bringing them on… ${brought.toLocaleString()} of ${cycle.notYetOnRegister.toLocaleString()}` : "Bringing them on…") : `Bring ${cycle.notYetOnRegister.toLocaleString()} candidate${cycle.notYetOnRegister === 1 ? "" : "s"} onto the register`}</Btn>}>
          Until they are on the student register nobody can screen, clear or register them. Each gets an admission number from the committed CAPS list.
        </Note>
      ) : (
        <Note kind="ok" title={cycle.offers ? "Every admitted candidate is on the register" : "No admitted candidate yet"}>
          {cycle.offers ? `${cycle.onTheRegister.toLocaleString()} of this session's entrants carry an admission number. The next tranche from CAPS appears here the moment it is committed.` : "Upload and commit the UTME and Direct Entry lists from CAPS, and the candidates appear here."}
        </Note>
      )}
      {recorded ? <Note kind="ok" title="Merit lists recorded">{recorded}</Note> : null}
      {refused.length ? (
        <Note kind="bad" title={`${refused.length.toLocaleString()} programme${refused.length === 1 ? " was" : "s were"} not recorded`}>
          Each was refused by the rule named; the others were recorded.
          <ul className="mt-1" style={{ paddingLeft: "1.2em", listStyle: "disc" }}>
            {refused.map((x) => <li key={x.code}><b>{x.name}</b> ({x.code}): {x.reason}{x.remedy ? ` — ${x.remedy}` : ""}</li>)}
          </ul>
        </Note>
      ) : null}
      <Panel title="Programmes — merit lists"
             right={may ? <span className="row row--inline">
               <span className="sub2">Quota is the NUC-approved carrying capacity</span>
               <Btn kind="primary" disabled={recording} onClick={() => void recordAll()}>{recording ? (recordedCount ? `Recording… ${recordedCount}` : "Recording…") : "Record all programmes"}</Btn>
             </span> : "Quota is the NUC-approved carrying capacity"}>
        <DTable
          cols={["Programme", "Applied|mid", "Quota|mid", "Offered|mid", "Accepted|mid", "Cut-off|mid", "Stage|num"]}
          rows={cycle.programmes.filter((p) => p.applied || p.offered).map((p) => [
            <Two key="p" a={p.name} b={p.facultyName} />,
            <span className="tnum" key="a">{p.applied.toLocaleString()}</span>,
            <span className="tnum" key="q">{p.quota == null ? "—" : p.quota.toLocaleString()}</span>,
            <span className="tnum" key="o">{p.offered.toLocaleString()}</span>,
            <span className="tnum" key="c">{p.accepted.toLocaleString()}</span>,
            <span className="tnum" key="k">{p.cutoff ?? "—"}</span>,
            p.stage === "Settings in force" ? <Pil kind="ok" key="s">Settings in force</Pil> : p.stage === "Awaiting settings" ? <Pil kind="info" key="s">Awaiting settings</Pil> : <Pil kind="bad" key="s">{p.stage}</Pil>,
          ])}
          texts={cycle.programmes.filter((p) => p.applied || p.offered).map((p) => `${p.name} ${p.facultyName} ${p.code}`)}
        />
        {!cycle.programmes.some((p) => p.applied || p.offered) ? <PBody><div className="sub2">No programme has an application in this session yet. <Link href={`/admissions/caps?session=${encodeURIComponent(cycle.session)}`}>Upload the CAPS list</Link>.</div></PBody> : null}
      </Panel>
      <Panel title="JAMB reconciliation" right="Candidates whose portal data disagrees with the CAPS record">
        <DTable
          cols={["Finding", "Candidates|mid", "What it means", "Action|num"]}
          rows={cycle.reconciliation.map((f) => [
            <strong key="f">{f.finding}</strong>,
            <span className={`tnum${f.n ? " ink-red b700" : ""}`} key="n">{f.n}</span>,
            <span className="sub2" key="w">{f.whatItMeans}</span>,
            <LinkBtn key="a" kind={f.n ? "primary" : "ghost"} href={`/admissions/caps?session=${encodeURIComponent(cycle.session)}`}>{f.n ? "Resolve" : "Open"}</LinkBtn>,
          ])}
        />
      </Panel>
    </>
  );
}
