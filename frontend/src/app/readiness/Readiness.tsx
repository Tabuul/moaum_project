"use client";

/** t/readiness — go-live readiness: each configuration gate that silently blocks part of launch, checked
 *  live, with a link to fix each. Read-only; nothing here changes state. */
import Link from "next/link";
import { useQueryNav } from "@/lib/query-nav";
import { Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";

export interface Check { key: string; label: string; status: "ok" | "warn" | "bad"; detail: string; fix: string | null }
export interface Readiness { session: string; ready: boolean; blocking: number; warnings: number; checks: Check[] }

const PILL: Record<string, "ok" | "warn" | "bad"> = { ok: "ok", warn: "warn", bad: "bad" };
const WORD: Record<string, string> = { ok: "Ready", warn: "Check", bad: "Blocking" };

export function ReadinessView({ data, sessions }: { data: Readiness; sessions: string[] }) {
  const queryNav = useQueryNav();
  const ok = data.checks.filter((c) => c.status === "ok").length;
  return (
    <>
      <Note kind={data.blocking ? "bad" : data.warnings ? "info" : "ok"}
        title={data.blocking ? `${data.blocking} thing${data.blocking === 1 ? "" : "s"} must be fixed before ${data.session} can go live`
          : data.warnings ? `${data.session} has no blockers, but ${data.warnings} thing${data.warnings === 1 ? "" : "s"} to review`
          : `${data.session} is ready to go live`}>
        {data.blocking ? "Each blocking item below stops part of launch — fix them, then this turns green." : data.warnings ? "The warnings are not blockers, but confirm each is intended before launch." : "Every launch gate for this session is set. Nothing here is blocking or unreviewed."}
      </Note>

      <div className="card"><div className="card__body" style={{ display: "flex", gap: 10, alignItems: "flex-end", flexWrap: "wrap" }}>
        <div className="field" style={{ minWidth: 160, margin: 0 }}><label htmlFor="rd-s">Session</label>
          <select id="rd-s" className="ctl" value={data.session} onChange={(e) => queryNav(`/readiness?session=${encodeURIComponent(e.target.value)}`)}>
            {(sessions.includes(data.session) ? sessions : [data.session, ...sessions]).map((x) => <option key={x} value={x}>{x}</option>)}
          </select>
        </div>
      </div></div>

      <Tiles items={[
        ["Ready", String(ok), "var(--green-ink)", "Gates that are set"],
        ["Blocking", String(data.blocking), data.blocking ? "var(--red-ink)" : null, "Must fix before launch"],
        ["To review", String(data.warnings), data.warnings ? "var(--chrome)" : null, "Not blocking, but confirm"],
        ["Total checks", String(data.checks.length), null, `For ${data.session}`],
      ]} />

      <Panel title="Launch gates" right={`${ok} of ${data.checks.length} ready`}>
        <PBody>
          <div style={{ display: "flex", flexDirection: "column", gap: 10 }}>
            {data.checks.map((c) => (
              <div key={c.key} style={{ display: "flex", gap: 12, alignItems: "flex-start", padding: "10px 0", borderTop: "1px solid var(--line)" }}>
                <Pil kind={PILL[c.status]}>{WORD[c.status]}</Pil>
                <div style={{ flexGrow: 1, minWidth: 0 }}>
                  <div style={{ fontWeight: 600 }}>{c.label}</div>
                  <div className="sub2" style={{ lineHeight: 1.35 }}>{c.detail}</div>
                </div>
                {c.fix && c.status !== "ok" ? <Link href={c.fix} className="btn btn--ghost btn--sm">Fix</Link> : null}
              </div>
            ))}
          </div>
        </PBody>
      </Panel>
    </>
  );
}
