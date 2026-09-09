import { NextRequest, NextResponse } from "next/server";
import { API_URL } from "@/lib/api";

/** set a new password against the reset token (staff, student or applicant); the user then signs in with it */
export async function POST(request: NextRequest) {
  const body = await request.json().catch(() => null);
  const upstream = await fetch(`${API_URL}/api/v1/auth/reset`, {
    method: "POST",
    headers: { "content-type": "application/json", "x-forwarded-for": request.headers.get("x-forwarded-for") ?? "" },
    body: JSON.stringify(body ?? {}),
    cache: "no-store",
  }).catch(() => null);
  if (!upstream) return NextResponse.json({ status: 503, title: "The portal API is not reachable" }, { status: 503 });
  const text = await upstream.text();
  return new NextResponse(text, { status: upstream.status, headers: { "content-type": upstream.headers.get("content-type") ?? "application/json" } });
}
