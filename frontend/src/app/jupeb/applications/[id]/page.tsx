import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { JupebApplication } from "../../JupebOffice";

export const dynamic = "force-dynamic";

/** /jupeb/applications/[id] — one JUPEB candidate's record on a page of its own: review, decide, place, number (V339) */
export default async function Page({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const me = await api<Me>("/api/v1/iam/me");
  const office = me.ok ? me.data.activeOffice : null;
  return (
    <Shell route="jupeb/applications" me={me.ok ? me.data : null}>
      <JupebApplication id={id} canWrite={office === "jupeb" || office === "super"} />
    </Shell>
  );
}
