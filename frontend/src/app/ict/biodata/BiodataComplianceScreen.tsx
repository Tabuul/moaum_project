"use client";

/**
 * V423 — Biodata compliance: the ICT Director's switch for mandatory student biodata completion (OFF until the University
 * goes live), the readiness the switch is turned on against, what is missing and where, the items required, the
 * exceptions and the history. Every number is counted on the server within the office's scope; the switch, the
 * requirements and the exceptions are the ICT Director's (or an administrator's) and the API refuses anyone else.
 */
import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { Btn, LinkBtn, Note, PageHead, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { notify, notifyProblem } from "@/components/proto/Toast";
import type { Ceiling, ScopeStructure } from "@/components/proto/ScopeBar";
import { reasonHeader } from "@/lib/reason";
import type { Problem } from "@/lib/api";
import { SECTION_LABEL, pct, type ComplianceOverview, type GateException, type Requirement } from "@/lib/biodata-gate";
import { ComplianceFilterBar, filterQuery, type ComplianceFilters } from "./ComplianceFilterBar";

const B = "/api/bff/api/v1/biodata-compliance";
const when = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleString("en-GB", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" }) : "—");
const dayOnly = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" }) : "—");

async function send(path: string, method: string, body: unknown, why: string): Promise<unknown | null> {
  const r = await fetch(path, { method, headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(why) }, body: JSON.stringify(body) });
  const j = await r.json().catch(() => null);
  if (!r.ok) { notifyProblem((j as Problem) ?? { status: r.status, title: r.statusText }); return null; }
  return j ?? {};
}

export function BiodataComplianceScreen({ data, filters, structure, sessions, ceiling }: {
  data: ComplianceOverview; filters: ComplianceFilters; structure: ScopeStructure; sessions: string[]; ceiling: Ceiling;
}) {
  const router = useRouter();
  const [ask, setAsk] = useState<"on" | "off" | null>(null);
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);
  const g = data.gate;
  const sum = data.summary;
  const labelOf = (item: string) => data.requirements.find((r) => r.item === item)?.label ?? item;
  const sectionOf = (item: string) => data.requirements.find((r) => r.item === item)?.section ?? "";
  const list = (more: Record<string, string>) => `/ict/biodata/students?${filterQuery(filters, more)}`;

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
    <>
      <PageHead description={`${sum.total.toLocaleString()} students on the register in this view · ${pct(sum.complete, sum.total)} with their required biodata complete`}
        actions={<>
          <LinkBtn kind="primary" href={list({ status: "INCOMPLETE" })}>View incomplete students</LinkBtn>
          <LinkBtn href={list({})}>View compliance report</LinkBtn>
        </>} />

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
            {data.canSet ? (
              <div className="row row--tight">
                {g.enabled ? <Btn kind="urgent" onClick={() => setAsk("off")}>Turn off</Btn> : <Btn kind="primary" onClick={() => setAsk("on")}>Turn on</Btn>}
              </div>
            ) : null}
          </div>
        </PBody>
      </Panel>

      <ComplianceFilterBar filters={filters} structure={structure} sessions={sessions} ceiling={ceiling} />

      <Tiles items={[
        ["Total students", sum.total.toLocaleString(), null, "On the register: admitted, active, on probation or deferred", list({})],
        ["Biodata complete", sum.complete.toLocaleString(), "var(--green-ink)", "Every required item given", list({ status: "COMPLETE" })],
        ["Biodata incomplete", sum.incomplete.toLocaleString(), sum.incomplete ? "var(--red-ink)" : null, "At least one required item missing", list({ status: "INCOMPLETE" })],
        ["Completion", `${sum.percent.toFixed(2)}%`, null, `${data.requirements.filter((r) => r.required).length} items required`],
      ]} />

      <div className="grid grid--2">
        <Panel title="What is missing" right={<span className="sub2">Students missing each required item</span>}>
          {sum.items.length ? (
            <DTable pageSize={0} cols={["Item", "Section", "Students|num", "Share|num", "|num"]} rows={sum.items.map((x) => [
              <span key="i" className="b600">{labelOf(x.item)}</span>,
              <span key="s" className="sub2">{SECTION_LABEL[sectionOf(x.item)] ?? "—"}</span>,
              <span key="n" className="tnum">{x.missing.toLocaleString()}</span>,
              <span key="p" className="tnum sub2">{pct(x.missing, sum.total)}</span>,
              <LinkBtn key="l" size="sm" href={list({ status: "INCOMPLETE", missing: x.item })}>Students</LinkBtn>,
            ])} texts={sum.items.map((x) => labelOf(x.item))} />
          ) : <PBody><div className="sub2">Nothing is missing in this view.</div></PBody>}
        </Panel>

        <Panel title="Old portal and this portal" right={<span className="sub2">Before the gate is turned on</span>}>
          <DTable pageSize={0} cols={["Students", "Total|num", "Complete|num", "Incomplete|num", "Completion|num"]} rows={sum.origin.map((o) => [
            <span key="o" className="b600">{o.origin === "MIGRATED" ? "Brought from the old portal" : "Admitted on this portal"}</span>,
            <span key="t" className="tnum">{o.total.toLocaleString()}</span>,
            <span key="c" className="tnum">{o.complete.toLocaleString()}</span>,
            <span key="i" className="tnum">{(o.total - o.complete).toLocaleString()}</span>,
            <span key="p" className="tnum">{pct(o.complete, o.total)}</span>,
          ])} />
          <PBody><div className="sub2">A student brought from the old portal has no admission on this one. Their record is read as it stands: what the old portal carried counts only where it fills a required item.</div></PBody>
        </Panel>
      </div>

      <Panel title={filters.fac ? "By department" : "By faculty"}>
        {(filters.fac ? sum.departments.filter((d) => d.faculty === filters.fac) : sum.faculties).length ? (
          <DTable pageSize={0} cols={[filters.fac ? "Department" : "Faculty", "Students|num", "Complete|num", "Incomplete|num", "Completion|num", "|num"]}
            rows={(filters.fac ? sum.departments.filter((d) => d.faculty === filters.fac) : sum.faculties).map((x) => [
              <span key="n" className="b600">{x.name}</span>,
              <span key="t" className="tnum">{x.total.toLocaleString()}</span>,
              <span key="c" className="tnum">{x.complete.toLocaleString()}</span>,
              <span key="i" className="tnum">{(x.total - x.complete).toLocaleString()}</span>,
              <span key="p" className="tnum">{pct(x.complete, x.total)}</span>,
              x.code ? <LinkBtn key="l" size="sm" href={list(filters.fac ? { dept: x.code, status: "INCOMPLETE" } : { fac: x.code, status: "INCOMPLETE" })}>Incomplete</LinkBtn> : <span key="l" />,
            ])} texts={(filters.fac ? sum.departments : sum.faculties).map((x) => x.name)} />
        ) : <PBody><div className="sub2">No student in this view.</div></PBody>}
      </Panel>

      <Requirements items={data.requirements} canSet={data.canSet} gateOn={g.enabled} />
      {data.canSet ? <Exceptions rows={data.exceptions ?? []} today={data.today} /> : null}
      {data.canSet ? (
        <Panel title="History" right={<span className="sub2">Every change, from the audit trail</span>}>
          {(data.history ?? []).length ? (
            <DTable cols={["When", "Change", "By", "Office", "Reason", "From|num"]} rows={(data.history ?? []).map((h) => [
              <span key="w" className="sub2 tnum">{when(h.occurred_at)}</span>,
              <span key="c" className="b600">{h.subject_type === "people.biodata_gate"
                ? (h.was_enabled === h.now_enabled ? "Gate setting saved" : `Mandatory completion ${h.was_enabled === "true" ? "ON" : "OFF"} → ${h.now_enabled === "true" ? "ON" : "OFF"}`)
                : `${labelOf(h.item ?? "")}: ${h.now_required === "true" ? "required" : h.now_required === "false" ? "not required" : "removed"}`}</span>,
              <span key="b">{h.actor}</span>,
              <span key="o" className="sub2">{h.actor_office ?? "—"}</span>,
              <span key="r" className="sub2">{h.reason ?? "—"}</span>,
              <span key="ip" className="sub2 tnum">{h.source_ip ?? "—"}</span>,
            ])} texts={(data.history ?? []).map((h) => `${h.actor} ${h.item ?? ""} ${h.reason ?? ""}`)} />
          ) : <PBody><div className="sub2">No change recorded yet.</div></PBody>}
        </Panel>
      ) : null}

      {ask === "on" ? (
        <Modal title="Enable mandatory biodata completion?" onClose={() => setAsk(null)}
          foot={<>
            <Btn kind="ghost" onClick={() => setAsk(null)}>Cancel</Btn>
            <Btn kind="primary" disabled={busy} onClick={() => void toggle(true)}>{busy ? "Enabling…" : sum.incomplete ? "Enable anyway" : "Enable"}</Btn>
          </>}>
          <p style={{ marginTop: 0 }}>Students with incomplete required biodata will be restricted to the Biodata Completion page until their required information is completed.</p>
          <div className="b600 mt-2">Biodata go-live readiness</div>
          <Tiles cls="grid--4" items={[
            ["Total students", sum.total.toLocaleString(), null],
            ["Complete", sum.complete.toLocaleString(), "var(--green-ink)"],
            ["Incomplete", sum.incomplete.toLocaleString(), sum.incomplete ? "var(--red-ink)" : null],
            ["Completion", `${sum.percent.toFixed(2)}%`, null],
          ]} />
          {filters.fac || filters.dept || filters.prog || filters.level || filters.session || filters.sex
            ? <Note kind="info" title="These figures are for the filtered view">The gate applies to every student on the register, whatever the filter.</Note> : null}
          {sum.incomplete ? <Note kind="bad" title={`${sum.incomplete.toLocaleString()} student${sum.incomplete === 1 ? "" : "s"} still ha${sum.incomplete === 1 ? "s" : "ve"} incomplete required biodata.`} /> : null}
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
    </>
  );
}

/** the items the gate requires: the photograph and the fields a student can enter; a JAMB or health field says why not */
/** V427: what requiring an item would do, over the students on the register */
interface ItemImpact { item: string; required: boolean; students: number; missing: number; newly_held: number; freed: number }

function Requirements({ items, canSet, gateOn }: { items: Requirement[]; canSet: boolean; gateOn: boolean }) {
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

function Exceptions({ rows, today }: { rows: GateException[]; today: string }) {
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
