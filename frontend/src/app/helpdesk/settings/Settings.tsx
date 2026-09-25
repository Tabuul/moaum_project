"use client";
/** The Director's settings (V251): each category with its fields (added, edited, deactivated — never deleted, so
 *  its tickets keep their category), the SLA hours by priority, and the quiet spell after which a resolved ticket
 *  nobody answered closes itself — off unless set. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, LinkBtn, Note, PageHead, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { PRIORITY, parse, type Category, type Field as F } from "@/lib/helpdesk";

export interface DeskSettings { auto_close_days: number | null; notify_agents_on_new: boolean; sla: { priority: string; first_response_hours: number; resolution_hours: number }[] }
interface Draft { id: string | null; code: string; name: string; description: string; active: boolean; ordinal: string; suggestedPriority: string; attachmentHint: string; fields: (F & { optionsText?: string; keyTouched?: boolean })[] }
const slug = (label: string) => label.toLowerCase().replace(/[^a-z0-9]+/g, "_").replace(/^_+|_+$/g, "").slice(0, 30);
const TYPES: [string, string][] = [["text", "Text"], ["date", "Date"], ["number", "Number"], ["select", "Choice"], ["session", "Academic session"], ["semester", "Semester"], ["level", "Level"]];

export function Settings({ categories, settings }: { categories: Category[]; settings: DeskSettings }) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [draft, setDraft] = useState<Draft | null>(null);
  const [days, setDays] = useState(settings.auto_close_days == null ? "" : String(settings.auto_close_days));
  const [tell, setTell] = useState(settings.notify_agents_on_new);
  const [sla, setSla] = useState(settings.sla.map((s) => ({ ...s, first: String(s.first_response_hours), res: String(s.resolution_hours) })));

  async function call(method: "POST" | "PUT", path: string, body: unknown, reason: string): Promise<boolean> {
    setBusy(true); setProblem(null);
    try {
      const r = await fetch(`/api/bff/api/v1/helpdesk/admin${path}`, { method, headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body) });
      if (!r.ok) { const p = (await r.json().catch(() => null)) ?? { status: r.status, title: r.statusText }; setProblem(p); notifyProblem(p); return false; }
      notify(reason);
      router.refresh();
      return true;
    } finally { setBusy(false); }
  }
  const open = (c: Category | null) => setDraft(c ? {
    id: c.id, code: c.code, name: c.name, description: c.description ?? "", active: c.active !== false, ordinal: String(c.ordinal ?? 100), suggestedPriority: c.suggested_priority, attachmentHint: c.attachment_hint ?? "",
    fields: parse<F[]>(c.fields, []).map((f) => ({ ...f, optionsText: (f.options ?? []).join("\n"), keyTouched: true })),
  } : { id: null, code: "", name: "", description: "", active: true, ordinal: "100", suggestedPriority: "NORMAL", attachmentHint: "", fields: [] });
  async function save() {
    if (!draft) return;
    const body = {
      code: draft.code || undefined, name: draft.name.trim(), description: draft.description.trim() || null, active: draft.active, ordinal: Number(draft.ordinal) || 100, suggestedPriority: draft.suggestedPriority, attachmentHint: draft.attachmentHint.trim() || null,
      fields: draft.fields.map((f) => ({ key: f.key, label: f.label, type: f.type, required: !!f.required, hint: f.hint ?? "", options: f.type === "select" ? (f.optionsText ?? "").split("\n").map((x) => x.trim()).filter(Boolean) : undefined })),
    };
    const ok = draft.id ? await call("PUT", `/categories/${draft.id}`, body, `Category ${draft.name.trim()} saved`) : await call("POST", "/categories", body, `Category ${draft.name.trim()} created`);
    if (ok) setDraft(null);
  }
  const setField = (i: number, patch: Partial<F & { optionsText?: string; keyTouched?: boolean }>) => { if (!draft) return; const fields = draft.fields.slice(); fields[i] = { ...fields[i], ...patch }; setDraft({ ...draft, fields }); };
  // what stops a save: a field without a key or label, two fields on one key, a choice without options
  const fieldFault = draft ? (draft.fields.some((f) => !f.key || !f.label.trim()) ? "Every field needs a key and a label." : new Set(draft.fields.map((f) => f.key)).size !== draft.fields.length ? "Two fields share a key." : draft.fields.some((f) => f.type === "select" && !(f.optionsText ?? "").split("\n").some((x) => x.trim())) ? "A choice field lists its options." : null) : null;
  const slaBlank = sla.some((s) => !s.first || !s.res);

  return (
    <>
      <PageHead title="ICT Support Settings" description="The categories a requester chooses from and what each asks for; the SLA by priority; whether resolved tickets close themselves."
        actions={<><Btn kind="primary" onClick={() => open(null)}>New Category</Btn><LinkBtn href="/helpdesk">The Queue</LinkBtn></>} />
      {problem ? <ProblemNotice problem={problem} /> : null}

      <Panel title="Categories" right={`${categories.filter((c) => c.active !== false).length} open for new tickets · ${categories.length} in all`}>
        <DTable cols={["Order|mid", "Category", "Asks for", "Handled as|mid", "Tickets|mid", "State|mid", "|num"]} rows={categories.map((c) => {
          const fs = parse<F[]>(c.fields, []);
          return [
            <span key="o" className="tnum sub2">{c.ordinal}</span>,
            <span key="n"><strong>{c.name}</strong> <span className="sub2 tnum">{c.code}</span>{c.description ? <div className="sub2">{c.description}</div> : null}</span>,
            <span key="f" className="sub2">{fs.length ? fs.map((f) => `${f.label}${f.required ? "*" : ""}`).join(", ") : "Subject and description only"}{c.attachment_hint ? ` · attachment: ${c.attachment_hint}` : ""}</span>,
            <Pil key="p" kind={PRIORITY[c.suggested_priority]?.[1] ?? "grey"}>{PRIORITY[c.suggested_priority]?.[0] ?? c.suggested_priority}</Pil>,
            <span key="t" className="tnum">{Number(c.tickets ?? 0)}</span>,
            <Pil key="s" kind={c.active === false ? "grey" : "ok"}>{c.active === false ? "Inactive" : "Active"}</Pil>,
            <Btn key="e" kind="ghost" size="sm" onClick={() => open(c)}>Edit</Btn>,
          ];
        })} />
        <PBody><div className="sub2">A category with tickets is deactivated rather than deleted: it leaves the requester&rsquo;s list, and its tickets keep their category.</div></PBody>
      </Panel>

      <div className="grid grid--2">
        <Panel title="The SLA by priority" right="Hours from submission">
          <PBody>
            <div className="stack">
              {sla.map((s, i) => (
                <div key={s.priority} className="row row--end">
                  <span style={{ flex: "0 0 90px" }}><Pil kind={PRIORITY[s.priority]?.[1] ?? "grey"}>{PRIORITY[s.priority]?.[0] ?? s.priority}</Pil></span>
                  <div className="field" style={{ flex: "1 1 130px" }}><label htmlFor={`sla-f-${s.priority}`}>First response (h)</label><input id={`sla-f-${s.priority}`} className="ctl tnum" inputMode="numeric" value={s.first} onChange={(e) => { const next = sla.slice(); next[i] = { ...s, first: e.target.value.replace(/[^0-9]/g, "") }; setSla(next); }} /></div>
                  <div className="field" style={{ flex: "1 1 130px" }}><label htmlFor={`sla-r-${s.priority}`}>Resolution (h)</label><input id={`sla-r-${s.priority}`} className="ctl tnum" inputMode="numeric" value={s.res} onChange={(e) => { const next = sla.slice(); next[i] = { ...s, res: e.target.value.replace(/[^0-9]/g, "") }; setSla(next); }} /></div>
                </div>
              ))}
              <div className="sub2">A ticket past its resolution hours, and not yet resolved, shows as overdue on the desk and in the reports; one past its first-response hours with no word from the desk shows as awaiting a response.</div>
            </div>
          </PBody>
        </Panel>
        <Panel title="Closing and notice" right="How the desk behaves">
          <PBody>
            <div className="stack">
              <Field id="hd-days" label="Close a resolved ticket automatically after" hint="Days without a reply from the requester, 1 to 90. Leave blank and no ticket ever closes itself; the requester confirms, or the desk closes on a reason.">
                <div className="row row--base"><input id="hd-days" className="ctl tnum" inputMode="numeric" style={{ width: 100 }} value={days} onChange={(e) => setDays(e.target.value.replace(/[^0-9]/g, ""))} placeholder="Off" /><span className="sub2">{days ? `day${days === "1" ? "" : "s"}` : "Off"}</span></div>
              </Field>
              <label className="row row--tight"><input type="checkbox" className="chk" checked={tell} onChange={(e) => setTell(e.target.checked)} /> <span>Email every agent and the Director when a new ticket arrives</span></label>
              <Note kind="info" title="Notices go through the portal's outbox">Every email here is queued in the same transaction as the act it announces and sent by the mail server set under Platform → Mail Server.</Note>
            </div>
          </PBody>
        </Panel>
      </div>
      <div className="row">
        <Btn kind="primary" disabled={busy || slaBlank} onClick={() => void call("PUT", "/settings", { autoCloseDays: days ? Number(days) : null, notifyAgentsOnNew: tell, sla: sla.map((s) => ({ priority: s.priority, firstResponseHours: Number(s.first), resolutionHours: Number(s.res) })) }, "ICT support settings saved")}>{busy ? "Saving…" : "Save SLA and Settings"}</Btn>
        {slaBlank ? <span className="sub2">Every SLA box needs a number of hours.</span> : null}
      </div>

      {draft ? (
        <Modal title={draft.id ? `Edit ${draft.name}` : "New Category"} sub="What the requester chooses, and what it asks for" onClose={() => setDraft(null)} wide
          foot={<>{fieldFault ? <span className="sub2 grow">{fieldFault}</span> : null}<Btn kind="ghost" onClick={() => setDraft(null)}>Cancel</Btn><Btn kind="primary" disabled={busy || draft.name.trim().length < 2 || !!fieldFault} onClick={() => void save()}>{busy ? "Saving…" : "Save the Category"}</Btn></>}>
          <div className="stack">
            <div className="row">
              <Field id="hd-c-name" label="Name" required style={{ flex: "2 1 220px" }}><input id="hd-c-name" className="ctl" value={draft.name} onChange={(e) => setDraft({ ...draft, name: e.target.value })} maxLength={120} /></Field>
              <Field id="hd-c-code" label="Code" hint={draft.id ? "Fixed once created" : "Optional; made from the name"} style={{ flex: "1 1 120px" }}><input id="hd-c-code" className="ctl tnum" value={draft.code} disabled={!!draft.id} onChange={(e) => setDraft({ ...draft, code: e.target.value.toUpperCase() })} maxLength={32} /></Field>
              <Field id="hd-c-ord" label="Order" style={{ width: 90 }}><input id="hd-c-ord" className="ctl tnum" inputMode="numeric" value={draft.ordinal} onChange={(e) => setDraft({ ...draft, ordinal: e.target.value.replace(/[^0-9]/g, "") })} /></Field>
              <Field id="hd-c-pri" label="Handled as" style={{ width: 150 }}><select id="hd-c-pri" className="ctl" value={draft.suggestedPriority} onChange={(e) => setDraft({ ...draft, suggestedPriority: e.target.value })}>{Object.entries(PRIORITY).map(([k, v]) => <option key={k} value={k}>{v[0]}</option>)}</select></Field>
            </div>
            <Field id="hd-c-desc" label="Description" hint="Shown under the category when chosen"><input id="hd-c-desc" className="ctl" value={draft.description} onChange={(e) => setDraft({ ...draft, description: e.target.value })} maxLength={500} /></Field>
            <Field id="hd-c-att" label="What to attach" hint="A hint beside the attachment field, e.g. the receipt"><input id="hd-c-att" className="ctl" value={draft.attachmentHint} onChange={(e) => setDraft({ ...draft, attachmentHint: e.target.value })} maxLength={200} /></Field>
            <label className="row row--tight"><input type="checkbox" className="chk" checked={draft.active} onChange={(e) => setDraft({ ...draft, active: e.target.checked })} /> <span>Open for new tickets</span></label>
            <div className="hr" />
            <div className="row row--base"><strong>Fields the category asks for</strong><span className="sub2">Beyond the subject, the description and the attachment.</span><span className="grow" /><Btn kind="ghost" size="sm" onClick={() => setDraft({ ...draft, fields: [...draft.fields, { key: "", label: "", type: "text", required: false }] })}>Add a Field</Btn></div>
            {draft.fields.map((f, i) => (
              <div key={i} className="row row--end" style={{ borderTop: "1px solid var(--line-2)", paddingTop: "var(--s-2)" }}>
                <Field id={`hd-f-label-${i}`} label="Label" style={{ flex: "2 1 160px" }}><input id={`hd-f-label-${i}`} className="ctl" value={f.label} onChange={(e) => setField(i, { label: e.target.value, key: f.keyTouched ? f.key : slug(e.target.value) })} /></Field>
                <Field id={`hd-f-key-${i}`} label="Key" style={{ flex: "1 1 120px" }}><input id={`hd-f-key-${i}`} className="ctl tnum" value={f.key} onChange={(e) => setField(i, { key: e.target.value.toLowerCase().replace(/[^a-z0-9_]/g, ""), keyTouched: true })} /></Field>
                <Field id={`hd-f-type-${i}`} label="Type" style={{ width: 160 }}><select id={`hd-f-type-${i}`} className="ctl" value={f.type} onChange={(e) => setField(i, { type: e.target.value as F["type"] })}>{TYPES.map(([k, l]) => <option key={k} value={k}>{l}</option>)}</select></Field>
                <label className="row row--tight" style={{ alignSelf: "center" }}><input type="checkbox" className="chk" checked={!!f.required} onChange={(e) => setField(i, { required: e.target.checked })} /> <span className="sub2">Required</span></label>
                <Field id={`hd-f-hint-${i}`} label="Hint" style={{ flex: "2 1 160px" }}><input id={`hd-f-hint-${i}`} className="ctl" value={f.hint ?? ""} onChange={(e) => setField(i, { hint: e.target.value })} /></Field>
                {f.type === "select" ? <Field id={`hd-f-opts-${i}`} label="Options, one a line" style={{ flex: "2 1 200px" }}><textarea id={`hd-f-opts-${i}`} className="ctl" rows={2} value={f.optionsText ?? ""} onChange={(e) => setField(i, { optionsText: e.target.value })} /></Field> : null}
                <Btn kind="ghost" size="sm" onClick={() => setDraft({ ...draft, fields: draft.fields.filter((_, j) => j !== i) })}>Remove</Btn>
              </div>
            ))}
          </div>
        </Modal>
      ) : null}
    </>
  );
}
