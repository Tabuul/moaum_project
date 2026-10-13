"use client";

/**
 * V434 — the ICT Director's half of the one Biodata compliance screen (V423, V427): the switch for mandatory student
 * biodata completion with the go-live readiness it is turned on against, the required items with what requiring each
 * would do, the exceptions and the history. The figures it shows are the screen's own — the quarter-hourly reading the
 * offices' counts and lists come from — so the switch is never turned on against a second count. The switch, the
 * requirements and the exceptions are the ICT Director's (or an administrator's); the API refuses anyone else.
 */
import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { Btn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { reasonHeader } from "@/lib/reason";
import type { Problem } from "@/lib/api";
import { SECTION_LABEL, pct, type ComplianceOverview, type GateException, type Requirement } from "@/lib/biodata-gate";

const B = "/api/bff/api/v1/biodata-compliance";
const when = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleString("en-GB", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" }) : "—");
const dayOnly = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" }) : "—");

async function send(path: string, method: string, body: unknown, why: string): Promise<unknown | null> {
  const r = await fetch(path, { method, headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(why) }, body: JSON.stringify(body) });
  const j = await r.json().catch(() => null);
  if (!r.ok) { notifyProblem((j as Problem) ?? { status: r.status, title: r.statusText }); return null; }
  return j ?? {};
}

/** the figures the switch is turned on against: the screen's own reading */
export interface Readiness { total: number; incomplete: number; computedAt: string | null; scoped: boolean }

/** the switch: ON or OFF, who turned it last and why; turning it on shows the readiness first */
export function GatePanel({ admin, readiness }: { admin: ComplianceOverview; readiness: Readiness }) {
  const router = useRouter();
  const [ask, setAsk] = useState<"on" | "off" | null>(null);
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);
  const g = admin.gate;
  const complete = Math.max(0, readiness.total - readiness.incomplete);

  async function toggle(on: boolean) {
    setBusy(true);
    try {
      const done = await send(`${B}/gate`, "PUT", { enabled: on, reason: reason.trim() || null },
        on ? "Mandatory student biodata completion turned ON" : "Mandatory student biodata completion turned OFF");
      if (!done) return;
      notify(on ? "Mandatory biodata completion is ON: students with incomplete biodata now complete it first" : "Mandatory biodata completion is OFF");
      setAsk(null);
      setReason("");
      router.refresh();
    } finally {
      setBusy(false);
    }
  }

  return (
    <Panel title="Mandatory student biodata completion" right={<Pil kind={g.enabled ? "ok" : "grey"}>{g.enabled ? "ON" : "OFF"}</Pil>}>
      <PBody>
        <div className="row row--top" style={{ flexWrap: "wrap", gap: "var(--s-4)" }}>
          <div className="grow" style={{ minWidth: 240 }}>
            <div className="b600">Status: {g.enabled ? "ON" : "OFF"}</div>
            <div className="sub2 mt-1" style={{ lineHeight: 1.55 }}>
              {g.enabled
                ? "Students with incomplete mandatory biodata will be required to complete their biodata before accessing other Student Dashboard functions."
                : "Require students with incomplete mandatory biodata to complete their profile before accessing the Student Dashboard."}
            </div>
            {g.changed_at ? <div className="sub2 mt-1">Last turned {g.enabled ? "on" : "off"} {when(g.changed_at)}{g.changed_by ? ` by ${g.changed_by}` : ""}{g.changed_office ? ` (${g.changed_office})` : ""}{g.reason ? ` — ${g.reason}` : ""}</div> : null}
          </div>
          {admin.canSet ? (
            <div className="row row--tight">
              {g.enabled ? <Btn kind="urgent" onClick={() => setAsk("off")}>Turn off</Btn> : <Btn kind="primary" onClick={() => setAsk("on")}>Turn on</Btn>}
            </div>
          ) : null}
        </div>
      </PBody>
      {ask === "on" ? (
        <Modal title="Enable mandatory biodata completion?" onClose={() => setAsk(null)}
          foot={<>
            <Btn kind="ghost" onClick={() => setAsk(null)}>Cancel</Btn>
            <Btn kind="primary" disabled={busy} onClick={() => void toggle(true)}>{busy ? "Enabling…" : readiness.incomplete ? "Enable anyway" : "Enable"}</Btn>
          </>}>
          <p style={{ marginTop: 0 }}>Students with incomplete required biodata will be restricted to the Biodata Completion page until their required information is completed.</p>
          <div className="b600 mt-2">Biodata go-live readiness</div>
          <Tiles cls="grid--4" items={[
            ["Total students", readiness.total.toLocaleString(), null],
            ["Complete", complete.toLocaleString(), "var(--green-ink)"],
            ["Incomplete", readiness.incomplete.toLocaleString(), readiness.incomplete ? "var(--red-ink)" : null],
            ["Completion", pct(complete, readiness.total), null],
          ]} />
          <div className="sub2">From the reading taken {when(readiness.computedAt)}.</div>
          {readiness.scoped ? <Note kind="info" title="These figures are for the faculty or department chosen">The gate applies to every student on the register.</Note> : null}
          {readiness.incomplete ? <Note kind="bad" title={`${readiness.incomplete.toLocaleString()} student${readiness.incomplete === 1 ? "" : "s"} still ha${readiness.incomplete === 1 ? "s" : "ve"} incomplete required biodata.`} /> : null}
          <Field id="bg-reason-on" label="Reason (optional)"><input id="bg-reason-on" className="ctl" value={reason} maxLength={500} onChange={(e) => setReason(e.target.value)} placeholder="e.g. Portal go-live" /></Field>
        </Modal>
      ) : null}
      {ask === "off" ? (
        <Modal title="Disable mandatory biodata completion?" onClose={() => setAsk(null)}
          foot={<>
            <Btn kind="ghost" onClick={() => setAsk(null)}>Cancel</Btn>
            <Btn kind="urgent" disabled={busy} onClick={() => void toggle(false)}>{busy ? "Disabling…" : "Disable"}</Btn>
          </>}>
          <p style={{ marginTop: 0 }}>Students will no longer be required to complete biodata before accessing the Student Dashboard.</p>
          <Field id="bg-reason-off" label="Reason (optional)"><input id="bg-reason-off" className="ctl" value={reason} maxLength={500} onChange={(e) => setReason(e.target.value)} /></Field>
        </Modal>
      ) : null}
    </Panel>
  );
}

