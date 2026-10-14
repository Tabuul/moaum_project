"use client";

/**
 * The Preliminary Science programme's settings (V446): the description and the O'Level rule (the Academic Office's, with a
 * reason; every open application is read again under the new rule), the target programmes (each an existing undergraduate
 * programme of the register, added, withdrawn or — when the notice named one the register does not hold — resolved to the
 * existing programme it is), the documents, and the fees (the Bursary's: an acceptance or checking fee only when the University
 * gives one; until then "Fee not configured"). The window is the Director of ICT's, on Application Registration.
 */
import { useEffect, useState } from "react";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, LinkBtn, Note, PageHead, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { SearchSelect } from "@/components/proto/SearchSelect";
import { naira, pcall, when } from "@/lib/preliminary";

interface Config {
  programme: {
    route: string; name: string; description: string; completion_note: string; procedure: string[]; office_note: string | null; min_credits: number; max_sittings: number;
    min_core_credits: number; core_subjects: string[]; credit_grade: string; completion_credits: number; completion_subjects: string[]; remediation_terms: string | null;
    rules_version: number; updated_at: string; updated_office: string | null;
  };
  session: string;
  targets: { id: string; group_name: string; ord: number; requested_name: string; programme_code: string | null; state: string; note: string | null; register_name: string | null;
             department: string | null; faculty: string | null; applications: number }[];
  documents: { kind: string; label: string; hint: string | null; required: boolean; second_sitting_only: boolean; ord: number }[];
  fee: { stated: boolean; application_fee: number | null; portal_charge: number | null; acceptance_fee: number | null; checking_fee: number | null; carried_from: string | null } | null;
  window: { state: string; opens_at: string | null; closes_at: string | null; configured: boolean };
}

