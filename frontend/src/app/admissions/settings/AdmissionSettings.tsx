"use client";

/**
 * Admission settings, per session — proto/part55.html tAdmissionSetup, as
 * the prototype lays it out, with the database behind it: the settings are
 * the rows of V008, the findings are admissions.policy_findings, and "Put in
 * force" is admissions.put_in_force, which refuses by name until nothing
 * stands in the way and a minute is cited. Settings in force are not edited.
 */
import { reasonHeader } from "@/lib/reason";
import { notify , notifyProblem } from "@/components/proto/Toast";
import { useState, type ReactNode } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { officeLabel } from "@/lib/offices";
import { Btn, IcoBtn, Note, Panel, PBody, Pil, RoleLine, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Modal, Field } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { OlevelGrading } from "./OlevelGrading";
import { LoadCutoff } from "../LoadCutoff";

export interface PolicySummary {
  session: string;
  state: string;
}

export interface AdmissionPolicy {
  session: string;
  state: string;
  inForce: boolean;
  instrument: string | null;
  inForceSince: string | null;
  nucQuota: number;
  weightUtme: number;
  weightPutme: number;
  ratioUtme: number;
  ratioDe: number;
  ratioScience: number;
  ratioArts: number;
  elgCapPct: number;
  deptSharePct: number;
  indexPrelimPlaces: number;
  indexPerZone: number;
  mpfOnly: boolean;
  screeningRequired: boolean;
  maxAlternatives: number;
  criteria: { criterion: string; percent: number }[];
  facultyCutoffs: { facultyCode: string; facultyName: string; quota: number | null; cutoff: number | null; ratioUtme: number | null; ratioDe: number | null }[];
  programmeCutoffs: { code: string; name: string; cutoff: number }[];
  programmes: {
    code: string;
    name: string;
    facultyCode: string;
    facultyName: string;
    cutoff: number | null;
    quota?: number | null;
    olevelText: string | null;
    utmeText: string | null;
    deText: string | null;
    olevelCredits: number | null;
    olevelSittings: number | null;
  /** the O'Level subjects relevant to the programme — the ones the screening counts (V020) */
  olevelSubjects?: string[];
  /** compulsory O'Level subjects this programme accepts a pass in / waives (V053) */
  olevelAllowances?: string[];
  /** the required UTME subjects the merit list checks (V189) */
  utmeSubjects?: string[];
  /** the required Direct Entry subjects the DE gate checks (V200) */
  deSubjects?: string[];
  /** how many of the DE subject set a candidate must offer (V200) */
  deChoose?: number | null;
  /** closed for the session (V023): not admitted into, needs no rule */
  closed?: boolean;
  closedReason?: string | null;
  /** the O'Level subjects the eligibility engine requires at a credit (V266) */
  olevelRequired?: string[];
  olevelRequiredMinGrade?: string | null;
  /** an additional screening the programme requires beyond the academic rules (V266) */
  additionalScreening?: string | null;
    stated: boolean;
  }[];
  findings: { finding: string; detail: string; owner: string }[];
  catchmentLgas?: string[];
  /** subject equivalencies the eligibility engine honours (V266) — stated by the Secretariat, never invented */
  equivalences?: { subject: string; equivalent: string; scope: "ANY" | "OLEVEL" | "UTME" }[];
}

const CRIT_LABEL: Record<string, [string, string]> = {
  NATIONAL_MERIT: ["National Merit", "Open, nationwide, on the merit list alone"],
  STATE_MERIT: ["State Merit", "Benue State candidates, on merit"],
  ELG: ["Equality of Local Government", "Each Local Government represented"],
  LOCALITY: ["Locality", "The University's immediate catchment"],
};
const CRITERIA = ["NATIONAL_MERIT", "STATE_MERIT", "ELG", "LOCALITY"];

/* What the guidelines call each faculty, where it differs from what the University's own programme table calls it. */
const FAC_GUIDE: Record<string, string> = {
  MS: "Administration and Management",
  BAMS: "College of Health Sciences",
  PS: "Pharmacy (quota table) / Pharmaceutical Sciences (subject combinations)",
  TI: "Technology education",
};

/* The questions the document itself raises — quoted, both readings given, unanswered, because the
   Directorate of ICT does not get to choose which reading of an admission rule is correct. */
const ADM_QUESTIONS: [string, string, ReactNode, string][] = [
  ["decided", "English and Mathematics: compulsory everywhere, or not?",
    <>Decided by the Academic Office: a <b>credit</b> in English and Mathematics is compulsory for every programme; a pass (D7/E8) is not a credit. Programmes that differ (B.Sc. Political Science and Sociology accept a pass in Mathematics; B.A. Linguistics does not require Mathematics; B.Ed. Guidance and Counselling accepts a pass) are <b>per-programme exceptions</b> on the Programme requirements tab.</>,
    "Central Admissions Committee"],
  ["decided", "Equality of Local Government: 30% or not more than 50%?",
    <>Decided: ELG is a <b>share the Committee sets</b> (30% at 2.4) up to the <b>ceiling of 50%</b> (2.11). Set the share in &ldquo;The four selection criteria&rdquo; and the ceiling in &ldquo;The ratios and the caps&rdquo;.</>,
    "Central Admissions Committee"],
  ["decided", "The Education exception: which ratio does 60:40 belong to?",
    <>Decided: 60:40 is the <b>UTME:Direct-Entry</b> ratio, per faculty: every faculty is 80:20 except <b>Education</b> (60:40), set on the Faculty quotas tab. The Science&ndash;Arts 60:40 is a separate rule.</>,
    "Central Admissions Committee"],
  ["answer", "Two names for four faculties",
    <>The quota table names <i>Administration and Management</i>, <i>College of Health Sciences</i>, <i>Pharmacy</i> and <i>Technology education</i>; the programme table names <i>Management Sciences</i>, <i>Basic and Applied Medical Sciences</i>, <i>Pharmaceutical Sciences</i> and <i>Technology and Industrial Studies</i>.</>,
    "Academic Office"],
  ["answer", "Biochemistry sits in two faculties",
    <>The subject combinations place <b>B.Sc. Biochemistry</b> under the Faculty of Science; the programme table places it under Basic and Applied Medical Sciences.</>,
    "Academic Office"],
  ["answer", "Mass Communication has no stated requirement",
    <>Six Communication and Media Studies programmes have subject combinations (Advertising, Broadcasting, Development Communication, Journalism, Public Relations, Strategic Communication); <b>Mass Communication</b> is not among them.</>,
    "Dean, Communication and Media Studies"],
];

