"use client";
/** V658: the partnerships settings (MANAGE_PARTNERSHIP_SETTINGS) — the public form open or closed, the response times, the limits,
 *  the contact, the categories, the desks with their leads and officers, the routing rules (the first active one by priority) */
import { useEffect, useState } from "react";
import { Btn, Note, Panel, PBody, Pil, Spinner } from "@/components/proto/ui";
import { Field } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { notify } from "@/components/proto/Toast";
import type { Problem } from "@/lib/api";
import { FUNDING, ORG_TYPES, word } from "@/lib/partnerships";
import { ptnCall } from "./ptn-call";

interface S {
  settings: Record<string, string | number | boolean | null>;
  groups: { code: string; label: string; active: boolean }[];
  categories: { code: string; grp: string; label: string; sort: number; active: boolean }[];
  desks: { code: string; label: string; lead_person: string | null; lead_name: string | null; active: boolean }[];
  officers: { desk_code: string; person_id: string; name: string; active: boolean }[];
  rules: { id: string; priority: number; category_group: string | null; category: string | null; international: boolean | null; org_type: string | null;
    funding_status: string | null; desk_code: string; active: boolean; note: string | null }[];
  linkagesStaff: { id: string; name: string }[];
}
const NUMS: [string, string, string][] = [["acknowledge_days", "acknowledgeDays", "Acknowledge within (working days)"], ["screening_days", "screeningDays", "Screening (working days)"],
  ["review_days", "reviewDays", "Review (working days)"], ["complex_review_days", "complexReviewDays", "Complex review (working days)"],
  ["info_days", "infoDays", "Time given to answer a request (working days)"], ["summary_max", "summaryMax", "Summary limit (characters)"],
  ["text_max", "textMax", "Long answer limit (characters)"], ["benefits_max", "benefitsMax", "Benefits limit (characters)"], ["max_files", "maxFiles", "Files at most"],
  ["max_file_mb", "maxFileMb", "Largest file (MB, up to 7)"], ["draft_days", "draftDays", "Drafts kept (days)"], ["expiry_alert_days", "expiryAlertDays", "Agreement expiry told (days before)"]];

