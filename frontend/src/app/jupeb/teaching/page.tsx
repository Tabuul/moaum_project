import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { JupebTeaching } from "./JupebTeaching";

export const dynamic = "force-dynamic";

/** /jupeb/teaching — a lecturer's JUPEB workspace (V354); the API decides what is theirs */
export default async function Page() {
  const me = await api<Me>("/api/v1/iam/me");
  return (
    <Shell route="jupeb/teaching" me={me.ok ? me.data : null}>
      <JupebTeaching />
    </Shell>
  );
}
