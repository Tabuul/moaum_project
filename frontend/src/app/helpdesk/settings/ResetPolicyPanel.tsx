"use client";

/** The desk's policy for a student's password reset to the default credential (V485): on or off, the lockout cleared unless the
 *  agent unticks it, a ticket optional or required, each agent's hourly limit (V526: none when left empty, the default), the
 *  statuses it may reach, (V528) the day's count of one agent's resets at which the Head is told, and (V563) the number of
 *  students above which a bulk reset waits for a Head's approval. The default credential
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
  // V526: empty is no limit (the default); a number from 1 to 500 limits each agent's resets in an hour
  const [hourly, setHourly] = useState(policy.hourly == null ? "" : String(policy.hourly));
  const [statuses, setStatuses] = useState<string[]>(policy.statuses);
  // V528: empty tells no one (the default); a number from 1 to 10,000 tells the Head once an agent a day when it is reached
  const [alertDaily, setAlertDaily] = useState(policy.alert_daily == null ? "" : String(policy.alert_daily));
  // V563: empty never waits; a number from 1 to 10,000 (V565) — a bulk reset of more students waits for a Head's approval
  const [bulkOver, setBulkOver] = useState(policy.bulk_approval_over == null ? "" : String(policy.bulk_approval_over));
  const bad = !statuses.length || (hourly !== "" && (!/^\d+$/.test(hourly) || Number(hourly) < 1 || Number(hourly) > 500))
    || (alertDaily !== "" && (!/^\d+$/.test(alertDaily) || Number(alertDaily) < 1 || Number(alertDaily) > 10000))
    || (bulkOver !== "" && (!/^\d+$/.test(bulkOver) || Number(bulkOver) < 1 || Number(bulkOver) > 10000));

  async function save() {
    const r = await fetch("/api/bff/api/v1/helpdesk/admin/settings/password-reset", {
      method: "PUT",
      headers: { "Content-Type": "application/json", "X-Reason": reasonHeader("Student support password reset policy saved") },
      body: JSON.stringify({ enabled, unlockByDefault: unlock, ticket, hourly: hourly === "" ? null : Number(hourly), statuses, alertDaily: alertDaily === "" ? null : Number(alertDaily),
        bulkApprovalOver: bulkOver === "" ? null : Number(bulkOver) }),
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
            <Field id="rp-hourly" label="Resets an agent may make in an hour" hint="Leave empty for no limit, or 1 to 500" style={{ width: 280 }}>
              <input id="rp-hourly" className="ctl tnum" inputMode="numeric" placeholder="No limit" value={hourly} onChange={(e) => setHourly(e.target.value.replace(/[^0-9]/g, ""))} />
            </Field>
            <Field id="rp-alert" label="Tell the Head when one agent's resets in a day reach" hint="Leave empty to tell no one. Nothing is refused." style={{ width: 340 }}>
              <input id="rp-alert" className="ctl tnum" inputMode="numeric" placeholder="Never" value={alertDaily} onChange={(e) => setAlertDaily(e.target.value.replace(/[^0-9]/g, ""))} />
            </Field>
            <Field id="rp-bulk" label="A bulk reset of more students than this waits for approval" hint="By the Head of the Support Desk or the Director of ICT, never the one who asked. Empty: never waits; 1 to 10,000." style={{ width: 380 }}>
              <input id="rp-bulk" className="ctl tnum" inputMode="numeric" placeholder="Never" value={bulkOver} onChange={(e) => setBulkOver(e.target.value.replace(/[^0-9]/g, ""))} />
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
