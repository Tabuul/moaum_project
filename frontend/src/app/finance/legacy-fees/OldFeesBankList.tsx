"use client";

/** V684: the bank's or the gateway's list of payments received, set at once against every possible double charge of the days it
 *  covers. A group whose payment numbers are all on the list is checked "every payment received"; one with some on it and some not
 *  is checked "not all", and each record not on the list is raised for withdrawal; the rest are left for a check by hand. Another
 *  Bursary officer then approves (or rejects) every withdrawal the list raised in one act — each still decided on its own, archived
 *  never deleted — and the officer who recorded the list may cancel them. The database judges, records and refuses; the screen
 *  reads the file and asks. */
import { useEffect, useState } from "react";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, Note, Panel, PBody, Pil, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal, money } from "@/components/proto/blocks";
import { csvRows, xlsxWorkbook } from "@/lib/xlsx";
import { brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import {
  BANK_GROUP_HEADERS, OUTCOME, bankGroupRow, blcPath, leftByHand, readBankList,
  type BankGroup, type BankListRead, type BankListRow, type BankPreview,
} from "@/lib/bank-list";
import { PNR_STATE } from "@/lib/double-charges";

const BASE = "/api/bff/api/v1/finance/legacy-fees";

interface Upload { name: string; read: BankListRead; from: string; to: string; evidence: string; note: string; preview: BankPreview | null }
type Action = "APPROVE" | "REJECT" | "CANCEL";
const ACTION: Record<Action, [string, string]> = {
  APPROVE: ["Approve every withdrawal waiting", "Withdrawing…"],
  REJECT: ["Reject every withdrawal waiting", "Rejecting…"],
  CANCEL: ["Cancel every withdrawal waiting", "Cancelling…"],
};

async function sheetOf(file: File): Promise<BankListRead> {
  if (/\.csv$/i.test(file.name)) return readBankList(csvRows(await file.text()));
  const sheets = await xlsxWorkbook(await file.arrayBuffer());
  // the sheet with a payment-number column and the most numbers, else the one with the most numbers found anywhere
  const reads = sheets.map((s) => readBankList(s.rows));
  const best = (xs: BankListRead[]) => xs.reduce<BankListRead | null>((a, b) => (!a || b.numbers.length > a.numbers.length ? b : a), null);
  return best(reads.filter((r) => r.mode === "column" && r.numbers.length)) ?? best(reads) ?? readBankList([]);
}

export function OldFeesBankList({ may, tick = 0, onChanged }: { may: boolean; tick?: number; onChanged?: () => void }) {
  const [lists, setLists] = useState<BankListRow[] | null>(null);
  const [answered, setAnswered] = useState<string | null>(null);
  const [own, setOwn] = useState(0);
  const [upload, setUpload] = useState<Upload | null>(null);
  const [reading, setReading] = useState(false);
  const [viewing, setViewing] = useState<{ l: BankListRow; rows: BankGroup[] | null } | null>(null);
  const [deciding, setDeciding] = useState<{ l: BankListRow; action: Action; note: string } | null>(null);

  const asked = `${tick}#${own}`;
  const loading = answered !== asked;

  useEffect(() => {
    let alive = true;
    void (async () => {
      const r = await fetch(`${BASE}/bank-lists`, { cache: "no-store" }).catch(() => null);
      const j = r ? await r.json().catch(() => null) : null;
      if (!alive) return;
      setAnswered(asked);
      if (!r || !r.ok) { notifyProblem((j ?? { status: r?.status ?? 0, title: r?.statusText || "The portal could not be reached" }) as Problem); return; }
      setLists((j as { rows: BankListRow[] }).rows);
    })();
    return () => { alive = false; };
  }, [asked]);

  async function choose(file: File) {
    setReading(true);
    try {
      const read = await sheetOf(file);
      if (read.problem) { notifyProblem({ status: 400, title: "No payment number could be read from that file.", detail: read.problem }); return; }
      setUpload({ name: file.name, read, from: read.from ?? "", to: read.to ?? "", evidence: "", note: "", preview: null });
    } catch {
      notifyProblem({ status: 400, title: "That file could not be read as a spreadsheet.", detail: "Save the bank's or the gateway's list as .xlsx or .csv." });
    } finally {
      setReading(false);
    }
  }

  function body(u: Upload) {
    return { session: "all", from: u.from, to: u.to, numbers: u.read.numbers, evidence: u.evidence.trim(), note: u.note.trim() || null, fileName: u.name, rowsRead: u.read.rows };
  }

  async function post(path: string, payload: unknown, why: string): Promise<Record<string, unknown> | null> {
    const r = await fetch(`${BASE}${path}`, {
      method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(why) }, body: JSON.stringify(payload),
    });
    const j = await r.json().catch(() => null);
    if (!r.ok) { notifyProblem((j ?? { status: r.status, title: r.statusText }) as Problem); return null; }
    return j as Record<string, unknown>;
  }

  async function previewIt() {
    if (!upload) return;
    const j = await post("/double-charges/bank-list/preview", body(upload), `Bank list ${upload.name} set against the possible double charges (preview)`);
    if (j) setUpload({ ...upload, preview: j as unknown as BankPreview });
  }

  async function record() {
    if (!upload?.preview) return;
    const j = await post("/double-charges/bank-list", body(upload), `Bank list ${upload.name} recorded against the possible double charges — ${upload.evidence.trim()}`);
    if (!j) return;
    const o = (j.outcomes ?? {}) as Record<string, number>;
    notify(`${String(j.listRef)} recorded: ${(o.RECEIVED ?? 0) + (o.NOT_RECEIVED ?? 0)} checked with the bank; ${o.raised ?? 0} withdrawal${o.raised === 1 ? "" : "s"} raised for another Bursary officer to approve`);
    setUpload(null);
    setOwn((x) => x + 1);
    onChanged?.();
  }

  async function view(l: BankListRow) {
    const path = blcPath(l.list_ref);
    if (!path) return;
    setViewing({ l, rows: null });
    const r = await fetch(`${BASE}/bank-lists/${path}`, { cache: "no-store" }).catch(() => null);
    const j = r ? await r.json().catch(() => null) : null;
    if (!r || !r.ok) { notifyProblem((j ?? { status: r?.status ?? 0, title: r?.statusText || "The portal could not be reached" }) as Problem); setViewing(null); return; }
    setViewing({ l, rows: (j as { rows: BankGroup[] }).rows });
  }

  async function excel(l: BankListRow, rows: BankGroup[]) {
    const blob = await brandedXlsx(`Bank list ${l.list_ref}: possible double charges judged`, BANK_GROUP_HEADERS, rows.map(bankGroupRow), {
      sheetName: "Bank list", serial: docSerial("BLC"),
      sub: `Payments from ${l.covers_from} to ${l.covers_to} · ${l.evidence}`,
    });
    downloadBlob(blob, `bank-list-${l.list_ref.replace(/\//g, "-")}.xlsx`);
  }

  async function decide() {
    if (!deciding) return;
    const path = blcPath(deciding.l.list_ref);
    if (!path) return;
    const { l, action, note } = deciding;
    const j = await post(`/bank-lists/${path}/decide`, { action, note: note.trim() || null },
      `Withdrawals of bank list ${l.list_ref}: ${ACTION[action][0].toLowerCase()}${note.trim() ? ` — ${note.trim()}` : ""}`);
    if (!j) return;
    const done = Number(j.done ?? 0);
    const refused = (j.refusals as string[] | undefined) ?? [];
    notify(`${l.list_ref}: ${done} withdrawal${done === 1 ? "" : "s"} ${action === "APPROVE" ? "approved — the records are archived and the students told" : action === "REJECT" ? "rejected" : "cancelled"}`
      + (refused.length ? `; ${refused.length} refused (${refused.slice(0, 3).join("; ")}${refused.length > 3 ? " …" : ""})` : ""));
    setDeciding(null);
    setOwn((x) => x + 1);
    onChanged?.();
  }

  const u = upload;
  const p = u?.preview;
  const settles = p ? (p.counts.RECEIVED ?? 0) + (p.counts.NOT_RECEIVED ?? 0) : 0;
  const ready = !!u && !!u.from && !!u.to && u.from <= u.to;
  return (
    <Panel title="Check against the bank's list" right="The bank's or the gateway's list of payments received, set against every possible double charge of the days it covers at once">
      <PBody>
        <Note kind="info" title="How a list is read">
          Each possible double charge paid within the days the list covers is looked up by its payment numbers. Every number on the list: the bank received each payment.
          Some on it and some not: those not on it never reached the University, and are raised for withdrawal for another Bursary officer to approve. None on the list,
          or the list showing less than the record: left for a check by hand. Nothing comes off a student&rsquo;s account until another officer approves, and a withdrawn
          payment is archived, never deleted.
        </Note>
        {may ? (
          <div className="row mt-2" style={{ flexWrap: "wrap", gap: "var(--s-3)", alignItems: "center" }}>
            <label className={`btn btn--secondary m-0${reading ? " btn--disabled" : ""}`} style={{ cursor: reading ? "not-allowed" : "pointer" }}>
              {reading ? "Reading…" : "Upload the bank's list…"}
              <input type="file" accept=".xlsx,.csv" style={{ display: "none" }} disabled={reading}
                onChange={(e) => { const f = e.target.files?.[0]; if (f) void choose(f); e.target.value = ""; }} />
            </label>
            <span className="sub2">An Excel or CSV file with a payment-reference column (with the amount and the date where it has them), or a bank statement whose narration carries the payment numbers.</span>
          </div>
        ) : null}
      </PBody>

      {lists && lists.length ? (
        <DTable cols={["S/N|num", "List", "Days covered", "Judged", "Withdrawals", ""]} rows={lists.map((l, i) => {
          const o = l.outcomes;
          const waiting = l.withdrawals.PROPOSED ?? 0;
          return [
            <span key="n" className="tnum sub2">{i + 1}</span>,
            <span key="r" className="tnum">{l.list_ref}<div className="sub2">{l.evidence}</div><div className="sub2">{l.checked_by ?? "—"} · {l.checked_at.slice(0, 16).replace("T", " ")}</div></span>,
            <span key="d" className="tnum sub2">{l.covers_from} to {l.covers_to}<div>{l.numbers_read.toLocaleString()} numbers{l.file_name ? ` · ${l.file_name}` : ""}</div></span>,
            <span key="j" className="sub2">{(o.RECEIVED ?? 0)} every payment received · {(o.NOT_RECEIVED ?? 0)} not all<div>{leftByHand(o)} left for a check by hand</div></span>,
            <span key="w" className="sub2">
              {waiting ? <div className="ink-amber" style={{ whiteSpace: "nowrap" }}>{waiting} waiting</div> : null}
              {(["APPROVED", "REJECTED", "CANCELLED"] as const).filter((s) => l.withdrawals[s]).map((s) => <div key={s}>{l.withdrawals[s]} {PNR_STATE[s][0].toLowerCase()}</div>)}
              {!o.raised ? <div>None raised</div> : <div>{money(Number(o.raised_amount ?? 0))} raised</div>}
            </span>,
            <span key="b" className="row" style={{ gap: "var(--s-2)", flexWrap: "wrap" }}>
              <Btn kind="ghost" size="sm" onClick={() => view(l)}>View</Btn>
              {may && waiting && !l.mine ? <>
                <Btn kind="primary" size="sm" onClick={() => setDeciding({ l, action: "APPROVE", note: "" })}>Approve all…</Btn>
                <Btn kind="ghost" size="sm" onClick={() => setDeciding({ l, action: "REJECT", note: "" })}>Reject all…</Btn>
              </> : null}
              {may && waiting && l.mine ? <Btn kind="ghost" size="sm" onClick={() => setDeciding({ l, action: "CANCEL", note: "" })}>Cancel all…</Btn> : null}
            </span>,
          ];
        })} />
      ) : <PBody><div className="sub2">{loading && !lists ? "Looking…" : "No bank list has been recorded yet."}</div></PBody>}

      {u ? (
        <Modal wide title="Check against the bank's list" sub={`${u.name} · ${u.read.numbers.length.toLocaleString()} payment numbers`} onClose={() => setUpload(null)}
          foot={<><Btn kind="ghost" onClick={() => setUpload(null)}>Cancel</Btn>
            <Btn kind="secondary" disabled={!ready} busyLabel="Looking…" onClick={() => previewIt()}>{p ? "Look again" : "Preview"}</Btn>
            <Btn kind="primary" disabled={!p || !settles || u.evidence.trim().length < 5} busyLabel="Recording…" onClick={() => record()}>
              {p ? `Record ${settles} check${settles === 1 ? "" : "s"}${p.toWithdraw ? ` and raise ${p.toWithdraw} withdrawal${p.toWithdraw === 1 ? "" : "s"}` : ""}` : "Record"}
            </Btn></>}>
          <div className="sub2">
            {u.read.mode === "column"
              ? <>{u.read.rows.toLocaleString()} rows read: the payment numbers from “{u.read.header.number}”{u.read.header.amount ? `, the amounts from “${u.read.header.amount}”` : ", no amounts"}{u.read.header.date ? `, the days from “${u.read.header.date}”` : ""}.</>
              : <>No column names the payment number, so every cell of {u.read.rows.toLocaleString()} rows was searched for one; amounts are not compared.</>}
          </div>
          <div className="row mt-2" style={{ flexWrap: "wrap", gap: "var(--s-3)", alignItems: "flex-end" }}>
            <Field id="blc-from" label="Payments from" required style={{ flex: "0 1 170px" }}>
              <input id="blc-from" type="date" className="ctl" value={u.from} onChange={(e) => setUpload({ ...u, from: e.target.value, preview: null })} />
            </Field>
            <Field id="blc-to" label="to" required style={{ flex: "0 1 170px" }}>
              <input id="blc-to" type="date" className="ctl" value={u.to} onChange={(e) => setUpload({ ...u, to: e.target.value, preview: null })} />
            </Field>
          </div>
          <div className="sub2">
            The days whose payments the list shows in full. A payment made late on the last day may reach the bank the next day: end the days a little before the list does.
          </div>
          <Field id="blc-evidence" label="Evidence" required hint="The statement or report, its account and the days it covers">
            <input id="blc-evidence" className="ctl" maxLength={500} value={u.evidence} onChange={(e) => setUpload({ ...u, evidence: e.target.value })}
              placeholder="e.g. Interswitch collections report, MOAU fees account, 1 Mar to 5 Apr 2026" />
          </Field>
          <Field id="blc-note" label="Note (optional)">
            <input id="blc-note" className="ctl" maxLength={500} value={u.note} onChange={(e) => setUpload({ ...u, note: e.target.value })} />
          </Field>
          {p ? (
            <>
              <Tiles items={[
                ["Every payment on the list", String(p.counts.RECEIVED ?? 0), null, "Checked: the excess is real"],
                ["Not all on the list", String(p.counts.NOT_RECEIVED ?? 0), p.counts.NOT_RECEIVED ? "var(--amber-ink)" : null,
                  `${p.toWithdraw} record${p.toWithdraw === 1 ? "" : "s"} (${money(Number(p.toWithdrawAmount))}) raised for withdrawal`],
                ["Left for a check by hand", String(leftByHand(p.counts)), null,
                  `${p.counts.NONE_FOUND ?? 0} none on the list · ${p.counts.AMOUNT_SHORT ?? 0} less on the list · ${p.counts.NO_NUMBER ?? 0} without a number`],
                ["Not judged", String((p.counts.CHECKED ?? 0) + (p.counts.OUTSIDE_PERIOD ?? 0)), null,
                  `${p.counts.CHECKED ?? 0} checked already · ${p.counts.OUTSIDE_PERIOD ?? 0} paid outside these days`],
              ]} />
              {!settles ? <Note kind="bad" title="The list settles nothing">No possible double charge of these days has a payment number on the list beside one that is not, or all of them on it. Check the days, or the file.</Note> : null}
              {p.rows.length ? (
                <DTable cols={["S/N|num", "Student", "Item", "Paid on|mid", "Amount|num", "Not on the list", "Outcome"]} rows={p.rows.map((g, i) => [
                  <span key="n" className="tnum sub2">{i + 1}</span>,
                  <Two key="s" a={g.name ?? "—"} b={g.number ?? ""} />,
                  <span key="p">{g.purpose}<div className="sub2">{g.session}</div></span>,
                  <span key="d" className="tnum">{g.paid_on}</span>,
                  <span key="a" className="tnum">{money(Number(g.amount))}<div className="sub2">× {g.refs.length}</div></span>,
                  <span key="m" className="sub2 tnum" style={{ overflowWrap: "anywhere" }}>{g.outcome === "NOT_RECEIVED" ? g.missing.map((r) => <div key={r}>{r}</div>) : "—"}</span>,
                  <span key="o"><Pil kind={OUTCOME[g.outcome][1]}>{OUTCOME[g.outcome][0]}</Pil></span>,
                ])} />
              ) : null}
            </>
          ) : null}
        </Modal>
      ) : null}

      {viewing ? (
        <Modal wide title={`Bank list ${viewing.l.list_ref}`} sub={`Payments from ${viewing.l.covers_from} to ${viewing.l.covers_to} · ${viewing.l.evidence}`} onClose={() => setViewing(null)}
          foot={<><Btn kind="ghost" disabled={!viewing.rows?.length} onClick={() => viewing.rows && excel(viewing.l, viewing.rows)}>Excel</Btn>
            <Btn kind="secondary" onClick={() => setViewing(null)}>Close</Btn></>}>
          {!viewing.rows ? <div className="sub2">Looking…</div> : !viewing.rows.length ? <div className="sub2">The list judged no possible double charge.</div> : (
            <DTable cols={["S/N|num", "Student", "Item", "Paid on|mid", "Amount|num", "On the list · not on it", "Outcome", "Withdrawals"]} rows={viewing.rows.map((g, i) => [
              <span key="n" className="tnum sub2">{i + 1}</span>,
              <Two key="s" a={g.name ?? "—"} b={g.number ?? ""} />,
              <span key="p">{g.purpose}<div className="sub2">{g.session}</div></span>,
              <span key="d" className="tnum">{g.paid_on}</span>,
              <span key="a" className="tnum">{money(Number(g.amount))}</span>,
              <span key="r" className="sub2 tnum" style={{ overflowWrap: "anywhere" }}>
                {g.found.map((r) => <div key={r}>On it: {r}</div>)}{g.missing.map((r) => <div key={r}>Not on it: {r}</div>)}</span>,
              <span key="o"><Pil kind={OUTCOME[g.outcome][1]}>{OUTCOME[g.outcome][0]}</Pil>{g.refusal ? <div className="sub2">{g.refusal}</div> : null}</span>,
              <span key="w" className="sub2 tnum">{(g.withdrawals ?? []).length ? (g.withdrawals ?? []).map((w) => <div key={w.requestRef}>{w.requestRef} · {PNR_STATE[w.state][0]}</div>) : "—"}</span>,
            ])} />
          )}
        </Modal>
      ) : null}

      {deciding ? (
        <Modal title={`${ACTION[deciding.action][0]} — ${deciding.l.list_ref}`} sub={`${deciding.l.withdrawals.PROPOSED ?? 0} withdrawal${deciding.l.withdrawals.PROPOSED === 1 ? "" : "s"} waiting · ${deciding.l.evidence}`}
          onClose={() => setDeciding(null)}
          foot={<><Btn kind="ghost" onClick={() => setDeciding(null)}>Cancel</Btn>
            <Btn kind="primary" disabled={deciding.action === "REJECT" && deciding.note.trim().length < 5} busyLabel={ACTION[deciding.action][1]} onClick={() => decide()}>
              {deciding.action === "APPROVE" ? "Withdraw the records" : deciding.action === "REJECT" ? "Reject them" : "Cancel them"}</Btn></>}>
          {deciding.action === "APPROVE" ? (
            <Note kind="bad" title="The records come off the students' accounts">
              Each payment record the list raised is withdrawn: its ledger posting reversed, the record archived (never deleted) and kept on the withdrawn list, its payment
              number remembered so the export loaded again does not bring it back, and the student told by e-mail, text and on the portal. Look at the list (View) first.
              A withdrawal that can no longer be made is left waiting and named.
            </Note>
          ) : deciding.action === "REJECT" ? (
            <Note kind="info" title="The records stand">Each withdrawal the list raised is rejected; the payments stay on the students&rsquo; accounts. The checks the list recorded stay: check those groups again by hand on Possible bank double charges.</Note>
          ) : (
            <Note kind="info" title="Taken back">Each withdrawal you raised from this list is cancelled; the payments stay. The checks the list recorded stay: check those groups again by hand on Possible bank double charges.</Note>
          )}
          <Field id="blc-decide-note" label={deciding.action === "REJECT" ? "Why they are rejected" : "Note (optional)"} required={deciding.action === "REJECT"}>
            <input id="blc-decide-note" className="ctl" maxLength={500} value={deciding.note} onChange={(e) => setDeciding({ ...deciding, note: e.target.value })} />
          </Field>
        </Modal>
      ) : null}
    </Panel>
  );
}
