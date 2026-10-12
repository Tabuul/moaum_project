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

export function CodeFamiliesPanel({ data, sessions, maySet }: { data: CodeFamilies; sessions: string[]; maySet: boolean }) {
  const router = useRouter();
  const current = data.moau_from_entry_session ?? "";
  const [value, setValue] = useState(current);
  const [busy, setBusy] = useState(false);
  const options = [...new Set([...(current ? [current] : []), ...sessions])].sort();

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
      </PBody>
    </Panel>
  );
}
