"use client";

/**
 * V773: the Preliminary Fit rules — how a Direct Entry candidate's qualification is read against a programme on the Direct Entry
 * candidates workbook (Relevant, Partly relevant, Not relevant, Check manually). The University's default applies to every
 * programme; a programme's own rule replaces it whole where the Office sets one. A guide for the Admissions Committee only: it never
 * changes the rank, the qualified test or the Board's decision, so it may be corrected while the settings are in force, as the
 * subject sets are. GET/PUT …/policy/de-fit, PUT …/policy/programmes/{code}/de-fit (DeFitController).
 */
import { useCallback, useEffect, useState } from "react";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, IcoBtn, Note, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { AdmissionPolicy } from "./AdmissionSettings";

type Kind = "DEGREE" | "UNIVERSITY_DIPLOMA" | "HND" | "ND" | "NCE" | "A_LEVEL";
/** one qualification's rule as the API gives it; a key whose value is null may be absent */
export interface FitRule {
  kind: Kind; coreDisciplines?: string[] | null; relevantMin?: number | null; partlyMin?: number | null; relatedDisciplines?: string[] | null;
  relatedRelevantMin?: number | null; relatedPartlyMin?: number | null; otherFit: string; relevantPasses?: number | null; partlyPasses?: number | null;
}
interface Criterion { qualification: string; rule: string }
interface ClassName { points: number; name: string }
export interface DeFit {
  session: string; policyState?: string;
  classes?: Partial<Record<Kind, ClassName[]>>;
  default: { source: "DEFAULT" | "BUILT_IN" | string; rows: FitRule[]; criteria: Criterion[] };
  programmes: { code: string; name: string; rows: FitRule[]; criteria: Criterion[] }[];
}

const KINDS: Kind[] = ["DEGREE", "UNIVERSITY_DIPLOMA", "HND", "ND", "NCE", "A_LEVEL"];
const KIND_LABEL: Record<Kind, string> = {
  DEGREE: "1st Degree (Nigerian or foreign)", UNIVERSITY_DIPLOMA: "University Diploma", HND: "Higher National Diploma (HND)",
  ND: "National Diploma (ND)", NCE: "Nigeria Certificate in Education (NCE)", A_LEVEL: "A'Level (GCE, IJMB, JUPEB)",
};
/** each kind's classes, highest first (admissions.de_class_name), where the API sends none */
const CLASSES: Partial<Record<Kind, ClassName[]>> = {
  DEGREE: [{ points: 5, name: "First Class" }, { points: 4, name: "2nd Class Upper" }, { points: 3, name: "2nd Class Lower" }, { points: 2, name: "3rd Class" }, { points: 1, name: "Pass" }],
  UNIVERSITY_DIPLOMA: [{ points: 4, name: "Distinction" }, { points: 3, name: "Credit" }, { points: 2, name: "Merit" }, { points: 1, name: "Pass" }],
  HND: [{ points: 5, name: "Distinction" }, { points: 4, name: "Upper Credit" }, { points: 3, name: "Lower Credit" }, { points: 2, name: "Pass" }],
  ND: [{ points: 4, name: "Distinction" }, { points: 3, name: "Upper Credit" }, { points: 2, name: "Lower Credit" }, { points: 1, name: "Pass" }],
  A_LEVEL: [{ points: 5, name: "A" }, { points: 4, name: "B" }, { points: 3, name: "C" }, { points: 2, name: "D" }, { points: 1, name: "E" }],
};
const OTHER: [string, string][] = [["RELEVANT", "Relevant"], ["PARTLY_RELEVANT", "Partly relevant"], ["NOT_RELEVANT", "Not relevant"], ["CHECK_MANUALLY", "Check manually"]];
const SECRETARIAT = ["academic", "registrar", "dregistrar"];

