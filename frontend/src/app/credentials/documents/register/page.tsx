import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { DocumentRow } from "@/lib/documents";
import { Register } from "./Register";

export const dynamic = "force-dynamic";

export interface RegFilters { kind: string; status: string; flagged: string; q: string; page: string }
export interface RegList { total: number; page: number; size: number; rows: DocumentRow[] }

/** t/documents › register — every issued document with its status, versions, downloads and verifications; revoked or reissued here */
export default async function DocumentRegisterPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const g = (k: string) => (typeof p[k] === "string" ? (p[k] as string).slice(0, 80) : "");
  const filters: RegFilters = { kind: g("kind"), status: g("status"), flagged: g("flagged"), q: g("q"), page: g("page") };
  const qs = new URLSearchParams(); for (const [k, v] of Object.entries(filters)) if (v) qs.set(k, v);
  qs.set("size", "500");
  const [me, view, verifications] = await Promise.all([api<Me>("/api/v1/iam/me"), api<RegList>(`/api/v1/documents/issued?${qs}`), api<{ key: string; status: string; kind: string | null; at: string; ip: string | null; number: string | null; student_name: string | null }[]>("/api/v1/documents/verifications?size=100")]);
  return (
    <Shell route="t/documents" me={me.ok ? me.data : null}>
      {view.ok ? <Register list={view.data} filters={filters} verifications={verifications.ok ? verifications.data : []} office={me.ok ? me.data.activeOffice ?? null : null} /> : <ProblemNotice problem={view.problem} />}
    </Shell>
  );
}
