"use client";

/**
 * V749: "UPDATE YOUR BLOOD GROUP INFORMATION" — asked on the dashboard of every student, and every member of staff, whose blood
 * group is missing or not confirmed. The person chooses one of the eight groups and confirms it is accurate; the server checks
 * it, keeps it on the person's own record with the time and the confirmation (credentials.confirm_my_blood_group) and only then
 * does the dialog close. A refusal keeps it open with the reason. It can be closed for this visit (×, Escape, a click beside it);
 * nothing remembers that, so the next visit to the dashboard asks again until it is saved. The identity card reads the group from
 * the record; the student's card is not printed until it is confirmed.
 */
import { useState, useSyncExternalStore } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { BLOOD_GROUPS, bloodGroupOf, canSaveBloodGroup } from "@/lib/identity";
import { Field, Modal } from "@/components/proto/blocks";
import { Btn } from "@/components/proto/ui";
import { notify } from "@/components/proto/Toast";
import { ProblemNotice } from "@/components/ProblemNotice";

/** iam/me: the value on the record that is not confirmed, or none */
export interface BloodGroupPromptData { current?: string | null }

export type BloodGroupHolder = "STUDENT" | "STAFF";

/** the holder's own door: the student's (PUT /me/blood-group) or the member of staff's (PUT /staff/identity/blood-group) — the
 *  server takes the person from the signed-in token, never from here */
const DOOR: Record<BloodGroupHolder, string> = {
  STUDENT: "/api/bff/api/v1/me/blood-group",
  STAFF: "/api/bff/api/v1/staff/identity/blood-group",
};

/** the form — the dialog's body, and the BLOOD GROUP section of the staff identity page */
export function BloodGroupForm({ kind, current, onSaved, onBusy, idPrefix = "bg" }: {
  kind: BloodGroupHolder;
  current: string | null;
  /** after the server has confirmed the save: the group it recorded and when */
  onSaved: (group: string, confirmedAt: string | null) => void;
  /** the save under way, or over — the dialog is not closed while it is */
  onBusy?: (busy: boolean) => void;
  idPrefix?: string;
}) {
  const [group, setGroup] = useState<string>(() => bloodGroupOf(current));
  const [confirmed, setConfirmed] = useState(false);
  const [busy, setBusyState] = useState(false);
  const setBusy = (b: boolean) => { setBusyState(b); onBusy?.(b); };
  const [problem, setProblem] = useState<Problem | null>(null);

  async function save() {
    if (busy || !canSaveBloodGroup(group, confirmed)) return;
    setBusy(true);
    setProblem(null);
    try {
      const r = await fetch(DOOR[kind], {
        method: "PUT",
        headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Blood group ${group} confirmed by the ${kind === "STUDENT" ? "student" : "holder"}`) },
        body: JSON.stringify({ bloodGroup: group, confirmed: true }),
      });
      const j = (await r.json().catch(() => null)) as (Problem & { bloodGroup?: string; confirmedAt?: string }) | null;
      if (!r.ok) {
        setProblem(j && typeof j === "object" ? { ...j, status: j.status ?? r.status } : { status: r.status, title: r.statusText || "The blood group was not saved" });
        return;
      }
      const saved = j?.bloodGroup ?? group;
      // a later change is confirmed afresh
      setConfirmed(false);
      notify(`Blood group ${saved} saved and confirmed`);
      onSaved(saved, j?.confirmedAt ?? null);
    } catch {
      setProblem({ status: 0, title: "The portal could not reach the server", detail: "Check your connection and try again; nothing was saved." });
    } finally {
      setBusy(false);
    }
  }

  return (
    <form className="stack" style={{ gap: "var(--s-3)" }} onSubmit={(e) => { e.preventDefault(); void save(); }} aria-busy={busy || undefined}>
      <Field id={`${idPrefix}-group`} label="Blood group" required>
        <select id={`${idPrefix}-group`} className="ctl" required value={group} disabled={busy} onChange={(e) => { setGroup(e.target.value); setProblem(null); }} style={{ maxWidth: 220 }}>
          <option value="">Choose your blood group…</option>
          {BLOOD_GROUPS.map((g) => <option key={g} value={g}>{g}</option>)}
        </select>
      </Field>
      <label className="row row--inline row--tight" style={{ alignItems: "flex-start" }}>
        <input type="checkbox" required checked={confirmed} disabled={busy} onChange={(e) => { setConfirmed(e.target.checked); setProblem(null); }} style={{ marginTop: 3 }} />
        <span>I confirm that the blood group information supplied is accurate.</span>
      </label>
      {problem ? <ProblemNotice problem={problem} /> : null}
      <div className="row row--tight">
        <Btn kind="primary" type="submit" disabled={!canSaveBloodGroup(group, confirmed)} busy={busy} busyLabel="Saving…">SAVE BLOOD GROUP</Btn>
      </div>
    </form>
  );
}

const noSubscription = () => () => {};

/** the dashboard's dialog (Shell): drawn in the browser only, so the server's page and the one that hydrates agree; open from the
 *  moment it is drawn until the person closes it for this visit or the server has saved the group */
export function BloodGroupPrompt({ kind, current }: { kind: BloodGroupHolder; current: string | null }) {
  const router = useRouter();
  const inBrowser = useSyncExternalStore(noSubscription, () => true, () => false);
  const [open, setOpen] = useState(true);
  // while the save is under way the dialog stays: its answer is shown where it was asked (the × as much as Escape or a click beside it)
  const [saving, setSaving] = useState(false);
  if (!inBrowser || !open) return null;
  return (
    <Modal title="UPDATE YOUR BLOOD GROUP INFORMATION" sub={kind === "STUDENT" ? "Needed for your identity card" : "Needed for your staff identity card"}
      onClose={() => { if (!saving) setOpen(false); }}>
      <p style={{ marginTop: 0 }}>
        Your blood group is printed on your {kind === "STUDENT" ? "student" : "staff"} identity card and helps in a medical emergency. The University
        has no confirmed blood group for you. Choose yours from the list and confirm that it is accurate; it is kept on your own record with the time you
        confirmed it.
        {kind === "STUDENT" ? " Your identity card is not printed until your blood group is confirmed." : ""}
      </p>
      {current && bloodGroupOf(current) ? <p className="sub2" style={{ marginTop: 0 }}>Your record shows {bloodGroupOf(current)}, not yet confirmed. Check it before you save.</p> : null}
      <BloodGroupForm kind={kind} current={current} idPrefix="bgp" onBusy={setSaving}
        onSaved={() => { setOpen(false); router.refresh(); }} />
    </Modal>
  );
}