/** the switch and the required items as they were changed, from the audit trail */
export function GateHistory({ admin }: { admin: ComplianceOverview }) {
  const labelOf = (item: string) => admin.requirements.find((r) => r.item === item)?.label ?? item;
  const rows = admin.history ?? [];
  return (
    <Panel title="History" right={<span className="sub2">Every change to the switch and the required items, from the audit trail</span>}>
      {rows.length ? (
        <DTable cols={["When", "Change", "By", "Office", "Reason", "From|num"]} rows={rows.map((h) => [
          <span key="w" className="sub2 tnum">{when(h.occurred_at)}</span>,
          <span key="c" className="b600">{h.subject_type === "people.biodata_gate"
            ? (h.was_enabled === h.now_enabled ? "Gate setting saved" : `Mandatory completion ${h.was_enabled === "true" ? "ON" : "OFF"} → ${h.now_enabled === "true" ? "ON" : "OFF"}`)
            : `${labelOf(h.item ?? "")}: ${h.now_required === "true" ? "required" : h.now_required === "false" ? "not required" : "removed"}`}</span>,
          <span key="b">{h.actor}</span>,
          <span key="o" className="sub2">{h.actor_office ?? "—"}</span>,
          <span key="r" className="sub2">{h.reason ?? "—"}</span>,
          <span key="ip" className="sub2 tnum">{h.source_ip ?? "—"}</span>,
        ])} texts={rows.map((h) => `${h.actor} ${h.item ?? ""} ${h.reason ?? ""}`)} />
      ) : <PBody><div className="sub2">No change recorded yet.</div></PBody>}
    </Panel>
  );
}

/** the items the gate requires: the photograph and the fields a student can enter; a JAMB or health field says why not */
/** V427: what requiring an item would do, over the students on the register */
interface ItemImpact { item: string; required: boolean; students: number; missing: number; newly_held: number; freed: number }

