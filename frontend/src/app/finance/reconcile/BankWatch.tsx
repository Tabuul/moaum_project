"use client";

/** V569: the bank matching's morning alerts, as they read now — a month not reconciled by the set day (to the Bursar), a credit for a
 *  reference never confirmed not sent to the bank credits (to the Bursar and the Students Account Officer), a payment confirmed on the
 *  portal and not in the bank (to Internal Audit) — each told once. The Bursary sets the days, or switches the alerts off. */
import { useEffect, useState } from "react";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, Panel, PBody, Pil, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal, money } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { bankWatchGroups, type BankWatch as Watch } from "@/lib/bank-watch";

const ACCOUNT: Record<string, string> = { "1010": "1010 Bank — Fees collection", "1020": "1020 Bank — Disbursements" };
const monthOf = (iso: string) => new Date(`${iso}T12:00:00Z`).toLocaleDateString("en-GB", { month: "long", year: "numeric", timeZone: "UTC" });
const dayOf = (iso: string) => new Date(`${iso}T12:00:00Z`).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric", timeZone: "UTC" });

export function BankWatch({ canSet }: { canSet: boolean }) {
  const [w, setW] = useState<Watch | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [form, setForm] = useState<{ enabled: boolean; reconDay: string; creditHours: string; missingDays: string } | null>(null);

  useEffect(() => {
    let live = true;
    fetch("/api/bff/api/v1/finance/bank-reconciliation/watch", { cache: "no-store" })
      .then(async (r) => ({ ok: r.ok, status: r.status, title: r.statusText, j: await r.json().catch(() => null) }))
      .catch(() => ({ ok: false, status: 0, title: "The portal could not reach the server", j: null }))
      .then((x) => {
        if (!live) return;
        if (x.ok) setW(x.j as Watch);
        else setProblem(x.j ?? { status: x.status, title: x.title });
      });
    return () => { live = false; };
  }, []);

  async function save() {
    if (!form) return;
    const r = await fetch("/api/bff/api/v1/finance/bank-reconciliation/watch", { method: "PUT",
      headers: { "Content-Type": "application/json", "X-Reason": reasonHeader("Bank matching alerts set") },
      body: JSON.stringify({ enabled: form.enabled, reconDay: Number(form.reconDay), creditHours: Number(form.creditHours), missingDays: Number(form.missingDays) }) });
    const j = await r.json().catch(() => null);
    if (!r.ok) { const refusal = j ?? { status: r.status, title: r.statusText }; setProblem(refusal); notifyProblem(refusal); return; }
    setW(j as Watch);
    setForm(null);
    notify("The bank matching alerts are set");
  }

  if (problem && !w) return <ProblemNotice problem={problem} />;
  if (!w) return <Panel title="Reminders"><PBody><div className="sub2">Reading what the morning alerts would say…</div></PBody></Panel>;
  const s = w.setting;
  const groups = bankWatchGroups(w.missing);
  // the latest month first: what is due now before what was missed long ago
  const overdue = [...w.overdue].sort((a, b) => b.month.localeCompare(a.month) || a.account.localeCompare(b.account));
  const valid = form && Number(form.reconDay) >= 1 && Number(form.reconDay) <= 28 && Number(form.creditHours) >= 1 && Number(form.creditHours) <= 336
    && Number(form.missingDays) >= 1 && Number(form.missingDays) <= 60;
  return (
    <>
      {problem ? <ProblemNotice problem={problem} /> : null}
      <Panel title="Reminders" right={<span className="row row--tight">
        <Pil kind={s.enabled ? "ok" : "grey"}>{s.enabled ? "Each morning at 08:20" : "Off"}</Pil>
        {canSet ? <Btn kind="ghost" size="sm" onClick={() => setForm({ enabled: s.enabled, reconDay: String(s.recon_day), creditHours: String(s.credit_hours), missingDays: String(s.missing_days) })}>Change</Btn> : null}
      </span>}>
        <PBody><div className="sub2">
          Each is told once to the office whose act it is, by e-mail and on the portal: a month with no signed reconciliation by the {s.recon_day}th of the next to the Bursar;
          a credit for a reference never confirmed, not sent to the bank credits {s.credit_hours} hours after its statement came, to the Bursar and the Students Account Officer;
          a payment confirmed on the portal that the statements do not show {s.missing_days} days after it, to Internal Audit.
          {s.set_by_name ? ` Set by ${s.set_by_name}.` : ""}
        </div></PBody>
        <PBody><div className="b600">Months not reconciled · {w.overdue.length}</div></PBody>
        {overdue.length ? (
          <DTable cols={["Account", "Month", "Due by|mid", "Late|num"]} rows={overdue.map((o) => [
            <span key="a">{ACCOUNT[o.account] ?? o.account}</span>, <span key="m">{monthOf(o.month)}</span>,
            <span key="d" className="tnum">{dayOf(o.due_on)}</span>, <span key="l" className="tnum">{o.days_late} day{o.days_late === 1 ? "" : "s"}</span>,
          ])} />
        ) : <PBody><div className="sub2">Every month due is reconciled and signed.</div></PBody>}
        <PBody><div className="b600">Credits for references never confirmed · {w.credits.length}</div></PBody>
        {w.credits.length ? (
          <DTable cols={["Payer", "Reference", "Statement", "Amount|num", "Waiting|num"]} rows={w.credits.map((c) => [
            <Two key="p" a={c.payer ?? "Payer unknown"} b={c.number ?? ""} />, <span key="r" className="tnum">{c.reference}</span>,
            <span key="s" className="sub2">{c.statement}, line {c.line_no}{c.value_date ? ` · ${dayOf(c.value_date)}` : ""}</span>,
            <b key="a" className="tnum">{money(Number(c.amount))}</b>, <span key="h" className="tnum">{c.hours} h</span>,
          ])} texts={w.credits.map((c) => `${c.reference} ${c.payer ?? ""} ${c.number ?? ""}`)} />
        ) : <PBody><div className="sub2">No credit for a never-confirmed reference is waiting: each was sent to the bank credits.</div></PBody>}
        <PBody><div className="b600">Confirmed on the portal, not in the bank · {w.missing.length}</div></PBody>
        {groups.length ? (
          <DTable cols={["Channel", "Day|mid", "Payments|num", "Amount|num"]} rows={groups.map((g) => [
            <span key="c">{g.channel}</span>, <span key="d" className="tnum">{dayOf(g.day)}</span>, <span key="n" className="tnum">{g.payments}</span>,
            <b key="a" className="tnum">{money(g.amount)}</b>,
          ])} />
        ) : <PBody><div className="sub2">Every payment confirmed through the bank, up to {s.missing_days} days before the latest statement, is on a statement.</div></PBody>}
      </Panel>
      {form ? (
        <Modal title="Reminders" onClose={() => setForm(null)}
          foot={<><Btn kind="ghost" onClick={() => setForm(null)}>Cancel</Btn><Btn kind="primary" busyLabel="Saving..." disabled={!valid} onClick={() => save()}>Save</Btn></>}>
          <label className="row row--inline row--tight"><input type="checkbox" className="chk" checked={form.enabled} onChange={(e) => setForm({ ...form, enabled: e.target.checked })} /> Send the morning alerts</label>
          <Field id="bw-day" label="A month is reconciled by this day of the next" required hint="1 to 28">
            <input id="bw-day" className="ctl" inputMode="numeric" value={form.reconDay} onChange={(e) => setForm({ ...form, reconDay: e.target.value.replace(/\D/g, "") })} />
          </Field>
          <Field id="bw-hours" label="A credit for a never-confirmed reference waits (hours)" required hint="1 to 336">
            <input id="bw-hours" className="ctl" inputMode="numeric" value={form.creditHours} onChange={(e) => setForm({ ...form, creditHours: e.target.value.replace(/\D/g, "") })} />
          </Field>
          <Field id="bw-days" label="A confirmed payment reaches the bank within (days)" required hint="1 to 60">
            <input id="bw-days" className="ctl" inputMode="numeric" value={form.missingDays} onChange={(e) => setForm({ ...form, missingDays: e.target.value.replace(/\D/g, "") })} />
          </Field>
        </Modal>
      ) : null}
    </>
  );
}
