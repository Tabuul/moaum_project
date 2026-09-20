import type { Me } from "@/components/proto/Shell";
import type { ClinicDesk } from "@/lib/health";
import { Note, Panel, PBody, Pil, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";

const at = (iso: string) => { try { return new Date(iso).toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit" }); } catch { return "—"; } };

/** The Support Services office's home, centred on University Health Services: the clinic's own
 *  figures, the patients waiting now, and the desks this office works. Clinical notes never leave
 *  the health module — this shows counts and the queue, never a record. */
export function ClinicDashboard({ me, desk }: { me: Me | null; desk: ClinicDesk | null }) {
  const t = desk?.tiles;
  const waiting = desk?.waiting ?? [];
  return (
    <>
      <Note kind="info" title="University Health Services">
        Your home is the clinic. Patients arrive as walk-ins or from a booking, wait here for triage, and leave with an
        outcome on the record. The figures below are the clinic&rsquo;s own; the clinical note stays inside the module.
      </Note>

      <Tiles items={[
        ["Waiting now", String(t?.waiting ?? 0), (t?.waiting ?? 0) ? "var(--red-ink)" : "var(--green-ink)",
          (t?.waiting ?? 0) ? `Longest wait ${t?.longest_wait_min ?? 0} min` : "Nobody waiting", "/clinic"],
        ["Encounters today", String(t?.encounters_today ?? 0), null, "Walk-in and booked", "/clinic"],
        ["Booked for today", String(t?.booked_today ?? 0), null, "Appointments expected", "/clinic"],
        ["Referrals this month", String(t?.referrals_month ?? 0), null, "Sent on for further care"],
      ]} />

      <Panel title="Waiting now" right={<a href="/clinic" className="btn btn--primary btn--sm">Open the clinic</a>}>
        {waiting.length ? (
          <DTable cols={["Arrived|mid", "Patient", "Presenting", "Triage|mid"]}
            rows={waiting.slice(0, 10).map((w) => [
              <span className="tnum" key="t">{at(w.arrived_at)}</span>,
              <Two key="p" a={w.patient} b={w.number} />,
              <span key="r">{w.presenting}</span>,
              <Pil kind={w.triage === "URGENT" ? "bad" : w.triage === "PRIORITY" ? "info" : "grey"} key="g">{w.triage}</Pil>,
            ])} />
        ) : (
          <PBody><div className="sub2">Nobody is waiting. New arrivals appear here the moment they are added to the list on the clinic desk.</div></PBody>
        )}
      </Panel>

      <Panel title="Support Services desks" right="What this office works">
        <PBody>
          <div style={{ display: "grid", gap: 8, gridTemplateColumns: "repeat(auto-fill, minmax(200px, 1fr))" }}>
            <a href="/clinic" className="btn btn--ghost btn--sm">Clinic</a>
            <a href="/library/circulation" className="btn btn--ghost btn--sm">Library circulation</a>
            <a href="/stores" className="btn btn--ghost btn--sm">Stores &amp; assets</a>
            <a href="/clearance" className="btn btn--ghost btn--sm">Student clearance</a>
          </div>
          <div className="sub2" style={{ marginTop: 8 }}>{me?.name ? `Signed in as ${me.name}.` : ""} Every act is on the record, in your name.</div>
        </PBody>
      </Panel>
    </>
  );
}
