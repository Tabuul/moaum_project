import type { Me } from "@/components/proto/Shell";
import type { ClinicDesk } from "@/lib/health";
import { Note, Panel, PBody, Pil, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";

const at = (iso: string) => { try { return new Date(iso).toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit" }); } catch { return "—"; } };
const dayAt = (iso: string) => { try { return new Date(iso).toLocaleString("en-GB", { weekday: "short", hour: "2-digit", minute: "2-digit" }); } catch { return "—"; } };

/** The Support Services office's home, centred on University Health Services: the clinic's own
 *  figures, the patients waiting now, and the desks this office works. Clinical notes never leave
 *  the health module — this shows counts and the queue, never a record. */
export function ClinicDashboard({ me, desk }: { me: Me | null; desk: ClinicDesk | null }) {
  const t = desk?.tiles;
  const waiting = desk?.waiting ?? [];
  const booked = desk?.booked ?? [];
  const concluded = desk?.concluded ?? [];
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

      <Panel title="Booked" right={`${booked.length} for today and tomorrow`}>
        {booked.length ? (
          <DTable cols={["When|mid", "Patient", "Reason", "Status|mid"]}
            rows={booked.slice(0, 10).map((b) => [
              <span className="tnum" key="t">{dayAt(b.preferred_at)}</span>,
              <Two key="p" a={b.patient} b={b.number} />,
              <span key="r">{b.reason}</span>,
              <Pil kind="grey" key="s">{b.state}</Pil>,
            ])} />
        ) : (
          <PBody><div className="sub2">No appointment is booked. A student books from their health page, and it appears here to be marked arrived.</div></PBody>
        )}
      </Panel>

      <Panel title="Concluded today" right={String(concluded.length)}>
        {concluded.length ? (
          <DTable cols={["Time|mid", "Patient", "Outcome", "Referred to|mid"]}
            rows={concluded.slice(0, 10).map((c) => [
              <span className="tnum" key="t">{at(c.concluded_at)}</span>,
              <Two key="p" a={c.patient} b={c.number} />,
              <span key="o">{c.outcome}</span>,
              c.referred_to ? <span className="sub2" key="r">{c.referred_to}</span> : <span className="sub2" key="r">&mdash;</span>,
            ])} />
        ) : (
          <PBody><div className="sub2">Nothing concluded yet today. A visit moves here once the clinician records its outcome.</div></PBody>
        )}
      </Panel>

      <Panel title="Support Services desks" right="What this office works">
        <PBody>
          <div className="grid--fill">
            <a href="/clinic" className="btn btn--ghost btn--sm">Clinic</a>
            <a href="/library/circulation" className="btn btn--ghost btn--sm">Library circulation</a>
            <a href="/stores" className="btn btn--ghost btn--sm">Stores &amp; assets</a>
            <a href="/clearance" className="btn btn--ghost btn--sm">Student clearance</a>
          </div>
          <div className="sub2 mt-2">{me?.name ? `Signed in as ${me.name}.` : ""} Every act is on the record, in your name.</div>
        </PBody>
      </Panel>
    </>
  );
}
