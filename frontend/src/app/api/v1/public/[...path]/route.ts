import { NextRequest, NextResponse } from "next/server";
import { API_URL } from "@/lib/api";

/**
 * The University's public figures at the portal's own address (V282): /api/v1/public/... is forwarded to the API
 * with no token — there is nothing to protect, only counts — and answered to any origin, so the public website reads
 * https://<portal>/api/v1/public/statistics straight from the browser. Cached for five minutes, as the API says.
 */
const CORS = { "access-control-allow-origin": "*", "access-control-allow-methods": "GET, HEAD, OPTIONS", "access-control-allow-headers": "Accept, Content-Type", "access-control-max-age": "3600" };

export async function OPTIONS() {
  return new NextResponse(null, { status: 204, headers: CORS });
}

export async function GET(request: NextRequest, context: { params: Promise<{ path: string[] }> }) {
  const { path } = await context.params;
  const upstream = await fetch(`${API_URL}/api/v1/public/${path.map(encodeURIComponent).join("/")}${request.nextUrl.search}`, { headers: { accept: "application/json" }, cache: "no-store" });
  const headers = new Headers(CORS);
  headers.set("content-type", upstream.headers.get("content-type") ?? "application/json");
  headers.set("cache-control", upstream.headers.get("cache-control") ?? "public, max-age=300");
  return new NextResponse(await upstream.arrayBuffer(), { status: upstream.status, headers });
}
