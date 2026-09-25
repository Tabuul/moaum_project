import { api } from "@/lib/api";
import type { Verify } from "@/lib/documents";
import { VerifyDocument } from "./VerifyDocument";

export const dynamic = "force-dynamic";

/** /verify/document?key= — public; the key typed or scanned */
export default async function Page({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const sp = await searchParams;
  const key = typeof sp.key === "string" ? sp.key.trim().slice(0, 60) : "";
  let v: Verify | null = null;
  if (key) {
    const r = await api<{ result: string }>(`/api/v1/verify/document?key=${encodeURIComponent(key)}`);
    v = r.ok ? (JSON.parse(r.data.result) as Verify) : { status: r.problem.status === 422 ? "INVALID" : "INVALID", remedy: r.problem.title };
  }
  return <VerifyDocument v={v} keyAsked={key} />;
}