const ADM_TABS: [string, string, ReactNode][] = [
  ["session", "Session and criteria", "Quota, weighting and the four criteria"],
  ["faculty", "Faculty settings", "NUC ceiling and the UTME:Direct-Entry split"],
  ["prog", "Programme requirements", <>O&rsquo;Level, UTME subjects, Direct Entry</>],
  ["force", "Put in force", "What stands in the way, and the minute that clears it"],
];

const SECRETARIAT = ["academic", "registrar", "dregistrar"];

function num(v: string): number | null {
  const t = v.trim();
  return /^-?\d+$/.test(t) ? Number(t) : null;
}

export function AdmissionSettings({
  session,
  policy,
  policyProblem,
  previous,
  previousSession,
  sessions,
  actingOffice,
  loadCutoff,
}: {
  session: string;
  policy: AdmissionPolicy | null;
  policyProblem: Problem | null;
  previous: AdmissionPolicy | null;
  previousSession: string;
  sessions: PolicySummary[];
  actingOffice: string | null;
  /** the one UTME cut-off the JAMB lists load under (V024), or null while it is not stated */
  loadCutoff: number | null;
}) {
  const router = useRouter();
  const [tab, setTab] = useState<string>("session");
  const [edits, setEdits] = useState<Record<string, string>>({});
  const equivText = (policy?.equivalences ?? []).map((e) => `${e.subject} = ${e.equivalent}${e.scope !== "ANY" ? ` @${e.scope}` : ""}`).join("\n");
  const [busy, setBusy] = useState<string | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [instrument, setInstrument] = useState("");
  const [reaffirm, setReaffirm] = useState("");
  const [tried, setTried] = useState(false);
  const [editing, setEditing] = useState<string | null>(null);
  const [newQuota, setNewQuota] = useState("");
  const [choosing, setChoosing] = useState(false);
  const [chosen, setChosen] = useState("");

  const may = actingOffice !== null && SECRETARIAT.includes(actingOffice);
  const locked = !may || !!policy?.inForce;
  const base = `/api/bff/api/v1/admissions/sessions/${session}/policy`;

  async function send(method: "PUT" | "POST", path: string, body: unknown, reason: string, key: string): Promise<boolean> {
    setBusy(key);
    setProblem(null);
    try {
      const response = await fetch(path, {
        method,
        headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) },
        body: body === undefined ? undefined : JSON.stringify(body),
      });
      if (response.ok) {
        notify(reason);
        router.refresh();
        return true;
      }
      const json = await response.json().catch(() => null);
      setProblem(json && typeof json === "object" && "status" in json ? (json as Problem) : { status: response.status, title: response.statusText }); notifyProblem(json && typeof json === "object" && "status" in json ? (json as Problem) : { status: response.status, title: response.statusText });
      return false;
    } finally {
      setBusy(null);
    }
  }

  const val = (key: string, current: number | null | undefined) => (key in edits ? edits[key] : current === null || current === undefined ? "" : String(current));
  /* `capacity` fields are quotas — places, not qualification rules — so they stay editable when the
     policy is in force (the NUC ceiling can rise mid-cycle and the Deans redistribute it); everything
     else is frozen once in force. */
  const field = (key: string, current: number | null | undefined, width: number, onSave: (v: number | null) => void, placeholder?: string, capacity?: boolean) => (
    <input
      className="tnum ws__in"
      style={{ width }}
      value={val(key, current)}
      placeholder={placeholder}
      disabled={capacity ? !may : locked}
      onChange={(e) => setEdits({ ...edits, [key]: e.target.value })}
      onBlur={() => {
        if (!(key in edits)) return;
        const v = num(edits[key]);
        const was = current === null || current === undefined ? null : current;
        if (v === was) return;
        onSave(v);
      }}
    />
  );

  /* ── no settings yet ── */
  if (!policy) {
    return (
      <>
        {policyProblem ? <ProblemNotice problem={policyProblem} /> : null}
        <Note kind="info" title={`No admission settings exist for ${session}`}>
          Until the Committee puts them in force, <b>no candidate can be ranked, cut off or admitted</b> for {session}.
        </Note>
        <div className="card">
          <div className="card__body">
            <div className="eyebrow">Begin the {session} settings</div>
            {previous ? (
              <>
                <div className="sub2 mb-3">
                  Start from <b>{previousSession}</b> ({previous.inForce ? `in force under ${previous.instrument}` : "a draft"}) as a new draft to amend.
                </div>
                <Btn
                  kind="primary"
                  disabled={!may || busy !== null}
                  onClick={() => void send("POST", `${base}/start-from/${previousSession}`, undefined, `${session} admission settings begun from ${previousSession}`, "start")}
                >
                  {busy === "start" ? "Beginning…" : `Begin from ${previousSession}`}
                </Btn>
              </>
            ) : null}
            <div className="sub2 mt-4 mb-2">Or begin blank, with the NUC approved quota:</div>
            <div className="row">
              <input className="tnum ws__in" style={{ width: 110 }} value={newQuota} placeholder="10198" onChange={(e) => setNewQuota(e.target.value)} disabled={!may} />
              <Btn
                kind="ghost"
                disabled={!may || busy !== null || !num(newQuota)}
                onClick={() =>
                  void send("PUT", base, {
                    nucQuota: num(newQuota), weightUtme: 70, weightPutme: 30, ratioUtme: 80, ratioDe: 20, ratioScience: 60, ratioArts: 40,
                    elgCapPct: 50, deptSharePct: 80, indexPrelimPlaces: 6, indexPerZone: 2, mpfOnly: true, screeningRequired: true, maxAlternatives: 3,
                  }, `${session} admission settings created`, "create")
                }
              >
                {busy === "create" ? "Creating…" : `Create the ${session} settings`}
              </Btn>
            </div>
            {!may ? (
              <div className="sub2 mt-3">
                Settings are made by the Academic Office or the Registrar. You are acting as{" "}
                <b>{officeLabel(actingOffice)}</b>.
              </div>
            ) : null}
          </div>
        </div>
        {problem ? <ProblemNotice problem={problem} /> : null}
        {sessions.length > 0 && (
          <Panel title="Sessions with settings" right={`${sessions.length}`}>
            <DTable
              cols={["Session", "State|mid"]}
              rows={sessions.map((s) => [
                <a key="s" href={`/admissions/settings?session=${encodeURIComponent(s.session)}`} className="b600" style={{ color: "var(--chrome)" }}>{s.session}</a>,
                s.state === "IN_FORCE" ? <Pil kind="ok" key="p">in force</Pil> : <Pil kind="grey" key="p">{s.state.toLowerCase()}</Pil>,
              ])}
            />
          </Panel>
        )}
      </>
    );
  }

  /* ── derived ── */
  const critTotal = policy.criteria.reduce((a, c) => a + c.percent, 0);
  /* quotas are per programme now — the distributed total is the sum of the programme quotas */
  const quotaTotal = policy.programmes.reduce((a, p) => a + (p.quota ?? 0), 0);
  const withRule = policy.programmes.filter((p) => p.stated && !p.closed);
  /* a programme closed for the session needs no rule: it is not admitted into (V023) */
  const closedThisSession = policy.programmes.filter((p) => p.closed);
  const withoutRule = policy.programmes.filter((p) => !p.stated && !p.closed);
  const f = policy.findings;
  const blocking = ADM_QUESTIONS.filter((q) => q[0] === "blocking");
  const facultyCutoff = (code: string) => policy.facultyCutoffs.find((x) => x.facultyCode === code)?.cutoff ?? null;
  const settingsBody = (patch: Partial<Record<string, number>>) => ({
    nucQuota: policy.nucQuota, weightUtme: policy.weightUtme, weightPutme: policy.weightPutme,
    ratioUtme: policy.ratioUtme, ratioDe: policy.ratioDe, ratioScience: policy.ratioScience, ratioArts: policy.ratioArts,
    elgCapPct: policy.elgCapPct, deptSharePct: policy.deptSharePct, indexPrelimPlaces: policy.indexPrelimPlaces,
    indexPerZone: policy.indexPerZone, mpfOnly: policy.mpfOnly, screeningRequired: policy.screeningRequired, maxAlternatives: policy.maxAlternatives ?? 3, ...patch,
  });
  const critMap = Object.fromEntries(policy.criteria.map((c) => [c.criterion, c.percent]));

  const aggregate = (utme: number, putme: number) =>
    Math.round(((utme / 400) * 100 * policy.weightUtme) / 100 * 100 + (putme * policy.weightPutme) / 100 * 100) / 100;

  const refusal =
    tried && !policy.inForce
      ? !instrument.trim()
        ? "Settings with no instrument behind them are somebody’s opinion about a cut-off. Cite the Central Admissions Committee minute that approved them."
        : f.length
          ? `${f.length} finding${f.length === 1 ? "" : "s"} still stand${f.length === 1 ? "s" : ""}, the first being ${f[0].finding}. A session opened over an unanswered finding is a session in which somebody is admitted against a rule that was never set.`
          : ""
      : "";

  const reaffirmRefusal =
    tried && policy.inForce && f.length
      ? `${f.length} finding${f.length === 1 ? "" : "s"} still stand${f.length === 1 ? "s" : ""}, the first being ${f[0].finding}. Re-affirming over an unanswered finding puts a rule in force that was never set.`
      : "";

  /* ── 1 · the session ── */
  const sessionTab = (
    <>
      <Panel title="The aggregate score" right="Paragraph 2.6 · NUC/JAMB approved weighting">
        <PBody>
          <div className="sub2 mb-3">
            UTME (out of 400) is <b>scaled to 100 before it is weighted</b> against the Post-UTME score (out of 100).
          </div>
          <DTable
            cols={["Component", "Weight|mid", "Worked example|num"]}
            rows={[
              ["UTME", <span key="w">{field("weightUtme", policy.weightUtme, 74, (v) => void send("PUT", base, settingsBody({ weightUtme: v ?? 0 }), "UTME weighting changed", "w"))} %</span>,
                <span className="sub2" key="e">247 of 400 &rarr; 61.8 &rarr; <b className="tnum">{Math.round((247 / 400) * 100 * policy.weightUtme) / 100}</b></span>],
              ["Post-UTME screening", <span key="w">{field("weightPutme", policy.weightPutme, 74, (v) => void send("PUT", base, settingsBody({ weightPutme: v ?? 0 }), "Post-UTME weighting changed", "w"))} %</span>,
                <span className="sub2" key="e">68.5 of 100 &rarr; <b className="tnum">{Math.round(68.5 * policy.weightPutme) / 100}</b></span>],
              [<strong key="a">Aggregate</strong>,
                <b className="tnum" key="t" style={{ color: policy.weightUtme + policy.weightPutme === 100 ? "var(--green-ink)" : "var(--red-ink)" }}>{policy.weightUtme + policy.weightPutme} %</b>,
                <strong className="tnum t-md" key="x">{aggregate(247, 68.5).toFixed(2)}</strong>],
            ]}
          />
        </PBody>
      </Panel>

      <LoadCutoff session={session} cutoff={loadCutoff} may={may} />

      <OlevelGrading session={session} may={may} />

      <Panel title="The four selection criteria" right="Paragraph 2.4 · total must be 100%">
        <DTable
          cols={["Criterion", "What it means", "Share|mid"]}
          rows={[
            ...CRITERIA.map((k) => [
              <strong key="n">{CRIT_LABEL[k][0]}</strong>,
              <span className="sub2" key="m">{CRIT_LABEL[k][1]}</span>,
              <span key="s">
                {field(`c:${k}`, critMap[k] ?? null, 74, (v) =>
                  void send("PUT", `${base}/criteria`, { ...Object.fromEntries(CRITERIA.map((c) => [c, critMap[c] ?? 0])), [k]: v ?? 0 }, `${CRIT_LABEL[k][0]} share changed`, "c"))} %
              </span>,
            ]),
            [<strong key="t">Total</strong>, "", <b className="tnum t-md" key="v" style={{ color: critTotal === 100 ? "var(--green-ink)" : "var(--red-ink)" }}>{critTotal} %</b>],
          ]}
        />
      </Panel>

      <Panel title="The ratios and the caps" right="Paragraphs 1.0, 2.5 and 2.11">
        <DTable
          cols={["Rule", "As issued|mid", "Where it comes from"]}
          rows={[
            ["UTME to Direct Entry", <span className="tnum" key="v">{policy.ratioUtme}:{policy.ratioDe}</span>, <span className="sub2" key="s">1.0(v) &mdash; the session default. Education carries a per-faculty 60:40 override on the Faculty quotas tab.</span>],
            ["Science to Arts", <span className="tnum" key="v">{policy.ratioScience}:{policy.ratioArts}</span>, <span className="sub2" key="s">1.0(vi) &mdash; separate from the UTME:DE Education exception</span>],
            ["Departmental recommendations", <span className="tnum" key="v">{policy.deptSharePct}%</span>, <span className="sub2" key="s">2.5 &mdash; departments make {policy.deptSharePct}% of the UTME merit recommendations</span>],
            ["Equality of Local Government ceiling", <span className="tnum" key="v">{policy.elgCapPct}%</span>, <span className="sub2" key="s" style={{ color: (critMap.ELG ?? 30) > policy.elgCapPct ? "var(--red-ink)" : undefined }}>2.11 &mdash; the share ({critMap.ELG ?? 30}% at 2.4) may go up to this, never above it{(critMap.ELG ?? 30) > policy.elgCapPct ? " — the share is over the ceiling" : ""}</span>],
            ["Index programmes, Preliminary placement", <span className="tnum" key="v">{policy.indexPrelimPlaces}</span>, <span className="sub2" key="s">2.5 &mdash; under State Merit, {policy.indexPerZone} from each Senatorial Zone</span>],
            ["Most Preferred First only", policy.mpfOnly ? <Pil kind="ok" key="v">Required</Pil> : <Pil kind="bad" key="v">Relaxed</Pil>, <span className="sub2" key="s">2.8 &mdash; every recommended name must be on the MPF list</span>],
            ["University screening passed", policy.screeningRequired ? <Pil kind="ok" key="v">Required</Pil> : <Pil kind="bad" key="v">Relaxed</Pil>, <span className="sub2" key="s">2.7 &mdash; only candidates who passed the University&rsquo;s own standard screening may be recommended</span>],
            ["Programmes suggested to a refused candidate", <span key="v">{field("maxAlternatives", policy.maxAlternatives ?? 3, 60, (v) => void send("PUT", base, settingsBody({ maxAlternatives: Math.max(1, Math.min(5, v ?? 3)) }), "Suggested programmes per candidate changed", "w"))}</span>, <span className="sub2" key="s">The eligibility engine evaluates every open programme but suggests only the best-ranked eligible ones &mdash; one to five, three by default &mdash; on Programme Eligibility, the applicant&rsquo;s page, the JAMB list and the reconsiderations; the rest stay on the desk&rsquo;s full view</span>],
          ]}
        />
      </Panel>
      <Panel title="Catchment local governments" right="For the Locality basis">
        <PBody>
          <div className="sub2 mb-2">LGAs in the University&rsquo;s catchment; their candidates carry the <b>Locality</b> basis. One per line, or comma-separated.</div>
          <textarea id="catchment" className="ctl" rows={4} value={"catchment" in edits ? edits["catchment"] : (policy.catchmentLgas ?? []).join(", ")} onChange={(e) => setEdits({ ...edits, catchment: e.target.value })} placeholder="Makurdi, Guma, Gwer East, Gwer West, Tarka" disabled={!may} />
          <div className="mt-2">
            <Btn kind="primary" disabled={!may || busy !== null} onClick={() => void send("PUT", `${base}/catchment`, { lgas: ("catchment" in edits ? edits["catchment"] : (policy.catchmentLgas ?? []).join(", ")).split(/[,\n]/).map((s) => s.trim()).filter(Boolean) }, `Catchment local governments stated for ${session}`, "catch")}>{busy === "catch" ? "Saving…" : "Save the catchment"}</Btn>
          </div>
        </PBody>
      </Panel>
      <Panel title="Subject equivalencies" right="For the eligibility engine">
        <PBody>
          <div className="sub2 mb-2">Senate-approved subject equivalences, one per line as <b>Required subject = Accepted subject</b>, optionally followed by <b>@OLEVEL</b> or <b>@UTME</b> (default: both).</div>
          <textarea id="equiv" className="ctl tnum" rows={5} value={"equiv" in edits ? edits["equiv"] : equivText} onChange={(e) => setEdits({ ...edits, equiv: e.target.value })} placeholder={"Biology = Agricultural Science\nMathematics = Further Mathematics @OLEVEL"} disabled={!may} />
          <div className="mt-2 row row--inline row--tight">
            <Btn kind="primary" disabled={!may || busy !== null} onClick={() => {
              const rows: { subject: string; equivalent: string; scope: string }[] = [];
              for (const line of ("equiv" in edits ? edits["equiv"] : equivText).split(/\n/)) {
                const m = line.trim().match(/^([^=]+?)\s*=\s*([^@]+?)\s*(?:@\s*(OLEVEL|UTME|ANY))?$/i);
                if (m) rows.push({ subject: m[1].trim(), equivalent: m[2].trim(), scope: (m[3] ?? "ANY").toUpperCase() });
              }
              void send("PUT", `${base}/equivalences`, { rows }, `Subject equivalencies stated for ${session}: ${rows.length}`, "equiv");
            }}>{busy === "equiv" ? "Saving…" : "Save the equivalencies"}</Btn>
            <span className="sub2">{(policy.equivalences ?? []).length} on record</span>
          </div>
        </PBody>
      </Panel>
    </>
  );

  /* ── 2 · the faculties ── */
  const facultiesSorted = [...policy.facultyCutoffs].sort((a, b) => (a.facultyName < b.facultyName ? -1 : 1));
  const facultyTab = (
    <>
      <Note kind="info" title="Quotas and cut-offs are set per programme">
        Set them on the <b>Programme requirements</b> tab. This tab holds the NUC ceiling and the UTME:Direct-Entry split.
      </Note>
      <Panel title="NUC approved quota" right="The ceiling for the session">
        <PBody>
          <div className="sub2">The total number of places the NUC approved for {session}: {field("nucQuota", policy.nucQuota, 96, (v) => void send("PUT", `${base}/nuc-quota`, { quota: v ?? policy.nucQuota }, `NUC approved quota stated as ${v ?? policy.nucQuota} for ${session}`, "q"), undefined, true)} <span className="sub2">— can be raised after the policy is in force.</span></div>
        </PBody>
      </Panel>
      <Panel title="Faculty UTME:Direct-Entry split" right="Paragraph 2.3">
        <DTable
          cols={["Faculty", "As the guidelines name it", "UTME:DE|num"]}
          rows={facultiesSorted.map((fc) => [
            <span key="n"><strong>{fc.facultyName}</strong><div className="sub2 tnum">{fc.facultyCode}</div></span>,
            FAC_GUIDE[fc.facultyCode] ? <span className="sub2 ink-red" key="g">{FAC_GUIDE[fc.facultyCode]}</span> : <span className="sub2" key="g">the same</span>,
            <span key="r">{field(`ru:${fc.facultyCode}`, fc.ratioUtme, 52, (v) => void send("PUT", `${base}/faculties/${fc.facultyCode}`, { quota: fc.quota, cutoff: fc.cutoff, ratioUtme: v, ratioDe: v == null ? null : 100 - v }, `${fc.facultyName} UTME:DE split changed`, "r"), String(policy.ratioUtme))}<span className="sub2">:{fc.ratioUtme == null ? `${policy.ratioDe} (default)` : (100 - fc.ratioUtme)}</span></span>,
          ])}
        />
        <PBody><div className="sub2">Type the UTME share; Direct Entry is the rest. Blank inherits the session default of {policy.ratioUtme}:{policy.ratioDe}. Education is 60:40.</div></PBody>
      </Panel>
    </>
  );

  /* ── 3 · the programmes ── */
  const progRows = policy.programmes;
  const editingProgramme = editing ? policy.programmes.find((p) => p.code === editing) ?? null : null;
  /** the eligibility engine's own fields (V266): required O'Level subjects at a grade, additional screening — saved whether the policy is draft or in force; the rules version moves and every evaluation is re-read */
  async function saveEligibility(pr: AdmissionPolicy["programmes"][number]): Promise<boolean> {
    const items = ("pr-oreq" in edits ? edits["pr-oreq"] : (pr.olevelRequired ?? []).join(", ")).split(/[,\n]/).map((x) => x.trim()).filter(Boolean);
    const minGrade = ("pr-ogr" in edits ? edits["pr-ogr"] : pr.olevelRequiredMinGrade ?? "C6").trim() || "C6";
    const same = items.join("|") === (pr.olevelRequired ?? []).join("|") && minGrade === (pr.olevelRequiredMinGrade ?? "C6");
    const ok = same ? true : await send("PUT", `${base}/programmes/${pr.code}/olevel-required`, { items, minGrade }, `Required O’Level subjects for eligibility set for ${pr.name} (${session})`, "pr");
    if (!ok) return false;
    const screening = ("pr-scr" in edits ? edits["pr-scr"] : pr.additionalScreening ?? "").trim();
    if (screening === (pr.additionalScreening ?? "").trim()) return true;
    return send("PUT", `${base}/programmes/${pr.code}/screening`, { additionalScreening: screening || null }, `Additional screening ${screening ? "stated" : "removed"} for ${pr.name} (${session})`, "pr");
  }
  const progTab = (
    <>
      <Note kind="info" title="Quotas and cut-offs are set here, per programme">
        Edit each programme&rsquo;s <b>quota</b> (Places) and <b>UTME cut-off</b> inline below, even while in force. A programme without a cut-off inherits its faculty&rsquo;s.
      </Note>
      {withoutRule.length ? (
        <Note kind="bad" title={`${withoutRule.length} of ${policy.programmes.length} programmes have no rule for this session`}>
          Nobody may be admitted into them until a rule is stated.
        </Note>
      ) : null}
      <Panel title="Every programme the University runs" right={<span className="row row--inline">{`${withRule.length} of ${policy.programmes.length} carry a requirement${closedThisSession.length ? ` · ${closedThisSession.length} closed this session` : ""}`}<Btn kind="primary" disabled={locked || !withoutRule.length} onClick={() => { setChoosing(true); setChosen(""); }}>New rule</Btn></span>}>
        <DTable
          cols={["Programme", "Faculty|mid", "Cut-off|num", "O’Level requirement", "UTME subjects", "Direct Entry", "Places|num", "|num"]}
          rows={progRows.map((p) => {
            const cut = p.cutoff ?? facultyCutoff(p.facultyCode);
            return [
              <span key="n"><strong>{p.name}</strong><div className="sub2 tnum">{p.code}</div></span>,
              <span className="sub2" key="f">{p.facultyName}</span>,
              p.closed ? <Pil kind="grey" key="c">closed</Pil>
                : p.stated ? <span key="c">{field(`pk:${p.code}`, p.cutoff, 64, (v) => void send("PUT", `${base}/programmes/${p.code}/cutoff`, { cutoff: v }, `${p.name} cut-off changed`, `pk-${p.code}`), facultyCutoff(p.facultyCode) != null ? String(facultyCutoff(p.facultyCode)) : "—", true)}<div className="sub2">{p.cutoff ? "its own" : cut ? "faculty" : "none"}</div></span>
                : cut ? <span key="c"><b className="tnum">{cut}</b><div className="sub2">faculty</div></span> : <Pil kind="bad" key="c">none</Pil>,
              p.closed ? <span className="sub2" key="o">Not admitting this session: {p.closedReason}</span> : p.stated ? <span className="sub2" key="o">{p.olevelText}</span> : <Pil kind="bad" key="o">not stated</Pil>,
              <span className="sub2" key="u">{p.stated && !p.closed ? p.utmeText : ""}</span>,
              <span className="sub2" key="d">{p.stated && !p.closed ? p.deText : ""}</span>,
              p.stated && !p.closed
                ? <span key="q">{field(`pq:${p.code}`, p.quota, 68, (v) => void send("PUT", `${base}/programmes/${p.code}/quota`, { quota: v }, `${p.name} quota changed`, `pq-${p.code}`), "—", true)}</span>
                : <span className="sub2" key="q">—</span>,
              <span key="e" className="row row--inline row--tight">
                {p.closed ? (
                  <Btn kind="ghost" disabled={locked || busy !== null} onClick={() => void send("POST", `${base}/programmes/${p.code}/reopen`, {}, `${p.name} reopened for ${session}`, `re-${p.code}`)}>{busy === `re-${p.code}` ? "Reopening…" : "Reopen"}</Btn>
                ) : (
                  <>
                    {p.stated
                      ? <IcoBtn icon="edit" label={`Edit the admission rule for ${p.name}`} disabled={!may} onClick={() => { setEditing(p.code); setEdits({}); }} />
                      : <Btn kind="urgent" disabled={locked} onClick={() => { setEditing(p.code); setEdits({}); }}>State</Btn>}
                    {!p.stated ? (
                      <Btn kind="ghost" disabled={locked || busy !== null} title="Close this programme for the session: it needs no rule and admits nobody" onClick={() => { const reason = window.prompt(`Why is ${p.name} not admitting in ${session}? This goes on the record.`); if (!reason) return; void send("POST", `${base}/programmes/${p.code}/close`, { reason }, `${p.name} closed for ${session}: ${reason}`, `cl-${p.code}`); }}>{busy === `cl-${p.code}` ? "Closing…" : "Disable"}</Btn>
                    ) : null}
                  </>
                )}
              </span>,
            ];
          })}
        />
        {choosing ? (
          <Modal title="A new rule" sub={`${withoutRule.length} programme${withoutRule.length === 1 ? "" : "s"} without one for ${session}`} onClose={() => setChoosing(false)}
            foot={<><Btn kind="ghost" onClick={() => setChoosing(false)}>Cancel</Btn><span className="grow" /><Btn kind="primary" disabled={!chosen} onClick={() => { setChoosing(false); setEditing(chosen); setEdits({}); }}>State the rule</Btn></>}>
            <Field id="new-rule-programme" label="Programme" hint="Those with no rule this session and not closed">
              <select id="new-rule-programme" className="ctl" value={chosen} onChange={(e) => setChosen(e.target.value)}>
                <option value="">Choose the programme…</option>
                {withoutRule.map((p) => <option key={p.code} value={p.code}>{p.code} · {p.name} · {p.facultyName}</option>)}
              </select>
            </Field>
          </Modal>
        ) : null}
      </Panel>
      {editingProgramme && (
        <Modal
          title={`${editingProgramme.stated ? "The rule for" : "State the rule for"} ${editingProgramme.name}`}
          sub={`${editingProgramme.facultyName} · ${editingProgramme.code} · faculty cut-off ${facultyCutoff(editingProgramme.facultyCode) ?? "none"}`}
          wide
          onClose={() => { setEditing(null); setEdits({}); }}
          foot={<>
            <Btn kind="ghost" onClick={() => { setEditing(null); setEdits({}); }}>Cancel</Btn>
            <span className="grow" />
            {policy.inForce ? (
              // the policy is in force: the rule a candidate is ranked by is frozen, but the relevant
              // O'Level subjects (which subjects the score reads) may still be corrected
              <Btn
                kind="primary"
                disabled={busy !== null}
                onClick={async () => {
                  const ok = await send("PUT", `${base}/programmes/${editingProgramme.code}/olevel-subjects`, {
                    subjects: ("pr-subj" in edits ? edits["pr-subj"] : (editingProgramme.olevelSubjects ?? []).join(", ")).split(/[,\n]/).map((s) => s.trim()).filter(Boolean),
                  }, `Relevant O’Level subjects corrected for ${editingProgramme.name} (${session})`, "pr");
                  const ok2 = ok && await send("PUT", `${base}/programmes/${editingProgramme.code}/utme-subjects`, {
                    subjects: ("pr-usubj" in edits ? edits["pr-usubj"] : (editingProgramme.utmeSubjects ?? []).join(", ")).split(/[,\n]/).map((s) => s.trim()).filter(Boolean),
                  }, `Required UTME subjects set for ${editingProgramme.name} (${session})`, "pr");
                  const ok3 = ok2 && await send("PUT", `${base}/programmes/${editingProgramme.code}/de-subjects`, {
                    subjects: ("pr-dsubj" in edits ? edits["pr-dsubj"] : (editingProgramme.deSubjects ?? []).join(", ")).split(/[,\n]/).map((s) => s.trim()).filter(Boolean),
                    choose: num("pr-dchoose" in edits ? edits["pr-dchoose"] : String(editingProgramme.deChoose ?? "")),
                  }, `Required Direct Entry subjects set for ${editingProgramme.name} (${session})`, "pr");
                  const ok4 = ok3 && await saveEligibility(editingProgramme);
                  if (ok4) { setEditing(null); setEdits({}); }
                }}
              >
                {busy === "pr" ? "Saving…" : "Save O’Level, UTME, DE & eligibility rules"}
              </Btn>
            ) : (
              <Btn
                kind="primary"
                disabled={busy !== null}
                onClick={async () => {
                  const ok = await send("PUT", `${base}/programmes/${editingProgramme.code}`, {
                    cutoff: num("pr-cut" in edits ? edits["pr-cut"] : String(editingProgramme.cutoff ?? "")),
                    quota: num("pr-quota" in edits ? edits["pr-quota"] : String(editingProgramme.quota ?? "")),
                    olevelText: "pr-ol" in edits ? edits["pr-ol"] : editingProgramme.olevelText ?? "",
                    utmeText: "pr-ut" in edits ? edits["pr-ut"] : editingProgramme.utmeText ?? "",
                    deText: "pr-de" in edits ? edits["pr-de"] : editingProgramme.deText ?? "",
                    olevelSubjects: ("pr-subj" in edits ? edits["pr-subj"] : (editingProgramme.olevelSubjects ?? []).join(", ")).split(/[,\n]/).map((s) => s.trim()).filter(Boolean),
                    olevelAllowances: ("pr-allow" in edits ? edits["pr-allow"] : (editingProgramme.olevelAllowances ?? []).join(",")).split(",").map((s) => s.trim()).filter(Boolean),
                    utmeSubjects: ("pr-usubj" in edits ? edits["pr-usubj"] : (editingProgramme.utmeSubjects ?? []).join(", ")).split(/[,\n]/).map((s) => s.trim()).filter(Boolean),
                    deSubjects: ("pr-dsubj" in edits ? edits["pr-dsubj"] : (editingProgramme.deSubjects ?? []).join(", ")).split(/[,\n]/).map((s) => s.trim()).filter(Boolean),
                    deChoose: num("pr-dchoose" in edits ? edits["pr-dchoose"] : String(editingProgramme.deChoose ?? "")),
                  }, `Rule stated for ${editingProgramme.name} (${session})`, "pr");
                  const okE = ok && await saveEligibility(editingProgramme);
                  if (okE) { setEditing(null); setEdits({}); }
                }}
              >
                {busy === "pr" ? "Saving…" : "Save the rule"}
              </Btn>
            )}
          </>}
        >
          {policy.inForce ? (
            <Note kind="bad" title="In force — only the subject sets and eligibility rules may be corrected">
              The cut-off, requirement text and UTME/Direct Entry rules are frozen; the <b>relevant O&rsquo;Level subjects</b> may still be corrected.
            </Note>
          ) : (
            <Note kind="info" title="A rule is what a candidate is admitted against">
              A programme with no rule cannot admit anybody.
            </Note>
          )}
          <div className="grid grid--2 rfgrid">
            <Field id="pr-cut" label="Cut-off of its own" hint={policy.inForce ? "Frozen while in force · edit inline in the table" : "Leave blank for the faculty’s"}>
              <input id="pr-cut" className="ctl tnum" disabled={policy.inForce} value={"pr-cut" in edits ? edits["pr-cut"] : editingProgramme.cutoff ?? ""} onChange={(e) => setEdits({ ...edits, "pr-cut": e.target.value })} autoComplete="off" />
            </Field>
            <Field id="pr-quota" label="Programme quota" hint={policy.inForce ? "Frozen here while in force · edit inline in the table" : "Blank: no quota (everyone eligible is offered)"}>
              <input id="pr-quota" className="ctl tnum" disabled={policy.inForce} value={"pr-quota" in edits ? edits["pr-quota"] : editingProgramme.quota ?? ""} onChange={(e) => setEdits({ ...edits, "pr-quota": e.target.value })} autoComplete="off" />
            </Field>
            {([["pr-ol", "O’Level requirement", editingProgramme.olevelText], ["pr-ut", "UTME subjects", editingProgramme.utmeText], ["pr-de", "Direct Entry", editingProgramme.deText]] as [string, string, string | null][]).map(([k, label, current]) => (
              <Field id={k} label={label} full key={k}>
                <textarea id={k} className="ctl" rows={3} disabled={policy.inForce} value={k in edits ? edits[k] : current ?? ""} onChange={(e) => setEdits({ ...edits, [k]: e.target.value })} />
              </Field>
            ))}
            <Field id="pr-subj" label="Relevant O’Level subjects" hint="Comma-separated, as JAMB names them · the screening counts the best of these" full>
              <textarea id="pr-subj" className="ctl" rows={2} value={"pr-subj" in edits ? edits["pr-subj"] : (editingProgramme.olevelSubjects ?? []).join(", ")} onChange={(e) => setEdits({ ...edits, "pr-subj": e.target.value })} placeholder="English Language, Mathematics, Physics, Chemistry, Biology" />
            </Field>
            <Field id="pr-usubj" label="Required UTME subjects (checked)" hint="Comma = all required · “/” = any-one-of (e.g. Government/History) · “N of A/B/C” = any N of a set (e.g. “2 of Chemistry/Physics/Mathematics”) · English is always counted · blank = not checked" full>
              <textarea id="pr-usubj" className="ctl" rows={2} value={"pr-usubj" in edits ? edits["pr-usubj"] : (editingProgramme.utmeSubjects ?? []).join(", ")} onChange={(e) => setEdits({ ...edits, "pr-usubj": e.target.value })} placeholder="Biology, 2 of Chemistry/Mathematics/Physics" />
            </Field>
            <Field id="pr-dsubj" label="Direct Entry subjects (checked)" hint="The set a DE candidate is checked against · comma or one per line · “/” = alternatives (e.g. Biology/Zoology) · read from the captured award, not from CAPS · English is NOT auto-counted · blank = not checked" full>
              <textarea id="pr-dsubj" className="ctl" rows={2} value={"pr-dsubj" in edits ? edits["pr-dsubj"] : (editingProgramme.deSubjects ?? []).join(", ")} onChange={(e) => setEdits({ ...edits, "pr-dsubj": e.target.value })} placeholder="Physics, Chemistry, Biology" />
            </Field>
            <Field id="pr-oreq" label="Required O’Level subjects for eligibility (checked)" hint="Comma = all required at the grade below · “/” = any-one-of (e.g. Economics/Accounting) · “N of A/B/C” = any N of a set · English and Mathematics are checked separately as the compulsory credits · blank = only the compulsory credits and the credit count are checked" full>
              <textarea id="pr-oreq" className="ctl" rows={2} value={"pr-oreq" in edits ? edits["pr-oreq"] : (editingProgramme.olevelRequired ?? []).join(", ")} onChange={(e) => setEdits({ ...edits, "pr-oreq": e.target.value })} placeholder="Physics, Chemistry, Biology/Agricultural Science" />
            </Field>
            <Field id="pr-ogr" label="Minimum grade for those subjects" hint="C6 is a credit · a pass (D7/E8) only where Senate allows it">
              <select id="pr-ogr" className="ctl" value={"pr-ogr" in edits ? edits["pr-ogr"] : editingProgramme.olevelRequiredMinGrade ?? "C6"} onChange={(e) => setEdits({ ...edits, "pr-ogr": e.target.value })}>{["A1", "B2", "B3", "C4", "C5", "C6", "D7", "E8"].map((g) => <option key={g} value={g}>{g}</option>)}</select>
            </Field>
            <Field id="pr-scr" label="Additional screening" hint="Named here when the programme requires more than the academic rules (an aptitude test, an interview, a medical) · a candidate who meets the rules then reads ACADEMICALLY ELIGIBLE — ADDITIONAL SCREENING REQUIRED · blank = none">
              <input id="pr-scr" className="ctl" value={"pr-scr" in edits ? edits["pr-scr"] : editingProgramme.additionalScreening ?? ""} onChange={(e) => setEdits({ ...edits, "pr-scr": e.target.value })} placeholder="Aptitude test and interview" autoComplete="off" />
            </Field>
            <Field id="pr-dchoose" label="DE passes required" hint="How many of the set above the candidate must offer (e.g. 2 for “two ’A’ Level passes”) · blank defaults to two">
              <input id="pr-dchoose" className="ctl tnum" inputMode="numeric" value={"pr-dchoose" in edits ? edits["pr-dchoose"] : editingProgramme.deChoose ?? ""} onChange={(e) => setEdits({ ...edits, "pr-dchoose": e.target.value })} autoComplete="off" placeholder="2" />
            </Field>
            <Field id="pr-allow" label="Compulsory-credit exceptions" hint="A credit in English and Mathematics is compulsory for all programmes; tick where this programme accepts a pass instead" full>
              {(() => {
                const allow = ("pr-allow" in edits ? edits["pr-allow"] : (editingProgramme.olevelAllowances ?? []).join(",")).split(",").map((s) => s.trim()).filter(Boolean);
                const toggle = (subject: string) => { const s = new Set(allow); if (s.has(subject)) s.delete(subject); else s.add(subject); setEdits({ ...edits, "pr-allow": [...s].join(",") }); };
                return (
                  <div className="row" style={{ gap: "var(--s-4)" }}>
                    {["English Language", "Mathematics"].map((subject) => (
                      <label key={subject} className="sub2 row" style={{ cursor: "pointer" }}>
                        <input type="checkbox" className="pchk" disabled={policy.inForce} checked={allow.includes(subject)} onChange={() => toggle(subject)} /> Accept a pass in {subject}
                      </label>
                    ))}
                  </div>
                );
              })()}
            </Field>
          </div>
        </Modal>
      )}
    </>
  );

  /* ── 4 · putting it in force ── */
  const forceTab = (
    <>
      {f.length ? (
        <Note kind="bad" title={`${f.length} finding${f.length === 1 ? " stands" : "s stand"} between these settings and a live session`}>
          The session cannot be put in force while any stands.
        </Note>
      ) : (
        <Note kind="ok" title="Nothing outstanding">
          The settings check out. They still need the Committee&rsquo;s minute to take effect.
        </Note>
      )}
      {f.length ? (
        <Panel title="Findings" right="All must clear before the session opens">
          <DTable cols={["Finding", "What it means", "Whose|mid"]} rows={f.map((x) => [<strong key="f">{x.finding}</strong>, <span className="sub2" key="d">{x.detail}</span>, <span className="sub2" key="o">{x.owner}</span>])} />
        </Panel>
      ) : null}
      <Panel title="Questions the guidelines raise" right={`${ADM_QUESTIONS.length} · ${blocking.length} of them decide who is admitted`}>
        <DTable
          cols={["", "Question", "Whose|mid"]}
          rows={ADM_QUESTIONS.map((qq) => [
            qq[0] === "blocking" ? <Pil kind="bad" key="p">Blocking</Pil> : qq[0] === "decided" ? <Pil kind="ok" key="p">Decided</Pil> : <Pil kind="grey" key="p">Answer</Pil>,
            <span key="q"><strong>{qq[1]}</strong><div className="sub2">{qq[2]}</div></span>,
            <span className="sub2" key="w">{qq[3]}</span>,
          ])}
        />
      </Panel>
      <div className="card">
        <div className="card__body">
          <div className="eyebrow">Put the {session} settings in force</div>
          {policy.inForce ? (
            <>
              <Field id="as-reaffirm" label="Central Admissions Committee minute (re-affirmation)" hint={<>
                  In force under <b>{policy.instrument}</b>
                  {policy.inForceSince ? <> since {new Date(policy.inForceSince).toLocaleDateString("en-GB")}</> : null}. Changes take effect at once.
                  Leave blank to re-affirm under <b>{policy.instrument}</b>, or type a new minute.
                </>}>
                <input id="as-reaffirm" value={reaffirm} onChange={(e) => setReaffirm(e.target.value)} placeholder={policy.instrument ?? "CAC/2026/08"} autoComplete="off" disabled={!may} />
              </Field>
              {reaffirmRefusal ? <Note kind="bad" title="Refused">{reaffirmRefusal}</Note> : null}
              {problem ? <ProblemNotice problem={problem} /> : null}
              <Btn
                kind="primary"
                disabled={!may || busy !== null}
                onClick={() => {
                  setTried(true);
                  const minute = reaffirm.trim() || (policy.instrument ?? "");
                  if (!minute || f.length) return;
                  void send("POST", `${base}/put-in-force`, { instrument: minute }, `${session} admission settings re-affirmed in force under ${minute}`, "force").then((ok) => { if (ok) setReaffirm(""); });
                }}
              >
                {busy === "force" ? "Putting in force…" : "Put in force again"}
              </Btn>
            </>
          ) : (
            <>
              <Field id="as-instr" label="Central Admissions Committee minute" hint={<>
                  Every candidate admitted this session is admitted under this minute.
                </>}>
                <input id="as-instr" value={instrument} onChange={(e) => setInstrument(e.target.value)} placeholder="CAC/2026/07" autoComplete="off" disabled={locked} />
              </Field>
              {refusal ? <Note kind="bad" title="Refused">{refusal}</Note> : null}
              {problem ? <ProblemNotice problem={problem} /> : null}
              <Btn
                kind="primary"
                disabled={locked || busy !== null}
                onClick={() => {
                  setTried(true);
                  if (!instrument.trim() || f.length) return;
                  void send("POST", `${base}/put-in-force`, { instrument: instrument.trim() }, `${session} admission settings put in force under ${instrument.trim()}`, "force");
                }}
              >
                {busy === "force" ? "Putting in force…" : "Put in force"}
              </Btn>
            </>
          )}
        </div>
      </div>
    </>
  );

  return (
    <>
      <RoleLine allowed={SECRETARIAT} actingOffice={actingOffice}
        action="Setting the admission policy and putting a session in force" />
      <Note kind={policy.inForce ? "ok" : "info"} title={policy.inForce ? `The ${session} admission settings are in force` : `The ${session} admission settings are a DRAFT, and nothing may be admitted under them`}>
        {policy.inForce ? (
          <>Cut-offs and subject combinations are frozen. <b>Quotas</b> stay adjustable.</>
        ) : (
          <>Until the Committee&rsquo;s minute puts them in force, <b>no candidate can be ranked, cut off or admitted</b>.</>
        )}
        {!may ? <> You are acting as <b>{officeLabel(actingOffice)}</b>; the settings are read here and made by the Academic Office or the Registrar.</> : null}
      </Note>

      <Tiles
        items={[
          ["NUC approved quota", policy.nucQuota.toLocaleString(), null, `Carrying capacity, ${session}`],
          ["Distributed", quotaTotal.toLocaleString(), quotaTotal === policy.nucQuota ? "var(--green-ink)" : "var(--red-ink)", quotaTotal === policy.nucQuota ? "Balanced to the unit" : `${(policy.nucQuota - quotaTotal).toLocaleString()} unallocated`],
          ["Programmes with a rule", `${withRule.length} of ${policy.programmes.length}`, withoutRule.length ? "var(--red-ink)" : "var(--green-ink)", withoutRule.length ? `${withoutRule.length} cannot be admitted into` : "All stated"],
          ["Outstanding", String(f.length + blocking.length), f.length ? "var(--red-ink)" : "var(--chrome)", "Findings and questions"],
        ]}
      />

      <div className="card">
        <div className="card__body">
          <div className="rectabs">
            {ADM_TABS.map((t) => (
              <button key={t[0]} className={`rectab${tab === t[0] ? " is-on" : ""}`} onClick={() => setTab(t[0])}>
                <span className="t">{t[1]}</span>
                <span className="s">{t[2]}</span>
              </button>
            ))}
          </div>
        </div>
      </div>

      {problem && tab !== "force" ? <ProblemNotice problem={problem} /> : null}

      {tab === "session" ? sessionTab : tab === "faculty" ? facultyTab : tab === "prog" ? progTab : forceTab}
    </>
  );
}
