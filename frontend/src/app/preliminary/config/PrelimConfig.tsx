"use client";

/**
 * A preliminary or proficiency programme's settings (V446; V701 every route — Preliminary Science, Preliminary Technology &
 * Industrial Studies, the Adikpo Campus certificate courses — chosen with ?route=): the description and the entry rule (the
 * Academic Office's, with a reason; every open application is read again under the new rule) — O'Level credits with the
 * required subjects and either one list of core subjects or each area's own, or an attempted secondary school certificate — the
 * qualifications accepted, the duration, campus wording and the target notice; the targets (each an existing undergraduate
 * programme of the register, added, withdrawn, reinstated or — when the notice named one the register does not hold — resolved
 * to the existing programme it is; an area's subjects and its specialisations), or the certificate courses by category; the
 * documents; and the fees (the Bursary's: an acceptance or checking fee only when the University gives one; until then "Fee not
 * configured"). The window is the Director of ICT's, on Application Registration.
 */
import { useEffect, useState } from "react";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, LinkBtn, Note, PageHead, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { SearchSelect } from "@/components/proto/SearchSelect";
import { useQueryNav } from "@/lib/query-nav";
import { naira, pcall, prelimPage, when, type PrelimDeskRoute } from "@/lib/preliminary";

interface Spec { id: string; code: string; name: string; ord: number; active: boolean }
interface Config {
  route: string;
  programme: {
    route: string; name: string; description: string; completion_note: string; procedure: string[]; office_note: string | null; min_credits: number; max_sittings: number;
    min_core_credits: number; core_subjects: string[]; credit_grade: string; completion_credits: number; completion_subjects: string[]; remediation_terms: string | null;
    rules_version: number; updated_at: string; updated_office: string | null;
    rule_kind: "OLEVEL_CREDITS" | "ATTEMPTED_CERTIFICATE"; required_subjects: string[]; core_by_target: boolean; completion_scope: "ANY" | "RELEVANT";
    qualification_types: string[]; duration_months: number | null; certificate_type: string | null; entry_requirement: string | null; target_note: string | null;
    programme_type: string; target_word: string; group_word: string;
  };
  session: string;
  targets: { id: string; kind: "PROGRAMME" | "COURSE"; group_name: string; ord: number; requested_name: string; programme_code: string | null; state: string; note: string | null;
             register_name: string | null; department: string | null; faculty: string | null; applications: number; core_subjects: string[] | null; min_core_credits: number | null;
             description: string | null; duration_months: number | null; specialisations: Spec[] }[];
  qualificationTypes: { code: string; label: string; active: boolean }[];
  documents: { kind: string; label: string; hint: string | null; required: boolean; second_sitting_only: boolean; ord: number }[];
  fee: { stated: boolean; application_fee: number | null; portal_charge: number | null; acceptance_fee: number | null; checking_fee: number | null; carried_from: string | null } | null;
  window: { state: string; opens_at: string | null; closes_at: string | null; configured: boolean };
}

const PRELIM_GROUPS = ["Health / Medical", "Science / Technology", "Built Environment / Design", "Science Education"];
const cap = (x: string) => x.charAt(0).toUpperCase() + x.slice(1);
/** a new option's short code, as the register keeps them (ACC-ED): the initials of its words, a number added when taken */
const codeFor = (name: string, taken: string[]): string => {
  const base = (name.split(/[^A-Za-z0-9]+/).filter((w) => w && !/^(and|of|the|in|for)$/i.test(w)).map((w) => w[0]).join("").toUpperCase() || "OPT").slice(0, 9);
  let code = base;
  for (let n = 2; taken.includes(code); n++) code = `${base}-${n}`;
  return code;
};

