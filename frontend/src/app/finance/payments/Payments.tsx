"use client";

/** t/payments — the Bursary's payments query. Confirmed student payments, newest first, sliced by
 *  session, faculty, department, programme, level, payment category and channel. Every figure is read
 *  from the record; the filters are server-side, so the count and total are the whole matching set,
 *  not just the page shown. Exports carry the crest, the title and a serial. */
import { useRouter } from "next/navigation";
import { when } from "@/lib/bursary";
import { Btn, Note, Panel, PBody, Two, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, money } from "@/components/proto/blocks";
import { SearchSelect } from "@/components/proto/SearchSelect";
import { brandedXlsx, brandedPrint, downloadBlob, docSerial } from "@/lib/exportbrand";

interface Row {
  reference: string; confirmed_at: string; payer: string; number: string;
  programme_code: string; programme: string; dept_code: string; dept: string;
  faculty_code: string; faculty: string; level: number; purpose: string; category: string;
  channel: string; amount: number; receipt_no: string | null; session: string;
}
interface Opt { code: string; name: string; faculty_code?: string; dept_code?: string }
export interface PaymentsData {
  rows: Row[]; count: number; total: number;
  options: { sessions: string[]; faculties: Opt[]; departments: Opt[]; programmes: Opt[]; categories: string[]; channels: string[] };
}
export interface Filters {
  session: string; faculty: string; dept: string; programme: string; level: string; category: string; channel: string; from: string; to: string;
}

const LEVELS = ["100", "200", "300", "400", "500", "600"];

