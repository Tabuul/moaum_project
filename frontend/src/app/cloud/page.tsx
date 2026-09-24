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
        The portal runs on managed PostgreSQL and a container image with no proprietary service lock-in, so the University can move it — between providers, or on-premises — to satisfy the Nigeria Data Protection Act&rsquo;s residency expectations. This page states that posture; it is not wired to live infrastructure telemetry, so no availability figure is shown here that the portal cannot itself measure.
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
            Personal data can be pinned to a region that satisfies the Act. Because the deployment is portable, residency is a deployment decision the University makes and can change — moving the database and image to a compliant region does not require rebuilding the system. Cross-border processing by a sub-processor (a payment gateway, an SMS provider) is listed in the processing register on the Data governance screen, each under its lawful basis.
          </div>
        </PBody>
      </Panel>
    </Shell>
  );
}
