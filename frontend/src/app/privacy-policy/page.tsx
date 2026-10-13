import type { Metadata } from "next";
import { api } from "@/lib/api";
import type { LegalDocument } from "@/lib/legal-text";
import { ProblemNotice } from "@/components/ProblemNotice";
import { LegalPage, LegalPending } from "./LegalPage";

export const dynamic = "force-dynamic";

type Inst = { name?: string | null; email?: string | null; phone?: string | null };

export async function generateMetadata(): Promise<Metadata> {
  const inst = await api<Inst>("/api/v1/public/institution", { anonymous: true });
  const name = inst.ok && inst.data.name ? inst.data.name : "MOAUM Portal";
  return { title: `University Privacy Policy | ${name}`, description: `How ${name} collects, uses, keeps, protects and shares personal information through its portal.` };
}

/** /privacy-policy — public, no sign-in; the one authoritative Privacy Policy (V441). ?preview=<id> shows a draft to an administrator. */
export default async function PrivacyPolicyPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const sp = await searchParams;
  const preview = typeof sp.preview === "string" && /^[0-9a-f-]{36}$/i.test(sp.preview) ? sp.preview : null;
  if (preview) {
    const r = await api<LegalDocument>(`/api/v1/privacy/admin/documents/${preview}/preview`);
    if (!r.ok) return <div style={{ padding: "var(--s-5)" }}><ProblemNotice problem={r.problem} /></div>;
    return <LegalPage doc={r.data} pdfHref={`/privacy-policy/pdf?preview=${preview}`} preview />;
  }
  const r = await api<LegalDocument>("/api/v1/public/legal/privacy-policy", { anonymous: true });
  if (!r.ok) {
    if (r.problem.status === 404) {
      const inst = await api<Inst>("/api/v1/public/institution", { anonymous: true });
      return <LegalPending title="Privacy Policy" institution={inst.ok ? inst.data : null} />;
    }
    return <div style={{ padding: "var(--s-5)" }}><ProblemNotice problem={r.problem} /></div>;
  }
  return <LegalPage doc={r.data} pdfHref="/privacy-policy/pdf" preview={false} />;
}
