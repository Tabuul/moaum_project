"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { legalDay } from "@/lib/legal-text";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, Note, Panel, PBody, Pil, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal, day } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";

export interface DocRow {
  id: string; kind: string; version: number; status: string; title: string; effective_on: string | null; created_at: string; updated_at: string;
  published_at: string | null; archived_at: string | null; archive_note: string | null; requires_acceptance: boolean; review_pending: number;
  created_by_name: string; updated_by_name: string; published_by_name: string;
  acceptance?: { subject_kind: string; accepted: number; withdrawn: number; last_at: string | null }[];
}
export interface Contact {
  dpo_name: string | null; dpo_title: string | null; dpo_office: string | null; dpo_email: string | null; dpo_phone: string | null; dpo_address: string | null;
  request_days: number; note: string | null; updated_at: string | null; updated_office: string | null; updated_by_name: string;
}
export interface AdminList { rows: DocRow[]; contact: Contact; providers: string; tokens: Record<string, string> }
export interface Section { key?: string; heading: string; body: string }
export interface ReviewPoint { key: string; text: string; confirmed_at: string | null; confirmed_by: string | null }
export interface DraftDoc extends DocRow { summary: string | null; sections: Section[]; review_points: ReviewPoint[] }
export interface HistoryRow { occurred_at: string; actor: string; actor_office: string; action: string; subject_type: string; reason: string | null; kind: string | null; version: string | null; status: string | null }

const KIND: Record<string, string> = { PRIVACY_POLICY: "Privacy Policy", TERMS_OF_USE: "Terms of Use", COOKIE_NOTICE: "Cookie Notice" };
const STATUS: Record<string, ["ok" | "info" | "grey" | "bad", string]> = { PUBLISHED: ["ok", "Published"], DRAFT: ["info", "Draft"], ARCHIVED: ["grey", "Archived"] };
const SUBJECT: Record<string, string> = { STUDENT: "Students", STAFF: "Staff", APPLICANT: "Applicants" };

