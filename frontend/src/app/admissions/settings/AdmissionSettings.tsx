"use client";

/**
 * Admission settings, per session — proto/part55.html tAdmissionSetup, as
 * the prototype lays it out, with the database behind it: the settings are
 * the rows of V008, the findings are admissions.policy_findings, and "Put in
 * force" is admissions.put_in_force, which refuses by name until nothing
 * stands in the way and a minute is cited. Settings in force are not edited.
 */
import { reasonHeader } from "@/lib/reason";
import { useState, type ReactNode } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { officeLabel } from "@/lib/offices";
import { Btn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Modal, Field } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";

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
  criteria: { criterion: string; percent: number }[];
  facultyCutoffs: { facultyCode: string; facultyName: string; quota: number | null; cutoff: number | null }[];
  programmeCutoffs: { code: string; name: string; cutoff: number }[];
  programmes: {
    code: string;
    name: string;
    facultyCode: string;
    facultyName: string;
    cutoff: number | null;
    olevelText: string | null;
    utmeText: string | null;
    deText: string | null;
    olevelCredits: number | null;
    olevelSittings: number | null;
    stated: boolean;
  }[];
  findings: { finding: string; detail: string; owner: string }[];
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
  ["blocking", "English and Mathematics: compulsory everywhere, or not?",
    <>The closing note says <i>&ldquo;Credit passes in English and Mathematics are compulsory for all programmes of the University&rdquo;</i>. At least four programme rows say otherwise: B.A. Linguistics asks for five credits <i>including English Language</i> and does not mention Mathematics; B.Sc. Political Science and B.Sc. Sociology ask for <b>a pass</b> in Mathematics, which is not a credit; B.Ed. Guidance and Counselling likewise says <i>&ldquo;with an &lsquo;O&rsquo; Level pass in Mathematics&rdquo;</i>. Under the note those candidates are ineligible; under their own rows they qualify. Every Sociology and Political Science applicant in the state turns on this one sentence.</>,
    "Central Admissions Committee"],
  ["blocking", "Equality of Local Government: 30% or not more than 50%?",
    <>Paragraph 2.4 sets ELG at <b>30%</b> of admissions. Paragraph 2.11 says recommendations on the basis of ELG <i>&ldquo;must not exceed 50%&rdquo;</i>. Thirty is a share to be filled; fifty is a ceiling not to be crossed. They are different instructions and they produce different lists.</>,
    "Central Admissions Committee"],
  ["blocking", "The Education exception: which ratio does 60:40 belong to?",
    <>Paragraph 1.0 reads <i>&ldquo;UTME/DE Ratio 80:20 (for all programmes except Education which is to maintain 60:40)&rdquo;</i>, and the next line sets the Science&ndash;Arts ratio at 60:40 for everybody. So the parenthesis reads either as <b>Education admits 40% by Direct Entry</b> &mdash; twice any other faculty &mdash; or as a restatement of the Science&ndash;Arts split that is already the rule. The Faculty&rsquo;s own 2024/2025 quota was 950 Science to 200 others, which is 83:17 and neither of them.</>,
    "Central Admissions Committee"],
  ["answer", "Two names for four faculties",
    <>The quota table names <i>Administration and Management</i>, <i>College of Health Sciences</i>, <i>Pharmacy</i> and <i>Technology education</i>. The University&rsquo;s programme table names <i>Management Sciences</i>, <i>Basic and Applied Medical Sciences</i>, <i>Pharmaceutical Sciences</i> and <i>Technology and Industrial Studies</i> &mdash; and the guidelines themselves use <i>Faculty of Pharmaceutical Sciences</i> four pages later. A quota is distributed against one name while the programmes hang off the other, which is exactly how a faculty ends up counted twice or not at all.</>,
    "Academic Office"],
  ["answer", "Biochemistry sits in two faculties",
    <>The subject combinations place <b>B.Sc. Biochemistry</b> under the Faculty of Science. The University&rsquo;s programme table places it under Basic and Applied Medical Sciences. Its candidates count against one faculty&rsquo;s quota and its cut-off comes from the other.</>,
    "Academic Office"],
  ["answer", "Mass Communication has no stated requirement",
    <>Six programmes of the Faculty of Communication and Media Studies are given subject combinations &mdash; Advertising, Broadcasting, Development Communication, Journalism, Public Relations and Strategic Communication. <b>Mass Communication</b>, the faculty&rsquo;s oldest programme, is not among them.</>,
    "Dean, Communication and Media Studies"],
];

