import "server-only";
import { cookies } from "next/headers";
import { OFFICE_COOKIE } from "./offices";
import { sessionToken } from "./session";
import { reasonHeader } from "./reason";

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
  if (options.reason) headers["X-Reason"] = reasonHeader(options.reason);
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
      : fallbackProblem(response.status, response.statusText, text);
  if (response.status === 401 && !token) {
    problem.remedy = problem.remedy ?? {
      message: "Sign in again.",
      office: "Directorate of ICT",
    };
  }
  return { ok: false, problem };
}

/**
 * A readable problem when the API answers with no problem body. This happens on a bare
 * 403/401 from the security layer, and on HTTP/2 (Railway) `statusText` is empty — so
 * without this the screen showed a blank red box. Give each status its own words.
 */
function fallbackProblem(status: number, statusText: string, text: string): Problem {
  const detail = text.slice(0, 500).trim() || undefined;
  switch (status) {
    case 401:
      return {
        status, title: "You are not signed in",
        detail: detail ?? "Your session has ended.",
        remedy: { message: "Sign in again.", office: "Directorate of ICT" },
      };
    case 403:
      return {
        status, title: "You don’t have access to this screen",
        detail: detail ?? "The office you are signed in as is not permitted to open this screen.",
        remedy: { message: "Switch to an office that owns this screen with the office selector, top left — or ask for access.", office: "Directorate of ICT" },
      };
    case 404:
      return { status, title: "Not found", detail: detail ?? "There is nothing at this address." };
    case 502:
    case 503:
    case 504:
      return {
        status, title: "The portal API is not answering",
        detail: detail ?? "The service is briefly unavailable.",
        remedy: { message: "Try again in a moment.", office: "Directorate of ICT" },
      };
    default:
      return { status, title: statusText.trim() || `The request was refused (${status})`, detail };
  }
}

function safeJson(text: string): unknown {
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
}
