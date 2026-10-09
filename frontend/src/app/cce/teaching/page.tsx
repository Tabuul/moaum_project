import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { CceTeaching } from "./CceTeaching";

export const dynamic = "force-dynamic";

/** /cce/teaching — a lecturer's evening classes of the Centre for Continuing Education (V380): the slots, the class list and the
 *  register of each lecture. The server answers only for the classes the person teaches (every CCE class for the Centre). */
export default async function Page() {
  const me = await api<Me>("/api/v1/iam/me");
  return (
    <Shell route="cce/teaching" me={me.ok ? me.data : null}>
      <CceTeaching />
    </Shell>
  );
}
