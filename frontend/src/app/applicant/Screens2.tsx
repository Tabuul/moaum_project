"use client";

/**
 * Screening slip, screening result, admission status — proto/part13.html
 * applicantScreening, applicantScore and applicantStatus, as drawn, from the
 * record: the seat the Academic Office assigned, the result under the
 * session's own weighting, and the Board's decision once it is released.
 */
import { at, type Application } from "@/lib/applicant";
import { KvGrid, LinkBtn, Note, Panel, PBody, Tick, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Bar } from "@/components/proto/blocks";
import { Rail, when } from "./common";
import { Eligibility } from "./Eligibility";

/* ── 4. screening slip: ScreeningSlip.tsx (V260) ── */

/* ── 5. screening result ── */

export function Score({ a }: { a: Application }) {
  const r = a.result;
  if (!at(a, 4) || !r) {
    return (
      <>
        <Note kind="info" title="Scores are released when every batch has been screened">
          Releasing one batch before the others would let later candidates learn the questions, so all scores are released together.
        </Note>
        <Rail a={a} />
      </>
    );
  }
  const agg = r.aggregate;
  const above = agg !== null && r.cutoff !== null ? agg >= r.cutoff : null;
  const utmeContribution = r.utmeScaled !== null ? Math.round(Number(r.utmeScaled) * r.weightUtme) / 100 : null;
  const screeningContribution = r.screening !== null ? Math.round(Number(r.screening) * r.weightPutme) / 100 : null;
  return (
    <>
      <Tiles items={[
        ["UTME", String(r.utme ?? "—"), null, r.utmeScaled !== null ? `of 400 · scaled to ${r.utmeScaled}` : "Direct Entry · no UTME"],
        ["Post-UTME screening", r.screening === null ? "—" : String(r.screening), null, r.screeningSource === "CBT" ? "of 100 · computer-based test" : r.screeningSource === "EXAM" ? (r.screening === null ? "your programme is screened by examination · score not yet entered" : "of 100 · the post-UTME examination") : r.screeningSource === "OLEVEL" ? "of 100 · your O’Level results, under the session’s grading" : "no screening component yet"],
        ["Aggregate", agg === null ? "—" : String(agg), above === null ? null : above ? "var(--green-ink)" : "var(--red-ink)", `Weighted ${r.weightUtme} / ${r.weightPutme}`],
        ["Departmental cut-off", r.cutoff === null ? "—" : String(r.cutoff), null, r.cutoff === null ? "Not stated in the settings yet" : `${a.programme ?? ""} · this session`],
      ]} />
      {above === null ? (
        <Note kind="info" title="No cut-off is stated for your programme yet">
          The cut-off comes from the session&rsquo;s admission settings. Your aggregate stands; where you stand against the line is shown the moment the settings state it.
        </Note>
      ) : (
        <Note kind={above ? "ok" : "bad"} title={above ? `Your aggregate is above the cut-off for ${a.programme}` : `Your aggregate is below the cut-off for ${a.programme}`}>
          {above ? "Being above the cut-off does not by itself give you a place. Places are filled from the merit list downwards until the approved quota is full, and the cut-off can rise as the list is worked through." : "You may still be considered for a related programme in the same faculty if places remain after the merit list is exhausted."}
        </Note>
      )}
      <Panel title="How your aggregate was calculated" right={`Weighting in force for ${a.session}`}>
        <DTable cols={["Component", "Raw|mid", "Of|mid", "Scaled|mid", "Weight|mid", "Contribution|num"]} rows={[
          ["UTME", <span className="tnum" key="r">{r.utme ?? "—"}</span>, <span className="tnum sub2" key="o">400</span>, <span className="tnum" key="s">{r.utmeScaled ?? "—"}</span>, <span className="tnum" key="w">{r.weightUtme}%</span>, <span className="tnum" key="c">{utmeContribution ?? "—"}</span>],
          ["Post-UTME screening", <span className="tnum" key="r">{r.screening ?? "—"}</span>, <span className="tnum sub2" key="o">100</span>, <span className="tnum" key="s">{r.screening ?? "—"}</span>, <span className="tnum" key="w">{r.weightPutme}%</span>, <span className="tnum" key="c">{screeningContribution ?? "—"}</span>],
          [<strong key="a">Aggregate</strong>, "", "", "", "", <strong className="tnum t-md" key="x">{agg ?? "—"}</strong>],
        ]} />
      </Panel>
      {r.meritPosition !== null && r.applied !== null ? (
        <Panel title="Where you stand" right={`Merit list, ${a.programme ?? ""}`}>
          <PBody>
            <div className="row" style={{ gap: "var(--s-4)" }}>
              <Bar pct={r.places ? Math.min(100, Math.round((r.meritPosition / r.places) * 100)) : Math.round((r.meritPosition / r.applied) * 100)} colour="var(--green)" />
              <div>
                <div className="t-md b700">Position {r.meritPosition} of {r.applied} with a released result{r.places ? ` · ${r.places} places` : ""}</div>
                <div className="sub2">Positions can move while the Board resolves ties and verifies results.</div>
              </div>
            </div>
          </PBody>
        </Panel>
      ) : null}
      <Note kind="info" title="If you think this score is wrong">
        A remark is requested in writing at the Registry within seven days of release, quoting your application number. What was entered, and by whom, is on the record.
      </Note>
    </>
  );
}

