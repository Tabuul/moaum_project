import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { Note, Panel, PBody } from "@/components/proto/ui";

export const dynamic = "force-dynamic";

/** t/ethics — research ethics review and the open-access repository (framework). */
export default async function EthicsPage() {
  const me = await api<Me>("/api/v1/iam/me");
  return (
    <Shell route="t/ethics" me={me.ok ? me.data : null}>
      <Note kind="info" title="Ethical review before the work, open access after it">
        The University&rsquo;s framework for ethical review before research begins and open-access deposit when it is done.
      </Note>
      <Panel title="Research ethics review">
        <PBody>
          <ul className="m-0" style={{ paddingLeft: "var(--s-4)", lineHeight: 1.9 }}>
            <li><b>Who reviews</b> — the University Research Ethics Committee, with delegated departmental review for low-risk studies.</li>
            <li><b>What needs it</b> — any study involving human participants, personal or health data, biological samples, or animals.</li>
            <li><b>The rule</b> — data collection may not begin before clearance; a study that touches personal data is also on the processing register under the Data governance screen.</li>
            <li><b>The record</b> — each application, its decision and any conditions are held so a published paper can be traced to its clearance.</li>
          </ul>
        </PBody>
      </Panel>
      <Panel title="Open-access repository">
        <PBody>
          <ul className="m-0" style={{ paddingLeft: "var(--s-4)", lineHeight: 1.9 }}>
            <li><b>What is deposited</b> — theses, dissertations, and staff publications, with metadata for discovery.</li>
            <li><b>Access</b> — open by default; an embargo is the exception, time-boxed and reasoned.</li>
            <li><b>Integrity</b> — every deposit carries its author, department and date, and cannot be silently replaced.</li>
          </ul>
        </PBody>
      </Panel>
    </Shell>
  );
}
