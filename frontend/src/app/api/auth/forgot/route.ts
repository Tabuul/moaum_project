import { NextRequest, NextResponse } from "next/server";
import { API_URL } from "@/lib/api";

/** a forgotten password for staff, students or applicants: always accepted, so the page cannot list accounts */
export async function POST(request: NextRequest) {
  const body = await request.json().catch(() => null);
  const upstream = await fetch(`${API_URL}/api/v1/auth/forgot`, {
    method: "POST",
    headers: { "content-type": "application/json", "x-forwarded-for": request.headers.get("x-forwarded-for") ?? "" },
    body: JSON.stringify(body ?? {}),
    cache: "no-store",
  }).catch(() => null);
  if (!upstream) return NextResponse.json({ status: 503, title: "The portal API is not reachable" }, { status: 503 });
  const text = await upstream.text();
  return new NextResponse(text, { status: upstream.status, headers: { "content-type": upstream.headers.get("content-type") ?? "application/json" } });
}
