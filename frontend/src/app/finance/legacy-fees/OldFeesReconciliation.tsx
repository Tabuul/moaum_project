"use client";

/** V498: the old-portal school-fees payments of a session reconciled against the fee setup — for every student with an
 *  old payment, what the setup says is due, what is paid (the old portal by semester, the retired Payment History Upload, the
 *  portal), the difference and the state; those under or over first, with the Excel list for the Bursary. */
import { useEffect, useState } from "react";
import type { Problem } from "@/lib/api";
import { notifyProblem } from "@/components/proto/Toast";
import { Btn, Note, Panel, PBody, Pil, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, money } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { RECON_HEADERS, RECON_STATE, reconRow, type ReconRow, type ReconState } from "@/lib/old-fees";

interface Summary { state: ReconState; students: number; due: number; paid: number; difference: number }
interface Recon { session: string; sessions: string[]; summary: Summary[]; total: number; rows: ReconRow[]; page: number; size: number }

const SIZE = 50;

/** tick: a change made elsewhere on the page (an upload, a withdrawal, records put right): the list reads again */
export function OldFeesReconciliation({ tick = 0 }: { tick?: number }) {
  const [session, setSession] = useState("");
  const [state, setState] = useState<ReconState | "">("");
  const [q, setQ] = useState("");
  const [typed, setTyped] = useState("");
  const [page, setPage] = useState(1);
  const [data, setData] = useState<Recon | null>(null);
  const [answered, setAnswered] = useState<string | null>(null);
  const [preparing, setPreparing] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);

  const url = (size: number, pg: number) => {
    const p = new URLSearchParams({ size: String(size), page: String(pg) });
    if (session) p.set("session", session);
    if (state) p.set("state", state);
    if (q.trim()) p.set("q", q.trim());
    return `/api/bff/api/v1/finance/legacy-fees/reconciliation?${p.toString()}`;
  };
  const listUrl = url(SIZE, page);
  // what is asked — the filters, the page, a change made on the page — and whether it is answered yet (no session chosen asks
  // for the current one, which the answer names)
  const asked = `${listUrl}#${tick}`;
  const loading = answered !== asked;
  const shown = session || data?.session || "";

  // the list as the filters and the page ask for it (a filter changed starts again at page one)
  useEffect(() => {
    let alive = true;
    void (async () => {
      const r = await fetch(listUrl, { cache: "no-store" }).catch(() => null);
      const j = r ? await r.json().catch(() => null) : null;
      if (!alive) return;
      setAnswered(asked);
      if (!r || !r.ok) { const p = (j ?? { status: r?.status ?? 0, title: r?.statusText || "The portal could not be reached" }) as Problem; setProblem(p); notifyProblem(p); return; }
      setProblem(null);
      setData(j as Recon);
    })();
    return () => { alive = false; };
  }, [listUrl, asked]);
  const ask = (change: () => void) => { setPage(1); change(); };
  // a number or name is looked for once the typing stops (each reading reconciles the whole session)
  useEffect(() => {
    if (typed === q) return;
    const t = setTimeout(() => { setPage(1); setQ(typed); }, 500);
    return () => clearTimeout(t);
  }, [typed, q]);

  async function excel() {
    setPreparing(true);
    try {
      const r = await fetch(url(100_000, 1), { cache: "no-store" });
      const j = (await r.json().catch(() => null)) as Recon | null;
      if (!r.ok || !j) { const p = (j ?? { status: r.status, title: r.statusText }) as unknown as Problem; notifyProblem(p); return; }
      const blob = await brandedXlsx(`Old fees reconciled with the fee setup, ${j.session}`, RECON_HEADERS, j.rows.map(reconRow), {
        sheetName: "Reconciliation", serial: docSerial("OFR"),
        sub: `${state ? RECON_STATE[state][0] : "Every state"}${q.trim() ? ` · "${q.trim()}"` : ""} · ${j.total.toLocaleString()} student${j.total === 1 ? "" : "s"}`,
      });
      downloadBlob(blob, `old-fees-reconciliation-${j.session.replace("/", "-")}${state ? `-${state.toLowerCase()}` : ""}.xlsx`);
    } finally {
      setPreparing(false);
    }
  }

  const by = (s: ReconState) => data?.summary.find((x) => x.state === s);
  const tile = (s: ReconState, colour: string | null): [string, string, string | null, string] => {
    const x = by(s);
    return [RECON_STATE[s][0], (x?.students ?? 0).toLocaleString(), x?.students ? colour : null,
      x ? `${s === "MATCHED" ? "Paid" : s === "NO_FEE_STATED" ? "Paid" : "Difference"} ${money(Number(s === "MATCHED" || s === "NO_FEE_STATED" ? x.paid : x.difference))}` : "None"];
  };
  const pages = data ? Math.max(1, Math.ceil(data.total / SIZE)) : 1;

  return (
    <Panel title="Reconciled with the fee setup" right="Every student with an old-portal school-fees payment in the session: due by the fee setup, paid, the difference">
      <PBody>
        <div className="row" style={{ flexWrap: "wrap", gap: "var(--s-3)", alignItems: "flex-end" }}>
          <Field id="ofr-session" label="Session" style={{ flex: "0 1 160px" }}>
            <select id="ofr-session" className="ctl" value={shown} onChange={(e) => { const v = e.target.value; ask(() => setSession(v)); }} disabled={loading}>
              {(data?.sessions.length ? data.sessions : shown ? [shown] : []).map((s) => <option key={s} value={s}>{s}</option>)}
              {data && shown && !data.sessions.includes(shown) ? <option value={shown}>{shown}</option> : null}
            </select>
          </Field>
          <Field id="ofr-state" label="State" style={{ flex: "0 1 220px" }}>
            <select id="ofr-state" className="ctl" value={state} onChange={(e) => { const v = e.target.value as ReconState | ""; ask(() => setState(v)); }} disabled={loading}>
              <option value="">Every state</option>
              {(Object.keys(RECON_STATE) as ReconState[]).map((s) => <option key={s} value={s}>{RECON_STATE[s][0]}</option>)}
            </select>
          </Field>
          <Field id="ofr-q" label="Number or name" style={{ flex: "1 1 220px" }}>
            <input id="ofr-q" className="ctl" value={typed} onChange={(e) => setTyped(e.target.value)} placeholder="e.g. BSU/SS/SOC/23" />
          </Field>
          <Btn kind="ghost" disabled={loading || preparing || !data?.total} onClick={() => void excel()}>{preparing ? "Preparing…" : "Excel"}</Btn>
          {loading && data ? <span className="sub2" role="status">Reconciling…</span> : null}
        </div>
      </PBody>
      {problem ? <PBody><ProblemNotice problem={problem} /></PBody> : null}
      {data ? (
        <>
          <PBody>
            <Tiles items={[
              tile("UNDER", "var(--red-ink)"),
              tile("OVER", "var(--red-ink)"),
              tile("NO_FEE_STATED", "var(--red-ink)"),
              tile("MATCHED", "var(--green-ink)"),
            ]} />
            {by("NO_FEE_STATED")?.students ? (
              <Note kind="info" title="No fee stated">
                The fee setup charges these students nothing for {data.session}: their programme, level or faculty has no fee line for the session.
                State the fees on Fee Setup and the list reconciles; the payments are not the problem.
              </Note>
            ) : null}
          </PBody>
          {data.rows.length ? (
            <DTable pageSize={0} cols={["Student", "Programme|mid", "Level|num", "Due|num", "Paid|num", "Old portal|num", "Portal|num", "Difference|num", "State"]}
              rows={data.rows.map((r) => [
                <Two key="s" a={r.name} b={r.number} />,
                <span key="p" className="sub2">{r.programme_code}{r.faculty_code ? ` · ${r.faculty_code}` : ""}</span>,
                <span key="l" className="tnum">{r.level ?? "—"}</span>,
                <span key="d" className="tnum">{money(Number(r.due))}</span>,
                <b key="pd" className="tnum">{money(Number(r.paid))}</b>,
                <span key="o" className="tnum sub2">
                  {Number(r.paid_old_s1) ? <div>S1 {money(Number(r.paid_old_s1))}</div> : null}
                  {Number(r.paid_old_s2) ? <div>S2 {money(Number(r.paid_old_s2))}</div> : null}
                  {Number(r.paid_old_session) ? <div>Session {money(Number(r.paid_old_session))}</div> : null}
                  {Number(r.paid_payment_history) ? <div>Payment History {money(Number(r.paid_payment_history))}</div> : null}
                </span>,
                <span key="pt" className="tnum sub2">{Number(r.paid_portal) ? money(Number(r.paid_portal)) : "—"}</span>,
                <b key="df" className="tnum" style={{ color: r.state === "UNDER" || r.state === "OVER" ? "var(--red-ink)" : undefined }}>{money(Number(r.difference))}</b>,
                <Pil key="st" kind={RECON_STATE[r.state][1]}>{RECON_STATE[r.state][0]}</Pil>,
              ])} />
          ) : <PBody><div className="sub2">No student {state ? `in "${RECON_STATE[state][0]}" ` : ""}has an old-portal school-fees payment in {data.session}{q.trim() ? " matching that" : ""}.</div></PBody>}
          {data.total > SIZE ? (
            <PBody>
              <div className="row" style={{ alignItems: "center" }}>
                <Btn kind="ghost" disabled={loading || page <= 1} onClick={() => setPage(page - 1)}>Previous</Btn>
                <span className="sub2">Page {page} of {pages} · {data.total.toLocaleString()} students</span>
                <Btn kind="ghost" disabled={loading || page >= pages} onClick={() => setPage(page + 1)}>Next</Btn>
              </div>
            </PBody>
          ) : null}
        </>
      ) : loading ? <PBody><div className="sub2" role="status">Reconciling…</div></PBody> : null}
    </Panel>
  );
}
