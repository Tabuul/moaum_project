import { NextResponse } from "next/server";
import { api } from "@/lib/api";
import type { DefermentFull } from "@/lib/deferments";
import { defermentApplication } from "@/lib/deferment-letter";

export const dynamic = "force-dynamic";

/** the desk's copy of the whole application as a PDF; the API refuses it to the Academic Office until the faculty has approved, and logs every download */
export async function GET(_req: Request, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const r = await api<DefermentFull>(`/api/v1/deferments/${id}/application`);
  if (!r.ok) return NextResponse.json(r.problem, { status: r.problem.status });
  const bytes = defermentApplication(r.data);
  return new NextResponse(Buffer.from(bytes), { headers: { "content-type": "application/pdf", "content-disposition": `inline; filename="${r.data.reference}-application.pdf"` } });
}
