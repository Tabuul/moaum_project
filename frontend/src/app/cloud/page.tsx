import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { Note, Panel, PBody } from "@/components/proto/ui";

export const dynamic = "force-dynamic";

/** t/cloud — cloud readiness and NDPA data residency (framework; live telemetry not wired). */
export default async function CloudPage() {
  const me = await api<Me>("/api/v1/iam/me");
  return (
    <Shell route="t/cloud" me={me.ok ? me.data : null}>
      <Note kind="info" title="Portability first, so residency is a choice and not a trap">
        No proprietary lock-in: the University can move the portal between providers or on-premises to satisfy the Nigeria Data Protection Act&rsquo;s residency expectations.
      </Note>
      <Panel title="What keeps the system portable">
        <PBody>
          <ul className="m-0" style={{ paddingLeft: "var(--s-4)", lineHeight: 1.9 }}>
            <li><b>Data</b> — standard PostgreSQL; the whole estate is a schema and its migrations, restorable anywhere Postgres runs.</li>
            <li><b>Application</b> — a single container image (API + portal), configured by environment variables, with no dependency on a specific cloud&rsquo;s managed services.</li>
            <li><b>Secrets</b> — payment-gateway keys, mail and SMS credentials are encrypted at rest with a passphrase the University holds, not the provider.</li>
            <li><b>Export</b> — every record is reachable through the API and the reporting store; a subject-access or portability request is answered in an open format.</li>
          </ul>
        </PBody>
      </Panel>
      <Panel title="Data residency">
        <PBody>
          <div className="sub2">
            Personal data can be pinned to a region that satisfies the Act; residency is the University&rsquo;s deployment decision. Cross-border processing by a sub-processor (a payment gateway, an SMS provider) is listed in the processing register on the Data governance screen, each under its lawful basis.
          </div>
        </PBody>
      </Panel>
    </Shell>
  );
}