export function Payments({ d, filters }: { d: PaymentsData; filters: Filters }) {
  const router = useRouter();
  const o = d.options;

  /* changing one filter clears the ones that depend on it, so a stale department can't sit under a new faculty */
  function go(next: Partial<Filters>) {
    const f: Filters = { ...filters, ...next };
    if (next.faculty !== undefined) { f.dept = ""; f.programme = ""; }
    if (next.dept !== undefined) { f.programme = ""; }
    const q = new URLSearchParams();
    for (const [k, v] of Object.entries(f)) if (v) q.set(k, v);
    router.push(`/finance/payments${q.toString() ? `?${q}` : ""}`);
  }

  const depts = o.departments.filter((x) => !filters.faculty || x.faculty_code === filters.faculty);
  const progs = o.programmes.filter((x) => (!filters.faculty || x.faculty_code === filters.faculty) && (!filters.dept || x.dept_code === filters.dept));
  const active = Object.values(filters).some(Boolean);
  const scope = [
    filters.session, o.faculties.find((f) => f.code === filters.faculty)?.name,
    o.departments.find((x) => x.code === filters.dept)?.name,
    o.programmes.find((p) => p.code === filters.programme)?.name,
    filters.level && `${filters.level} Level`, filters.category, filters.channel,
    filters.from && `from ${filters.from}`, filters.to && `to ${filters.to}`,
  ].filter(Boolean).join(" · ") || "All confirmed student payments";

  const XCOLS = ["When", "Payer", "Number", "Faculty", "Programme", "Level", "Category", "Channel", "Amount", "Receipt", "Reference", "Session"];
  const xrows = () => d.rows.map((r) => [when(r.confirmed_at), r.payer, r.number, r.faculty, r.programme, r.level, r.category, r.channel, Number(r.amount), r.receipt_no ?? "", r.reference, r.session]);

  async function toExcel() {
    const serial = docSerial("PAY");
    const blob = await brandedXlsx("Payments query", XCOLS, xrows(), { sheetName: "Payments", serial, sub: scope });
    downloadBlob(blob, `payments-${serial.replace(/\//g, "-")}.xlsx`);
  }
  function toPdf() {
    brandedPrint("Payments query", scope, XCOLS, xrows(), docSerial("PAY"));
  }

  return (
    <>
      <Note kind="info" title="Payments, queried from the record">
        Confirmed student payments, newest first. Choose any combination of session, faculty, department, programme, level, payment category and channel; the count and the total below are the whole matching set. Payments are charged per session, so there is no semester to choose. Applicant application and acceptance fees are on the day-book ledger.
      </Note>

      <Panel title="Query" right={active ? <Btn kind="ghost" onClick={() => router.push("/finance/payments")}>Clear filters</Btn> : undefined}>
        <PBody>
          <div className="grid grid--4">
            <Field id="pq-ses" label="Session">
              <SearchSelect id="pq-ses" value={filters.session} allLabel="All sessions" placeholder="Search a session…"
                options={o.sessions.map((s) => ({ value: s, label: s }))} onChange={(v) => go({ session: v })} />
            </Field>
            <Field id="pq-fac" label="Faculty">
              <SearchSelect id="pq-fac" value={filters.faculty} allLabel="All faculties" placeholder="Search a faculty…"
                options={o.faculties.map((f) => ({ value: f.code, label: f.name }))} onChange={(v) => go({ faculty: v })} />
            </Field>
            <Field id="pq-dept" label="Department">
              <SearchSelect id="pq-dept" value={filters.dept} allLabel="All departments" placeholder="Search a department…"
                options={depts.map((x) => ({ value: x.code, label: x.name }))} onChange={(v) => go({ dept: v })} />
            </Field>
            <Field id="pq-prog" label="Programme">
              <SearchSelect id="pq-prog" value={filters.programme} allLabel="All programmes" placeholder="Search a programme…"
                options={progs.map((p) => ({ value: p.code, label: p.name }))} onChange={(v) => go({ programme: v })} />
            </Field>
            <Field id="pq-lvl" label="Level">
              <SearchSelect id="pq-lvl" value={filters.level} allLabel="All levels" placeholder="Level…"
                options={LEVELS.map((l) => ({ value: l, label: `${l} Level` }))} onChange={(v) => go({ level: v })} />
            </Field>
            <Field id="pq-cat" label="Payment category">
              <SearchSelect id="pq-cat" value={filters.category} allLabel="All categories" placeholder="Category…"
                options={o.categories.map((c) => ({ value: c, label: c }))} onChange={(v) => go({ category: v })} />
            </Field>
            <Field id="pq-chn" label="Channel">
              <SearchSelect id="pq-chn" value={filters.channel} allLabel="All channels" placeholder="Channel…"
                options={o.channels.map((c) => ({ value: c, label: c }))} onChange={(v) => go({ channel: v })} />
            </Field>
            <div className="grid grid--2" style={{ gap: 8 }}>
              <Field id="pq-from" label="From"><input id="pq-from" type="date" className="ctl" value={filters.from} onChange={(e) => go({ from: e.target.value })} /></Field>
              <Field id="pq-to" label="To"><input id="pq-to" type="date" className="ctl" value={filters.to} onChange={(e) => go({ to: e.target.value })} /></Field>
            </div>
          </div>
        </PBody>
      </Panel>

      <Tiles items={[
        ["Payments matched", Number(d.count).toLocaleString(), null, active ? "for the filters above" : "all confirmed payments"],
        ["Total collected", money(Number(d.total)), Number(d.total) ? "var(--green-ink)" : null, "sum of the matching payments"],
        ["Showing", `${d.rows.length.toLocaleString()}${d.count > d.rows.length ? " of " + Number(d.count).toLocaleString() : ""}`, null, d.count > d.rows.length ? "newest first — narrow the filters to see the rest" : "newest first"],
        ["Scope", active ? "Filtered" : "Everything", null, scope.length > 40 ? scope.slice(0, 40) + "…" : scope],
      ]} />

      <Panel title="Payments" right={<span style={{ display: "inline-flex", gap: 8 }}>
        <Btn kind="ghost" disabled={!d.rows.length} onClick={() => void toExcel()}>Export Excel</Btn>
        <Btn kind="ghost" disabled={!d.rows.length} onClick={toPdf}>Export PDF</Btn>
      </span>}>
        {d.rows.length ? (
          <DTable
            cols={["When|mid", "Payer", "Programme", "Level|mid", "Category", "Channel", "Amount|num", "Receipt|num"]}
            texts={d.rows.map((r) => `${r.payer} ${r.number} ${r.programme} ${r.category} ${r.channel}`)}
            rows={d.rows.map((r) => [
              <span className="tnum sub2" key="w">{when(r.confirmed_at)}</span>,
              <Two key="p" a={r.payer} b={`${r.number} · ${r.faculty}`} />,
              <span className="sub2" key="pr">{r.programme}</span>,
              <span className="tnum" key="l">{r.level}</span>,
              <span className="sub2" key="c">{r.category}</span>,
              <span className="sub2" key="ch">{r.channel}</span>,
              <b className="tnum" key="a">{money(Number(r.amount))}</b>,
              <span className="tnum sub2" key="r">{r.receipt_no ?? r.reference}</span>,
            ])} />
        ) : <PBody><div className="sub2">No confirmed payment matches this query. Widen the filters, or clear them to see every payment.</div></PBody>}
      </Panel>
    </>
  );
}