export function Privacy({ list, draft: draft0, history, actingOffice }: { list: AdminList; draft: DraftDoc | null; history: HistoryRow[]; actingOffice: string | null }) {
  const router = useRouter();
  const canSet = ["ict", "admin", "super"].includes(actingOffice ?? "");
  const canContact = canSet || actingOffice === "registrar";
  const published = list.rows.find((r) => r.kind === "PRIVACY_POLICY" && r.status === "PUBLISHED") ?? null;
  const [draft, setDraft] = useState<DraftDoc | null>(draft0);
  const [title, setTitle] = useState(draft0?.title ?? "Privacy Policy");
  const [summary, setSummary] = useState(draft0?.summary ?? "");
  const [effective, setEffective] = useState(draft0?.effective_on ?? "");
  const [requires, setRequires] = useState(draft0?.requires_acceptance ?? true);
  const [sections, setSections] = useState<Section[]>(draft0?.sections ?? []);
  const [dirty, setDirty] = useState(false);
  const [openSec, setOpenSec] = useState<number | null>(null);
  const [c, setC] = useState({ name: list.contact.dpo_name ?? "", title: list.contact.dpo_title ?? "", office: list.contact.dpo_office ?? "", email: list.contact.dpo_email ?? "",
    phone: list.contact.dpo_phone ?? "", address: list.contact.dpo_address ?? "", requestDays: list.contact.request_days ?? 30, note: list.contact.note ?? "" });
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [confirmPublish, setConfirmPublish] = useState(false);
  const [confirmWithdraw, setConfirmWithdraw] = useState(false);
  const [publishOn, setPublishOn] = useState(draft0?.effective_on ?? new Date().toISOString().slice(0, 10));

  async function send(path: string, method: "POST" | "PUT", body: unknown, reason: string): Promise<Record<string, unknown> | null> {
    setBusy(true);
    setProblem(null);
    try {
      const r = await fetch(`/api/bff/api/v1/privacy/admin${path}`, { method, headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body ?? {}) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { const p = j ?? { status: r.status, title: r.statusText }; setProblem(p); notifyProblem(p); return null; }
      notify(reason);
      return j as Record<string, unknown>;
    } finally {
      setBusy(false);
    }
  }

  async function save(): Promise<boolean> {
    if (!draft) return false;
    const j = await send(`/documents/${draft.id}`, "PUT", { title, summary, sections, effectiveOn: effective || null, requiresAcceptance: requires }, `Privacy Policy draft v${draft.version} saved`);
    if (!j) return false;
    setDraft(j as unknown as DraftDoc);
    setDirty(false);
    return true;
  }

  async function review(key: string, confirmed: boolean) {
    if (!draft) return;
    const j = await send(`/documents/${draft.id}/review`, "POST", { key, confirmed }, confirmed ? "Review point confirmed" : "Review point reopened");
    if (j) setDraft(j as unknown as DraftDoc);
  }

  async function publish() {
    if (!draft) return;
    if (dirty && !(await save())) return;
    const j = await send(`/documents/${draft.id}/publish`, "POST", { effectiveOn: publishOn || null }, `Privacy Policy v${draft.version} published`);
    if (j) { setConfirmPublish(false); router.refresh(); }
  }

  async function withdraw() {
    if (!draft) return;
    const j = await send(`/documents/${draft.id}/withdraw`, "POST", {}, `Privacy Policy draft v${draft.version} withdrawn`);
    if (j) { setConfirmWithdraw(false); setDraft(null); router.refresh(); }
  }

  async function newDraft() {
    const j = await send("/documents/draft", "POST", { kind: "PRIVACY_POLICY" }, "A new Privacy Policy draft opened");
    if (j) router.refresh();
  }

  async function saveContact() {
    const j = await send("/contact", "PUT", { ...c, requestDays: Number(c.requestDays) || 30 }, "Privacy contact set");
    if (j) router.refresh();
  }

  function patch(i: number, p: Partial<Section>) {
    setSections((s) => s.map((x, k) => (k === i ? { ...x, ...p } : x)));
    setDirty(true);
  }
  function move(i: number, d: -1 | 1) {
    setSections((s) => { const j = i + d; if (j < 0 || j >= s.length) return s; const n = [...s]; [n[i], n[j]] = [n[j], n[i]]; return n; });
    setDirty(true);
  }
  function remove(i: number) { setSections((s) => s.filter((_, k) => k !== i)); setDirty(true); }
  function add() { setSections((s) => [...s, { key: `s${s.length + 1}-${Date.now().toString(36)}`, heading: "New section", body: "" }]); setOpenSec(sections.length); setDirty(true); }

  const pending = draft?.review_points.filter((p) => !p.confirmed_at).length ?? 0;
  const accepted = published?.acceptance ?? [];

  return (
    <>
      {problem ? <ProblemNotice problem={problem} /> : null}
      <Tiles items={[
        ["Published", published ? `v${published.version}` : "none", published ? `effective ${legalDay(published.effective_on)}` : "no version is published yet"],
        ["Draft", draft ? `v${draft.version}` : "—", draft ? `${pending} review point${pending === 1 ? "" : "s"} to confirm` : "no draft open"],
        ...accepted.map((a): [string, string, string] => [`${SUBJECT[a.subject_kind] ?? a.subject_kind} accepted`, String(a.accepted), a.last_at ? `last ${day(a.last_at)}` : "none yet"]),
      ]} />

      <Panel title="The published Privacy Policy" right={published ? `Version ${published.version} · published ${day(published.published_at)} by ${published.published_by_name || "—"}` : undefined}>
        <PBody>
          {published ? (
            <div className="row row--wrap">
              <a className="btn btn--secondary btn--sm" href="/privacy-policy" target="_blank" rel="noopener">View the public page</a>
              <a className="btn btn--ghost btn--sm" href="/privacy-policy/pdf" target="_blank" rel="noopener">PDF</a>
              <span className="sub2">Effective {legalDay(published.effective_on)} · {published.requires_acceptance ? "acceptance asked of everyone who signs in, once" : "acceptance not asked"}</span>
              {canSet && !draft ? <Btn kind="primary" disabled={busy} onClick={() => void newDraft()}>Start a new version</Btn> : null}
            </div>
          ) : (
            <Note kind="info" title="Not yet published">
              The public page says the policy is being finalised. Confirm the review points on the draft below, enter the privacy contact, and publish.
              {canSet && !draft ? <div className="mt-2"><Btn kind="primary" disabled={busy} onClick={() => void newDraft()}>Open a draft</Btn></div> : null}
            </Note>
          )}
        </PBody>
      </Panel>

      {draft ? (
        <Panel title={`Draft — version ${draft.version}`} right={`last saved ${day(draft.updated_at)}${draft.updated_by_name ? ` by ${draft.updated_by_name}` : ""}`}>
          <PBody>
            <div className="grid grid--3">
              <Field id="pv-title" label="Title"><input id="pv-title" value={title} disabled={!canSet} onChange={(e) => { setTitle(e.target.value); setDirty(true); }} /></Field>
              <Field id="pv-eff" label="Effective date" hint="Set here or at publication"><input id="pv-eff" type="date" value={effective} disabled={!canSet} onChange={(e) => { setEffective(e.target.value); setDirty(true); }} /></Field>
              <Field id="pv-req" label="Acceptance">
                <label className="row row--inline row--tight"><input id="pv-req" type="checkbox" checked={requires} disabled={!canSet} onChange={(e) => { setRequires(e.target.checked); setDirty(true); }} /> Ask everyone who signs in to accept this version, once</label>
              </Field>
            </div>
            <Field id="pv-sum" label="Summary" hint="Plain language, at the top of the page"><textarea id="pv-sum" rows={3} value={summary} disabled={!canSet} onChange={(e) => { setSummary(e.target.value); setDirty(true); }} style={{ width: "100%" }} /></Field>

            <div className="eyebrow mt-2 mb-1">Sections ({sections.length})</div>
            <div className="sub2 mb-2">Paragraphs are separated by a blank line; a line beginning &quot;- &quot; is a list item. Tokens in double braces are filled in when the page is read: {Object.keys(list.tokens).map((k) => `{{${k}}}`).join(", ")}.</div>
            {sections.map((s, i) => (
              <details key={s.key ?? i} open={openSec === i} onToggle={(e) => { if ((e.target as HTMLDetailsElement).open) setOpenSec(i); else if (openSec === i) setOpenSec(null); }} style={{ border: "1px solid var(--line)", borderRadius: "var(--r-sm)", padding: "6px 10px", marginBottom: 6 }}>
                <summary style={{ cursor: "pointer" }}><b>{i + 1}.</b> {s.heading || "(untitled)"} <span className="sub2">· {s.body.trim().split(/\s+/).filter(Boolean).length} words</span></summary>
                <div className="mt-2">
                  <Field id={`pv-h-${i}`} label="Heading"><input id={`pv-h-${i}`} value={s.heading} disabled={!canSet} onChange={(e) => patch(i, { heading: e.target.value })} /></Field>
                  <Field id={`pv-b-${i}`} label="Text"><textarea id={`pv-b-${i}`} rows={Math.min(18, Math.max(6, s.body.split("\n").length + 2))} value={s.body} disabled={!canSet} onChange={(e) => patch(i, { body: e.target.value })} style={{ width: "100%", fontFamily: "inherit" }} /></Field>
                  {canSet ? (
                    <div className="row row--tight">
                      <Btn kind="ghost" size="sm" disabled={i === 0} onClick={() => move(i, -1)}>Move up</Btn>
                      <Btn kind="ghost" size="sm" disabled={i === sections.length - 1} onClick={() => move(i, 1)}>Move down</Btn>
                      <Btn kind="ghost" size="sm" onClick={() => remove(i)}>Remove</Btn>
                    </div>
                  ) : null}
                </div>
              </details>
            ))}
            {canSet ? <div className="row row--tight mt-1"><Btn kind="ghost" size="sm" onClick={add}>Add a section</Btn></div> : null}

            <div className="eyebrow mt-3 mb-1">Review points — confirmed before publication</div>
            <div className="sub2 mb-2">Each is the Data Protection Officer&apos;s or legal adviser&apos;s word on an item the policy states; the person who confirms it here records that word.</div>
            {draft.review_points.map((p) => (
              <label key={p.key} className="row row--top row--tight" style={{ alignItems: "flex-start", marginBottom: 6 }}>
                <input type="checkbox" checked={!!p.confirmed_at} disabled={!canSet || busy} onChange={(e) => void review(p.key, e.target.checked)} style={{ marginTop: 4 }} />
                <span><span className={p.confirmed_at ? "" : "b600"}>{p.text}</span>{p.confirmed_at ? <span className="sub2"> · confirmed {day(p.confirmed_at)}</span> : null}</span>
              </label>
            ))}

            <div className="row row--wrap mt-3">
              {canSet ? <Btn kind="primary" disabled={busy || !dirty} onClick={() => void save()}>{busy ? "Saving…" : dirty ? "Save the draft" : "Saved"}</Btn> : null}
              <a className="btn btn--secondary btn--sm" href={`/privacy-policy?preview=${draft.id}`} target="_blank" rel="noopener">Preview</a>
              <a className="btn btn--ghost btn--sm" href={`/privacy-policy/pdf?preview=${draft.id}`} target="_blank" rel="noopener">Preview PDF</a>
              <span className="grow" />
              {canSet ? <Btn kind="ghost" disabled={busy} onClick={() => setConfirmWithdraw(true)}>Withdraw the draft</Btn> : null}
              {canSet ? <Btn kind="go" disabled={busy || pending > 0} onClick={() => setConfirmPublish(true)} title={pending > 0 ? `${pending} review point${pending === 1 ? "" : "s"} to confirm first` : undefined}>Publish version {draft.version}</Btn> : null}
            </div>
          </PBody>
        </Panel>
      ) : null}

      <div className="grid grid--2">
        <Panel title="Privacy contact" right="Named in the policy; set by ICT, the Registrar or an administrator">
          <PBody>
            <div className="grid grid--2">
              <Field id="pc-name" label="Name"><input id="pc-name" value={c.name} disabled={!canContact} onChange={(e) => setC({ ...c, name: e.target.value })} /></Field>
              <Field id="pc-title" label="Title" hint="e.g. Data Protection Officer"><input id="pc-title" value={c.title} disabled={!canContact} onChange={(e) => setC({ ...c, title: e.target.value })} /></Field>
              <Field id="pc-office" label="Office"><input id="pc-office" value={c.office} disabled={!canContact} onChange={(e) => setC({ ...c, office: e.target.value })} /></Field>
              <Field id="pc-email" label="E-mail"><input id="pc-email" type="email" value={c.email} disabled={!canContact} onChange={(e) => setC({ ...c, email: e.target.value })} /></Field>
              <Field id="pc-phone" label="Telephone"><input id="pc-phone" value={c.phone} disabled={!canContact} onChange={(e) => setC({ ...c, phone: e.target.value })} /></Field>
              <Field id="pc-days" label="Requests answered within (days)" hint="1 to 90; the governance log's due date"><input id="pc-days" type="number" min={1} max={90} value={c.requestDays} disabled={!canContact} onChange={(e) => setC({ ...c, requestDays: Number(e.target.value) })} /></Field>
            </div>
            <Field id="pc-addr" label="Address"><input id="pc-addr" value={c.address} disabled={!canContact} onChange={(e) => setC({ ...c, address: e.target.value })} /></Field>
            <div className="row">
              {canContact ? <Btn kind="primary" disabled={busy} onClick={() => void saveContact()}>Save the contact</Btn> : null}
              {list.contact.updated_at ? <span className="sub2">Set {day(list.contact.updated_at)} by {list.contact.updated_by_name || list.contact.updated_office}</span> : <span className="sub2">Not yet set — the policy names a placeholder until it is</span>}
            </div>
          </PBody>
        </Panel>
        <Panel title="Providers the policy names" right="Read from the configuration, never typed">
          <PBody>
            <pre style={{ whiteSpace: "pre-wrap", fontFamily: "inherit", fontSize: 13, margin: 0, lineHeight: 1.5 }}>{list.providers}</pre>
            <div className="sub2 mt-2">Hosting and object-storage providers are described in the policy&apos;s own &quot;Third-party services&quot; section; the payment gateways, SMS and e-mail services and the file store are detected from what is switched on.</div>
            <div className="sub2 mt-1">Requests filed through the portal appear on <a className="lnk" href="/governance">Data governance</a> as filed through the portal.</div>
          </PBody>
        </Panel>
      </div>

      <Panel title="Every version" right="Earlier versions are kept, never deleted">
        <DTable cols={["Document", "Version|num", "Status", "Effective|mid", "Published|mid", "By", "Note"]} rows={list.rows.map((r) => [
          KIND[r.kind] ?? r.kind,
          <span className="tnum" key="v">{r.version}</span>,
          <Pil key="s" kind={STATUS[r.status]?.[0] ?? "grey"}>{STATUS[r.status]?.[1] ?? r.status}</Pil>,
          <span className="tnum sub2" key="e">{legalDay(r.effective_on)}</span>,
          <span className="tnum sub2" key="p">{r.published_at ? day(r.published_at) : "—"}</span>,
          <Two key="b" a={r.published_by_name || r.updated_by_name || "—"} b={r.status === "DRAFT" ? `${r.review_pending} to confirm` : r.archived_at ? `archived ${day(r.archived_at)}` : ""} />,
          <span className="sub2" key="n">{r.archive_note ?? ""}</span>,
        ])} texts={list.rows.map((r) => `${r.kind} ${r.version} ${r.status}`)} />
      </Panel>

      <Panel title="Change history" right="From the audit trail">
        {history.length ? (
          <DTable cols={["When|mid", "Who", "Acting as", "Action", "Document", "Reason"]} rows={history.map((h) => [
            <span className="tnum sub2" key="w">{day(h.occurred_at)}</span>,
            h.actor, h.actor_office, h.action,
            h.kind ? `${KIND[h.kind] ?? h.kind} v${h.version ?? ""} ${h.status ?? ""}` : h.subject_type === "platform.privacy_contact" ? "Privacy contact" : h.subject_type,
            <span className="sub2" key="r">{h.reason ?? ""}</span>,
          ])} texts={history.map((h) => `${h.actor} ${h.action}`)} />
        ) : <PBody><div className="sub2">No change yet.</div></PBody>}
      </Panel>

      {confirmPublish && draft ? (
        <Modal title={`Publish version ${draft.version}`} sub="The version published now is archived and kept" onClose={() => setConfirmPublish(false)}
          foot={<><Btn kind="go" disabled={busy} onClick={() => void publish()}>{busy ? "Publishing…" : "Publish"}</Btn><Btn kind="ghost" disabled={busy} onClick={() => setConfirmPublish(false)}>Cancel</Btn></>}>
          <Field id="pv-pub-on" label="Effective date"><input id="pv-pub-on" type="date" value={publishOn} onChange={(e) => setPublishOn(e.target.value)} /></Field>
          <div className="sub2">{requires ? "Everyone who signs in will be asked to read and accept this version, once." : "Acceptance will not be asked for this version."}{dirty ? " Unsaved edits are saved first." : ""}</div>
        </Modal>
      ) : null}
      {confirmWithdraw && draft ? (
        <Modal title={`Withdraw draft version ${draft.version}`} sub="Kept as an archived draft; the published version is untouched" onClose={() => setConfirmWithdraw(false)}
          foot={<><Btn kind="urgent" disabled={busy} onClick={() => void withdraw()}>Withdraw</Btn><Btn kind="ghost" disabled={busy} onClick={() => setConfirmWithdraw(false)}>Cancel</Btn></>}>
          <div className="sub2">A later draft starts again from the published version.</div>
        </Modal>
      ) : null}
    </>
  );
}
