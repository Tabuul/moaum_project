import { NextResponse } from "next/server";
import { api } from "@/lib/api";
import type { DefermentFull } from "@/lib/deferments";
import { defermentLetter } from "@/lib/deferment-letter";

export const dynamic = "force-dynamic";

/** the student's own approval letter; the API answers only for their own request, and only once it is approved */
export async function GET(req: Request, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const r = await api<DefermentFull>(`/api/v1/me/deferments/${id}`);
  if (!r.ok) return NextResponse.json(r.problem, { status: r.problem.status });
  if (!["APPROVED", "ACTIVE", "COMPLETED"].includes(r.data.state)) {
    return NextResponse.json({ status: 409, title: "The letter is issued once the deferment is approved." }, { status: 409 });
  }
  const bytes = defermentLetter(r.data, `${new URL(req.url).origin}/verify/deferment/${encodeURIComponent(r.data.reference)}`);
  return new NextResponse(Buffer.from(bytes), { headers: { "content-type": "application/pdf", "content-disposition": `inline; filename="${r.data.reference}.pdf"` } });
}
