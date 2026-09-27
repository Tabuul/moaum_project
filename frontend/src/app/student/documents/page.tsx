import { Shell } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { api } from "@/lib/api";
import type { MyDocuments } from "@/lib/documents";
import type { AdmissionDocRow } from "@/lib/admission-documents";
import { loadStudent } from "../load";
import { Documents } from "./Documents";

export const dynamic = "force-dynamic";

/** s/documents — my documents (V262): certificates and transcripts issued, requests in hand with their timelines, and the request wizard */
export default async function Page({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const loaded = await loadStudent();
  if (!loaded.student) return <Shell route="s/documents" me={loaded.me}><ProblemNotice problem={loaded.problem} /></Shell>;
  const d = await api<MyDocuments>("/api/v1/me/documents");
  // the documents of the admission the student came through (V282): none for a student who did not
  const adm = await api<{ rows: AdmissionDocRow[] }>("/api/v1/me/admission-documents");
  return (
    <Shell route="s/documents" me={loaded.me}>
      {d.ok ? <Documents d={d.data} admission={adm.ok ? adm.data.rows : []} open={typeof p.request === "string" ? p.request : ""} wizard={typeof p.new === "string" ? p.new : ""} /> : <ProblemNotice problem={d.problem} />}
    </Shell>
  );
}
