"use client";
/** V658: a proposal the Linkages office records itself (it came by letter, e-mail or a meeting) — the essential answers, routed like any other */
import { useState } from "react";
import { Btn } from "@/components/proto/ui";
import { Field, Modal } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { Problem } from "@/lib/api";
import { FUNDING, ORG_TYPES, YES_NO_NOT_SURE, countries, type Answers } from "@/lib/partnerships";
import { ptnCall, type DeskData } from "./ptn-call";

export function RecordProposal({ desk, onClose, onSaved }: { desk: DeskData; onClose: () => void; onSaved: (id: string) => void }) {
  const [a, setA] = useState<Answers>({ proposalKind: "NEW", hasContact: false, collaboratedBefore: "NOT_SURE", international: false, personalData: "NOT_SURE", ethics: "NOT_SURE" });
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const set = (p: Partial<Answers>) => setA((x) => ({ ...x, ...p }));
  const deps = desk.departments.filter((d) => !a.facultyCode || d.faculty_code === a.facultyCode);
  const txt = (k: keyof Answers, label: string, req = false, rows = 0) => (
    <Field id={`rp-${String(k)}`} label={label} required={req} full={rows > 0}>
      {rows ? <textarea id={`rp-${String(k)}`} className="ctl" rows={rows} value={String(a[k] ?? "")} onChange={(e) => set({ [k]: e.target.value } as Partial<Answers>)} />
        : <input id={`rp-${String(k)}`} className="ctl" value={String(a[k] ?? "")} onChange={(e) => set({ [k]: e.target.value } as Partial<Answers>)} />}
    </Field>
  );

  async function save() {
    setBusy(true); setProblem(null);
    try {
      const r = await ptnCall<{ id: string; reference: string }>("/record", { method: "POST", body: { answers: a, reason }, reason: `Partnership proposal recorded: ${a.title ?? ""}` });
      if (!r.ok) { setProblem(r.problem); return; }
      onSaved(r.data.id);
    } finally { setBusy(false); }
  }

  return (
    <Modal wide title="Record a proposal" sub="A proposal that came by letter, e-mail or a meeting: routed and screened like one from the public form" onClose={onClose}
      foot={<><Btn kind="ghost" onClick={onClose}>Cancel</Btn><span className="grow" /><Btn kind="primary" busy={busy} busyLabel="Recording…" disabled={reason.trim().length < 5} onClick={() => void save()}>Record</Btn></>}>
      <div className="grid grid--2">
        {txt("orgName", "Organisation name", true)}
        <Field id="rp-orgType" label="Organisation type" required>
          <select id="rp-orgType" className="ctl" value={a.orgType ?? ""} onChange={(e) => set({ orgType: e.target.value })}><option value="">Choose…</option>{ORG_TYPES.map(([k, l]) => <option key={k} value={k}>{l}</option>)}</select>
        </Field>
        {a.orgType === "OTHER" ? txt("orgTypeOther", "Organisation type (describe)", true) : null}
        {txt("firstName", "Contact first name", true)}
        {txt("lastName", "Contact last name", true)}
        {txt("email", "Contact email", true)}
        <Field id="rp-country" label="Country" required>
          <select id="rp-country" className="ctl" value={a.country ?? ""} onChange={(e) => set({ country: e.target.value })}><option value="">Choose…</option>{countries().map((c) => <option key={c} value={c}>{c}</option>)}</select>
        </Field>
        <Field id="rp-category" label="Category" required>
          <select id="rp-category" className="ctl" value={a.category ?? ""} onChange={(e) => set({ category: e.target.value })}>
            <option value="">Choose…</option>
            {desk.groups.map((g) => <optgroup key={g.code} label={g.label}>{desk.categories.filter((c) => c.grp === g.code).map((c) => <option key={c.code} value={c.code}>{c.label}</option>)}</optgroup>)}
          </select>
        </Field>
        {txt("title", "Title", true)}
        {txt("summary", "Summary", true, 3)}
        {txt("description", "Description", true, 4)}
        <Field id="rp-fac" label="Faculty">
          <select id="rp-fac" className="ctl" value={a.facultyCode ?? ""} onChange={(e) => set({ facultyCode: e.target.value, deptCode: "" })}><option value="">None</option>{desk.faculties.map((x) => <option key={x.code} value={x.code}>{x.name}</option>)}</select>
        </Field>
        <Field id="rp-dept" label="Department">
          <select id="rp-dept" className="ctl" value={a.deptCode ?? ""} onChange={(e) => set({ deptCode: e.target.value })}><option value="">None</option>{deps.map((x) => <option key={x.code} value={x.code}>{x.name}</option>)}</select>
        </Field>
        <Field id="rp-funding" label="Funding" required>
          <select id="rp-funding" className="ctl" value={a.fundingStatus ?? ""} onChange={(e) => set({ fundingStatus: e.target.value })}><option value="">Choose…</option>{FUNDING.map(([k, l]) => <option key={k} value={k}>{l}</option>)}</select>
        </Field>
        <Field id="rp-intl" label="Partners outside the country">
          <select id="rp-intl" className="ctl" value={a.international ? "YES" : "NO"} onChange={(e) => set({ international: e.target.value === "YES" })}><option value="NO">No</option><option value="YES">Yes</option></select>
        </Field>
        <Field id="rp-pd" label="Personal data">
          <select id="rp-pd" className="ctl" value={a.personalData ?? ""} onChange={(e) => set({ personalData: e.target.value })}>{YES_NO_NOT_SURE.map(([k, l]) => <option key={k} value={k}>{l}</option>)}</select>
        </Field>
        <Field id="rp-eth" label="Ethics approval">
          <select id="rp-eth" className="ctl" value={a.ethics ?? ""} onChange={(e) => set({ ethics: e.target.value })}>{YES_NO_NOT_SURE.map(([k, l]) => <option key={k} value={k}>{l}</option>)}</select>
        </Field>
        <Field id="rp-reason" label="How it came" required full hint="A letter of 12 October, an e-mail to the Director, a meeting…">
          <input id="rp-reason" className="ctl" value={reason} onChange={(e) => setReason(e.target.value)} />
        </Field>
      </div>
      {problem ? <ProblemNotice problem={problem} /> : null}
    </Modal>
  );
}