/* ── 6. admission status ── */

export function Status({ a }: { a: Application }) {
  if (!at(a, 5) || !a.decision) {
    return (
      <>
        <Note kind="info" title="Your application is with the Admissions Board">
          Your admission status appears here the moment the University uploads JAMB&rsquo;s admission list, or when the Admissions Board releases its decision after the screening scores and the O&rsquo;Level verification. It is published here and by email on the same day &mdash; there is no earlier list circulating anywhere. Once offered: accept and pay the acceptance fee, take your acceptance letter, then complete the online screening.
        </Note>
        {at(a, 2) ? <Eligibility /> : null}
        <Rail a={a} />
        <Panel title="What the Board can decide" right="Three outcomes">
          <DTable cols={["Outcome", "What it means"]} rows={[
            [<Two key="o" a="Offered" b="A place on the merit list" />, "Accept the offer and pay the acceptance fee before the deadline, or the place is released."],
            [<Two key="o" a="Waiting list" b="Above the cut-off, but the quota is full" />, "You are offered a place only if an offered candidate fails to accept in time."],
            [<Two key="o" a="Not offered" b="Below the line for this programme" />, "You may be considered for a related programme in the same faculty, or reapply next session."],
          ]} />
        </Panel>
      </>
    );
  }
  const r = a.result;
  if (a.decision !== "OFFERED") {
    return (
      <>
        <Note kind={a.decision === "WAITING" ? "info" : "bad"} title={a.decision === "WAITING" ? "You are on the waiting list" : "You were not offered a place this session"}>
          {a.decision === "WAITING" ? "You are above the cut-off, but the approved quota is full. You are offered a place only if an offered candidate fails to accept in time; this page changes the moment that happens." : "You may be considered for a related programme in the same faculty if places remain, or reapply next session."}{a.decisionNote ? ` ${a.decisionNote}` : ""}
        </Note>
        <Eligibility />
        <Rail a={a} />
      </>
    );
  }
  return (
    <>
      <div className="card" style={{ borderTop: "4px solid var(--green)" }}>
        <PBody>
          <div className="row">
            <div style={{ width: 26, height: 26, borderRadius: "var(--r-pill)", background: "var(--green)", display: "flex", alignItems: "center", justifyContent: "center" }}><Tick size={14} colour="var(--surface)" /></div>
            <span className="eyebrow ink-green">Offer of provisional admission</span>
          </div>
          <div className="phead__t" style={{ fontFamily: "var(--serif)", fontSize: "var(--t-2xl)" }}>{a.programme}</div>
          <div className="sub2">{a.faculty ? `Faculty of ${a.faculty} · ` : ""}{a.entryLevel} Level &middot; {a.session} session &middot; released {when(a.decisionReleasedAt)}</div>
          <div className="hr" />
          <KvGrid pairs={[
            ["UTME score", <span className="tnum t-lg b700" key="u">{r?.utme ?? "—"}</span>],
            ["Screening", <span className="tnum t-lg b700" key="s">{r?.screening ?? "—"}</span>],
            ["Aggregate", <span className="tnum t-lg b700" key="a">{r?.aggregate ?? "—"}</span>],
            ["Merit position", <span className="tnum t-lg b700" key="m">{r?.meritPosition ?? "—"}{r?.applied ? ` of ${r.applied}` : ""}</span>],
          ]} />
        </PBody>
      </div>
      {at(a, 6) ? (
        <Note kind="ok" title={`You accepted this offer on ${when(a.acceptedAt)}`} action={<LinkBtn kind="primary" href="/applicant/clearance">Clearance checklist</LinkBtn>}>
          Your place is held. Document clearance is the next step.
        </Note>
      ) : a.declinedAt ? (
        <Note kind="bad" title={`You declined this offer on ${when(a.declinedAt)}`}>A declined offer is not reinstated.</Note>
      ) : (
        <Note kind="bad" title="Accept your offer" action={<LinkBtn kind="urgent" href="/applicant/accept">Accept the offer</LinkBtn>}>
          An offer that lapses cannot be reinstated, and the place goes to the next candidate on the waiting list.
        </Note>
      )}
      <Note kind="info" title="Provisional means exactly that">
        This offer stands on the results JAMB sent. The Registry verifies every one of them with WAEC, NECO and JAMB before clearance. A result that does not verify voids the admission at any point afterwards &mdash; including after you have graduated.
      </Note>
      {at(a, 6) ? (
        <div className="row">
          <a href="/applicant/status/letter" target="_blank" rel="noopener" className="btn btn--primary">Print Offer Letter</a>
        </div>
      ) : null}
    </>
  );
}
