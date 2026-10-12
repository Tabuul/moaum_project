"use client";

/** V399: the applicants told of another faculty's programme before suggestions were held to the faculty applied to (V397),
 *  or still asking to move to one. The Office sends each the corrected list (the programmes of their faculty they may be
 *  considered for, or none at present) and rejects a request still open, with its reason; nothing told is deleted. Shown only
 *  while somebody is on it. */
import { useEffect, useState } from "react";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import type { Problem } from "@/lib/api";
import { Btn, Note, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { ProblemNotice } from "@/components/ProblemNotice";

interface Told {
  application_id: string; application_no: string; name: string; jamb_reg_no: string; email: string | null;
  programme: string; faculty: string | null; told: string | null; told_at: string | null; told_other: string[] | null;
  suggested_now: string[] | null; corrected_at: string | null; request_id: string | null; request_to: string | null; request_faculty: string | null;
}

const OFFICE = ["academic", "registrar", "dregistrar"];
const REJECT_NOTE = "Only programmes of the faculty you applied to are offered as a change of programme.";
const day = (iso: string | null) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" }) : "—");

export function CrossFacultyTold({ session, actingOffice }: { session: string; actingOffice: string | null }) {
  const may = OFFICE.includes(actingOffice ?? "");
  const [rows, setRows] = useState<Told[] | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const base = `/api/bff/api/v1/admissions/sessions/${session}`;

  async function load() {
    try {
      const r = await fetch(`${base}/reconsiderations/cross-faculty`, { cache: "no-store" });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j ?? { status: r.status, title: r.statusText }); setRows([]); return; }
      setProblem(null);
      setRows((j as Told[]) ?? []);
    } catch {
      setProblem({ status: 0, title: "Could not load the applicants told of another faculty's programme." });
      setRows([]);
    }
  }

  useEffect(() => {
    let live = true;
    void (async () => { await load(); if (!live) return; })();
    return () => { live = false; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [session]);

  async function correct(ids: string[] | null) {
    setBusy(ids ? ids[0] : "all");
    try {
      const r = await fetch(`${base}/reconsiderations/cross-faculty/correct`, {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`suggestions corrected to the applicants' own faculty, ${session}`) },
        body: JSON.stringify({ applicationIds: ids }),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) { notifyProblem(j ?? { status: r.status, title: r.statusText }); return; }
      notify(`${j.corrected} corrected list${j.corrected === 1 ? "" : "s"} sent${j.withoutEmail ? ` (${j.withoutEmail} with no email on file: recorded, by text where a phone is on file)` : ""}`);
      await load();
    } finally {
      setBusy(null);
    }
  }

  async function reject(t: Told) {
    if (!t.request_id) return;
    setBusy(t.request_id);
    try {
      const r = await fetch(`${base}/eligibility/changes/${t.request_id}/reject`, {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`request to move ${t.name} to another faculty's programme rejected`) },
        body: JSON.stringify({ note: REJECT_NOTE }),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) { notifyProblem(j ?? { status: r.status, title: r.statusText }); return; }
      notify(`${t.name}'s request rejected; the applicant is told`);
      await load();
    } finally {
      setBusy(null);
    }
  }

  if (rows == null || (rows.length === 0 && !problem)) return null;
  const toCorrect = rows.filter((t) => t.told_other && t.told_other.length);
  return (
    <Panel title="Told of another faculty's programme"
           right={may && toCorrect.length ? <Btn kind="primary" size="sm" disabled={!!busy} onClick={() => void correct(null)}>{busy === "all" ? "Sending…" : `Send ${toCorrect.length} corrected list${toCorrect.length === 1 ? "" : "s"}`}</Btn> : undefined}>
      <PBody>
        {problem ? <ProblemNotice problem={problem} /> : null}
        <Note kind="info" title="Suggestions are of the faculty applied to">
          These applicants were suggested, or asked for, a programme of another faculty before the rule. Send each the programmes of their own faculty, and reject a request still open.
        </Note>
        <DTable
          cols={["Applicant", "Applied for", "Told", "Suggested now", "Request open", "Act|num"]}
          rows={rows.map((t) => [
            <span key="n"><b>{t.name}</b><div className="sub2 tnum">{t.jamb_reg_no} · {t.application_no}</div>{t.email ? null : <div className="sub2">no email on file</div>}</span>,
            <span key="p">{t.programme}{t.faculty ? <div className="sub2">{t.faculty}</div> : null}</span>,
            t.told_other && t.told_other.length
              ? <span key="t">{t.told_other.join(", ")}<div className="sub2">{day(t.told_at)}{t.corrected_at ? ` · corrected ${day(t.corrected_at)}` : ""}</div></span>
              : <span key="t" className="sub2">{t.corrected_at ? `Corrected ${day(t.corrected_at)}` : "—"}</span>,
            t.suggested_now && t.suggested_now.length ? <span key="s">{t.suggested_now.join(", ")}</span> : <span key="s" className="sub2">None at present</span>,
            t.request_id ? <span key="r"><Pil kind="warn">{t.request_to}</Pil>{t.request_faculty ? <div className="sub2">{t.request_faculty}</div> : null}</span> : <span key="r" className="sub2">—</span>,
            <span key="a" className="row row--inline row--tight" style={{ justifyContent: "flex-end" }}>
              {t.told_other && t.told_other.length ? <Btn kind="secondary" size="sm" disabled={!may || !!busy} onClick={() => void correct([t.application_id])}>{busy === t.application_id ? "Sending…" : "Send corrected list"}</Btn> : null}
              {t.request_id ? <Btn kind="ghost" size="sm" disabled={!may || !!busy} onClick={() => { if (window.confirm(`Reject ${t.name}'s request to move to ${t.request_to}? The reason given: "${REJECT_NOTE}"`)) void reject(t); }}>{busy === t.request_id ? "Rejecting…" : "Reject request"}</Btn> : null}
            </span>,
          ])}
          texts={rows.map((t) => `${t.name} ${t.jamb_reg_no} ${t.application_no} ${t.programme} ${(t.told_other ?? []).join(" ")} ${t.request_to ?? ""}`)}
        />
      </PBody>
    </Panel>
  );
}