export function Requirements({ items, canSet, gateOn }: { items: Requirement[]; canSet: boolean; gateOn: boolean }) {
  const router = useRouter();
  const [busy, setBusy] = useState<string | null>(null);
  // V427: what each item would do, counted on the server over the register — read after the page, so the page never waits on it
  const [impact, setImpact] = useState<Record<string, ItemImpact> | null>(null);
  const [asking, setAsking] = useState<Requirement | null>(null);
  const sections = [...new Set(items.map((r) => r.section))];
  const n = items.filter((r) => r.required).length;
  const key = items.filter((r) => r.required).map((r) => r.item).join(",");

  useEffect(() => {
    let live = true;
    fetch(`${B}/requirements/impact`, { cache: "no-store" }).then((r) => (r.ok ? r.json() : [])).then((j: ItemImpact[]) => {
      if (live) setImpact(Object.fromEntries((Array.isArray(j) ? j : []).map((x) => [x.item, x])));
    }).catch(() => { if (live) setImpact({}); });
    return () => { live = false; };
  }, [key]);

  async function set(r: Requirement, required: boolean) {
    setBusy(r.item);
    try {
      const done = await send(`${B}/requirements/${encodeURIComponent(r.item)}`, "PUT", { required }, `${r.label} ${required ? "required" : "no longer required"}`);
      if (!done) return;
      notify(`${r.label}: ${required ? "required" : "no longer required"}`);
      setAsking(null);
      router.refresh();
    } finally {
      setBusy(null);
    }
  }

  /** ticking an item that would hold students who are complete now asks first, with the number */
  function tick(r: Requirement, required: boolean) {
    const x = impact?.[r.item];
    if (required && gateOn && x && x.newly_held > 0) { setAsking(r); return; }
    void set(r, required);
  }

  const students = impact ? Object.values(impact)[0]?.students ?? 0 : 0;
  const what = (r: Requirement) => {
    const x = impact?.[r.item];
    if (!x || r.refused) return null;
    return (
      <span className="sub2 tnum" style={{ display: "block", lineHeight: 1.35 }}>
        {x.missing.toLocaleString()} without it
        {r.required ? (x.freed ? <> · <b>frees {x.freed.toLocaleString()}</b> if not required</> : null)
          : (x.newly_held ? <> · <b style={{ color: "var(--red-ink)" }}>holds {x.newly_held.toLocaleString()} more</b> if required</> : null)}
      </span>
    );
  };

  return (
    <Panel title="Required biodata" right={<span className="sub2">{n} item{n === 1 ? "" : "s"} required{canSet ? " · changes apply at once" : ""}</span>}>
      <PBody>
        {canSet ? <div className="sub2">Make required only what the University needs. A field read from JAMB cannot be required (the student cannot enter it), and health information is given under consent, never required.</div> : null}
        <div className="sub2">{impact ? `Counted over the ${students.toLocaleString()} students on the register: how many lack each item, and what requiring it would change.` : "Counting what each item would change…"}</div>
        <div className="grid grid--3">
          {sections.map((sec) => (
            <div key={sec} className="stack" style={{ gap: 6 }}>
              <div className="eyebrow">{SECTION_LABEL[sec] ?? sec}</div>
              {items.filter((r) => r.section === sec).map((r) => canSet ? (
                <label key={r.item} className="row row--top" style={{ gap: 8, opacity: r.refused ? 0.6 : 1 }} title={r.refused ?? undefined}>
                  <input type="checkbox" style={{ marginTop: 3 }} checked={r.required} disabled={busy !== null || (!!r.refused && !r.required)} onChange={(e) => tick(r, e.target.checked)} />
                  <span>{r.label}{r.refused ? <span className="sub2"> — {r.refused}</span> : null}{what(r)}</span>
                </label>
              ) : r.required ? <div key={r.item} className="row row--top" style={{ gap: 8 }}><Pil kind="info">Required</Pil><span>{r.label}{what(r)}</span></div> : null)}
            </div>
          ))}
        </div>
      </PBody>
      {asking ? (
        <Modal title={`Require ${asking.label.toLowerCase()}?`} onClose={() => setAsking(null)}
          foot={<><Btn kind="ghost" onClick={() => setAsking(null)}>Cancel</Btn><Btn kind="primary" disabled={busy !== null} onClick={() => void set(asking, true)}>{busy ? "Saving…" : "Require it"}</Btn></>}>
          <p style={{ marginTop: 0 }}>
            <b>{(impact?.[asking.item]?.newly_held ?? 0).toLocaleString()}</b> student{(impact?.[asking.item]?.newly_held ?? 0) === 1 ? "" : "s"} whose required biodata is complete now
            would be held at the biodata page until they give it, because mandatory completion is ON.
            {" "}{(impact?.[asking.item]?.missing ?? 0).toLocaleString()} of the {students.toLocaleString()} students on the register lack it.
          </p>
        </Modal>
      ) : null}
    </Panel>
  );
}

/** a named student let through for a stated reason until a date — never more than 30 days, revoked when no longer needed */
/** a date some days after another, both as YYYY-MM-DD */
function plusDays(day: string, n: number): string {
  const d = new Date(`${day}T12:00:00Z`);
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
}

