import { api } from "@/lib/api";
import type { Verify } from "@/lib/documents";
import { VerifyDocument } from "../VerifyDocument";

export const dynamic = "force-dynamic";

/** /verify/document/{key} — what the QR on a certificate or transcript opens */
export default async function Page({ params }: { params: Promise<{ key: string }> }) {
  const { key } = await params;
  const k = decodeURIComponent(key).trim().slice(0, 60);
  const r = await api<{ result: string }>(`/api/v1/verify/document/${encodeURIComponent(k)}`);
  const v: Verify = r.ok ? (JSON.parse(r.data.result) as Verify) : { status: "INVALID", remedy: r.problem.title };
  return <VerifyDocument v={v} keyAsked={k} />;
}
