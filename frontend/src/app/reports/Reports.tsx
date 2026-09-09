"use client";

import { useRouter } from "next/navigation";
import { Note, Panel } from "@/components/proto/ui";
import { REPORTS } from "@/lib/report";

/** The returns desk: pick a session, then open a return. Each return opens as a
 *  branded, printable document with a CSV beside it. Only the returns this office
 *  may take are shown. */
export function Reports({ session, sessions, activeOffice }: {
  session: string; sessions: { name: string; state: string }[]; activeOffice: string | null;
}) {
  const router = useRouter();
  const mine = REPORTS.filter((r) => activeOffice != null && r.offices.includes(activeOffice));
  const pick = (name: string) => router.push(`/reports?session=${encodeURIComponent(name)}`);
  const open = (slug: string) => router.push(`/reports/${slug}/view?session=${encodeURIComponent(session)}`);

  return (
    <>
      <Note kind="info" title="The University's returns, read off the register">
        A return is a view of the record for a session — the crest, the figures, and the footing that says it is verified against the
        register, not by its appearance. Open one to read it on screen, print it or save it as a PDF, or take the same rows as a CSV.
      </Note>

      <Panel title="Choose a session" right={sessions.find((s) => s.name === session)?.state ?? ""}>
        <div className="card__body" style={{ display: "flex", gap: 8, flexWrap: "wrap", alignItems: "flex-end" }}>
          <div className="field" style={{ flexGrow: 1, minWidth: 280 }}>
            <label htmlFor="rp-session">Session</label>
            <select id="rp-session" className="ctl" value={session} onChange={(e) => pick(e.target.value)}>
              {sessions.length ? sessions.map((s) => <option key={s.name} value={s.name}>{s.name}{s.state === "CURRENT" ? " · current" : ""}</option>)
                : <option value={session}>{session}</option>}
            </select>
          </div>
        </div>
      </Panel>

      {mine.length ? (
        <div className="grid grid--2" style={{ gap: 12 }}>
          {mine.map((r) => (
            <button key={r.slug} type="button" className="card rpt-card" onClick={() => open(r.slug)}
                    style={{ textAlign: "left", cursor: "pointer", border: "1px solid var(--line)", background: "var(--surface)" }}>
              <div className="card__body">
                <div style={{ fontWeight: 650, fontSize: 15 }}>{r.title}</div>
                <div className="sub2" style={{ marginTop: 4 }}>{r.subtitle}</div>
                <div className="sub2" style={{ marginTop: 10, color: "var(--chrome)", fontWeight: 600 }}>Open return →</div>
              </div>
            </button>
          ))}
        </div>
      ) : (
        <Note kind="info" title="No returns for this office">This office does not take any of the portal&rsquo;s returns.</Note>
      )}
    </>
  );
}
