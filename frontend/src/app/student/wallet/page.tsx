import { Shell } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { api } from "@/lib/api";
import type { StudentWallet } from "@/lib/wallet";
import { loadStudent } from "../load";
import { Wallet } from "./Wallet";

export const dynamic = "force-dynamic";

/** s/wallet — money the Fund has paid on your behalf */
export default async function Page({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const params = await searchParams;
  /* V327: a session may be asked for (the wallet is session-aware: a refund is of one session's money); the current one otherwise */
  const session = typeof params.session === "string" && /^[0-9]{4}\/[0-9]{4}$/.test(params.session) ? params.session : null;
  const loaded = await loadStudent();
  const w = loaded.student ? await api<StudentWallet>(`/api/v1/me/wallet${session ? `?session=${encodeURIComponent(session)}` : ""}`) : null;
  return (
    <Shell route="s/wallet" me={loaded.me}>
      {loaded.student && w && w.ok ? <Wallet w={w.data} /> : <ProblemNotice problem={w && !w.ok ? w.problem : loaded.student ? { status: 500, title: "Unreadable" } : loaded.problem} />}
    </Shell>
  );
}
