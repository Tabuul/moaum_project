import { Shell } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { api } from "@/lib/api";
import type { StudentWallet } from "@/lib/wallet";
import { loadStudent } from "../load";
import { Wallet } from "./Wallet";

export const dynamic = "force-dynamic";

/** s/wallet — money the Fund has paid on your behalf */
export default async function Page() {
  const loaded = await loadStudent();
  const w = loaded.student ? await api<StudentWallet>("/api/v1/me/wallet") : null;
  return (
    <Shell route="s/wallet" me={loaded.me}>
      {loaded.student && w && w.ok ? <Wallet w={w.data} /> : <ProblemNotice problem={w && !w.ok ? w.problem : loaded.student ? { status: 500, title: "Unreadable" } : loaded.problem} />}
    </Shell>
  );
}
