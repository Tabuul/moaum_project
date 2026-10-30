"use client";
/** V710: applicants' passwords reset in bulk back to the default number — on the undergraduate desk the JAMB number (the application
 *  number where there is none), on the postgraduate desk the application number. The numbers or emails are pasted, one to a line (a
 *  column copied from Excel), checked first (what would be reset, and what would not and why), then reset under one reference with the
 *  reason; each reset is written down as the desk's own and the applicant told. The server decides every row. */
import { useState } from "react";
import type { Problem } from "@/lib/api";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, Note, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { BULK_OUTCOME, bulkNumbers, bulkProblem, reasonProblem } from "@/lib/applicant-password";
import { brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";

interface BulkRow { row_no: number; given: string; outcome: string; account_id: string | null; applicant: string | null; default_number: string | null; detail: string | null }
interface BulkResult { committed: boolean; bulkRef: string | null; counts: Record<string, number>; rows: BulkRow[] }

export function BulkPasswordReset({ endpoint, postgraduate, onDone }: { endpoint: string; postgraduate?: boolean; onDone?: () => void }) {
  const [text, setText] = useState("");
  const [reason, setReason] = useState("");
  const [checked, setChecked] = useState<BulkResult | null>(null);
  const [done, setDone] = useState<BulkResult | null>(null);
  const [busy, setBusy] = useState<"" | "check" | "reset">("");
  const [problem, setProblem] = useState<Problem | null>(null);
  const numbers = bulkNumbers(text);
  const listProblem = bulkProblem(numbers);
  const what = postgraduate ? "application number (or the old portal's) or email" : "JAMB number, application number or email";
  const back = postgraduate ? "their application number" : "their JAMB number (the application number where there is none)";

  async function send(commit: boolean) {
    const p = listProblem ?? reasonProblem(reason);
    if (p) { setProblem({ status: 400, title: p }); return; }
    setBusy(commit ? "reset" : "check"); setProblem(null);
    try {
      const r = await fetch(`/api/bff${endpoint}/bulk`, { method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ numbers, reason: reason.trim(), commit }) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { const pr = (j as Problem) ?? { status: r.status, title: r.statusText }; setProblem(pr); notifyProblem(pr); return; }
      const res = j as BulkResult;
      if (commit) {
        setDone(res); setChecked(null);
        notify(`${(res.counts.RESET ?? 0).toLocaleString()} password${res.counts.RESET === 1 ? "" : "s"} reset · ${res.bulkRef ?? ""}`);
        onDone?.();
      } else {
        setChecked(res); setDone(null);
      }
    } finally { setBusy(""); }
  }

  async function exportRows(res: BulkResult) {
    const head = ["Row", "Given", "Outcome", "Applicant", "Reset to", "Detail"];
    const body = res.rows.map((r) => [r.row_no, r.given, BULK_OUTCOME[r.outcome]?.[0] ?? r.outcome, r.applicant ?? "", r.default_number ?? "", r.detail ?? ""]);
    downloadBlob(await brandedXlsx(postgraduate ? "Postgraduate applicant passwords reset in bulk" : "Applicant passwords reset in bulk", head, body,
      { sheetName: "Bulk reset", serial: docSerial("APW"), sub: res.bulkRef ?? "checked, not reset" }), `applicant-passwords-${(res.bulkRef ?? "checked").replace(/\//g, "-")}.xlsx`);
  }

  const shown = done ?? checked;
  const willReset = checked ? checked.counts.WILL_RESET ?? 0 : 0;
  return (
    <Panel title="Reset many at once" right={<span className="sub2">Back to {back}</span>}>
      <PBody>
        {problem ? <ProblemNotice problem={problem} /> : null}
        <Field id={`bulk-${postgraduate ? "pg" : "ug"}`} label="Numbers" hint={`One ${what} to a line — paste a column from Excel. At most 2,000.`}>
          <textarea id={`bulk-${postgraduate ? "pg" : "ug"}`} className="ctl tnum" rows={5} value={text}
            onChange={(e) => { setText(e.target.value); setChecked(null); setDone(null); }} />
        </Field>
        <Field id={`bulk-why-${postgraduate ? "pg" : "ug"}`} label="Reason" required hint="Ten characters or more, e.g. “Applicants at the screening desk could not sign in; identities checked”">
          <input id={`bulk-why-${postgraduate ? "pg" : "ug"}`} className="ctl" maxLength={1000} value={reason} onChange={(e) => setReason(e.target.value)} />
        </Field>
        <div className="row row--inline mt-2" style={{ gap: "var(--s-2)", flexWrap: "wrap" }}>
          <span className="sub2">{numbers.length.toLocaleString()} number{numbers.length === 1 ? "" : "s"}</span>
          <span className="grow" />
          <Btn kind="secondary" disabled={busy !== "" || !!listProblem || !!reasonProblem(reason)} onClick={() => void send(false)}>{busy === "check" ? "Checking…" : "Check the list"}</Btn>
          <Btn kind="primary" disabled={busy !== "" || !checked || willReset === 0} onClick={() => void send(true)}>
            {busy === "reset" ? "Resetting…" : `Reset ${willReset.toLocaleString()} password${willReset === 1 ? "" : "s"}`}</Btn>
        </div>
        {checked && !done ? (
          <Note kind={willReset ? "info" : "bad"} title={willReset ? `${willReset.toLocaleString()} will be reset to ${back}` : "Nothing in the list can be reset"}>
            {Object.entries(checked.counts).filter(([k]) => k !== "WILL_RESET").map(([k, n]) => `${n} ${(BULK_OUTCOME[k]?.[0] ?? k).toLowerCase()}`).join(" · ") || "Every number names one applicant."}
            {willReset ? " Each applicant is told by email and SMS, and chooses their own password at the next sign-in." : ""}
          </Note>
        ) : null}
        {done ? (
          <Note kind="ok" title={`${(done.counts.RESET ?? 0).toLocaleString()} password${done.counts.RESET === 1 ? "" : "s"} reset · ${done.bulkRef ?? ""}`}>
            {Object.entries(done.counts).filter(([k]) => k !== "RESET").map(([k, n]) => `${n} ${(BULK_OUTCOME[k]?.[0] ?? k).toLowerCase()}`).join(" · ") || "Every number given was reset."}
            {" "}Each reset is on the history below with the reference.
          </Note>
        ) : null}
      </PBody>
      {shown ? <PBody><div className="row"><span className="grow" /><Btn kind="ghost" size="sm" onClick={() => void exportRows(shown)}>Excel</Btn></div></PBody> : null}
      {shown ? (
        <DTable pageSize={25} cols={["Row|num", "Given", "Outcome|mid", "Applicant", "Reset to", "Detail"]}
          texts={shown.rows.map((r) => `${r.given} ${r.applicant ?? ""} ${r.default_number ?? ""} ${r.outcome}`)}
          rows={shown.rows.map((r) => {
            const [word, kind] = BULK_OUTCOME[r.outcome] ?? [r.outcome, "grey"];
            return [
              <span key="n" className="tnum sub2">{r.row_no}</span>, <span key="g" className="tnum">{r.given}</span>, <Pil key="o" kind={kind}>{word}</Pil>,
              <span key="a">{r.applicant ?? "—"}</span>, <span key="d" className="tnum">{r.default_number ?? "—"}</span>, <span key="x" className="sub2">{r.detail ?? ""}</span>,
            ];
          })} />
      ) : null}
    </Panel>
  );
}
