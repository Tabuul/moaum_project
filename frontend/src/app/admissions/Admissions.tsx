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

export function Admissions({ cycle, actingOffice }: { cycle: AdmissionCycle; actingOffice: string | null }) {
  const router = useRouter();
  const [problem, setProblem] = useState<Problem | null>(null);
  const [busy, setBusy] = useState(false);
  const [said, setSaid] = useState<string | null>(null);
  const [brought, setBrought] = useState(0);
  const [recording, setRecording] = useState(false);
  const [recorded, setRecorded] = useState<string | null>(null);
  const may = ["academic", "registrar", "dregistrar"].includes(actingOffice ?? "");
  const pct = (a: number, b: number) => (b ? `${Math.round((1000 * a) / b) / 10}%` : "—");

  async function recordAll() {
    if (!window.confirm("Record the merit list for every programme with applicants this session? Offers, waiting and not-offered decisions are entered for all of them; released decisions are left untouched. Decisions are not released yet.")) return;
    setRecording(true);
    setProblem(null);
    setRecorded(null);
    try {
      const r = await fetch("/api/bff/api/v1/admissions/merit/record-many", {
        method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Merit list recorded across all programmes for ${cycle.session}`) },
        body: JSON.stringify({ session: cycle.session }),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j ?? { status: r.status, title: r.statusText }); notifyProblem(j ?? { status: r.status, title: r.statusText }); return; }
      setRecorded(`${j.programmes} programme${j.programmes === 1 ? "" : "s"} recorded — ${j.offered} offered, ${j.waited} waiting, ${j.notOffered} not offered${j.skipped ? `, ${j.skipped} left untouched (already released)` : ""}. Release the decisions from the Applicants desk when the Board is ready.`);
      notify(`${j.programmes} programme${j.programmes === 1 ? "" : "s"} recorded`);
      router.refresh();
    } finally {
      setRecording(false);
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
      <Panel title="Programmes — merit lists"
             right={may ? <span className="row row--inline">
               <span className="sub2">Quota is the NUC-approved carrying capacity</span>
               <Btn kind="primary" disabled={recording} onClick={() => void recordAll()}>{recording ? "Recording…" : "Record all programmes"}</Btn>
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
