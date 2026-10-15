"use client";
/** V482: whether registration refuses a course whose prerequisite the student has not passed — the Academic Office's rule.
 *  ADVISORY (as before: shown, never refused) or ENFORCED (the student's form and add/drop refuse it; ICT Support's override
 *  sets it aside on a ticket). Shown to every office that reads the structure checks; set only by the Academic Office. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, Panel, PBody, Pil } from "@/components/proto/ui";
import { Field } from "@/components/proto/blocks";

export interface PrerequisitePolicy {
  mode: "ADVISORY" | "ENFORCED" | string; changed_at: string | null; changed_office: string | null; changed_by: string | null; reason: string | null;
  recorded: number; courses: number;
}

const WORDS: Record<string, string> = {
  ADVISORY: "Advisory — a student sees which prerequisites they have not passed; registration never refuses on them.",
  ENFORCED: "Enforced — the student's form and add/drop refuse a course whose prerequisite has no published pass on the record; ICT Support's override sets it aside on the student's ticket.",
};

export function PrerequisiteRule({ policy, may }: { policy: PrerequisitePolicy; may: boolean }) {
  const router = useRouter();
  const [mode, setMode] = useState(policy.mode);
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);

  async function save() {
    setBusy(true);
    try {
      const why = reason.trim();
      const r = await fetch("/api/bff/api/v1/registration/prerequisite-policy", {
        method: "PUT", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Prerequisites at registration ${mode.toLowerCase()}: ${why}`) },
        body: JSON.stringify({ mode, reason: why }),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) { notifyProblem(j && typeof j === "object" && "status" in j ? j : { status: r.status, title: r.statusText }); return; }
      notify(`Prerequisites at registration: ${mode === "ENFORCED" ? "enforced" : "advisory"}`);
      setReason("");
      router.refresh();
    } finally { setBusy(false); }
  }

  return (
    <Panel title="Prerequisites at registration" right={<Pil kind={policy.mode === "ENFORCED" ? "bad" : "info"}>{policy.mode === "ENFORCED" ? "Enforced" : "Advisory"}</Pil>}>
      <PBody>
        <div className="sub2">{WORDS[policy.mode] ?? policy.mode}</div>
        <div className="sub2 mt-1">
          {policy.recorded} prerequisite{policy.recorded === 1 ? "" : "s"} recorded on {policy.courses} course{policy.courses === 1 ? "" : "s"}. A prerequisite counts as met by a
          published pass in the course (or its BSU-/MOAU- twin, or a code merged into it), and for a student who entered above its level.
          {policy.changed_at ? <> Set {new Date(policy.changed_at).toLocaleString("en-GB", { timeZone: "Africa/Lagos" })}{policy.changed_by ? ` by ${policy.changed_by}` : ""}{policy.reason ? ` — ${policy.reason}` : ""}.</> : null}
        </div>
        {may ? (
          <div className="row mt-2" style={{ alignItems: "flex-end", flexWrap: "wrap" }}>
            <Field id="pr-mode" label="Rule" style={{ flex: "0 1 220px" }}>
              <select id="pr-mode" className="ctl" value={mode} disabled={busy} onChange={(e) => setMode(e.target.value)}>
                <option value="ADVISORY">Advisory (shown only)</option>
                <option value="ENFORCED">Enforced (refused)</option>
              </select>
            </Field>
            <Field id="pr-why" label="Why" style={{ flex: "1 1 320px" }}>
              <input id="pr-why" className="ctl" value={reason} disabled={busy} maxLength={300} onChange={(e) => setReason(e.target.value)}
                placeholder="e.g. Senate decision on prerequisites, with its minute" />
            </Field>
            <Btn kind="primary" disabled={busy || mode === policy.mode || !reason.trim()} busyLabel="Saving…" onClick={() => void save()}>Set the rule</Btn>
          </div>
        ) : <div className="sub2 mt-1">The Academic Office sets this rule.</div>}
      </PBody>
    </Panel>
  );
}