/** a rule as the editor holds it: lists as the text typed, a threshold "" for Never */
interface Draft {
  kind: Kind; coreMode: "ANY" | "LIST" | "NONE"; core: string; relevantMin: string; partlyMin: string;
  related: string; relatedRelevantMin: string; relatedPartlyMin: string; otherFit: string; relevantPasses: string; partlyPasses: string;
}
const n2s = (v: number | null | undefined) => (v === null || v === undefined ? "" : String(v));
const s2n = (v: string) => (v.trim() === "" ? null : Number(v));
/** one per line or comma-separated; "/" keeps alternatives together */
const listOf = (text: string) => text.split(/[,\n]/).map((x) => x.trim()).filter(Boolean);

function toDraft(r: FitRule): Draft {
  const core = r.coreDisciplines;
  return {
    kind: r.kind, coreMode: core === null || core === undefined ? "ANY" : core.length ? "LIST" : "NONE", core: (core ?? []).join("\n"),
    relevantMin: n2s(r.relevantMin), partlyMin: n2s(r.partlyMin), related: (r.relatedDisciplines ?? []).join("\n"),
    relatedRelevantMin: n2s(r.relatedRelevantMin), relatedPartlyMin: n2s(r.relatedPartlyMin), otherFit: r.otherFit || "NOT_RELEVANT",
    relevantPasses: n2s(r.relevantPasses), partlyPasses: n2s(r.partlyPasses),
  };
}
/** the rule sent: coreDisciplines written out every time — null for "Any discipline", [] for "None", the list otherwise */
function toRule(d: Draft): FitRule {
  const a = d.kind === "A_LEVEL";
  return {
    kind: d.kind,
    coreDisciplines: d.coreMode === "LIST" ? listOf(d.core) : d.coreMode === "NONE" && !a ? [] : null,
    relevantMin: s2n(d.relevantMin), partlyMin: s2n(d.partlyMin),
    relatedDisciplines: a ? [] : listOf(d.related),
    relatedRelevantMin: a ? null : s2n(d.relatedRelevantMin), relatedPartlyMin: a ? null : s2n(d.relatedPartlyMin),
    otherFit: d.otherFit,
    relevantPasses: a ? s2n(d.relevantPasses) : null, partlyPasses: a ? s2n(d.partlyPasses) : null,
  };
}
/** the six rules in their order, each kind once */
const draftsOf = (rows: FitRule[]): Draft[] => KINDS.map((k) => toDraft(rows.find((r) => r.kind === k) ?? { kind: k, otherFit: "NOT_RELEVANT" }));

