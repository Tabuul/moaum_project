"use client";

/** t/readiness — go-live readiness: each configuration gate that silently blocks part of launch, checked
 *  live, with a link to fix each. Read-only; nothing here changes state. The admission exercise is checked for the
 *  intake session (the session candidates apply into), registration and fees for the running session. */
import { useQueryNav } from "@/lib/query-nav";
import { LinkBtn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { Field } from "@/components/proto/blocks";

export interface Check { group?: "intake" | "running" | "institution"; key: string; label: string; status: "ok" | "warn" | "bad"; detail: string; fix: string | null }
export interface Readiness { session: string; intakeSession?: string; ready: boolean; blocking: number; warnings: number; checks: Check[] }

const PILL: Record<string, "ok" | "warn" | "bad"> = { ok: "ok", warn: "warn", bad: "bad" };
const WORD: Record<string, string> = { ok: "Ready", warn: "Check", bad: "Blocking" };

function Gates({ title, checks }: { title: string; checks: Check[] }) {
  if (!checks.length) return null;
  const ok = checks.filter((c) => c.status === "ok").length;
  return (
    <Panel title={title} right={`${ok} of ${checks.length} ready`}>
      <PBody>
        <div className="stack">
          {checks.map((c) => (
            <div key={c.key} className="row row--top" style={{ gap: "var(--s-3)", padding: "var(--s-3) 0", borderTop: "1px solid var(--line)" }}>
              <Pil kind={PILL[c.status]}>{WORD[c.status]}</Pil>
              <div className="grow">
                <div className="b600">{c.label}</div>
                <div className="sub2" style={{ lineHeight: 1.35 }}>{c.detail}</div>
              </div>
              {c.fix && c.status !== "ok" ? <LinkBtn href={c.fix} kind="ghost">Fix</LinkBtn> : null}
            </div>
          ))}
        </div>
      </PBody>
    </Panel>
  );
}

export function ReadinessView({ data, sessions }: { data: Readiness; sessions: string[] }) {
  const queryNav = useQueryNav();
  const intake = data.intakeSession ?? data.session;
  const ok = data.checks.filter((c) => c.status === "ok").length;
  const go = (running: string, admission: string) => queryNav(`/readiness?session=${encodeURIComponent(running)}&intake=${encodeURIComponent(admission)}`);
  const choices = (value: string) => (sessions.includes(value) ? sessions : [value, ...sessions]);
  return (
    <>
      <Note kind={data.blocking ? "bad" : data.warnings ? "info" : "ok"}
        title={data.blocking ? `${data.blocking} thing${data.blocking === 1 ? "" : "s"} to fix before launch`
          : data.warnings ? `No blockers; ${data.warnings} thing${data.warnings === 1 ? "" : "s"} to review`
          : "Ready to go live"}>
        Admissions are checked for {intake}; registration, school fees and clearance for {data.session}.
      </Note>

      <div className="card"><div className="card__body row row--end" style={{ flexWrap: "wrap", gap: "var(--s-3)" }}>
        <div style={{ minWidth: 160 }}><Field id="rd-i" label="Admission session">
          <select id="rd-i" className="ctl" value={intake} onChange={(e) => go(data.session, e.target.value)}>
            {choices(intake).map((x) => <option key={x} value={x}>{x}</option>)}
          </select>
        </Field></div>
        <div style={{ minWidth: 160 }}><Field id="rd-s" label="Running session">
          <select id="rd-s" className="ctl" value={data.session} onChange={(e) => go(e.target.value, intake)}>
            {choices(data.session).map((x) => <option key={x} value={x}>{x}</option>)}
          </select>
        </Field></div>
      </div></div>

      <Tiles items={[
        ["Ready", String(ok), "var(--green-ink)", "Gates that are set"],
        ["Blocking", String(data.blocking), data.blocking ? "var(--red-ink)" : null, "Must fix before launch"],
        ["To review", String(data.warnings), data.warnings ? "var(--chrome)" : null, "Not blocking, but confirm"],
        ["Total checks", String(data.checks.length), null, `${intake} admissions · ${data.session}`],
      ]} />

      <Gates title={`Admission exercise · ${intake}`} checks={data.checks.filter((c) => c.group === "intake")} />
      <Gates title={`Running session · ${data.session}`} checks={data.checks.filter((c) => c.group === "running")} />
      <Gates title="Across the University" checks={data.checks.filter((c) => c.group === "institution" || !c.group)} />
    </>
  );
}
