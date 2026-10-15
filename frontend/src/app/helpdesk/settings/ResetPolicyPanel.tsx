"use client";

/** The desk's policy for a student's password reset to the default credential (V485): on or off, the lockout cleared unless the
 *  agent unticks it, a ticket optional or required, each agent's hourly limit, and the statuses it may reach. The default credential
 *  is the matriculation number and the change at the next sign-in is always forced — neither is a setting. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, Note, Panel, PBody } from "@/components/proto/ui";
import { Field } from "@/components/proto/blocks";
import type { ResetPolicy } from "@/lib/password-reset";

const STATUSES: [string, string][] = [["ACTIVE", "Active"], ["PROBATION", "On probation"], ["DEFERRED", "Deferred"], ["DORMANT", "Dormant"], ["GRADUATED", "Graduated (alumni)"], ["SUSPENDED", "Suspended"]];

export function ResetPolicyPanel({ policy }: { policy: ResetPolicy }) {
  const router = useRouter();
  const [enabled, setEnabled] = useState(policy.enabled);
  const [unlock, setUnlock] = useState(policy.unlock_by_default);
  const [ticket, setTicket] = useState(policy.ticket);
  const [hourly, setHourly] = useState(String(policy.hourly));
  const [statuses, setStatuses] = useState<string[]>(policy.statuses);
  const bad = !statuses.length || !/^\d+$/.test(hourly) || Number(hourly) < 1 || Number(hourly) > 500;

  async function save() {
    const r = await fetch("/api/bff/api/v1/helpdesk/admin/settings/password-reset", {
      method: "PUT",
      headers: { "Content-Type": "application/json", "X-Reason": reasonHeader("Student support password reset policy saved") },
      body: JSON.stringify({ enabled, unlockByDefault: unlock, ticket, hourly: Number(hourly), statuses }),
    });
    if (!r.ok) { notifyProblem((await r.json().catch(() => null)) ?? { status: r.status, title: r.statusText }); return; }
    notify("Student support password reset policy saved");
    router.refresh();
  }

  return (
    <Panel title="Student support password reset" right="The default student credential">
      <PBody>
        <div className="stack">
          <label className="row row--tight"><input type="checkbox" className="chk" checked={enabled} onChange={(e) => setEnabled(e.target.checked)} /> <span>Enabled: ICT Support may reset a student&rsquo;s password to the default credential</span></label>
          <div className="grid grid--2">
            <div className="kv"><span className="k">Default student password</span><span className="v">Matriculation number</span></div>
            <div className="kv"><span className="k">Force password change</span><span className="v">Yes, always</span></div>
            <div className="kv"><span className="k">Require support reason</span><span className="v">Yes, always (10 characters or more)</span></div>
          </div>
          <label className="row row--tight"><input type="checkbox" className="chk" checked={unlock} onChange={(e) => setUnlock(e.target.checked)} /> <span>Unlock the account with the reset unless the agent unticks it</span></label>
          <div className="row">
            <Field id="rp-ticket" label="Support ticket" style={{ width: 200 }}>
              <select id="rp-ticket" className="ctl" value={ticket} onChange={(e) => setTicket(e.target.value)}>
                <option value="OPTIONAL">Optional</option>
                <option value="REQUIRED">Required</option>
              </select>
            </Field>
            <Field id="rp-hourly" label="Resets an agent may make in an hour" hint="1 to 500" style={{ width: 240 }}>
              <input id="rp-hourly" className="ctl tnum" inputMode="numeric" value={hourly} onChange={(e) => setHourly(e.target.value.replace(/[^0-9]/g, ""))} />
            </Field>
          </div>
          <Field id="rp-statuses" label="Student statuses the reset may reach">
            <div className="row" style={{ flexWrap: "wrap", gap: 12 }}>
              {STATUSES.map(([code, word]) => (
                <label key={code} className="row row--inline row--tight">
                  <input type="checkbox" className="chk" checked={statuses.includes(code)}
                    onChange={(e) => setStatuses(e.target.checked ? [...statuses, code] : statuses.filter((x) => x !== code))} /> {word}
                </label>
              ))}
            </div>
          </Field>
          <Note kind="info" title="Never reached by a desk reset">A withdrawn, expelled, transferred-out, deceased or rusticated student, or one not yet matriculated. Such a student goes to the Registry.</Note>
          <div className="row"><Btn kind="primary" disabled={bad} busyLabel="SAVING..." onClick={() => save()}>Save the reset policy</Btn>{!statuses.length ? <span className="sub2">Choose at least one status.</span> : null}</div>
        </div>
      </PBody>
    </Panel>
  );
}