export function PrelimConfig({ may, route, routes }: { may: { configure: boolean; fees: boolean }; route: string; routes: PrelimDeskRoute[] }) {
  const go = useQueryNav();
  const [c, setC] = useState<Config | null>(null);
  const [rules, setRules] = useState<Record<string, string>>({});
  const [quals, setQuals] = useState<string[]>([]);
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState<string | null>(null);
  const [opts, setOpts] = useState<{ value: string; label: string; sub?: string }[]>([]);
  const [adding, setAdding] = useState({ code: "", group: "" });
  const [course, setCourse] = useState({ name: "", category: "", description: "", months: "" });
  const [resolve, setResolve] = useState<Record<string, string>>({});
  const [areas, setAreas] = useState<Record<string, { subjects: string; min: string }>>({});
  const [spec, setSpec] = useState<Record<string, string>>({});
  const [fee, setFee] = useState({ application: "", acceptance: "", checking: "" });
  const rq = `route=${encodeURIComponent(route)}`;
  const take = (x: Config) => {
    setC(x);
    const p = x.programme;
    setRules({ name: p.name, description: p.description, completion_note: p.completion_note, office_note: p.office_note ?? "", procedure: p.procedure.join("\n"),
      min_credits: String(p.min_credits), max_sittings: String(p.max_sittings), min_core_credits: String(p.min_core_credits), core_subjects: p.core_subjects.join(", "),
      credit_grade: p.credit_grade, completion_credits: String(p.completion_credits), completion_subjects: p.completion_subjects.join(", "), remediation_terms: p.remediation_terms ?? "",
      required_subjects: p.required_subjects.join(", "), completion_scope: p.completion_scope, duration_months: p.duration_months == null ? "" : String(p.duration_months),
      certificate_type: p.certificate_type ?? "", entry_requirement: p.entry_requirement ?? "", target_note: p.target_note ?? "" });
    setQuals(p.qualification_types);
    setAreas(Object.fromEntries(x.targets.filter((t) => t.kind === "PROGRAMME").map((t) => [t.id, { subjects: (t.core_subjects ?? []).join(", "), min: t.min_core_credits == null ? "" : String(t.min_core_credits) }])));
    setFee({ application: x.fee?.application_fee != null ? String(Number(x.fee.application_fee) + Number(x.fee.portal_charge ?? 0)) : "", acceptance: x.fee?.acceptance_fee != null ? String(x.fee.acceptance_fee) : "", checking: x.fee?.checking_fee != null ? String(x.fee.checking_fee) : "" });
  };
  useEffect(() => {
    let live = true;
    void pcall<Config>(`/api/v1/admissions/preliminary/config?${rq}`).then((r) => { if (live) { if (r.ok) take(r.data); else notifyProblem(r.problem); } });
    if (may.configure) {
      void pcall<{ code: string; name: string; department: string; faculty: string; target: boolean }[]>(`/api/v1/admissions/preliminary/programmes?q=&${rq}`)
        .then((r) => { if (live && r.ok) setOpts(r.data.filter((x) => !x.target).map((x) => ({ value: x.code, label: x.name, sub: `${x.department} · ${x.faculty}` }))); });
    }
    return () => { live = false; };
  }, [may.configure, rq]);
  async function search(q: string) {
    if (!may.configure) return;
    const r = await pcall<{ code: string; name: string; department: string; faculty: string; target: boolean }[]>(`/api/v1/admissions/preliminary/programmes?q=${encodeURIComponent(q)}&${rq}`);
    if (r.ok) setOpts(r.data.filter((x) => !x.target).map((x) => ({ value: x.code, label: x.name, sub: `${x.department} · ${x.faculty}` })));
  }
  async function send(key: string, method: "POST" | "PUT", path: string, body: unknown, word: string) {
    setBusy(key);
    try {
      const r = await pcall<Config>(`/api/v1/admissions/preliminary${path}${path.includes("?") ? "&" : "?"}${rq}`, method, body, word);
      if (!r.ok) { notifyProblem(r.problem); return; }
      take(r.data); notify(word);
    } finally { setBusy(null); }
  }
  if (!c) return <Note kind="info" title="Reading the programme settings…">One moment.</Note>;
  const p = c.programme;
  const attempted = p.rule_kind === "ATTEMPTED_CERTIFICATE";
  const courses = c.targets.length > 0 && c.targets.every((t) => t.kind === "COURSE");
  const targetWord = courses ? "certificate course" : p.target_word;
  const groupWord = p.group_word;
  const groups = [...new Set([...c.targets.map((t) => t.group_name), ...(p.route === "PRELIMINARY_SCIENCE" ? PRELIM_GROUPS : [])])];
  const list = (v: string) => v.split(/[,\n]/).map((x) => x.trim()).filter(Boolean);
  const missing = c.targets.filter((t) => t.state === "MISSING");
  const needReason = () => { if (reason.trim().length < 5) { notifyProblem({ status: 422, title: "Write the reason for the change first" }); return false; } return true; };
  const change = (id: string, action: string, word: string, programmeCode?: string) => {
    if (!needReason()) return;
    void send(`${action}-${id}`, "POST", `/config/targets/${id}`, { action, programmeCode: programmeCode ?? null, reason: reason.trim() }, word);
  };
  const stateWord = (t: Config["targets"][number]) => t.state === "MAPPED" ? "Offered" : t.state === "MISSING" ? "Missing from the register" : "Withdrawn";
  const action = (t: Config["targets"][number]) => !may.configure ? <span key="x" /> : t.state === "MAPPED" ? (
    <Btn key="x" kind="ghost" size="sm" disabled={busy !== null} onClick={() => change(t.id, "WITHDRAW", `${cap(targetWord)} withdrawn`)}>Withdraw</Btn>
  ) : t.state === "MISSING" ? (
    <span key="x" className="row row--inline row--tight">
      <div style={{ minWidth: 220 }}><SearchSelect id={`pc-r-${t.id}`} value={resolve[t.id] ?? ""} onChange={(v) => setResolve({ ...resolve, [t.id]: v })} onQuery={(q) => void search(q)} options={opts} placeholder="The existing programme" /></div>
      <Btn kind="ghost" size="sm" disabled={busy !== null || !resolve[t.id]} onClick={() => change(t.id, "RESOLVE", "Target programme resolved", resolve[t.id])}>Resolve</Btn>
    </span>
  ) : (
    <Btn key="x" kind="ghost" size="sm" disabled={busy !== null} onClick={() => change(t.id, "REINSTATE", `${cap(targetWord)} reinstated`)}>Reinstate</Btn>
  );

  return (
    <>
      <PageHead title={`${p.name} settings`} description={`Session ${c.session} · rule version ${p.rules_version}, last changed ${when(p.updated_at)}`}
        actions={<>
          {routes.length > 1 ? <select className="ctl" aria-label="Programme" value={route} onChange={(e) => go(`/preliminary/config?route=${encodeURIComponent(e.target.value)}`)}>
            {routes.map((r) => <option key={r.route} value={r.route}>{r.name}</option>)}</select> : null}
          <LinkBtn href={`/preliminary?${rq}`}>{p.name} desk</LinkBtn><LinkBtn href={prelimPage(p.route)}>Public page</LinkBtn></>} />
      <Field id="pc-reason" label="Reason for the change (recorded with every change below)"><input id="pc-reason" className="ctl" value={reason} onChange={(e) => setReason(e.target.value)} placeholder="e.g. Senate decision of …" /></Field>
      {missing.length ? (
        <Note kind="bad" title={`${missing.length} target programme${missing.length === 1 ? "" : "s"} named in the notice ${missing.length === 1 ? "is" : "are"} not on the register`}>
          {missing.map((t) => t.requested_name).join("; ")}. Name the existing programme each one is below, or leave it out; no programme is created here.
        </Note>
      ) : null}

      <Panel title="Application window and fees">
        <PBody>
          <div className="row row--inline row--tight mb-2" style={{ flexWrap: "wrap" }}>
            <Pil kind={c.window.state === "OPEN" ? "ok" : "grey"}>{`Window ${c.window.state.toLowerCase()}`}</Pil>
            <span className="sub2">{c.window.opens_at ? `opens ${when(c.window.opens_at)}` : "no opening date"}{c.window.closes_at ? ` · closes ${when(c.window.closes_at)}` : " · no closing date set"}</span>
            <LinkBtn href="/ict/applications">Application Registration (Director of ICT)</LinkBtn>
          </div>
          <div className="grid grid--4">
            <Field id="pc-fa" label="Application fee (NGN)" hint={c.fee?.application_fee == null ? "Fee not configured" : undefined}><input id="pc-fa" className="ctl tnum" inputMode="numeric" disabled={!may.fees} placeholder="Not configured" value={fee.application} onChange={(e) => setFee({ ...fee, application: e.target.value.replace(/[^0-9.]/g, "") })} /></Field>
            <Field id="pc-fc" label="Acceptance fee (NGN)" hint={c.fee?.acceptance_fee == null ? "Fee not configured" : undefined}><input id="pc-fc" className="ctl tnum" inputMode="numeric" disabled={!may.fees} placeholder="Not configured" value={fee.acceptance} onChange={(e) => setFee({ ...fee, acceptance: e.target.value.replace(/[^0-9.]/g, "") })} /></Field>
            <Field id="pc-fk" label="Admission checking fee (NGN)" hint={c.fee?.checking_fee == null ? "Fee not configured" : undefined}><input id="pc-fk" className="ctl tnum" inputMode="numeric" disabled={!may.fees} placeholder="Not configured" value={fee.checking} onChange={(e) => setFee({ ...fee, checking: e.target.value.replace(/[^0-9.]/g, "") })} /></Field>
            <div className="sub2">Stated now: application {c.fee?.application_fee != null ? naira(Number(c.fee.application_fee) + Number(c.fee.portal_charge ?? 0)) : "not configured"}{c.fee?.carried_from ? ` (carried from ${c.fee.carried_from})` : ""}. School fees and other charges are not part of this programme&rsquo;s configuration until the University states them.</div>
          </div>
          {may.fees ? <Btn kind="primary" disabled={busy !== null || !fee.application} onClick={() => void send("fee", "PUT", "/config/fee", { session: c.session, applicationFee: Number(fee.application),
            acceptanceFee: fee.acceptance ? Number(fee.acceptance) : null, checkingFee: fee.checking ? Number(fee.checking) : null }, `${p.name} fees stated`)}>{busy === "fee" ? "Saving…" : "State the fees"}</Btn> : null}
        </PBody>
      </Panel>

      <Panel title={attempted ? "Programme and entry requirement" : "Programme and O’Level requirement"} right={<span className="sub2">Changes re-read every unpublished application</span>}>
        <PBody>
          <div className="grid grid--2">
            <Field id="pc-n" label="Display name"><input id="pc-n" className="ctl" disabled={!may.configure} value={rules.name} onChange={(e) => setRules({ ...rules, name: e.target.value })} /></Field>
            <Field id="pc-o" label="Office note (public page)"><input id="pc-o" className="ctl" disabled={!may.configure} value={rules.office_note} onChange={(e) => setRules({ ...rules, office_note: e.target.value })} /></Field>
          </div>
          <Field id="pc-d" label="Programme description"><textarea id="pc-d" className="ctl" rows={3} disabled={!may.configure} value={rules.description} onChange={(e) => setRules({ ...rules, description: e.target.value })} /></Field>
          <div className="grid grid--3">
            <Field id="pc-dm" label="Duration (months)" hint={rules.duration_months ? undefined : "Not configured"}><input id="pc-dm" className="ctl tnum" inputMode="numeric" disabled={!may.configure} placeholder="Not configured" value={rules.duration_months} onChange={(e) => setRules({ ...rules, duration_months: e.target.value.replace(/[^0-9]/g, "") })} /></Field>
            <Field id="pc-ct" label="Certificate awarded" hint={rules.certificate_type ? undefined : "Not configured"}><input id="pc-ct" className="ctl" disabled={!may.configure} placeholder="Not configured" value={rules.certificate_type} onChange={(e) => setRules({ ...rules, certificate_type: e.target.value })} /></Field>
            <Field id="pc-er" label="Entry requirement (public wording)"><input id="pc-er" className="ctl" disabled={!may.configure} value={rules.entry_requirement} onChange={(e) => setRules({ ...rules, entry_requirement: e.target.value })} /></Field>
          </div>
          <Field id="pc-q" label="Qualifications accepted">
            <div className="row row--inline row--tight" style={{ flexWrap: "wrap" }}>
              {c.qualificationTypes.filter((q) => q.active || quals.includes(q.code)).map((q) => (
                <label key={q.code} className="row row--inline row--tight" style={{ gap: 4 }}>
                  <input type="checkbox" disabled={!may.configure} checked={quals.includes(q.code)} onChange={(e) => setQuals(e.target.checked ? [...quals, q.code] : quals.filter((x) => x !== q.code))} />{q.label}
                </label>
              ))}
            </div>
          </Field>
          {attempted ? <div className="sub2 mb-2">The applicant gives the examination sat and its results; no credit grade is asked.</div> : (
            <>
              <div className="grid grid--4">
                <Field id="pc-mc" label="Minimum credits"><input id="pc-mc" className="ctl tnum" disabled={!may.configure} value={rules.min_credits} onChange={(e) => setRules({ ...rules, min_credits: e.target.value })} /></Field>
                <Field id="pc-ms" label="Maximum sittings"><select id="pc-ms" className="ctl" disabled={!may.configure} value={rules.max_sittings} onChange={(e) => setRules({ ...rules, max_sittings: e.target.value })}><option value="1">1</option><option value="2">2</option></select></Field>
                <Field id="pc-mk" label={p.core_by_target ? `Minimum credits in the ${groupWord}'s subjects` : "Minimum core credits"}><input id="pc-mk" className="ctl tnum" disabled={!may.configure} value={rules.min_core_credits} onChange={(e) => setRules({ ...rules, min_core_credits: e.target.value })} /></Field>
                <Field id="pc-cg" label="A credit is this grade or better"><select id="pc-cg" className="ctl" disabled={!may.configure} value={rules.credit_grade} onChange={(e) => setRules({ ...rules, credit_grade: e.target.value })}>{["A1", "B2", "B3", "C4", "C5", "C6"].map((g) => <option key={g}>{g}</option>)}</select></Field>
              </div>
              <Field id="pc-rs" label="Subjects every applicant needs a credit in (comma-separated)"><input id="pc-rs" className="ctl" disabled={!may.configure} placeholder="None" value={rules.required_subjects} onChange={(e) => setRules({ ...rules, required_subjects: e.target.value })} /></Field>
              {p.core_by_target ? <div className="sub2 mb-2">The core subjects are each {groupWord}&rsquo;s own, set under {cap(targetWord)}s below.</div> : (
                <Field id="pc-cs" label="Core subjects (comma-separated)"><input id="pc-cs" className="ctl" disabled={!may.configure} value={rules.core_subjects} onChange={(e) => setRules({ ...rules, core_subjects: e.target.value })} /></Field>
              )}
              <div className="grid grid--3">
                <Field id="pc-cc" label="Credits required to complete the programme"><input id="pc-cc" className="ctl tnum" disabled={!may.configure} value={rules.completion_credits} onChange={(e) => setRules({ ...rules, completion_credits: e.target.value })} /></Field>
                <Field id="pc-csc" label="Which credits count to complete"><select id="pc-csc" className="ctl" disabled={!may.configure} value={rules.completion_scope} onChange={(e) => setRules({ ...rules, completion_scope: e.target.value })}>
                  <option value="ANY">Any subject</option><option value="RELEVANT">The relevant subjects only</option></select></Field>
                <Field id="pc-cps" label="Subjects to be credited before completion"><input id="pc-cps" className="ctl" disabled={!may.configure} value={rules.completion_subjects} onChange={(e) => setRules({ ...rules, completion_subjects: e.target.value })} /></Field>
              </div>
              <Field id="pc-cn" label="Remediation requirement (public wording)"><textarea id="pc-cn" className="ctl" rows={2} disabled={!may.configure} value={rules.completion_note} onChange={(e) => setRules({ ...rules, completion_note: e.target.value })} /></Field>
              <Field id="pc-rt" label="Remediation terms (examinations, attempts, fees, pass marks) — only as the University has stated them"><textarea id="pc-rt" className="ctl" rows={2} disabled={!may.configure} placeholder="Not stated by the University" value={rules.remediation_terms} onChange={(e) => setRules({ ...rules, remediation_terms: e.target.value })} /></Field>
              <div className="sub2 mb-2">An awaiting result is never accepted: that part of the rule is fixed.</div>
            </>
          )}
          {courses ? null : <Field id="pc-tn" label="Target notice (said wherever the target is shown)"><textarea id="pc-tn" className="ctl" rows={2} disabled={!may.configure} placeholder="The Preliminary Science wording" value={rules.target_note} onChange={(e) => setRules({ ...rules, target_note: e.target.value })} /></Field>}
          <Field id="pc-pr" label="Method of application (one step per line)"><textarea id="pc-pr" className="ctl" rows={6} disabled={!may.configure} value={rules.procedure} onChange={(e) => setRules({ ...rules, procedure: e.target.value })} /></Field>
          {may.configure ? <Btn kind="primary" disabled={busy !== null} onClick={() => { if (!needReason()) return; void send("rules", "PUT", "/config/rules", { reason: reason.trim(), settings: {
            name: rules.name, description: rules.description, office_note: rules.office_note, procedure: rules.procedure.split("\n").map((x) => x.trim()).filter(Boolean),
            qualification_types: quals, duration_months: rules.duration_months, certificate_type: rules.certificate_type, entry_requirement: rules.entry_requirement,
            ...(courses ? {} : { target_note: rules.target_note }),
            ...(attempted ? {} : { completion_note: rules.completion_note, min_credits: Number(rules.min_credits), max_sittings: Number(rules.max_sittings), min_core_credits: Number(rules.min_core_credits),
              required_subjects: list(rules.required_subjects), ...(p.core_by_target ? {} : { core_subjects: list(rules.core_subjects) }), credit_grade: rules.credit_grade,
              completion_credits: Number(rules.completion_credits), completion_scope: rules.completion_scope, completion_subjects: list(rules.completion_subjects), remediation_terms: rules.remediation_terms }) } }, "Programme and requirement saved"); }}>
            {busy === "rules" ? "Saving…" : "Save the programme and requirement"}</Btn> : null}
        </PBody>
      </Panel>

      {courses ? (
        <Panel title="Certificate courses" right={<span className="sub2">{c.targets.filter((t) => t.state === "MAPPED").length} offered · {new Set(c.targets.map((t) => t.group_name)).size} categories</span>}>
          <PBody>
            {may.configure ? (
              <div className="grid grid--4 mb-2">
                <Field id="pc-cn2" label="Course"><input id="pc-cn2" className="ctl" value={course.name} onChange={(e) => setCourse({ ...course, name: e.target.value })} /></Field>
                <Field id="pc-cat" label="Category"><input id="pc-cat" className="ctl" list="pc-cats" value={course.category} onChange={(e) => setCourse({ ...course, category: e.target.value })} />
                  <datalist id="pc-cats">{groups.map((g) => <option key={g} value={g} />)}</datalist></Field>
                <Field id="pc-cm" label="Duration (months), if not the programme's"><input id="pc-cm" className="ctl tnum" inputMode="numeric" value={course.months} onChange={(e) => setCourse({ ...course, months: e.target.value.replace(/[^0-9]/g, "") })} /></Field>
                <div className="row row--inline" style={{ alignItems: "end" }}>
                  <Btn kind="primary" size="sm" disabled={busy !== null || !course.name.trim() || !course.category.trim()} onClick={() => { if (!needReason()) return; void send("course", "POST", "/config/courses", { name: course.name.trim(), category: course.category.trim(),
                    description: course.description.trim() || null, durationMonths: course.months ? Number(course.months) : null, reason: reason.trim() }, "Certificate course added").then(() => setCourse({ name: "", category: course.category, description: "", months: "" })); }}>Add the course</Btn>
                </div>
              </div>
            ) : null}
            <DTable noPrint pageSize={0} cols={["Category", "Course", "Duration", "Applications|num", "State", ""]}
              rows={c.targets.map((t) => [t.group_name, t.requested_name, t.duration_months ? `${t.duration_months} months` : p.duration_months ? `${p.duration_months} months` : "Not configured", t.applications,
                <Pil key="s" kind={t.state === "MAPPED" ? "ok" : "grey"}>{stateWord(t)}</Pil>, action(t)])} />
          </PBody>
        </Panel>
      ) : (
        <Panel title={`${cap(targetWord)}s`} right={<span className="sub2">{c.targets.filter((t) => t.state === "MAPPED").length} offered</span>}>
          <PBody>
            {may.configure ? (
              <div className="row row--inline row--tight mb-2" style={{ flexWrap: "wrap" }}>
                <div style={{ minWidth: 320, flex: 1 }}><SearchSelect id="pc-add" value={adding.code} onChange={(v) => setAdding({ ...adding, code: v })} onQuery={(q) => void search(q)} options={opts} placeholder="Find an existing undergraduate programme" /></div>
                <input className="ctl" aria-label={cap(groupWord)} list="pc-groups" placeholder={cap(groupWord)} value={adding.group} onChange={(e) => setAdding({ ...adding, group: e.target.value })} />
                <datalist id="pc-groups">{groups.map((g) => <option key={g} value={g} />)}</datalist>
                <Btn kind="primary" size="sm" disabled={busy !== null || !adding.code} onClick={() => { if (!needReason()) return; void send("add", "POST", "/config/targets", { programmeCode: adding.code, group: adding.group || null, reason: reason.trim() }, "Target programme added"); }}>Add as a target</Btn>
              </div>
            ) : null}
            <DTable noPrint pageSize={0} cols={[cap(groupWord), "Name in the notice", "Programme on the register", "Department · faculty", "Applications|num", "State", ""]}
              rows={c.targets.map((t) => [t.group_name, t.requested_name, t.register_name ? `${t.register_name} (${t.programme_code})` : <span key="m" className="sub2">—</span>,
                t.department ? `${t.department} · ${t.faculty}` : "—", t.applications,
                <Pil key="s" kind={t.state === "MAPPED" ? "ok" : t.state === "MISSING" ? "warn" : "grey"}>{stateWord(t)}</Pil>, action(t)])} />
            {c.targets.filter((t) => t.kind === "PROGRAMME" && (p.core_by_target || t.specialisations.length)).map((t) => {
              const a = areas[t.id] ?? { subjects: "", min: "" };
              return (
                <div key={t.id} className="card mt-2" style={{ padding: 10 }}>
                  <div className="eyebrow">{t.group_name} · {t.register_name ?? t.requested_name}</div>
                  {p.core_by_target ? (
                    <div className="row row--inline row--tight" style={{ flexWrap: "wrap", alignItems: "end" }}>
                      <Field id={`pc-as-${t.id}`} label={`The ${groupWord}'s subjects (comma-separated)`}><input id={`pc-as-${t.id}`} className="ctl" style={{ minWidth: 380 }} disabled={!may.configure} value={a.subjects} onChange={(e) => setAreas({ ...areas, [t.id]: { ...a, subjects: e.target.value } })} /></Field>
                      <Field id={`pc-am-${t.id}`} label="Credits needed among them"><input id={`pc-am-${t.id}`} className="ctl tnum" style={{ width: 90 }} disabled={!may.configure} placeholder={String(p.min_core_credits)} value={a.min} onChange={(e) => setAreas({ ...areas, [t.id]: { ...a, min: e.target.value.replace(/[^0-9]/g, "") } })} /></Field>
                      {may.configure ? <Btn kind="ghost" size="sm" disabled={busy !== null} onClick={() => { if (!needReason()) return; void send(`area-${t.id}`, "PUT", `/config/targets/${t.id}/rule`, { coreSubjects: list(a.subjects), minCoreCredits: a.min ? Number(a.min) : null, reason: reason.trim() }, `${t.group_name}: subjects saved`); }}>Save the subjects</Btn> : null}
                    </div>
                  ) : null}
                  <div className="row row--inline row--tight mt-1" style={{ flexWrap: "wrap" }}>
                    <b>Specialisations:</b>
                    {t.specialisations.length ? t.specialisations.map((x) => (
                      <span key={x.id} className="row row--inline row--tight" style={{ gap: 4 }}>
                        <Pil kind={x.active ? "ok" : "grey"}>{x.name}</Pil>
                        {may.configure ? <button type="button" className="lnk" disabled={busy !== null} onClick={() => { if (!needReason()) return; void send(`sp-${x.id}`, "PUT", `/config/targets/${t.id}/specialisations/${x.code}`, { name: x.name, ord: x.ord, active: !x.active, reason: reason.trim() }, `${x.name}: ${x.active ? "withdrawn" : "offered"}`); }}>{x.active ? "withdraw" : "offer"}</button> : null}
                      </span>
                    )) : <span className="sub2">none</span>}
                    {may.configure ? (
                      <span className="row row--inline row--tight">
                        <input className="ctl" aria-label="New specialisation" placeholder="Add a specialisation" value={spec[t.id] ?? ""} onChange={(e) => setSpec({ ...spec, [t.id]: e.target.value })} />
                        <Btn kind="ghost" size="sm" disabled={busy !== null || !(spec[t.id] ?? "").trim()} onClick={() => { if (!needReason()) return; const name = (spec[t.id] ?? "").trim();
                          void send(`spn-${t.id}`, "PUT", `/config/targets/${t.id}/specialisations/${codeFor(name, t.specialisations.map((x) => x.code))}`, { name, active: true, reason: reason.trim() }, `${name} added`).then(() => setSpec({ ...spec, [t.id]: "" })); }}>Add</Btn>
                      </span>
                    ) : null}
                  </div>
                </div>
              );
            })}
          </PBody>
        </Panel>
      )}

      <Panel title="Documents">
        <PBody>
          <DTable noPrint pageSize={0} cols={["Document", "Label the applicant reads", "Required", "Second sitting only", ""]} rows={c.documents.map((d) => [d.kind, d.label,
            d.required ? "Yes" : "No", d.second_sitting_only ? "Yes" : "No",
            may.configure ? <Btn key="t" kind="ghost" size="sm" disabled={busy !== null} onClick={() => { if (!needReason()) return; void send(`d-${d.kind}`, "PUT", `/config/documents/${d.kind}`,
              { label: d.label, hint: d.hint, required: !d.required, secondSittingOnly: d.second_sitting_only, ord: d.ord, reason: reason.trim() }, `${d.label}: ${d.required ? "optional" : "required"}`); }}>{d.required ? "Make optional" : "Make required"}</Btn> : <span key="t" />])} />
          <div className="sub2 mt-1">The payment receipt is the University&rsquo;s own, issued on the verified payment; the applicant does not upload it.</div>
        </PBody>
      </Panel>
    </>
  );
}
