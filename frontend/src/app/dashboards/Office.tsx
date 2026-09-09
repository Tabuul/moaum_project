import type { Me } from "@/components/proto/Shell";
import { KvGrid, Note, Panel, PBody, Tiles } from "@/components/proto/ui";
import { officeLabel, roleUnit } from "@/lib/offices";

/** An office whose dashboard arrives with its module: what the portal can say, and no invented figure. */
export function OfficeDashboard({ me, requestsOpen = null }: { me: Me | null; requestsOpen?: number | null }) {
  const label = officeLabel(me?.activeOffice);
  return (
    <>
      <Note kind="info" title={`The ${label}'s dashboard arrives with its module`}>
        The menu on the left is this office&rsquo;s, exactly as designed; the screens it can already reach are the portal&rsquo;s, and the rest say so when pressed. The figures this dashboard will carry come from modules not yet on the portal, so none are shown here.
      </Note>
      <Tiles items={[
        ["Signed in as", me?.name ?? label, null, me?.staffNumber ?? ""],
        ["Acting as", label, null, roleUnit(me?.activeOffice) || "The University"],
        ["Offices held", String(me?.offices.length ?? 0), null, "Under dated instruments"],
        ["Session", "2026/2027", null, "As the calendar names it"],
      ]} />
      {requestsOpen !== null ? (
        <Note kind={requestsOpen ? "bad" : "ok"} title={requestsOpen ? `${requestsOpen} request${requestsOpen === 1 ? "" : "s"} from students waiting on this office` : "No request from a student is waiting on this office"}>
          {requestsOpen ? "The oldest is at the top of the Help & requests desk; an answer is recorded in your name and the student is told." : "Requests students put to this office arrive on the Help & requests desk."} <a href="/support">Open the desk</a>.
        </Note>
      ) : null}
      <Panel title="Your offices">
        <PBody>
          <KvGrid cls="grid--3" pairs={(me?.offices ?? []).map((o) => [officeLabel(o), roleUnit(o) || "The University"])} />
        </PBody>
      </Panel>
    </>
  );
}
