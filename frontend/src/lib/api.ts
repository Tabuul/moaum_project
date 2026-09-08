import "server-only";
import { cookies } from "next/headers";
import { OFFICE_COOKIE } from "./offices";
import { sessionToken } from "./session";

/**
 * The server side of the BFF (ARC §8): pages and route handlers call the API
 * from here, on the server, with a token the browser never sees.
 *
 * Until Keycloak is wired, the token comes from PORTAL_API_TOKEN — a token
 * minted against the API's development secret — and the acting office from
 * PORTAL_ACTIVE_OFFICE. Both are server-side environment variables.
 */

export const API_URL = (process.env.PORTAL_API_URL ?? "http://localhost:8081").replace(/\/$/, "");

/** RFC 9457 problem details, as the API renders them. */
export interface Problem {
  type?: string;
  title?: string;
  status: number;
  detail?: string;
  instance?: string;
  code?: string;
  correlationId?: string;
  remedy?: { message: string; office: string };
  violations?: { field: string; code: string; message: string }[];
}

export type ApiResult<T> = { ok: true; data: T; status: number } | { ok: false; problem: Problem };

export interface ApiOptions {
  method?: "GET" | "POST" | "PUT" | "PATCH" | "DELETE";
  body?: unknown;
  /** Overrides PORTAL_ACTIVE_OFFICE for this call. */
  office?: string;
  /** Sent as X-Reason and recorded in the audit trail. */
  reason?: string;
  /** Sent as X-Correlation-Id; echoed back and generated when absent. */
  correlationId?: string;
}

export async function api<T>(path: string, options: ApiOptions = {}): Promise<ApiResult<T>> {
  const headers: Record<string, string> = { Accept: "application/json" };
  const token = await sessionToken();
  if (token) headers.Authorization = `Bearer ${token}`;
  let office = options.office ?? null;
  if (!office) {
    try {
      office = (await cookies()).get(OFFICE_COOKIE)?.value ?? null;
    } catch {
      office = null;
    }
  }
  office = office ?? process.env.PORTAL_ACTIVE_OFFICE ?? null;
  if (office) headers["X-Active-Office"] = office;
  if (options.reason) headers["X-Reason"] = options.reason;
  if (options.correlationId) headers["X-Correlation-Id"] = options.correlationId;
  if (options.body !== undefined) headers["Content-Type"] = "application/json";

  let response: Response;
  try {
    response = await fetch(`${API_URL}${path}`, {
      method: options.method ?? "GET",
      headers,
      body: options.body === undefined ? undefined : JSON.stringify(options.body),
      cache: "no-store",
    });
  } catch (error) {
    return {
      ok: false,
      problem: {
        status: 503,
        title: "The portal API is not reachable",
        detail: `${API_URL}: ${error instanceof Error ? error.message : String(error)}`,
        code: "API_UNREACHABLE",
        remedy: { message: "Start the API (api/: ./mvnw spring-boot:run) or set PORTAL_API_URL.", office: "Directorate of ICT" },
      },
    };
  }

  const text = await response.text();
  const json = text ? safeJson(text) : null;
  if (response.ok) {
    return { ok: true, data: json as T, status: response.status };
  }
  const problem: Problem =
    json && typeof json === "object" && "status" in (json as object)
      ? (json as Problem)
      : { status: response.status, title: response.statusText, detail: text.slice(0, 500) };
  if (response.status === 401 && !token) {
    problem.remedy = problem.remedy ?? {
      message: "Sign in again.",
      office: "Directorate of ICT",
    };
  }
  return { ok: false, problem };
}

function safeJson(text: string): unknown {
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
}