/** the editor: one card for each qualification, in the six-kind order */
function FitEditor({ drafts, onChange, classes, disabled, idp }: {
  drafts: Draft[]; onChange: (d: Draft[]) => void; classes: Partial<Record<Kind, ClassName[]>>; disabled: boolean; idp: string;
}) {
  const set = (i: number, patch: Partial<Draft>) => onChange(drafts.map((d, j) => (j === i ? { ...d, ...patch } : d)));
  const classSelect = (id: string, kind: Kind, value: string, onSet: (v: string) => void, never = true) => kind === "NCE" ? (
    <input id={id} className="ctl tnum" type="number" min={0} max={15} value={value} disabled={disabled} placeholder="Never" onChange={(e) => onSet(e.target.value)} style={{ maxWidth: 120 }} />
  ) : (
    <select id={id} className="ctl" value={value} disabled={disabled} onChange={(e) => onSet(e.target.value)}>
      {never ? <option value="">Never</option> : null}
      {(classes[kind] ?? CLASSES[kind] ?? []).map((c) => <option key={c.points} value={String(c.points)}>{c.name}{kind === "A_LEVEL" ? "" : " or better"}</option>)}
    </select>
  );
  return (
    <div className="grid grid--2" style={{ gap: "var(--s-3)" }}>
      {drafts.map((d, i) => {
        const id = `${idp}-${d.kind}`;
        const a = d.kind === "A_LEVEL";
        const what = d.kind === "NCE" ? "subjects" : "disciplines";
        return (
          <div className="card" key={d.kind}>
            <div className="card__body">
              <div className="eyebrow">{KIND_LABEL[d.kind]}</div>
              {a ? (
                <>
                  <Field id={`${id}-mode`} label="Subjects counted">
                    <div className="row" style={{ gap: "var(--s-4)" }}>
                      <label className="sub2 row row--inline row--tight"><input type="radio" name={`${id}-mode`} checked={d.coreMode !== "LIST"} disabled={disabled} onChange={() => set(i, { coreMode: "ANY" })} /> The programme&rsquo;s Direct Entry subjects where set, else any</label>
                      <label className="sub2 row row--inline row--tight"><input type="radio" name={`${id}-mode`} checked={d.coreMode === "LIST"} disabled={disabled} onChange={() => set(i, { coreMode: "LIST" })} /> These subjects</label>
                    </div>
                  </Field>
                  {d.coreMode === "LIST" ? (
                    <Field id={`${id}-core`} label="Subjects" hint="One per line or comma-separated · “/” for alternatives (Biology/Zoology/Botany)">
                      <textarea id={`${id}-core`} className="ctl" rows={3} value={d.core} disabled={disabled} onChange={(e) => set(i, { core: e.target.value })} placeholder={"Biology/Zoology/Botany\nChemistry\nPhysics"} />
                    </Field>
                  ) : null}
                  <div className="row row--inline" style={{ gap: "var(--s-2)", flexWrap: "wrap" }}>
                    <span className="sub2">Relevant:</span>
                    <input aria-label="Passes for Relevant" className="ctl tnum" type="number" min={1} max={9} style={{ width: 70 }} value={d.relevantPasses} disabled={disabled} onChange={(e) => set(i, { relevantPasses: e.target.value })} />
                    <span className="sub2">passes at</span>
                    {classSelect(`${id}-rel`, "A_LEVEL", d.relevantMin, (v) => set(i, { relevantMin: v }), false)}
                    <span className="sub2">or better</span>
                  </div>
                  <div className="row row--inline mt-2" style={{ gap: "var(--s-2)", flexWrap: "wrap" }}>
                    <span className="sub2">Partly relevant:</span>
                    <input aria-label="Passes for Partly relevant" className="ctl tnum" type="number" min={1} max={9} style={{ width: 70 }} value={d.partlyPasses} disabled={disabled} onChange={(e) => set(i, { partlyPasses: e.target.value })} />
                    <span className="sub2">passes at</span>
                    {classSelect(`${id}-part`, "A_LEVEL", d.partlyMin, (v) => set(i, { partlyMin: v }), false)}
                    <span className="sub2">or better</span>
                  </div>
                  <div className="sub2 mt-2">Fewer passes are Not relevant; F is a fail.</div>
                </>
              ) : (
                <>
                  <Field id={`${id}-mode`} label={d.kind === "NCE" ? "Subjects" : "Disciplines"}>
                    <div className="row" style={{ gap: "var(--s-4)", flexWrap: "wrap" }}>
                      <label className="sub2 row row--inline row--tight"><input type="radio" name={`${id}-mode`} checked={d.coreMode === "ANY"} disabled={disabled} onChange={() => set(i, { coreMode: "ANY" })} /> Any {d.kind === "NCE" ? "subjects" : "discipline"}</label>
                      <label className="sub2 row row--inline row--tight"><input type="radio" name={`${id}-mode`} checked={d.coreMode === "LIST"} disabled={disabled} onChange={() => set(i, { coreMode: "LIST" })} /> These {what}</label>
                      <label className="sub2 row row--inline row--tight"><input type="radio" name={`${id}-mode`} checked={d.coreMode === "NONE"} disabled={disabled} onChange={() => set(i, { coreMode: "NONE" })} /> None <span className="sub2">(only the programme&rsquo;s own discipline)</span></label>
                    </div>
                  </Field>
                  {d.coreMode === "LIST" ? (
                    <Field id={`${id}-core`} label={`Core ${what}`} hint="One per line or comma-separated · “/” for alternatives">
                      <textarea id={`${id}-core`} className="ctl" rows={3} value={d.core} disabled={disabled} onChange={(e) => set(i, { core: e.target.value })} />
                    </Field>
                  ) : null}
                  <div className="grid grid--2 rfgrid">
                    <Field id={`${id}-rel`} label="Relevant at">{classSelect(`${id}-rel`, d.kind, d.relevantMin, (v) => set(i, { relevantMin: v }))}</Field>
                    <Field id={`${id}-part`} label="Partly relevant at">{classSelect(`${id}-part`, d.kind, d.partlyMin, (v) => set(i, { partlyMin: v }))}</Field>
                  </div>
                  <Field id={`${id}-related`} label={`Related ${what}`} hint="Read on their own two thresholds · blank: none">
                    <textarea id={`${id}-related`} className="ctl" rows={2} value={d.related} disabled={disabled} onChange={(e) => set(i, { related: e.target.value })} />
                  </Field>
                  {d.related.trim() ? (
                    <div className="grid grid--2 rfgrid">
                      <Field id={`${id}-rrel`} label="Related: Relevant at">{classSelect(`${id}-rrel`, d.kind, d.relatedRelevantMin, (v) => set(i, { relatedRelevantMin: v }))}</Field>
                      <Field id={`${id}-rpart`} label="Related: Partly relevant at">{classSelect(`${id}-rpart`, d.kind, d.relatedPartlyMin, (v) => set(i, { relatedPartlyMin: v }))}</Field>
                    </div>
                  ) : null}
                  <Field id={`${id}-other`} label={`Any other ${d.kind === "NCE" ? "subjects" : "discipline"}`}>
                    <select id={`${id}-other`} className="ctl" value={d.otherFit} disabled={disabled} onChange={(e) => set(i, { otherFit: e.target.value })}>
                      {OTHER.map(([v, l]) => <option key={v} value={v}>{l}</option>)}
                    </select>
                  </Field>
                </>
              )}
            </div>
          </div>
        );
      })}
    </div>
  );
}

