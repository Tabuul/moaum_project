"use client";

/** V609: Old Fees History's upload history — every upload of old fees in one query: the Bursary's own loads (the file, what each
 *  part did; those before the history was kept rebuilt from the payments on record), the Students Account Officer's uploads for the
 *  Bursar's approval and each start over. Filtered by the day, how, the state, the person, the office, a session, or a reference,
 *  file or name; ten a page (or 25, 50, 100, all), each figure's View all listing every upload of its kind; Excel of what the filters
 *  find; an upload opened shows its parts and the payments it recorded (or deleted). */
import { useEffect, useState, type ReactNode } from "react";
import type { Problem } from "@/lib/api";
import { notifyProblem } from "@/components/proto/Toast";
import { Btn, KvGrid, Note, Panel, PBody, Pil, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, money } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import {
  filtersInWords, historyRow, historyUrl, HISTORY_HEADERS, HISTORY_STATE, KIND_STATES, KIND_WORD, partRows, paymentRow, PAYMENT_HEADERS, rowsWord,
  skipped, when, type History, type HistoryFilters, type HistoryKind, type HistoryPart, type HistoryPayment, type HistoryRow, type HistoryState,
} from "@/lib/old-fees-history";

/** the uploads a page: the default, and the choices (0 = every upload the filters find, on one page) */
const SIZES = [10, 25, 50, 100, 0];
const ALL = 100_000;
const API = "/api/bff/api/v1/finance/legacy-fees/history";
const KINDS: HistoryKind[] = ["DIRECT", "FOR_APPROVAL", "RESET"];

const amount = (v: number | string | null | undefined) => money(Number(v ?? 0));
const count = (v: number | null | undefined) => (v == null ? "—" : v.toLocaleString());

async function read<T>(url: string): Promise<T> {
  const r = await fetch(url, { cache: "no-store" }).catch(() => null);
  const j = r ? await r.json().catch(() => null) : null;
  if (!r || !r.ok) throw (j ?? { status: r?.status ?? 0, title: r?.statusText || "The portal could not be reached" }) as Problem;
  return j as T;
}

