"use client";

/** Period over period on the returns desk: the last three sessions side by side and the last six
 *  months, each as a chart above its table — a chart is for seeing the shape, a table for quoting the
 *  number — with the change against the previous period. The figures are the returns' own. */
import type { ReactNode } from "react";
import { Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { HBars, Line, Stack, VZ, vzNum } from "@/components/proto/vz";
import { money } from "@/lib/format";

export interface SessionTrend {
  session: string; admitted: number; female: number; male: number; postgraduate: number;
  candidates: number; offered: number; accepted: number; pg_applications: number; pg_offered: number; fees_confirmed: number;
}
export interface MonthTrend { month: string; label: string; fees: number; payments: number; paid: number; raised: number }

const N = (x: unknown) => Number(x ?? 0);

/** the change against the previous period, as a pill: up, down, flat, or nothing to compare */
function delta(cur: number, prev: number | null, moneyish = false): ReactNode {
  if (prev == null) return <span className="sub2">—</span>;
  const d = cur - prev;
  if (d === 0) return <Pil kind="grey">no change</Pil>;
  const pct = prev > 0 ? ` (${d > 0 ? "+" : ""}${Math.round((100 * d) / prev)}%)` : "";
  const txt = `${d > 0 ? "+" : "−"}${moneyish ? money(Math.abs(d)) : vzNum(Math.abs(d))}${pct}`;
  return <Pil kind={d > 0 ? "ok" : "warn"}>{txt}</Pil>;
}

function niceMax(v: number) {
  if (v <= 0) return 1;
  const p = Math.pow(10, Math.floor(Math.log10(v)));
  const f = v / p;
  return (f <= 1 ? 1 : f <= 2 ? 2 : f <= 5 ? 5 : 10) * p;
}

export function Trends({ sessions, months }: { sessions: SessionTrend[]; months: MonthTrend[] }) {
  const ss = sessions.map((s) => ({ ...s, admitted: N(s.admitted), female: N(s.female), male: N(s.male), postgraduate: N(s.postgraduate),
    candidates: N(s.candidates), offered: N(s.offered), accepted: N(s.accepted), pg_applications: N(s.pg_applications), pg_offered: N(s.pg_offered), fees_confirmed: N(s.fees_confirmed) }));
  const mm = months.map((m) => ({ ...m, fees: N(m.fees), payments: N(m.payments), paid: N(m.paid), raised: N(m.raised) }));
  const anySession = ss.some((s) => s.admitted || s.candidates || s.pg_applications || s.fees_confirmed);
  const anyMonth = mm.some((m) => m.fees || m.paid || m.raised);
  const yMax = niceMax(Math.max(1, ...mm.map((m) => Math.max(m.fees, m.paid))));

  return (
    <>
      <div className="grid grid--2" style={{ alignItems: "start" }}>
        <Panel title="Intake, session over session" right={ss.length ? `${ss[0].session} → ${ss[ss.length - 1].session}` : ""}>
          <PBody>
            {anySession ? (
              <Stack rows={ss.map((s) => ({ l: s.session, parts: [s.accepted, Math.max(0, s.offered - s.accepted), Math.max(0, s.candidates - s.offered)] }))}
                keys={[{ l: "Accepted", c: VZ.s3 }, { l: "Offered, not yet accepted", c: VZ.s1 }, { l: "Not offered", c: VZ.grid }]} />
            ) : <div className="sub2">No session has figures yet.</div>}
          </PBody>
          <DTable cols={["Session", "Candidates|num", "Offered|num", "Accepted|num", "On register|num", "Δ register|mid"]}
            rows={ss.map((s, i) => [
              <strong key="s">{s.session}</strong>,
              <span key="c" className="tnum">{vzNum(s.candidates)}</span>,
              <span key="o" className="tnum">{vzNum(s.offered)}</span>,
              <span key="a" className="tnum">{vzNum(s.accepted)}</span>,
              <span key="r" className="tnum">{vzNum(s.admitted)}<div className="sub2">{vzNum(s.female)} F · {vzNum(s.male)} M{s.postgraduate ? ` · ${vzNum(s.postgraduate)} PG` : ""}</div></span>,
              <span key="d">{delta(s.admitted, i > 0 ? ss[i - 1].admitted : null)}</span>,
            ])} texts={ss.map((s) => s.session)} />
        </Panel>

        <Panel title="Fees confirmed, session over session" right="School fees and admission fees confirmed">
          <PBody>
            {anySession ? <HBars items={ss.map((s) => ({ l: s.session, v: Math.round(s.fees_confirmed) }))} colour={VZ.s3} /> : <div className="sub2">Nothing confirmed yet.</div>}
          </PBody>
          <DTable cols={["Session", "Fees confirmed|num", "PG applications|num", "PG offered|num", "Δ fees|mid"]}
            rows={ss.map((s, i) => [
              <strong key="s">{s.session}</strong>,
              <span key="f" className="tnum">{money(s.fees_confirmed)}</span>,
              <span key="p" className="tnum">{vzNum(s.pg_applications)}</span>,
              <span key="po" className="tnum">{vzNum(s.pg_offered)}</span>,
              <span key="d">{delta(s.fees_confirmed, i > 0 ? ss[i - 1].fees_confirmed : null, true)}</span>,
            ])} texts={ss.map((s) => s.session)} />
        </Panel>
      </div>

      <Panel title="The last six months" right="Fees confirmed against vouchers paid, by month">
        <PBody>
          {anyMonth ? (
            <Line xs={mm.map((m) => m.label.slice(0, 3))} yMax={yMax} yLabel="Naira by month"
              series={[{ l: "Fees in", v: mm.map((m) => m.fees), c: VZ.s3 }, { l: "Paid out", v: mm.map((m) => m.paid), c: VZ.s2 }]} />
          ) : <div className="sub2">No fee has been confirmed and no voucher paid in the last six months.</div>}
        </PBody>
        <DTable cols={["Month", "Payments|num", "Fees confirmed|num", "Δ fees|mid", "Vouchers raised|num", "Vouchers paid|num", "Δ paid|mid"]}
          rows={mm.map((m, i) => [
            <strong key="m">{m.label}</strong>,
            <span key="n" className="tnum">{vzNum(m.payments)}</span>,
            <span key="f" className="tnum">{money(m.fees)}</span>,
            <span key="df">{delta(m.fees, i > 0 ? mm[i - 1].fees : null, true)}</span>,
            <span key="r" className="tnum">{money(m.raised)}</span>,
            <span key="p" className="tnum">{money(m.paid)}</span>,
            <span key="dp">{delta(m.paid, i > 0 ? mm[i - 1].paid : null, true)}</span>,
          ])} texts={mm.map((m) => m.label)} />
      </Panel>
    </>
  );
}
