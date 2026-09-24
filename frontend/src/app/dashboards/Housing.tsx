import type { Me } from "@/components/proto/Shell";
import type { HostelDeskData } from "@/lib/hostel";
import { LinkBtn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";

/** The Deputy Registrar (Housing, Welfare and Passages) home: the accommodation draw at a glance —
 *  beds, allocations, reserves and the maintenance still open — from the hostel module (V038). */
export function HousingDashboard({ me, desk }: { me: Me | null; desk: HostelDeskData | null }) {
  if (!desk) return <Note kind="bad" title="The accommodation figures could not be read">The dashboard reads the hostel module; it did not answer. Open the hostel desk from the menu.</Note>;
  const c = desk.counts;
  const drawn = !!desk.setting?.drawn_at;
  const openMaint = (desk.maintenance ?? []).filter((m) => m.state !== "FIXED");
  return (
    <>
      {!desk.setting ? (
        <Note kind="bad" title={`Accommodation is not stated for ${desk.session}`} action={<LinkBtn kind="urgent" href="/hostel">State the session</LinkBtn>}>
          Set the fee and the application close date before students can apply and the draw can run.
        </Note>
      ) : !drawn ? (
        <Note kind="info" title={`${c.applications} application${Number(c.applications) === 1 ? "" : "s"} in, draw not yet run`} action={<LinkBtn kind="primary" href="/hostel">Run the draw</LinkBtn>}>
          The draw allocates beds from a published seed, priority names first. Reserves fill the holds that lapse.
        </Note>
      ) : (
        <Note kind="ok" title={`Draw run for ${desk.session}`} action={<LinkBtn kind="ghost" href="/hostel">Open the hostel desk</LinkBtn>}>
          {c.allocated} allocated, {c.confirmed} confirmed, {c.reserves} on the reserve list. Lapse expired holds to pass beds to the next name.
        </Note>
      )}

      <Tiles items={[
        ["Beds", Number(c.beds).toLocaleString(), null, `${c.out_of_service} out of service · ${c.free} free`],
        ["Allocated", String(c.allocated), null, `${c.priority} by priority`, "/hostel"],
        ["Confirmed", String(c.confirmed), Number(c.confirmed) ? "var(--green-ink)" : null, "Paid and taken up"],
        ["Applications", String(c.applications), null, `${c.reserves} on the reserve list`],
      ]} />

      <Panel title="Maintenance" right={openMaint.length ? `${openMaint.length} open` : "Nothing open"}>
        {openMaint.length ? (
          <DTable cols={["Issue", "Where", "Status|num"]}
            rows={openMaint.slice(0, 10).map((m) => [
              <span key="i">{m.issue}</span>,
              <span className="sub2" key="w">{[m.hall_name, m.block, m.room_no].filter(Boolean).join(" ") || "—"}</span>,
              <Pil kind={m.state === "RAISED" ? "bad" : "info"} key="s">{m.state === "RAISED" ? "Raised" : m.state === "ASSIGNED" ? "Assigned" : m.state}</Pil>,
            ])} texts={openMaint.map((m) => `${m.issue} ${m.hall_name ?? ""}`)} />
        ) : <PBody><div className="sub2">No maintenance is open. A student&rsquo;s report appears here to be assigned and fixed.</div></PBody>}
      </Panel>

      <Panel title="Housing desks" right={me?.name ? `Signed in as ${me.name}` : "Housing & Welfare"}>
        <PBody>
          <div className="grid--fill">
            <LinkBtn kind="ghost" href="/hostel">Hostel &amp; allocation</LinkBtn>
            <LinkBtn kind="ghost" href="/clearance">Student clearance</LinkBtn>
            <LinkBtn kind="ghost" href="/support">Help &amp; requests</LinkBtn>
          </div>
        </PBody>
      </Panel>
    </>
  );
}