export function Settings() {
  const [s, setS] = useState<S | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [form, setForm] = useState<Record<string, string | boolean>>({});
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState<string | null>(null);
  const [cat, setCat] = useState({ code: "", group: "OTHER", label: "" });
  const [rule, setRule] = useState<{ id: string | null; priority: string; group: string; category: string; international: string; orgType: string; funding: string; desk: string; note: string; active: boolean }>(
    { id: null, priority: "", group: "", category: "", international: "", orgType: "", funding: "", desk: "GENERAL", note: "", active: true });
  const [officer, setOfficer] = useState({ desk: "GENERAL", person: "" });

  function take(d: S) {
    setS(d);
    const f: Record<string, string | boolean> = { publicOpen: Boolean(d.settings.public_open), contactEmail: String(d.settings.contact_email ?? ""), contactPhone: String(d.settings.contact_phone ?? "") };
    for (const [col, key] of NUMS) f[key] = String(d.settings[col] ?? "");
    setForm(f);
  }
  useEffect(() => { void ptnCall<S>("/settings").then((r) => (r.ok ? take(r.data) : setProblem(r.problem))); }, []);

  async function run(key: string, path: string, method: "PUT" | "POST", body: unknown, why: string) {
    setBusy(key); setProblem(null);
    try {
      const r = await ptnCall<S>(path, { method, body, reason: why });
      if (!r.ok) { setProblem(r.problem); return false; }
      take(r.data); notify("Saved"); return true;
    } finally { setBusy(null); }
  }

  if (!s) return problem ? <ProblemNotice problem={problem} /> : <div className="row row--tight sub2"><Spinner /> Reading the settings…</div>;
  const settingsBody: Record<string, unknown> = { publicOpen: form.publicOpen, contactEmail: form.contactEmail, contactPhone: form.contactPhone };
  for (const [, key] of NUMS) settingsBody[key] = Number(form[key]);

  return (
    <div className="stack">
      {problem ? <ProblemNotice problem={problem} /> : null}
      <Panel title="The public form and the response times">
        <PBody>
          <div className="grid grid--3">
            <Field id="ps-open" label="Public form">
              <select id="ps-open" className="ctl" value={form.publicOpen ? "1" : "0"} onChange={(e) => setForm({ ...form, publicOpen: e.target.value === "1" })}><option value="1">Open</option><option value="0">Closed</option></select>
            </Field>
            <Field id="ps-email" label="Contact email (shown and in the acknowledgement)"><input id="ps-email" className="ctl" value={String(form.contactEmail ?? "")} onChange={(e) => setForm({ ...form, contactEmail: e.target.value })} /></Field>
            <Field id="ps-phone" label="Contact telephone"><input id="ps-phone" className="ctl" value={String(form.contactPhone ?? "")} onChange={(e) => setForm({ ...form, contactPhone: e.target.value })} /></Field>
            {NUMS.map(([col, key, label]) => (
              <Field key={col} id={`ps-${key}`} label={label}><input id={`ps-${key}`} className="ctl tnum" inputMode="numeric" value={String(form[key] ?? "")} onChange={(e) => setForm({ ...form, [key]: e.target.value })} /></Field>
            ))}
            <Field id="ps-reason" label="Reason for the change" required full><input id="ps-reason" className="ctl" value={reason} onChange={(e) => setReason(e.target.value)} /></Field>
          </div>
          <div className="row mt-1"><Btn kind="primary" busy={busy === "settings"} busyLabel="Saving…" disabled={reason.trim().length < 5}
            onClick={() => void run("settings", "/settings", "PUT", { settings: settingsBody, reason }, `Partnership settings: ${reason}`).then((ok) => ok && setReason(""))}>Save settings</Btn></div>
          {s.settings.set_by_name ? <p className="sub2 mt-1">Last changed by {String(s.settings.set_by_name)}{s.settings.reason ? ` — ${String(s.settings.reason)}` : ""}</p> : null}
        </PBody>
      </Panel>

      <Panel title="Categories">
        <PBody>
          <div className="tablewrap" tabIndex={0}><table className="tbl--data"><thead><tr><th>Group</th><th>Category</th><th>Code</th><th>In use</th><th /></tr></thead>
            <tbody>{s.categories.map((c) => (
              <tr key={c.code}><td className="sub2">{s.groups.find((g) => g.code === c.grp)?.label ?? c.grp}</td><td>{c.label}</td><td className="tnum sub2">{c.code}</td>
                <td>{c.active ? <Pil kind="ok">Offered</Pil> : <Pil kind="grey">Not offered</Pil>}</td>
                <td><Btn kind="ghost" onClick={() => void run(`cat-${c.code}`, `/categories/${encodeURIComponent(c.code)}`, "PUT", { group: c.grp, label: c.label, sort: c.sort, active: !c.active }, `Partnership category ${c.code} ${c.active ? "withdrawn" : "offered"}`)}>{c.active ? "Withdraw" : "Offer"}</Btn></td></tr>
            ))}</tbody></table></div>
          <div className="grid grid--3 mt-2">
            <Field id="pc-group" label="Group"><select id="pc-group" className="ctl" value={cat.group} onChange={(e) => setCat({ ...cat, group: e.target.value })}>{s.groups.map((g) => <option key={g.code} value={g.code}>{g.label}</option>)}</select></Field>
            <Field id="pc-label" label="New category"><input id="pc-label" className="ctl" value={cat.label} onChange={(e) => setCat({ ...cat, label: e.target.value, code: e.target.value.toUpperCase().replace(/[^A-Z0-9]+/g, "_").replace(/^_|_$/g, "").slice(0, 60) })} /></Field>
            <Field id="pc-code" label="Code"><input id="pc-code" className="ctl tnum" value={cat.code} onChange={(e) => setCat({ ...cat, code: e.target.value.toUpperCase() })} /></Field>
          </div>
          <div className="row mt-1"><Btn kind="secondary" disabled={!cat.code || !cat.label} onClick={() => void run("cat", `/categories/${encodeURIComponent(cat.code)}`, "PUT", { group: cat.group, label: cat.label, active: true }, `Partnership category added: ${cat.label}`).then((ok) => ok && setCat({ code: "", group: cat.group, label: "" }))}>Add category</Btn></div>
        </PBody>
      </Panel>

      <Panel title="Desks of the Linkages & Partnerships office">
        <PBody>
          {!s.linkagesStaff.length ? <Note kind="info" title="Nobody holds the Director, Linkages & Partnerships office yet; the Directorate of ICT grants it on Staff & Offices." /> : null}
          <div className="tablewrap" tabIndex={0}><table className="tbl--data"><thead><tr><th>Desk</th><th>Lead (takes a proposal routed here)</th><th>Officers</th><th>Open</th></tr></thead>
            <tbody>{s.desks.map((d) => (
              <tr key={d.code}><td>{d.label}</td>
                <td><select aria-label={`Lead of ${d.label}`} className="ctl" value={d.lead_person ?? ""} onChange={(e) => void run(`desk-${d.code}`, `/desks/${d.code}`, "PUT", { label: d.label, lead: e.target.value || null, active: d.active }, `Lead of the ${d.label} desk`)}>
                  <option value="">None</option>{s.linkagesStaff.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}</select></td>
                <td className="sub2">{s.officers.filter((o) => o.desk_code === d.code && o.active).map((o) => o.name).join(", ") || "—"}</td>
                <td>{d.code === "GENERAL" ? <Pil kind="ok">Always</Pil> : <Btn kind="ghost" onClick={() => void run(`desk-${d.code}`, `/desks/${d.code}`, "PUT", { label: d.label, lead: d.lead_person, active: !d.active }, `${d.label} desk ${d.active ? "closed" : "opened"}`)}>{d.active ? "Close" : "Open"}</Btn>}</td></tr>
            ))}</tbody></table></div>
          <div className="grid grid--3 mt-2">
            <Field id="po-desk" label="Desk"><select id="po-desk" className="ctl" value={officer.desk} onChange={(e) => setOfficer({ ...officer, desk: e.target.value })}>{s.desks.map((d) => <option key={d.code} value={d.code}>{d.label}</option>)}</select></Field>
            <Field id="po-person" label="Officer"><select id="po-person" className="ctl" value={officer.person} onChange={(e) => setOfficer({ ...officer, person: e.target.value })}><option value="">Choose…</option>{s.linkagesStaff.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}</select></Field>
          </div>
          <div className="row mt-1" style={{ gap: 8 }}>
            <Btn kind="secondary" disabled={!officer.person} onClick={() => void run("officer", `/desks/${officer.desk}/officers/${officer.person}`, "PUT", { active: true }, "Desk officer added")}>Add officer</Btn>
            <Btn kind="ghost" disabled={!officer.person} onClick={() => void run("officer", `/desks/${officer.desk}/officers/${officer.person}`, "PUT", { active: false }, "Desk officer removed")}>Remove officer</Btn>
          </div>
        </PBody>
      </Panel>

      <Panel title="Routing rules" right={<span className="sub2">The first active rule by priority whose conditions all match names the desk; none matching, the general desk</span>}>
        <PBody>
          <div className="tablewrap" tabIndex={0}><table className="tbl--data"><thead><tr><th className="num">Priority</th><th>When</th><th>Desk</th><th>Active</th><th /></tr></thead>
            <tbody>{s.rules.map((r) => (
              <tr key={r.id}><td className="num tnum">{r.priority}</td>
                <td>{[r.category_group ? `group ${s.groups.find((g) => g.code === r.category_group)?.label ?? r.category_group}` : null, r.category ? `category ${s.categories.find((c) => c.code === r.category)?.label ?? r.category}` : null,
                  r.international == null ? null : r.international ? "international" : "local", r.org_type ? word(ORG_TYPES, r.org_type) : null, r.funding_status ? word(FUNDING, r.funding_status) : null].filter(Boolean).join(" · ") || "Any"}
                  {r.note ? <div className="sub2">{r.note}</div> : null}</td>
                <td>{s.desks.find((d) => d.code === r.desk_code)?.label ?? r.desk_code}</td><td>{r.active ? "Yes" : "No"}</td>
                <td><Btn kind="ghost" onClick={() => setRule({ id: r.id, priority: String(r.priority), group: r.category_group ?? "", category: r.category ?? "", international: r.international == null ? "" : r.international ? "YES" : "NO",
                  orgType: r.org_type ?? "", funding: r.funding_status ?? "", desk: r.desk_code, note: r.note ?? "", active: r.active })}>Edit</Btn></td></tr>
            ))}</tbody></table></div>
          <div className="grid grid--4 mt-2">
            <Field id="pr-priority" label="Priority"><input id="pr-priority" className="ctl tnum" value={rule.priority} onChange={(e) => setRule({ ...rule, priority: e.target.value })} /></Field>
            <Field id="pr-group" label="Group"><select id="pr-group" className="ctl" value={rule.group} onChange={(e) => setRule({ ...rule, group: e.target.value })}><option value="">Any</option>{s.groups.map((g) => <option key={g.code} value={g.code}>{g.label}</option>)}</select></Field>
            <Field id="pr-category" label="Category"><select id="pr-category" className="ctl" value={rule.category} onChange={(e) => setRule({ ...rule, category: e.target.value })}><option value="">Any</option>{s.categories.map((c) => <option key={c.code} value={c.code}>{c.label}</option>)}</select></Field>
            <Field id="pr-intl" label="International/local"><select id="pr-intl" className="ctl" value={rule.international} onChange={(e) => setRule({ ...rule, international: e.target.value })}><option value="">Either</option><option value="YES">International</option><option value="NO">Local</option></select></Field>
            <Field id="pr-org" label="Organisation type"><select id="pr-org" className="ctl" value={rule.orgType} onChange={(e) => setRule({ ...rule, orgType: e.target.value })}><option value="">Any</option>{ORG_TYPES.map(([k, l]) => <option key={k} value={k}>{l}</option>)}</select></Field>
            <Field id="pr-fund" label="Funding"><select id="pr-fund" className="ctl" value={rule.funding} onChange={(e) => setRule({ ...rule, funding: e.target.value })}><option value="">Any</option>{FUNDING.map(([k, l]) => <option key={k} value={k}>{l}</option>)}</select></Field>
            <Field id="pr-desk" label="Desk"><select id="pr-desk" className="ctl" value={rule.desk} onChange={(e) => setRule({ ...rule, desk: e.target.value })}>{s.desks.map((d) => <option key={d.code} value={d.code}>{d.label}</option>)}</select></Field>
            <Field id="pr-active" label="Active"><select id="pr-active" className="ctl" value={rule.active ? "1" : "0"} onChange={(e) => setRule({ ...rule, active: e.target.value === "1" })}><option value="1">Yes</option><option value="0">No</option></select></Field>
            <Field id="pr-note" label="Note" full><input id="pr-note" className="ctl" value={rule.note} onChange={(e) => setRule({ ...rule, note: e.target.value })} /></Field>
          </div>
          <div className="row mt-1" style={{ gap: 8 }}>
            <Btn kind="secondary" disabled={!/^\d+$/.test(rule.priority)} onClick={() => void run("rule", "/rules", "POST", { id: rule.id, priority: Number(rule.priority), group: rule.group, category: rule.category,
              international: rule.international === "" ? null : rule.international === "YES", orgType: rule.orgType, funding: rule.funding, desk: rule.desk, active: rule.active, note: rule.note },
              rule.id ? "Routing rule changed" : "Routing rule added").then((ok) => ok && setRule({ id: null, priority: "", group: "", category: "", international: "", orgType: "", funding: "", desk: "GENERAL", note: "", active: true }))}>{rule.id ? "Save rule" : "Add rule"}</Btn>
            {rule.id ? <Btn kind="ghost" onClick={() => setRule({ id: null, priority: "", group: "", category: "", international: "", orgType: "", funding: "", desk: "GENERAL", note: "", active: true })}>New rule</Btn> : null}
          </div>
        </PBody>
      </Panel>
    </div>
  );
}
