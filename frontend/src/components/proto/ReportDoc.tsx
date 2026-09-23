import type { ReactNode } from "react";
import { money, day } from "@/lib/format";
import type { ReportColumn } from "@/lib/report";

/** A branded, printable return: the crest and the University's name, the title
 *  and session, a ruled table with a totals row, and a footer that says a return
 *  is a view of the register. It renders as a standalone document (not inside the
 *  Shell) so it prints clean; the toolbar is the only thing marked no-print. */
export function ReportDoc({
  title, subtitle, session, columns, rows, totals, note, issuedFor, toolbar, kept,
}: {
  title: string;
  subtitle: string;
  session: string;
  columns: ReportColumn[];
  rows: Record<string, string | number | null>[];
  totals?: Record<string, string | number | null> | null;
  note?: ReactNode;
  issuedFor?: string | null;
  toolbar?: ReactNode;
  /** when this is a kept copy (V229): the footing says so, with the code anyone can verify it by */
  kept?: { code: string; takenAt: string; office?: string | null; by?: string | null; filedTo?: string | null; filedAt?: string | null } | null;
}) {
  const show = (c: ReportColumn, v: string | number | null | undefined) => {
    if (v == null || v === "") return c.money ? money(0) : "—";
    return c.money ? money(Number(v)) : String(v);
  };
  const now = new Date();
  const pad = (n: number) => String(n).padStart(2, "0");
  const serial = kept ? `MOAUM/RPT/${kept.code}` : `MOAUM/RPT/${now.getFullYear()}${pad(now.getMonth() + 1)}${pad(now.getDate())}/${pad(now.getHours())}${pad(now.getMinutes())}${pad(now.getSeconds())}`;
  const generated = now.toLocaleDateString("en-GB", { day: "2-digit", month: "long", year: "numeric" });
  return (
    <div className="rpt">
      {toolbar ? <div className="rpt__toolbar no-print">{toolbar}</div> : null}
      <div className="rpt__paper">
        <header className="rpt__head">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img className="rpt__crest" src="/crest.png" alt="University crest" />
          <div>
            <div className="rpt__uni">Rev. Fr. Moses Orshio Adasu University, Makurdi</div>
            <div className="rpt__place">Makurdi, Benue State · Unified University Portal</div>
          </div>
        </header>

        <div className="rpt__banner">
          <h1 className="rpt__title">{title}</h1>
          <div className="rpt__meta">{subtitle}</div>
          <div className="rpt__session">Session {session}</div>
          <div className="rpt__meta" style={{ marginTop: 4, fontSize: 11 }}>Serial {serial} · generated {generated}</div>
        </div>

        {rows.length ? (
          <table className="rpt__table">
            <thead>
              <tr>
                {columns.map((c) => (
                  <th key={c.key} style={{ textAlign: c.align ?? (c.money ? "right" : "left") }}>{c.label}</th>
                ))}
              </tr>
            </thead>
            <tbody>
              {rows.map((r, i) => (
                <tr key={i}>
                  {columns.map((c) => (
                    <td key={c.key} style={{ textAlign: c.align ?? (c.money ? "right" : "left") }} className={c.money ? "tnum" : undefined}>
                      {show(c, r[c.key])}
                    </td>
                  ))}
                </tr>
              ))}
            </tbody>
            {totals ? (
              <tfoot>
                <tr>
                  {columns.map((c, i) => (
                    <td key={c.key} style={{ textAlign: c.align ?? (c.money ? "right" : "left") }} className={c.money ? "tnum" : undefined}>
                      {i === 0 ? "Total" : c.total ? show(c, totals[c.key]) : ""}
                    </td>
                  ))}
                </tr>
              </tfoot>
            ) : null}
          </table>
        ) : (
          <div className="rpt__empty">Nothing to return for this session yet. The figures fill as the record does.</div>
        )}

        <footer className="rpt__foot">
          {note ? <div className="rpt__note">{note}</div> : null}
          {kept ? (
            <div className="rpt__issued" style={{ fontWeight: 600 }}>
              Kept copy · taken {day(kept.takenAt)}{kept.by ? ` by ${kept.by}` : ""}{kept.office ? ` (${kept.office})` : ""}
              {kept.filedAt ? ` · filed with ${kept.filedTo} on ${day(kept.filedAt)}` : " · not yet filed"}.
              Verification code <span className="tnum">{kept.code}</span> — check it at /verify/report/{kept.code}.
            </div>
          ) : null}
          <div className="rpt__issued">
            {kept ? "Printed" : "Issued"} by the portal on {day(new Date().toISOString())}{issuedFor ? ` · ${issuedFor}` : ""}. A return is a view of the
            register, verified against it — not by its appearance.
          </div>
        </footer>
      </div>
    </div>
  );
}