/** tick: a change made elsewhere on the page (an upload, a start over, a decision): the history reads again */
export function OldFeesUploadHistory({ tick = 0 }: { tick?: number }) {
  const [f, setF] = useState<HistoryFilters>({});
  const [typed, setTyped] = useState("");
  const [page, setPage] = useState(1);
  const [size, setSize] = useState(SIZES[0]);
  const [data, setData] = useState<History | null>(null);
  const [answered, setAnswered] = useState<string | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [preparing, setPreparing] = useState(false);
  const [openId, setOpenId] = useState<string | null>(null);

  const listUrl = historyUrl(f, size || ALL, size ? page : 1);
  const asked = `${listUrl}#${tick}`;
  const loading = answered !== asked;

  useEffect(() => {
    let alive = true;
    void (async () => {
      try {
        const j = await read<History>(listUrl);
        if (!alive) return;
        setProblem(null);
        setData(j);
      } catch (e) {
        if (!alive) return;
        setProblem(e as Problem); notifyProblem(e as Problem);
      } finally {
        if (alive) setAnswered(asked);
      }
    })();
    return () => { alive = false; };
  }, [listUrl, asked]);

  // a filter changed starts again at page one
  const ask = (change: Partial<HistoryFilters>) => { setPage(1); setF((x) => ({ ...x, ...change })); };
  useEffect(() => {
    if (typed === (f.q ?? "")) return;
    const t = setTimeout(() => { setPage(1); setF((x) => ({ ...x, q: typed })); }, 500);
    return () => clearTimeout(t);
  }, [typed, f.q]);
  const filtered = Object.values(f).some((v) => (v ?? "").trim());

  async function excel() {
    setPreparing(true);
    try {
      const j = await read<History>(historyUrl(f, ALL, 1));
      const blob = await brandedXlsx("Old fees upload history", HISTORY_HEADERS, j.rows.map(historyRow), {
        sheetName: "Uploads", serial: docSerial("OFH"),
        sub: `${filtersInWords(f, j.people)} · ${j.total.toLocaleString()} upload${j.total === 1 ? "" : "s"}`,
      });
      downloadBlob(blob, `old-fees-upload-history${f.kind ? `-${f.kind.toLowerCase()}` : ""}.xlsx`);
    } catch (e) {
      notifyProblem(e as Problem);
    } finally {
      setPreparing(false);
    }
  }

  const t = data?.totals;
  const pages = data && size ? Math.max(1, Math.ceil(data.total / size)) : 1;
  const states: HistoryState[] = f.kind ? KIND_STATES[f.kind] : (Object.keys(HISTORY_STATE) as HistoryState[]);
  /** a figure's View all: every upload of its kind, on one page */
  const kindTile = (k: HistoryKind, sub: string): [string, string, string | null, ReactNode] => {
    const n = data?.by_kind[k] ?? 0;
    const open = f.kind === k && size === 0;
    return [KIND_WORD[k], n.toLocaleString(), null, <span key="v">{sub}<span className="blk mt-1">
      <Btn kind={open ? "primary" : "ghost"} size="sm" disabled={loading || !n}
        onClick={() => { setPage(1); if (open) { ask({ kind: "", state: "" }); setSize(SIZES[0]); } else { ask({ kind: k, state: "" }); setSize(0); } }}>
        {open ? "Back to ten a page" : "View all"}</Btn></span></span>];
  };

  return (
    <Panel title="Upload history" right="Every upload of old fees — the Bursary's own, the officer's for approval, each start over: who, when, the file and what it did">
      <PBody>
        <div className="row" style={{ flexWrap: "wrap", gap: "var(--s-3)", alignItems: "flex-end" }}>
          <Field id="ofh-from" label="From" style={{ flex: "0 1 150px" }}>
            <input id="ofh-from" type="date" className="ctl" value={f.from ?? ""} max={f.to || undefined} onChange={(e) => ask({ from: e.target.value })} />
          </Field>
          <Field id="ofh-to" label="To" style={{ flex: "0 1 150px" }}>
            <input id="ofh-to" type="date" className="ctl" value={f.to ?? ""} min={f.from || undefined} onChange={(e) => ask({ to: e.target.value })} />
          </Field>
          <Field id="ofh-kind" label="How" style={{ flex: "0 1 200px" }}>
            <select id="ofh-kind" className="ctl" value={f.kind ?? ""} onChange={(e) => ask({ kind: e.target.value as HistoryKind | "", state: "" })}>
              <option value="">Every upload</option>
              {KINDS.map((k) => <option key={k} value={k}>{KIND_WORD[k]}</option>)}
            </select>
          </Field>
          <Field id="ofh-state" label="State" style={{ flex: "0 1 190px" }}>
            <select id="ofh-state" className="ctl" value={f.state ?? ""} onChange={(e) => ask({ state: e.target.value as HistoryState | "" })}>
              <option value="">Every state</option>
              {states.map((s) => <option key={s} value={s}>{HISTORY_STATE[s][0]}</option>)}
            </select>
          </Field>
          <Field id="ofh-person" label="By" style={{ flex: "0 1 200px" }}>
            <select id="ofh-person" className="ctl" value={f.person ?? ""} onChange={(e) => ask({ person: e.target.value })}>
              <option value="">Anyone</option>
              {(data?.people ?? []).map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
            </select>
          </Field>
          <Field id="ofh-office" label="Office" style={{ flex: "0 1 150px" }}>
            <select id="ofh-office" className="ctl" value={f.office ?? ""} onChange={(e) => ask({ office: e.target.value })}>
              <option value="">Any office</option>
              {(data?.offices ?? []).map((o) => <option key={o} value={o}>{o}</option>)}
            </select>
          </Field>
          <Field id="ofh-session" label="Session" style={{ flex: "0 1 150px" }}>
            <select id="ofh-session" className="ctl" value={f.session ?? ""} onChange={(e) => ask({ session: e.target.value })}>
              <option value="">Any session</option>
              {(data?.sessions ?? []).map((s) => <option key={s} value={s}>{s}</option>)}
            </select>
          </Field>
          <Field id="ofh-q" label="Reference, file or name" style={{ flex: "1 1 200px" }}>
            <input id="ofh-q" className="ctl" value={typed} onChange={(e) => setTyped(e.target.value)} placeholder="e.g. OFL-2026 or export.xlsx" />
          </Field>
          <Btn kind="ghost" disabled={loading || preparing || !data?.total} onClick={() => void excel()}>{preparing ? "Preparing…" : "Excel"}</Btn>
          {filtered ? <Btn kind="ghost" onClick={() => { setTyped(""); setPage(1); setF({}); }}>Clear filters</Btn> : null}
          {loading && data ? <span className="sub2" role="status">Reading…</span> : null}
        </div>
      </PBody>
      {problem ? <PBody><ProblemNotice problem={problem} /></PBody> : null}
      {data && t ? (
        <>
          <PBody>
            <Tiles cls="grid--5" items={[
              kindTile("DIRECT", `${amount(t.amount)} recorded`),
              kindTile("FOR_APPROVAL", t.pending ? `${t.pending.toLocaleString()} waiting for the Bursar` : "None waiting"),
              kindTile("RESET", `${t.deleted.toLocaleString()} payment${t.deleted === 1 ? "" : "s"} deleted`),
              ["Payments recorded", t.recorded.toLocaleString(), t.recorded ? "var(--green-ink)" : null,
                t.rows_read == null ? "Rows read: not kept for rebuilt uploads" : `Of ${t.rows_read.toLocaleString()} rows read`],
              t.already == null && t.no_student == null
                ? ["Skipped", "—", null, "Not kept for rebuilt uploads"]
                : ["Skipped", ((t.already ?? 0) + (t.no_student ?? 0)).toLocaleString(), t.no_student ? "var(--red-ink)" : null,
                  `${(t.already ?? 0).toLocaleString()} already on record · ${(t.no_student ?? 0).toLocaleString()} no such student`],
            ]} />
            {data.rows.some((r) => r.rebuilt) ? (
              <div className="sub2 mt-2">
                Uploads before the history was kept are rebuilt from the payments on record: their file&rsquo;s name and what they skipped were
                not kept then, and an upload whose payments a start over deleted shows as that start over.
              </div>
            ) : null}
          </PBody>
          {data.rows.length ? (
            <DTable pageSize={0} title="Upload history" cols={["Began|mid", "Upload", "How", "By", "Rows|num", "Recorded|num", "Skipped|num", "Amount|num", "State", "|num"]}
              rows={data.rows.map((r) => [
                <span key="a" className="sub2 tnum">{when(r.at)}</span>,
                <Two key="u" a={<span style={{ whiteSpace: "nowrap" }}>{r.ref}</span>}
                  b={r.file_name ?? (r.rebuilt ? "Rebuilt from the records" : r.kind === "RESET" ? (r.note ?? "—") : "No file named")} />,
                <Two key="h" a={KIND_WORD[r.kind]} b={r.sessions ? `${r.sessions.split(", ").length} session${r.sessions.includes(",") ? "s" : ""}` : "—"} />,
                <Two key="b" a={r.by_name ?? "—"} b={r.office ?? "—"} />,
                <span key="r" className="tnum">{rowsWord(r)}</span>,
                r.kind === "RESET"
                  ? <span key="c" className="tnum" style={{ color: "var(--red-ink)" }}>{r.deleted.toLocaleString()} deleted</span>
                  : <b key="c" className="tnum">{r.recorded.toLocaleString()}</b>,
                <span key="s" className="tnum">{r.kind === "RESET" ? "—" : count(skipped(r))}</span>,
                <span key="m" className="tnum">{r.kind === "FOR_APPROVAL" ? <>{amount(r.file_amount)}<div className="sub2">stated</div></> : amount(r.amount)}</span>,
                <Pil key="st" kind={HISTORY_STATE[r.state]?.[1] ?? "grey"}>{HISTORY_STATE[r.state]?.[0] ?? r.state}</Pil>,
                <Btn key="o" kind={openId === r.id ? "primary" : "ghost"} size="sm" onClick={() => setOpenId(openId === r.id ? null : r.id)}>{openId === r.id ? "Close" : "Open"}</Btn>,
              ])} />
          ) : <PBody><div className="sub2">No upload {filtered ? "matches these filters" : "of old fees yet"}.</div></PBody>}
          {data.total > SIZES[0] ? (
            <PBody>
              <div className="row" style={{ alignItems: "center", flexWrap: "wrap", gap: "var(--s-3)" }}>
                {size ? <Btn kind="ghost" disabled={loading || page <= 1} onClick={() => setPage(page - 1)}>Previous</Btn> : null}
                <span className="sub2">{size ? `Page ${page} of ${pages} · ` : "Every upload · "}{data.total.toLocaleString()} uploads</span>
                {size ? <Btn kind="ghost" disabled={loading || page >= pages} onClick={() => setPage(page + 1)}>Next</Btn> : null}
                <label className="row row--tight sub2" style={{ marginLeft: "auto" }}>
                  Rows
                  <select className="ctl" style={{ width: "auto" }} value={size} disabled={loading} aria-label="Uploads a page"
                    onChange={(e) => { setPage(1); setSize(Number(e.target.value)); }}>
                    {SIZES.map((n) => <option key={n} value={n}>{n || "All"}</option>)}
                  </select>
                </label>
              </div>
            </PBody>
          ) : null}
          {openId ? <UploadDetail key={`${openId}#${tick}`} id={openId} onClose={() => setOpenId(null)} /> : null}
        </>
      ) : loading ? <PBody><div className="sub2" role="status">Reading the upload history…</div></PBody> : null}
    </Panel>
  );
}

type Detail = HistoryRow & { part_list: HistoryPart[] };
interface Payments { total: number; amount: number | string; page: number; size: number; rows: HistoryPayment[] }

/** one upload opened: what it is, its parts, and the payments it recorded or deleted */
function UploadDetail({ id, onClose }: { id: string; onClose: () => void }) {
  const [d, setD] = useState<Detail | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [page, setPage] = useState(1);
  const [pay, setPay] = useState<Payments | null>(null);
  const [preparing, setPreparing] = useState(false);
  const withPayments = d != null && d.kind !== "FOR_APPROVAL";

  useEffect(() => {
    let alive = true;
    read<Detail>(`${API}/${id}`).then((j) => { if (alive) setD(j); }).catch((e) => { if (alive) { setProblem(e as Problem); notifyProblem(e as Problem); } });
    return () => { alive = false; };
  }, [id]);
  useEffect(() => {
    if (!withPayments) return;
    let alive = true;
    read<Payments>(`${API}/${id}/payments?page=${page}&size=10`).then((j) => { if (alive) setPay(j); }).catch((e) => { if (alive) notifyProblem(e as Problem); });
    return () => { alive = false; };
  }, [id, page, withPayments]);

  async function excel() {
    if (!d) return;
    setPreparing(true);
    try {
      const j = await read<Payments>(`${API}/${id}/payments?page=1&size=200000`);
      const blob = await brandedXlsx(`Old fees ${d.kind === "RESET" ? "start over" : "upload"} ${d.ref}: the payments ${d.kind === "RESET" ? "deleted" : "recorded"}`,
        PAYMENT_HEADERS, j.rows.map(paymentRow), {
          sheetName: "Payments", serial: docSerial("OFP"),
          sub: `${d.file_name ?? KIND_WORD[d.kind]} · ${when(d.at)} · ${j.total.toLocaleString()} payment${j.total === 1 ? "" : "s"}, ${amount(j.amount)}`,
        });
      downloadBlob(blob, `old-fees-${d.ref.toLowerCase()}-payments.xlsx`);
    } catch (e) {
      notifyProblem(e as Problem);
    } finally {
      setPreparing(false);
    }
  }

  if (problem) return <PBody><ProblemNotice problem={problem} /></PBody>;
  if (!d) return <PBody><div className="sub2" role="status">Opening the upload…</div></PBody>;
  const reset = d.kind === "RESET";
  const pages = pay ? Math.max(1, Math.ceil(pay.total / 10)) : 1;
  return (
    <PBody>
      <Note kind="info" title={`${d.ref} · ${KIND_WORD[d.kind]} · ${HISTORY_STATE[d.state]?.[0] ?? d.state}`} action={<Btn kind="ghost" size="sm" onClick={onClose}>Close</Btn>}>
        {d.rebuilt ? (reset ? "Rebuilt from what the start over kept. " : "Rebuilt from the payments on record: the file's name and what was skipped were not kept then. ") : null}
        {d.kind === "FOR_APPROVAL" ? "Its rows and the Bursar's check are under Uploads for the Bursar's approval above. " : null}
        {d.state === "STOPPED" ? "It stopped part-way: choose the file again and load it; rows already on record are skipped, never twice. " : null}
        {d.note && !d.rebuilt ? <>Note: {d.note}</> : null}
      </Note>
      <div className="mt-3">
        <KvGrid pairs={[
          ["File", d.file_name ?? "—"],
          ["By", d.by_name ? `${d.by_name}${d.office ? ` (${d.office})` : ""}` : "—"],
          ["Began", when(d.at)],
          ["Ended", when(d.finished_at)],
          ...(reset ? [
            ["Payments deleted", d.deleted.toLocaleString()],
            ["Amount deleted", amount(d.amount)],
          ] as [string, string][] : [
            ["Rows in the file", count(d.file_rows)],
            ["Rows read", count(d.rows_read)],
            ["Payments recorded", d.recorded.toLocaleString()],
            ["Already on record", count(d.already)],
            ["No such student", count(d.no_student)],
            ["Nothing to settle", count(d.no_due)],
            ["Added beside another", count(d.separate)],
            ["Taken over", count(d.taken_over)],
            ["Corrected", count(d.corrected)],
            ["No usable date", count(d.undated)],
            ["Amount stated in the file", d.file_amount == null ? "—" : amount(d.file_amount)],
            ["Amount recorded", d.kind === "FOR_APPROVAL" ? "—" : amount(d.amount)],
          ] as [string, string][]),
          ["Students", d.students.toLocaleString()],
          ["Sessions", d.sessions || "—"],
          ...(d.kind === "FOR_APPROVAL" ? [["Decided by", d.decided_by_name ?? "—"], ["Decided", when(d.decided_at)]] as [string, string][] : []),
        ]} />
      </div>
      {d.part_list.length ? (
        <div className="mt-3">
          <div className="sub2 mb-1"><b>{reset ? "Batches" : "Parts"}</b> · {d.part_list.length.toLocaleString()}</div>
          {reset ? (
            <DTable title={`${d.ref} batches`} cols={["Batch|num", "Deleted at|mid", "Payments deleted|num", "Amount|num"]}
              rows={d.part_list.map((p) => [p.seq, when(p.at), (p.deleted ?? 0).toLocaleString(), amount(p.amount)])} />
          ) : d.kind === "FOR_APPROVAL" ? (
            <DTable title={`${d.ref} parts`} cols={["Part|num", "Rows sent|num"]} rows={d.part_list.map((p) => [p.seq, count(p.rows_read)])} />
          ) : (
            <DTable title={`${d.ref} parts`} cols={["Part|num", "Rows of the file|mid", "Loaded|mid", "Read|num", "Recorded|num", "Already|num", "No such student|num", "Nothing to settle|num", "Amount|num", "Sent again|num"]}
              rows={d.part_list.map((p) => [p.seq, partRows(p), when(p.at), count(p.rows_read), (p.recorded ?? 0).toLocaleString(),
                p.duplicates == null && p.matched == null ? "—" : ((p.duplicates ?? 0) + (p.matched ?? 0)).toLocaleString(), count(p.no_student), count(p.no_due),
                amount(p.amount), p.resent ? p.resent.toLocaleString() : "—"])} />
          )}
        </div>
      ) : null}
      {withPayments ? (
        <div className="mt-3">
          <div className="row" style={{ alignItems: "center", flexWrap: "wrap", gap: "var(--s-3)" }}>
            <span className="sub2"><b>{reset ? "Payments deleted" : "Payments recorded (those still on record)"}</b>{pay ? ` · ${pay.total.toLocaleString()}, ${amount(pay.amount)}` : " · reading…"}</span>
            <Btn kind="ghost" size="sm" disabled={preparing || !pay?.total} onClick={() => void excel()} >{preparing ? "Preparing…" : "Excel"}</Btn>
          </div>
          {pay && pay.rows.length ? (
            <>
              <DTable pageSize={0} title={`${d.ref} payments`} cols={["Part|num", "Student", "Session|mid", "Purpose", "Amount|num", "Paid on|mid", "Reference"]}
                rows={pay.rows.map((p) => [p.part, <Two key="s" a={p.name || "—"} b={p.number ?? "—"} />, p.session, p.purpose, amount(p.amount),
                  p.paid_on ? p.paid_on.slice(0, 10) : "—", <Two key="r" a={p.reference} b={p.payref ?? p.receipt_no ?? ""} />])} />
              {pay.total > 10 ? (
                <div className="row mt-2" style={{ alignItems: "center", gap: "var(--s-3)" }}>
                  <Btn kind="ghost" size="sm" disabled={page <= 1} onClick={() => setPage(page - 1)}>Previous</Btn>
                  <span className="sub2">Page {page} of {pages.toLocaleString()}</span>
                  <Btn kind="ghost" size="sm" disabled={page >= pages} onClick={() => setPage(page + 1)}>Next</Btn>
                </div>
              ) : null}
            </>
          ) : pay ? <div className="sub2 mt-2">{reset ? "None kept." : "None of its payments is on record now (a start over may have deleted them)."}</div> : null}
        </div>
      ) : null}
    </PBody>
  );
}