export function PrelimConfig({ may }: { may: { configure: boolean; fees: boolean } }) {
  const [c, setC] = useState<Config | null>(null);
  const [rules, setRules] = useState<Record<string, string>>({});
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState<string | null>(null);
  const [opts, setOpts] = useState<{ value: string; label: string; sub?: string }[]>([]);
  const [adding, setAdding] = useState({ code: "", group: "Science / Technology" });
  const [resolve, setResolve] = useState<Record<string, string>>({});
  const [fee, setFee] = useState({ application: "", acceptance: "", checking: "" });
  const take = (x: Config) => {
    setC(x);
    const p = x.programme;
    setRules({ name: p.name, description: p.description, completion_note: p.completion_note, office_note: p.office_note ?? "", procedure: p.procedure.join("\n"),
      min_credits: String(p.min_credits), max_sittings: String(p.max_sittings), min_core_credits: String(p.min_core_credits), core_subjects: p.core_subjects.join(", "),
      credit_grade: p.credit_grade, completion_credits: String(p.completion_credits), completion_subjects: p.completion_subjects.join(", "), remediation_terms: p.remediation_terms ?? "" });
    setFee({ application: x.fee?.application_fee != null ? String(Number(x.fee.application_fee) + Number(x.fee.portal_charge ?? 0)) : "", acceptance: x.fee?.acceptance_fee != null ? String(x.fee.acceptance_fee) : "", checking: x.fee?.checking_fee != null ? String(x.fee.checking_fee) : "" });
  };
  useEffect(() => {
    let live = true;
    void pcall<Config>("/api/v1/admissions/preliminary/config").then((r) => { if (live) { if (r.ok) take(r.data); else notifyProblem(r.problem); } });
    if (may.configure) {
      void pcall<{ code: string; name: string; department: string; faculty: string; target: boolean }[]>("/api/v1/admissions/preliminary/programmes?q=")
        .then((r) => { if (live && r.ok) setOpts(r.data.filter((x) => !x.target).map((x) => ({ value: x.code, label: x.name, sub: `${x.department} · ${x.faculty}` }))); });
    }
    return () => { live = false; };
  }, [may.configure]);
  async function search(q: string) {
    if (!may.configure) return;
    const r = await pcall<{ code: string; name: string; department: string; faculty: string; target: boolean }[]>(`/api/v1/admissions/preliminary/programmes?q=${encodeURIComponent(q)}`);
    if (r.ok) setOpts(r.data.filter((x) => !x.target).map((x) => ({ value: x.code, label: x.name, sub: `${x.department} · ${x.faculty}` })));
  }
  async function send(key: string, method: "POST" | "PUT", path: string, body: unknown, word: string) {
    setBusy(key);
    try {
      const r = await pcall<Config>(`/api/v1/admissions/preliminary${path}`, method, body, word);
      if (!r.ok) { notifyProblem(r.problem); return; }
      take(r.data); notify(word);
    } finally { setBusy(null); }
  }
  if (!c) return <Note kind="info" title="Reading the programme settings…">One moment.</Note>;
  const list = (v: string) => v.split(/[,\n]/).map((x) => x.trim()).filter(Boolean);
  const missing = c.targets.filter((t) => t.state === "MISSING");
  const needReason = () => { if (reason.trim().length < 5) { notifyProblem({ status: 422, title: "Write the reason for the change first" }); return false; } return true; };

  return (
    <>
      <PageHead title="Preliminary Science settings" description={`${c.programme.name} · session ${c.session} · rule version ${c.programme.rules_version}, last changed ${when(c.programme.updated_at)}`}
        actions={<><LinkBtn href="/preliminary">Preliminary Science desk</LinkBtn><LinkBtn href="/preliminary-science">Public page</LinkBtn></>} />
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
            <Field id="pc-fa" label="Application fee (NGN)"><input id="pc-fa" className="ctl tnum" inputMode="numeric" disabled={!may.fees} value={fee.application} onChange={(e) => setFee({ ...fee, application: e.target.value.replace(/[^0-9.]/g, "") })} /></Field>
            <Field id="pc-fc" label="Acceptance fee (NGN)" hint={c.fee?.acceptance_fee == null ? "Fee not configured" : undefined}><input id="pc-fc" className="ctl tnum" inputMode="numeric" disabled={!may.fees} placeholder="Not configured" value={fee.acceptance} onChange={(e) => setFee({ ...fee, acceptance: e.target.value.replace(/[^0-9.]/g, "") })} /></Field>
            <Field id="pc-fk" label="Admission checking fee (NGN)" hint={c.fee?.checking_fee == null ? "Fee not configured" : undefined}><input id="pc-fk" className="ctl tnum" inputMode="numeric" disabled={!may.fees} placeholder="Not configured" value={fee.checking} onChange={(e) => setFee({ ...fee, checking: e.target.value.replace(/[^0-9.]/g, "") })} /></Field>
            <div className="sub2">Stated now: application {c.fee?.application_fee != null ? naira(Number(c.fee.application_fee) + Number(c.fee.portal_charge ?? 0)) : "not configured"}{c.fee?.carried_from ? ` (carried from ${c.fee.carried_from})` : ""}. School fees and other charges are not part of this programme&rsquo;s configuration until the University states them.</div>
          </div>
          {may.fees ? <Btn kind="primary" disabled={busy !== null || !fee.application} onClick={() => void send("fee", "PUT", "/config/fee", { session: c.session, applicationFee: Number(fee.application),
            acceptanceFee: fee.acceptance ? Number(fee.acceptance) : null, checkingFee: fee.checking ? Number(fee.checking) : null }, "Preliminary Science fees stated")}>{busy === "fee" ? "Saving…" : "State the fees"}</Btn> : null}
        </PBody>
      </Panel>

      <Panel title={"Programme and O’Level requirement"} right={<span className="sub2">Changes re-read every unpublished application</span>}>
        <PBody>
          <div className="grid grid--2">
            <Field id="pc-n" label="Display name"><input id="pc-n" className="ctl" disabled={!may.configure} value={rules.name} onChange={(e) => setRules({ ...rules, name: e.target.value })} /></Field>
            <Field id="pc-o" label="Office note (public page)"><input id="pc-o" className="ctl" disabled={!may.configure} value={rules.office_note} onChange={(e) => setRules({ ...rules, office_note: e.target.value })} /></Field>
          </div>
          <Field id="pc-d" label="Programme description"><textarea id="pc-d" className="ctl" rows={3} disabled={!may.configure} value={rules.description} onChange={(e) => setRules({ ...rules, description: e.target.value })} /></Field>
          <div className="grid grid--4">
            <Field id="pc-mc" label="Minimum credits"><input id="pc-mc" className="ctl tnum" disabled={!may.configure} value={rules.min_credits} onChange={(e) => setRules({ ...rules, min_credits: e.target.value })} /></Field>
            <Field id="pc-ms" label="Maximum sittings"><select id="pc-ms" className="ctl" disabled={!may.configure} value={rules.max_sittings} onChange={(e) => setRules({ ...rules, max_sittings: e.target.value })}><option value="1">1</option><option value="2">2</option></select></Field>
            <Field id="pc-mk" label="Minimum core science credits"><input id="pc-mk" className="ctl tnum" disabled={!may.configure} value={rules.min_core_credits} onChange={(e) => setRules({ ...rules, min_core_credits: e.target.value })} /></Field>
            <Field id="pc-cg" label="A credit is this grade or better"><select id="pc-cg" className="ctl" disabled={!may.configure} value={rules.credit_grade} onChange={(e) => setRules({ ...rules, credit_grade: e.target.value })}>{["A1", "B2", "B3", "C4", "C5", "C6"].map((g) => <option key={g}>{g}</option>)}</select></Field>
          </div>
          <Field id="pc-cs" label="Core science subjects (comma-separated)"><input id="pc-cs" className="ctl" disabled={!may.configure} value={rules.core_subjects} onChange={(e) => setRules({ ...rules, core_subjects: e.target.value })} /></Field>
          <div className="grid grid--2">
            <Field id="pc-cc" label="Credits required to complete the programme"><input id="pc-cc" className="ctl tnum" disabled={!may.configure} value={rules.completion_credits} onChange={(e) => setRules({ ...rules, completion_credits: e.target.value })} /></Field>
            <Field id="pc-cps" label="Subjects to be credited before completion"><input id="pc-cps" className="ctl" disabled={!may.configure} value={rules.completion_subjects} onChange={(e) => setRules({ ...rules, completion_subjects: e.target.value })} /></Field>
          </div>
          <Field id="pc-cn" label="Remediation requirement (public wording)"><textarea id="pc-cn" className="ctl" rows={2} disabled={!may.configure} value={rules.completion_note} onChange={(e) => setRules({ ...rules, completion_note: e.target.value })} /></Field>
          <Field id="pc-rt" label="Remediation terms (examinations, attempts, fees, pass marks) — only as the University has stated them"><textarea id="pc-rt" className="ctl" rows={2} disabled={!may.configure} placeholder="Not stated by the University" value={rules.remediation_terms} onChange={(e) => setRules({ ...rules, remediation_terms: e.target.value })} /></Field>
          <Field id="pc-pr" label="Method of application (one step per line)"><textarea id="pc-pr" className="ctl" rows={6} disabled={!may.configure} value={rules.procedure} onChange={(e) => setRules({ ...rules, procedure: e.target.value })} /></Field>
          <div className="sub2 mb-2">An awaiting result is never accepted: that part of the rule is fixed.</div>
          {may.configure ? <Btn kind="primary" disabled={busy !== null} onClick={() => { if (!needReason()) return; void send("rules", "PUT", "/config/rules", { reason: reason.trim(), settings: {
            name: rules.name, description: rules.description, completion_note: rules.completion_note, office_note: rules.office_note, procedure: rules.procedure.split("\n").map((x) => x.trim()).filter(Boolean),
            min_credits: Number(rules.min_credits), max_sittings: Number(rules.max_sittings), min_core_credits: Number(rules.min_core_credits), core_subjects: list(rules.core_subjects),
            credit_grade: rules.credit_grade, completion_credits: Number(rules.completion_credits), completion_subjects: list(rules.completion_subjects), remediation_terms: rules.remediation_terms } }, "Programme and requirement saved"); }}>
            {busy === "rules" ? "Saving…" : "Save the programme and requirement"}</Btn> : null}
        </PBody>
      </Panel>

      <Panel title="Target programmes" right={<span className="sub2">{c.targets.filter((t) => t.state === "MAPPED").length} offered</span>}>
        <PBody>
          {may.configure ? (
            <div className="row row--inline row--tight mb-2" style={{ flexWrap: "wrap" }}>
              <div style={{ minWidth: 320, flex: 1 }}><SearchSelect id="pc-add" value={adding.code} onChange={(v) => setAdding({ ...adding, code: v })} onQuery={(q) => void search(q)} options={opts} placeholder="Find an existing undergraduate programme" /></div>
              <select className="ctl" aria-label="Group" value={adding.group} onChange={(e) => setAdding({ ...adding, group: e.target.value })}>
                {["Health / Medical", "Science / Technology", "Built Environment / Design", "Science Education"].map((g) => <option key={g}>{g}</option>)}</select>
              <Btn kind="primary" size="sm" disabled={busy !== null || !adding.code} onClick={() => { if (!needReason()) return; void send("add", "POST", "/config/targets", { programmeCode: adding.code, group: adding.group, reason: reason.trim() }, "Target programme added"); }}>Add as a target</Btn>
            </div>
          ) : null}
          <DTable noPrint pageSize={0} cols={["Group", "Name in the notice", "Programme on the register", "Department · faculty", "Applications|num", "State", ""]}
            rows={c.targets.map((t) => [t.group_name, t.requested_name, t.register_name ? `${t.register_name} (${t.programme_code})` : <span key="m" className="sub2">—</span>,
              t.department ? `${t.department} · ${t.faculty}` : "—", t.applications,
              <Pil key="s" kind={t.state === "MAPPED" ? "ok" : t.state === "MISSING" ? "warn" : "grey"}>{t.state === "MAPPED" ? "Offered" : t.state === "MISSING" ? "Missing from the register" : "Withdrawn"}</Pil>,
              !may.configure ? <span key="x" /> : t.state === "MAPPED" ? (
                <Btn key="x" kind="ghost" size="sm" disabled={busy !== null} onClick={() => { if (!needReason()) return; void send(`w-${t.id}`, "POST", `/config/targets/${t.id}`, { action: "WITHDRAW", reason: reason.trim() }, "Target programme withdrawn"); }}>Withdraw</Btn>
              ) : t.state === "MISSING" ? (
                <span key="x" className="row row--inline row--tight">
                  <div style={{ minWidth: 220 }}><SearchSelect id={`pc-r-${t.id}`} value={resolve[t.id] ?? ""} onChange={(v) => setResolve({ ...resolve, [t.id]: v })} onQuery={(q) => void search(q)} options={opts} placeholder="The existing programme" /></div>
                  <Btn kind="ghost" size="sm" disabled={busy !== null || !resolve[t.id]} onClick={() => { if (!needReason()) return; void send(`r-${t.id}`, "POST", `/config/targets/${t.id}`, { action: "RESOLVE", programmeCode: resolve[t.id], reason: reason.trim() }, "Target programme resolved"); }}>Resolve</Btn>
                </span>
              ) : (
                <Btn key="x" kind="ghost" size="sm" disabled={busy !== null || !t.programme_code} onClick={() => { if (!needReason()) return; void send(`a-${t.id}`, "POST", "/config/targets", { programmeCode: t.programme_code, group: t.group_name, ord: t.ord, reason: reason.trim() }, "Target programme reinstated"); }}>Reinstate</Btn>
              ),
            ])} />
        </PBody>
      </Panel>

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
