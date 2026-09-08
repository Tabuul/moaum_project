import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { People, type GrantRow, type PersonRow } from "./People";

export const dynamic = "force-dynamic";

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
        <People q={q} persons={persons.data} grants={grants.ok ? grants.data : []} offices={offices.ok ? offices.data : []} actingOffice={me.ok ? me.data.activeOffice : null} />
      )}
    </Shell>
  );
}