export function Exceptions({ rows, today }: { rows: GateException[]; today: string }) {
  const router = useRouter();
  const max = plusDays(today, 29);
  const [form, setForm] = useState({ number: "", reason: "", until: plusDays(today, 7) });
  const [revoking, setRevoking] = useState<GateException | null>(null);
  const [why, setWhy] = useState("");
  const [busy, setBusy] = useState(false);

  async function grant() {
    setBusy(true);
    try {
      const expires = new Date(`${form.until}T23:59:00`);
      const done = await send(`${B}/exceptions`, "POST", { number: form.number.trim(), reason: form.reason.trim(), expiresAt: expires.toISOString() },
        `Biodata gate exception for ${form.number.trim()}`);
      if (!done) return;
      notify(`Exception granted to ${form.number.trim()} until ${dayOnly(expires.toISOString())}`);
      setForm({ ...form, number: "", reason: "" });
      router.refresh();
    } finally {
      setBusy(false);
    }
  }

  async function revoke() {
    if (!revoking) return;
    setBusy(true);
    try {
      const done = await send(`${B}/exceptions/${revoking.id}/revoke`, "POST", { reason: why.trim() || null }, `Biodata gate exception revoked for ${revoking.number ?? revoking.name}`);
      if (!done) return;
      notify(`Exception revoked for ${revoking.name}`);
      setRevoking(null);
      setWhy("");
      router.refresh();
    } finally {
      setBusy(false);
    }
  }

  return (
    <Panel title="Exceptions" right={<span className="sub2">A named student let through for a stated reason, 30 days at most</span>}>
      <PBody>
        <div className="grid grid--3">
          <Field id="bx-number" label="Student number" hint="Matriculation, JAMB or admission number"><input id="bx-number" className="ctl tnum" value={form.number} onChange={(e) => setForm({ ...form, number: e.target.value })} /></Field>
          <Field id="bx-until" label="Until"><input id="bx-until" type="date" className="ctl" value={form.until} min={today} max={max} onChange={(e) => setForm({ ...form, until: e.target.value })} /></Field>
          <Field id="bx-reason" label="Reason"><input id="bx-reason" className="ctl" value={form.reason} maxLength={1000} onChange={(e) => setForm({ ...form, reason: e.target.value })} placeholder="Why this student needs access now" /></Field>
        </div>
        <div className="row mt-1"><Btn kind="primary" disabled={busy || !form.number.trim() || form.reason.trim().length < 5 || !form.until} onClick={() => void grant()}>{busy ? "Granting…" : "Grant exception"}</Btn></div>
      </PBody>
      {rows.length ? (
        <DTable cols={["Student", "Reason", "From", "Until", "Granted by", "State|mid", "|num"]} rows={rows.map((e) => [
          <span key="s"><b>{e.name}</b><div className="sub2 tnum">{e.number ?? ""}</div></span>,
          <span key="r" className="sub2">{e.reason}{e.revoke_reason ? ` · revoked: ${e.revoke_reason}` : ""}</span>,
          <span key="f" className="sub2 tnum">{dayOnly(e.starts_at)}</span>,
          <span key="u" className="sub2 tnum">{dayOnly(e.expires_at)}</span>,
          <span key="g" className="sub2">{e.granted_by} ({e.granted_office})</span>,
          <Pil key="st" kind={e.live ? "ok" : e.revoked_at ? "grey" : "warn"}>{e.live ? "Live" : e.revoked_at ? "Revoked" : new Date(e.starts_at) > new Date() ? "Not started" : "Ended"}</Pil>,
          !e.revoked_at && new Date(e.expires_at) > new Date() ? <Btn key="x" kind="ghost" size="sm" onClick={() => setRevoking(e)}>Revoke</Btn> : <span key="x" />,
        ])} texts={rows.map((e) => `${e.name} ${e.number ?? ""} ${e.reason}`)} />
      ) : <PBody><div className="sub2">No exception in the last 90 days.</div></PBody>}
      {revoking ? (
        <Modal title={`Revoke ${revoking.name}'s exception?`} onClose={() => setRevoking(null)}
          foot={<><Btn kind="ghost" onClick={() => setRevoking(null)}>Cancel</Btn><Btn kind="urgent" disabled={busy} onClick={() => void revoke()}>{busy ? "Revoking…" : "Revoke"}</Btn></>}>
          <p style={{ marginTop: 0 }}>The gate applies to the student again at once if their required biodata is incomplete.</p>
          <Field id="bx-why" label="Reason (optional)"><input id="bx-why" className="ctl" value={why} maxLength={1000} onChange={(e) => setWhy(e.target.value)} /></Field>
        </Modal>
      ) : null}
    </Panel>
  );
}