const ADM_TABS: [string, string, ReactNode][] = [
  ["session", "Session and criteria", "Quota, weighting and the four criteria"],
  ["faculty", "Faculty quotas", "Distribution and cut-off marks"],
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
}: {
  session: string;
  policy: AdmissionPolicy | null;
  policyProblem: Problem | null;
  previous: AdmissionPolicy | null;
  previousSession: string;
  sessions: PolicySummary[];
  actingOffice: string | null;
}) {
  const router = useRouter();
  const [tab, setTab] = useState<string>("session");
  const [edits, setEdits] = useState<Record<string, string>>({});
  const [busy, setBusy] = useState<string | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [instrument, setInstrument] = useState("");
  const [tried, setTried] = useState(false);
  const [editing, setEditing] = useState<string | null>(null);
  const [newQuota, setNewQuota] = useState("");

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
        router.refresh();
        return true;
      }
      const json = await response.json().catch(() => null);
      setProblem(json && typeof json === "object" && "status" in json ? (json as Problem) : { status: response.status, title: response.statusText });
      return false;
    } finally {
      setBusy(null);
    }
  }

  const val = (key: string, current: number | null | undefined) => (key in edits ? edits[key] : current === null || current === undefined ? "" : String(current));
  const field = (key: string, current: number | null | undefined, width: number, onSave: (v: number | null) => void, placeholder?: string) => (
    <input
      className="tnum ws__in"
      style={{ width }}
      value={val(key, current)}
      placeholder={placeholder}
      disabled={locked}
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
          These will be the Central Admissions Committee&rsquo;s guidelines, made into settings the portal can actually
          apply. Until they are put in force by the Committee&rsquo;s minute, <b>no candidate can be ranked, cut off or
          admitted</b> for {session} &mdash; the portal refuses rather than falling back on last year&rsquo;s numbers.
        </Note>
        <div className="card">
          <div className="card__body">
            <div className="eyebrow">Begin the {session} settings</div>
            {previous ? (
              <>
                <div className="sub2" style={{ marginBottom: 10 }}>
                  Start from <b>{previousSession}</b> ({previous.inForce ? `in force under ${previous.instrument}` : "a draft"}): the
                  quota, weighting, criteria, every faculty&rsquo;s quota and cut-off and every programme&rsquo;s rule, as a new
                  draft to amend.
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
            <div className="sub2" style={{ margin: "14px 0 6px" }}>Or begin blank, with the NUC approved quota:</div>
            <div style={{ display: "flex", gap: 9, alignItems: "center", flexWrap: "wrap" }}>
              <input className="tnum ws__in" style={{ width: 110 }} value={newQuota} placeholder="10198" onChange={(e) => setNewQuota(e.target.value)} disabled={!may} />
              <Btn
                kind="ghost"
                disabled={!may || busy !== null || !num(newQuota)}
                onClick={() =>
                  void send("PUT", base, {
                    nucQuota: num(newQuota), weightUtme: 70, weightPutme: 30, ratioUtme: 80, ratioDe: 20, ratioScience: 60, ratioArts: 40,
                    elgCapPct: 50, deptSharePct: 80, indexPrelimPlaces: 6, indexPerZone: 2, mpfOnly: true, screeningRequired: true,
                  }, `${session} admission settings created`, "create")
                }
              >
                {busy === "create" ? "Creating…" : `Create the ${session} settings`}
              </Btn>
            </div>
            {!may ? (
              <div className="sub2" style={{ marginTop: 10 }}>
                The settings are made by the Committee&rsquo;s secretariat &mdash; the Academic Office or the Registrar. You are acting as{" "}
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
                <a key="s" href={`/admissions/settings?session=${encodeURIComponent(s.session)}`} style={{ fontWeight: 600, color: "var(--chrome)" }}>{s.session}</a>,
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
  const quotaTotal = policy.facultyCutoffs.reduce((a, f) => a + (f.quota ?? 0), 0);
  const withRule = policy.programmes.filter((p) => p.stated);
  const withoutRule = policy.programmes.filter((p) => !p.stated);
  const f = policy.findings;
  const blocking = ADM_QUESTIONS.filter((q) => q[0] === "blocking");
  const facultyCutoff = (code: string) => policy.facultyCutoffs.find((x) => x.facultyCode === code)?.cutoff ?? null;
  const settingsBody = (patch: Partial<Record<string, number>>) => ({
    nucQuota: policy.nucQuota, weightUtme: policy.weightUtme, weightPutme: policy.weightPutme,
    ratioUtme: policy.ratioUtme, ratioDe: policy.ratioDe, ratioScience: policy.ratioScience, ratioArts: policy.ratioArts,
    elgCapPct: policy.elgCapPct, deptSharePct: policy.deptSharePct, indexPrelimPlaces: policy.indexPrelimPlaces,
    indexPerZone: policy.indexPerZone, mpfOnly: policy.mpfOnly, screeningRequired: policy.screeningRequired, ...patch,
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

  /* ── 1 · the session ── */
  const sessionTab = (
    <>
      <Panel title="The aggregate score" right="Paragraph 2.6 · NUC/JAMB approved weighting">
        <PBody>
          <div className="sub2" style={{ marginBottom: 10 }}>
            UTME is marked out of 400 and the Post-UTME screening out of 100, so the UTME mark is <b>scaled to 100 before it is weighted</b>.
            Adding 247 to 68.5 is not an aggregate, and a system that does it ranks the whole University by UTME alone.
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
                <strong className="tnum" style={{ fontSize: 15 }} key="x">{aggregate(247, 68.5).toFixed(2)}</strong>],
            ]}
          />
        </PBody>
      </Panel>

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
            [<strong key="t">Total</strong>, "", <b className="tnum" key="v" style={{ fontSize: 15, color: critTotal === 100 ? "var(--green-ink)" : "var(--red-ink)" }}>{critTotal} %</b>],
          ]}
        />
      </Panel>

      <Panel title="The ratios and the caps" right="Paragraphs 1.0, 2.5 and 2.11">
        <DTable
          cols={["Rule", "As issued|mid", "Where it comes from"]}
          rows={[
            ["UTME to Direct Entry", <span className="tnum" key="v">{policy.ratioUtme}:{policy.ratioDe}</span>, <span className="sub2" key="s">1.0(v) &mdash; with an exception for Education that reads two ways. See the questions.</span>],
            ["Science to Arts", <span className="tnum" key="v">{policy.ratioScience}:{policy.ratioArts}</span>, <span className="sub2" key="s">1.0(vi)</span>],
            ["Departmental recommendations", <span className="tnum" key="v">{policy.deptSharePct}%</span>, <span className="sub2" key="s">2.5 &mdash; departments make {policy.deptSharePct}% of the UTME merit recommendations</span>],
            ["Equality of Local Government ceiling", <span className="tnum" key="v">{policy.elgCapPct}%</span>, <span className="sub2" key="s">2.11 &mdash; and {critMap.ELG ?? 30}% as a share at 2.4. See the questions.</span>],
            ["Index programmes, Preliminary placement", <span className="tnum" key="v">{policy.indexPrelimPlaces}</span>, <span className="sub2" key="s">2.5 &mdash; under State Merit, {policy.indexPerZone} from each Senatorial Zone</span>],
            ["Most Preferred First only", policy.mpfOnly ? <Pil kind="ok" key="v">Required</Pil> : <Pil kind="bad" key="v">Relaxed</Pil>, <span className="sub2" key="s">2.8 &mdash; every recommended name must be on the MPF list</span>],
            ["University screening passed", policy.screeningRequired ? <Pil kind="ok" key="v">Required</Pil> : <Pil kind="bad" key="v">Relaxed</Pil>, <span className="sub2" key="s">2.7 &mdash; only candidates who passed the University&rsquo;s own standard screening may be recommended</span>],
          ]}
        />
      </Panel>
    </>
  );

  /* ── 2 · the faculties ── */
  const facultiesSorted = [...policy.facultyCutoffs].sort((a, b) => (a.facultyName < b.facultyName ? -1 : 1));
  const prevQuota = (code: string) => previous?.facultyCutoffs.find((x) => x.facultyCode === code)?.quota ?? null;
  const prevTotal = previous ? previous.facultyCutoffs.reduce((a, x) => a + (x.quota ?? 0), 0) : 0;
  const facultyTab = (
    <>
      <Note kind="info" title={`The ${session} distribution is the Deans' to submit`}>
        Paragraph 2.3 asks each Dean to distribute the faculty quota across the courses in the faculty and submit it to the
        Academic Office; this is where it is submitted. The NUC approved quota is <b>{policy.nucQuota.toLocaleString()}</b>
        {previous ? <>; the {previousSession} distribution beside it totals <b>{prevTotal.toLocaleString()}</b>.</> : "."}
      </Note>
      <Panel title="Faculty quotas and cut-off marks" right="Paragraphs 2.3 and 2.13">
        <DTable
          cols={["Faculty", "As the guidelines name it", `${previousSession}|num`, `${session}|num`, "UTME cut-off|num"]}
          rows={[
            ...facultiesSorted.map((fc) => [
              <span key="n"><strong>{fc.facultyName}</strong><div className="sub2 tnum">{fc.facultyCode}</div></span>,
              FAC_GUIDE[fc.facultyCode] ? <span className="sub2" style={{ color: "var(--red-ink)" }} key="g">{FAC_GUIDE[fc.facultyCode]}</span> : <span className="sub2" key="g">the same</span>,
              <span className="tnum sub2" key="p">{prevQuota(fc.facultyCode)?.toLocaleString() ?? "—"}</span>,
              <span key="q">{field(`q:${fc.facultyCode}`, fc.quota, 88, (v) => void send("PUT", `${base}/faculties/${fc.facultyCode}`, { quota: v, cutoff: fc.cutoff }, `${fc.facultyName} quota changed`, "q"), "—")}</span>,
              <span key="k">{field(`k:${fc.facultyCode}`, fc.cutoff, 74, (v) => void send("PUT", `${base}/faculties/${fc.facultyCode}`, { quota: fc.quota, cutoff: v }, `${fc.facultyName} cut-off changed`, "k"))}</span>,
            ]),
            [<strong key="t">Total</strong>, "", <b className="tnum" key="p">{prevTotal.toLocaleString()}</b>,
              <span key="q"><b className="tnum" style={{ fontSize: 15, color: quotaTotal === policy.nucQuota ? "var(--green-ink)" : "var(--red-ink)" }}>{quotaTotal.toLocaleString()}</b><div className="sub2">of {policy.nucQuota.toLocaleString()}</div></span>, ""],
          ]}
        />
      </Panel>
      <Panel title="Programme cut-offs above their faculty’s" right="Paragraph 2.13">
        <DTable
          cols={["Programme", "Faculty", "Faculty cut-off|num", "Programme cut-off|num"]}
          rows={policy.programmeCutoffs.map((pc) => {
            const p = policy.programmes.find((x) => x.code === pc.code);
            return [
              <strong key="n">{pc.name}</strong>,
              <span className="sub2" key="f">{p?.facultyName ?? ""}</span>,
              <span className="tnum sub2" key="k">{p ? facultyCutoff(p.facultyCode) ?? "—" : "—"}</span>,
              <b className="tnum" key="c">{pc.cutoff}</b>,
            ];
          })}
        />
      </Panel>
    </>
  );

  /* ── 3 · the programmes ── */
  const progRows = policy.programmes;
  const editingProgramme = editing ? policy.programmes.find((p) => p.code === editing) ?? null : null;
  const progTab = (
    <>
      {withoutRule.length ? (
        <Note kind="bad" title={`${withoutRule.length} of ${policy.programmes.length} programmes have no rule for this session`}>
          Nobody may be admitted into them. That is the correct behaviour and not a gap to be papered over: a candidate
          admitted into a programme whose requirements nobody stated is a candidate nobody can defend at accreditation.
          The Deans and Heads of Department below have to state one.
        </Note>
      ) : null}
      <Panel title="Every programme the University runs" right={`${withRule.length} of ${policy.programmes.length} carry a requirement`}>
        <DTable
          cols={["Programme", "Faculty|mid", "Cut-off|num", "O’Level requirement", "UTME subjects", "Direct Entry", "|num"]}
          rows={progRows.map((p) => {
            const cut = p.cutoff ?? facultyCutoff(p.facultyCode);
            return [
              <span key="n"><strong>{p.name}</strong><div className="sub2 tnum">{p.code}</div></span>,
              <span className="sub2" key="f">{p.facultyName}</span>,
              cut ? <span key="c"><b className="tnum">{cut}</b><div className="sub2">{p.cutoff ? "its own" : "faculty"}</div></span> : <Pil kind="bad" key="c">none</Pil>,
              p.stated ? <span className="sub2" key="o">{p.olevelText}</span> : <Pil kind="bad" key="o">not stated</Pil>,
              <span className="sub2" key="u">{p.stated ? p.utmeText : ""}</span>,
              <span className="sub2" key="d">{p.stated ? p.deText : ""}</span>,
              <Btn kind={p.stated ? "ghost" : "urgent"} key="e" disabled={locked} onClick={() => { setEditing(p.code); setEdits({}); }}>
                {p.stated ? "Edit" : "State"}
              </Btn>,
            ];
          })}
        />
      </Panel>
      {editingProgramme && (
        <Modal
          title={`${editingProgramme.stated ? "The rule for" : "State the rule for"} ${editingProgramme.name}`}
          sub={`${editingProgramme.facultyName} · ${editingProgramme.code} · faculty cut-off ${facultyCutoff(editingProgramme.facultyCode) ?? "none"}`}
          wide
          onClose={() => { setEditing(null); setEdits({}); }}
          foot={<>
            <Btn kind="ghost" onClick={() => { setEditing(null); setEdits({}); }}>Cancel</Btn>
            <span style={{ flexGrow: 1 }} />
            <Btn
              kind="primary"
              disabled={busy !== null}
              onClick={async () => {
                const ok = await send("PUT", `${base}/programmes/${editingProgramme.code}`, {
                  cutoff: num("pr-cut" in edits ? edits["pr-cut"] : String(editingProgramme.cutoff ?? "")),
                  olevelText: "pr-ol" in edits ? edits["pr-ol"] : editingProgramme.olevelText ?? "",
                  utmeText: "pr-ut" in edits ? edits["pr-ut"] : editingProgramme.utmeText ?? "",
                  deText: "pr-de" in edits ? edits["pr-de"] : editingProgramme.deText ?? "",
                }, `Rule stated for ${editingProgramme.name} (${session})`, "pr");
                if (ok) { setEditing(null); setEdits({}); }
              }}
            >
              {busy === "pr" ? "Saving…" : "Save the rule"}
            </Btn>
          </>}
        >
          <Note kind="info" title="A rule is what a candidate is admitted against">
            The O&rsquo;Level requirement, the UTME subject combination and the Direct Entry rule are Senate&rsquo;s to state; a programme with none cannot admit anybody, and that is the correct behaviour.
          </Note>
          <div className="grid grid--2 rfgrid">
            <Field id="pr-cut" label="Cut-off of its own" hint="Leave blank for the faculty’s">
              <input id="pr-cut" className="ctl tnum" value={"pr-cut" in edits ? edits["pr-cut"] : editingProgramme.cutoff ?? ""} onChange={(e) => setEdits({ ...edits, "pr-cut": e.target.value })} autoComplete="off" />
            </Field>
            {([["pr-ol", "O’Level requirement", editingProgramme.olevelText], ["pr-ut", "UTME subjects", editingProgramme.utmeText], ["pr-de", "Direct Entry", editingProgramme.deText]] as [string, string, string | null][]).map(([k, label, current]) => (
              <Field id={k} label={label} full key={k}>
                <textarea id={k} className="ctl" rows={3} value={k in edits ? edits[k] : current ?? ""} onChange={(e) => setEdits({ ...edits, [k]: e.target.value })} />
              </Field>
            ))}
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
          Each names what is missing, by how much, and whose it is to answer. The session cannot be put in force while any
          of them stands &mdash; not as a warning that can be clicked past.
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
            qq[0] === "blocking" ? <Pil kind="bad" key="p">Blocking</Pil> : <Pil kind="grey" key="p">Answer</Pil>,
            <span key="q"><strong>{qq[1]}</strong><div className="sub2">{qq[2]}</div></span>,
            <span className="sub2" key="w">{qq[3]}</span>,
          ])}
        />
      </Panel>
      <div className="card">
        <div className="card__body">
          <div className="eyebrow">Put the {session} settings in force</div>
          <div className="field">
            <label htmlFor="as-instr">Central Admissions Committee minute</label>
            <input id="as-instr" value={policy.inForce ? policy.instrument ?? "" : instrument} onChange={(e) => setInstrument(e.target.value)} placeholder="CAC/2026/07" autoComplete="off" disabled={locked} />
            <div className="hint">
              Settings without an instrument are somebody&rsquo;s opinion about a cut-off. Every candidate admitted this session is
              admitted under this minute, and it is what the University produces when one of them is queried in four years&rsquo; time.
            </div>
          </div>
          {refusal ? <Note kind="bad" title="Refused">{refusal}</Note> : null}
          {problem ? <ProblemNotice problem={problem} /> : null}
          {policy.inForce ? (
            <Note kind="ok" title="In force">
              Cited to <b>{policy.instrument}</b>
              {policy.inForceSince ? <> since {new Date(policy.inForceSince).toLocaleDateString("en-GB")}</> : null}. A change from here is a new version citing a new minute; this one
              stays readable for as long as anybody admitted under it is alive.
            </Note>
          ) : (
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
          )}
        </div>
      </div>
    </>
  );

  return (
    <>
      <Note kind={policy.inForce ? "ok" : "info"} title={policy.inForce ? `The ${session} admission settings are in force` : `The ${session} admission settings are a DRAFT, and nothing may be admitted under them`}>
        {policy.inForce ? (
          <>Every cut-off, quota and subject combination the portal applies this session comes from here, and carries the minute that approved it. A correction is a new version citing a new minute; nothing is edited away.</>
        ) : (
          <>These are the Central Admissions Committee&rsquo;s guidelines, made into settings the portal can actually apply. Until they are put in force by the Committee&rsquo;s minute, <b>no candidate can be ranked, cut off or admitted</b> &mdash; the portal refuses rather than falling back on last year&rsquo;s numbers. Last year&rsquo;s quota applied to this year&rsquo;s candidates is how a university over-admits by nine hundred and learns of it at accreditation.</>
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