/** the rules as GET …/policy/de-fit gives them, or why not */
async function readFit(base: string): Promise<DeFit | Problem> {
  try {
    const r = await fetch(`${base}/de-fit`, { cache: "no-store" });
    const j = await r.json().catch(() => null);
    if (r.ok && j && typeof j === "object" && "default" in j) return j as DeFit;
    return j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText || "The Preliminary Fit rules could not be read." };
  } catch {
    return { status: 0, title: "The network dropped the request.", detail: "Try again in a moment." };
  }
}

/** the rule in force, in the words the Fit Criteria sheet prints */
function Words({ criteria }: { criteria: Criterion[] }) {
  return criteria.length ? (
    <DTable noPrint cols={["Qualification", "Rule applied"]} rows={criteria.map((c, i) => [<strong key={`q${i}`}>{c.qualification}</strong>, <span className="sub2" key={`r${i}`}>{c.rule}</span>])} />
  ) : null;
}

export function DeFitRules({ session, policy, actingOffice }: { session: string; policy: AdmissionPolicy; actingOffice: string | null }) {
  const base = `/api/bff/api/v1/admissions/sessions/${session}/policy`;
  const may = actingOffice !== null && SECRETARIAT.includes(actingOffice);
  const [data, setData] = useState<DeFit | null>(null);
  const [loadProblem, setLoadProblem] = useState<Problem | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [defaults, setDefaults] = useState<Draft[] | null>(null);
  const [choosing, setChoosing] = useState(false);
  const [chosen, setChosen] = useState("");
  const [editing, setEditing] = useState<{ code: string; name: string; drafts: Draft[] } | null>(null);

  // what was read; the default's own draft is dropped only when asked (its own save, the first read) — a programme's save
  // re-reads the rules and must not take the officer's unsaved changes to the default with it
  const take = useCallback((got: DeFit | Problem, dropDraft = true) => {
    if ("default" in got) { setData(got); if (dropDraft) setDefaults(null); setLoadProblem(null); } else setLoadProblem(got);
  }, []);
  const load = useCallback(async (dropDraft: boolean) => take(await readFit(base), dropDraft), [base, take]);
  useEffect(() => {
    let live = true;
    (async () => { const got = await readFit(base); if (live) take(got); })();
    return () => { live = false; };
  }, [base, take]);

  async function put(path: string, rows: FitRule[], reason: string, key: string): Promise<boolean> {
    setBusy(key);
    setProblem(null);
    try {
      const r = await fetch(`${base}${path}`, { method: "PUT", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify({ rows }) });
      if (!r.ok) {
        const j = await r.json().catch(() => null);
        const refusal = j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText };
        setProblem(refusal); notifyProblem(refusal);
        return false;
      }
      notify(reason);
      await load(key === "default");
      return true;
    } finally {
      setBusy(null);
    }
  }

  if (!data) {
    return loadProblem ? <ProblemNotice problem={loadProblem} /> : <Panel title="Direct Entry Preliminary Fit"><PBody><div className="sub2">Reading the rules…</div></PBody></Panel>;
  }
  const classes = { ...CLASSES, ...(data.classes ?? {}) };
  const draft = defaults ?? draftsOf(data.default.rows);
  const own = new Set(data.programmes.map((p) => p.code));
  const without = policy.programmes.filter((p) => !own.has(p.code));
  const deText = editing ? policy.programmes.find((p) => p.code === editing.code)?.deText ?? null : null;

  return (
    <>
      <Note kind="info" title="A preliminary guide for the Admissions Committee">
        Preliminary Fit is shown on the Direct Entry candidates workbook. It never changes the rank, the qualified test or the Board&rsquo;s decision, and may be corrected while the settings are in force.
      </Note>
      {problem && !editing ? <ProblemNotice problem={problem} /> : null}

      <Panel title="The University's default" right={data.default.source === "DEFAULT" ? <Pil kind="ok">set for {session}</Pil> : <Pil kind="grey">built-in</Pil>}>
        <PBody>
          <div className="sub2 mb-3">Applies to every Direct Entry programme without a rule of its own.{data.default.source === "DEFAULT" ? "" : ` None is set for ${session} yet: the built-in default is read until the Office saves one.`}</div>
          <FitEditor drafts={draft} onChange={setDefaults} classes={classes} disabled={!may} idp="fit-default" />
          <div className="row mt-3">
            <Btn kind="primary" disabled={!may || busy !== null} onClick={() => void put("/de-fit", draft.map(toRule), `Direct Entry Preliminary Fit default saved (${session})`, "default")}>{busy === "default" ? "Saving…" : "Save the default"}</Btn>
            {defaults ? <Btn kind="ghost" disabled={busy !== null} onClick={() => setDefaults(null)}>Undo the changes</Btn> : null}
            {!may ? <span className="sub2">The rules are set by the Academic Office, the Registrar or the Deputy Registrar.</span> : null}
          </div>
          <div className="eyebrow mt-4">The rule in force, in words</div>
          <Words criteria={data.default.criteria} />
        </PBody>
      </Panel>

      <Panel title="Programmes with a rule of their own" right={<span className="row row--inline">{data.programmes.length}<Btn kind="primary" disabled={!may || busy !== null || !without.length} onClick={() => { setChoosing(true); setChosen(""); }}>Give a programme its own rule</Btn></span>}>
        {data.programmes.length ? (
          <DTable
            cols={["Programme", "The rule in words", "|num"]}
            texts={data.programmes.map((p) => `${p.name} ${p.code}`)}
            rows={data.programmes.map((p) => [
              <span key="n"><strong>{p.name}</strong><div className="sub2 tnum">{p.code}</div></span>,
              <span className="sub2" key="w">{p.criteria.map((c, i) => <span key={i}>{c.qualification}: {c.rule}<br /></span>)}</span>,
              <span key="a" className="row row--inline row--tight">
                <IcoBtn icon="edit" label={`Edit the Preliminary Fit rule of ${p.name}`} disabled={!may || busy !== null} onClick={() => { setProblem(null); setEditing({ code: p.code, name: p.name, drafts: draftsOf(p.rows) }); }} />
                <Btn kind="ghost" disabled={!may || busy !== null} onClick={() => {
                  if (!window.confirm(`${p.name} will follow the University's default Preliminary Fit rule again. Its own rule is removed. Go ahead?`)) return;
                  void put(`/programmes/${p.code}/de-fit`, [], `Direct Entry Preliminary Fit of ${p.name} back to the University's default (${session})`, `back-${p.code}`);
                }}>{busy === `back-${p.code}` ? "Removing…" : "Back to the default"}</Btn>
              </span>,
            ])}
          />
        ) : <PBody><div className="sub2">None: every programme follows the University&rsquo;s default.</div></PBody>}
      </Panel>

      {choosing ? (
        <Modal title="Give a programme its own rule" sub="Its own rule replaces the University's default whole" onClose={() => setChoosing(false)}
          foot={<><Btn kind="ghost" onClick={() => setChoosing(false)}>Cancel</Btn><span className="grow" /><Btn kind="primary" disabled={!chosen} onClick={() => {
            const p = policy.programmes.find((x) => x.code === chosen);
            setChoosing(false);
            if (p) { setProblem(null); setEditing({ code: p.code, name: p.name, drafts: draftsOf(data.default.rows) }); }
          }}>Write its rule</Btn></>}>
          <Field id="fit-programme" label="Programme" hint="Those that follow the default · the rule starts as a copy of it">
            <select id="fit-programme" className="ctl" value={chosen} onChange={(e) => setChosen(e.target.value)}>
              <option value="">Choose the programme…</option>
              {without.map((p) => <option key={p.code} value={p.code}>{p.code} · {p.name} · {p.facultyName}</option>)}
            </select>
          </Field>
        </Modal>
      ) : null}

      {editing ? (
        <Modal title={`Preliminary Fit for ${editing.name}`} sub={`${editing.code} · its own rule, in place of the University's default`} wide onClose={() => setEditing(null)}
          foot={<>
            <Btn kind="ghost" onClick={() => setEditing(null)}>Cancel</Btn>
            <span className="grow" />
            <Btn kind="primary" disabled={!may || busy !== null} onClick={async () => {
              const ok = await put(`/programmes/${editing.code}/de-fit`, editing.drafts.map(toRule), `Direct Entry Preliminary Fit rule saved for ${editing.name} (${session})`, "own");
              if (ok) setEditing(null);
            }}>{busy === "own" ? "Saving…" : "Save its rule"}</Btn>
          </>}>
          {problem ? <ProblemNotice problem={problem} /> : null}
          <div className="sub2 mb-3"><b>Direct Entry requirement as stated:</b> {deText?.trim() ? deText : "none stated on the programme's rule"}</div>
          <FitEditor drafts={editing.drafts} onChange={(d) => setEditing({ ...editing, drafts: d })} classes={classes} disabled={!may} idp={`fit-${editing.code}`} />
          {own.has(editing.code) ? (
            <>
              <div className="eyebrow mt-4">Its rule in force, in words</div>
              <Words criteria={data.programmes.find((p) => p.code === editing.code)?.criteria ?? []} />
            </>
          ) : null}
        </Modal>
      ) : null}
    </>
  );
}
