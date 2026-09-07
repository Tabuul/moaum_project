import { NextRequest, NextResponse } from "next/server";
import { API_URL } from "@/lib/api";

/**
 * The BFF (ARC §8, ADR-007): the browser talks to this origin only, and this
 * handler forwards to the API with a token the browser never holds. Only the
 * versioned API is reachable through it, and only the headers the API
 * understands are forwarded.
 */
const FORWARDED_HEADERS = ["content-type", "accept", "x-correlation-id", "x-active-office", "x-reason", "idempotency-key"];

async function forward(request: NextRequest, path: string[]): Promise<NextResponse> {
  if (path[0] !== "api" || path[1] !== "v1") {
    return NextResponse.json(
      { status: 404, title: "Not found", detail: "Only /api/v1/... is reachable through the BFF." },
      { status: 404, headers: { "content-type": "application/problem+json" } },
    );
  }
  const headers = new Headers();
  for (const name of FORWARDED_HEADERS) {
    const value = request.headers.get(name);
    if (value) headers.set(name, value);
  }
  const token = process.env.PORTAL_API_TOKEN;
  if (token) headers.set("authorization", `Bearer ${token}`);
  if (!headers.has("x-active-office") && process.env.PORTAL_ACTIVE_OFFICE) {
    headers.set("x-active-office", process.env.PORTAL_ACTIVE_OFFICE);
  }

  const url = `${API_URL}/${path.map(encodeURIComponent).join("/")}${request.nextUrl.search}`;
  const hasBody = request.method !== "GET" && request.method !== "HEAD";
  const upstream = await fetch(url, {
    method: request.method,
    headers,
    body: hasBody ? await request.text() : undefined,
    cache: "no-store",
  });

  const responseHeaders = new Headers();
  for (const name of ["content-type", "x-correlation-id", "location"]) {
    const value = upstream.headers.get(name);
    if (value) responseHeaders.set(name, value);
  }
  return new NextResponse(await upstream.text(), { status: upstream.status, headers: responseHeaders });
}

type Context = { params: Promise<{ path: string[] }> };

export async function GET(request: NextRequest, context: Context) {
  return forward(request, (await context.params).path);
}

export async function POST(request: NextRequest, context: Context) {
  return forward(request, (await context.params).path);
}

export async function PUT(request: NextRequest, context: Context) {
  return forward(request, (await context.params).path);
}

export async function PATCH(request: NextRequest, context: Context) {
  return forward(request, (await context.params).path);
}

export async function DELETE(request: NextRequest, context: Context) {
  return forward(request, (await context.params).path);
}
