import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { Profile } from "./Profile";

export const dynamic = "force-dynamic";

export default async function ProfilePage() {
  const [me, profile] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<Record<string, unknown>>("/api/v1/staff/profile"),
  ]);

  return (
    <Shell route="t/myprofile" me={me.ok ? me.data : null}>
      <Profile initial={profile.ok ? profile.data : null} me={me.ok ? me.data : null} />
    </Shell>
  );
}
