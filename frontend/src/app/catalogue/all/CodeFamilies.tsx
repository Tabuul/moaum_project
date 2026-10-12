"use client";

/** V402: the University's course codes are moving from BSU- to MOAU-. Both codes stay in the catalogue and on offer, and nothing
 *  is linked: a student is shown their cohort's code — MOAU- for the cohorts admitted from the entry session stated here, BSU-
 *  for the cohorts before it, until they graduate (a carry-over keeps the code it was failed under). Stated by a central office. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import { Btn, Panel, PBody } from "@/components/proto/ui";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { reasonHeader } from "@/lib/reason";

export interface CodeFamilies {
  moau_from_entry_session: string | null; stated_at: string | null; stated_by: string | null;
  pairs: number; linked_pairs: number; current_session: string | null;
}

/** V413: a registration line holding the other family's code of a course the student's cohort registers under its own */
export interface CodeFamilyMismatch {
  registration_id: string; student_id: string; matric_no: string | null; surname: string; other_names: string | null; level: number; registration_status: string;
  semester: number; course_code: string; offering_id: string; own_code: string | null; own_offering_id: string | null; scored: boolean;
}

export function CodeFamiliesPanel({ data, sessions, maySet, mismatches = [] }: { data: CodeFamilies; sessions: string[]; maySet: boolean; mismatches?: CodeFamilyMismatch[] }) {
  const router = useRouter();
  const current = data.moau_from_entry_session ?? "";
  const [value, setValue] = useState(current);
  const [busy, setBusy] = useState(false);
  const options = [...new Set([...(current ? [current] : []), ...sessions])].sort();

  async function move(m: CodeFamilyMismatch) {
    setBusy(true);
    try {
      const r = await fetch("/api/bff/api/v1/catalogue/code-families/mismatches/move", {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`${m.matric_no ?? m.surname}: ${m.course_code} moved to ${m.own_code}`) },
        body: JSON.stringify({ registrationId: m.registration_id, offeringId: m.offering_id, reason: "Registered before the cohort rule; moved to the cohort's code" }),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) { notifyProblem(j ?? { status: r.status, title: r.statusText }); return; }
      notify(`${m.matric_no ?? m.surname}: ${m.course_code} moved to ${m.own_code}`);
      router.refresh();
    } finally {
      setBusy(false);
    }
  }

  async function save() {
    setBusy(true);
    try {
      const r = await fetch("/api/bff/api/v1/catalogue/code-families", {
        method: "PUT",
        headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(value ? `MOAU- codes from the cohort admitted in ${value}` : "Code families unstated: both codes reach everyone") },
        body: JSON.stringify({ moauFromEntrySession: value || null }),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) { notifyProblem(j ?? { status: r.status, title: r.statusText }); return; }
      notify(value ? `Cohorts admitted from ${value} register MOAU- codes; earlier cohorts BSU-` : "Both codes reach every student until the rule is stated");
      router.refresh();
    } finally {
      setBusy(false);
    }
  }

  return (
    <Panel title="BSU- and MOAU- codes" right={`${data.pairs} course${data.pairs === 1 ? "" : "s"} under both codes`}>
      <PBody>
        <div className="sub2 mb-2">
          The University&rsquo;s codes are moving from <b>BSU-</b> to <b>MOAU-</b>. Both stay in the catalogue and on offer, and nothing is linked:
          a student is shown their cohort&rsquo;s code — <b>MOAU-</b> for the cohorts admitted from the session stated here, <b>BSU-</b> for the
          cohorts before it, until they graduate. A carry-over keeps the code it was failed under. A course whose other code is not on offer
          reaches everyone.
        </div>
        <div className="row row--inline row--tight">
          <label className="sub2" htmlFor="cf-from">MOAU- codes from the cohort admitted in</label>
          <select id="cf-from" className="ctl" value={value} onChange={(e) => setValue(e.target.value)} disabled={!maySet || busy}>
            <option value="">Not stated — both codes reach everyone</option>
            {options.map((s) => <option key={s} value={s}>{s}</option>)}
          </select>
          {maySet ? <Btn kind="secondary" size="sm" disabled={busy || value === current} onClick={() => void save()}>{busy ? "Saving…" : "Set the rule"}</Btn> : null}
        </div>
        <div className="sub2 mt-1">
          {data.stated_at
            ? `Stated ${new Date(data.stated_at).toLocaleDateString("en-GB")}${data.stated_by ? ` by ${data.stated_by}` : ""}.`
            : current ? "Set up as the cohort now in 200 level; the Academic Office confirms or changes it here." : "Not yet stated."}
          {data.linked_pairs ? ` ${data.linked_pairs} pair${data.linked_pairs === 1 ? " is" : "s are"} still linked from before; a department unlinks its own on Department courses.` : ""}
        </div>
        {mismatches.length ? (
          <div className="mt-2">
            <div className="b600">{mismatches.length} registration line{mismatches.length === 1 ? "" : "s"} in {data.current_session ?? "this session"} under the other family&rsquo;s code</div>
            <div className="sub2 mb-1">Students registered before the rule. Each line is moved to the cohort&rsquo;s class of the same semester, opened if it is not yet; a line with a score already on it is left for the Examinations Office.</div>
            {mismatches.map((m) => (
              <div key={`${m.registration_id}|${m.offering_id}`} className="row row--between" style={{ padding: "6px 0", borderBottom: "1px solid var(--line-2)" }}>
                <div className="grow"><b className="tnum">{m.matric_no ?? "\u2014"}</b> &middot; {m.surname}{m.other_names ? `, ${m.other_names}` : ""} &middot; {m.level} level &middot; <span className="tnum">{m.course_code}</span> &rarr; <span className="tnum">{m.own_code ?? "\u2014"}</span>{m.own_offering_id ? "" : " (class not yet open)"}</div>
                {m.scored ? <span className="sub2">score entered &mdash; Examinations Office</span> : maySet ? <Btn kind="secondary" size="sm" disabled={busy} onClick={() => void move(m)}>Move to {m.own_code}</Btn> : null}
              </div>
            ))}
          </div>
        ) : null}
      </PBody>
    </Panel>
  );
}
