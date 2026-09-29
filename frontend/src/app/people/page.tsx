import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { People, type GrantRow, type PersonRow } from "./People";

export const dynamic = "force-dynamic";

/** the API leaves a null field out of the JSON: a person with no account arrives with no username at all, so put the nulls back
 *  before the console tests them (without this, Create account, Contact and Grant an office opened nothing for anyone without an account) */
function personOf(p: PersonRow): PersonRow {
  return { ...p, staffNumber: p.staffNumber ?? null, email: p.email ?? null, phone: p.phone ?? null, endedOn: p.endedOn ?? null, username: p.username ?? null,
    mustChange: p.mustChange ?? false, lastSignInAt: p.lastSignInAt ?? null, lockedUntil: p.lockedUntil ?? null, liveOffices: Number(p.liveOffices ?? 0) };
}
function grantOf(g: GrantRow): GrantRow {
  return { ...g, staffNumber: g.staffNumber ?? null, scopeId: g.scopeId ?? null, grantedByName: g.grantedByName ?? null, validTo: g.validTo ?? null };
}

export default async function PeoplePage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const params = await searchParams;
  const q = typeof params.q === "string" ? params.q : "";
  const [me, persons, grants, offices] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<PersonRow[]>(`/api/v1/iam/persons${q ? `?q=${encodeURIComponent(q)}` : ""}`),
    api<GrantRow[]>("/api/v1/iam/office-assignments"),
    api<{ code: string; label: string; scope_kind: string }[]>("/api/v1/iam/offices"),
  ]);
  return (
    <Shell route="t/users" me={me.ok ? me.data : null}>
      {!persons.ok ? (
        <ProblemNotice problem={persons.problem} />
      ) : (
        <People q={q} persons={persons.data.map(personOf)} grants={grants.ok ? grants.data.map(grantOf) : []} offices={offices.ok ? offices.data : []} actingOffice={me.ok ? me.data.activeOffice : null} open={typeof params.new === "string" ? params.new : null} />
      )}
    </Shell>
  );
}
