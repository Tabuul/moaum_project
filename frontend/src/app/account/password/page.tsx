import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ChangePassword } from "./ChangePassword";

export const dynamic = "force-dynamic";

export default async function PasswordPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const params = await searchParams;
  const next = typeof params.next === "string" && params.next.startsWith("/") ? params.next : "/";
  const me = await api<Me>("/api/v1/iam/me");
  return (
    <Shell route="a/password" me={me.ok ? me.data : null}>
      <ChangePassword next={next} />
    </Shell>
  );
}
