import { NextRequest, NextResponse } from "next/server";
import { API_URL } from "@/lib/api";
import { OFFICE_COOKIE } from "@/lib/offices";
import { SESSION_COOKIE, cookieOptions } from "@/lib/session";

/**
 * One door for everybody. The number typed says who is signing in:
 *   MOAUM/XXX/YY/NNNN                 a student, on the matriculation number
 *   12 digits + 2–3 letters, APP/…    an applicant, on the JAMB or application number
 *   anything else                     a member of staff, on the staff number or email —
 *                                     and, failing that, an applicant on an email address
 * The token goes into a cookie the browser cannot read; the office cookie says
 * which side of the portal opens.
 */
const MATRIC = /^MOAUM\/[A-Z]{2,4}\/[0-9]{2}\/[0-9]{4}$/i;
/* the admission number an admitted candidate carries before matriculation: MOAUM/ADM/YY/NNNNNN.
   It opens the student door too, so they pay school fees and register courses under it. */
const ADMISSION = /^MOAUM\/ADM\/[0-9]{2}\/[0-9]{6}$/i;
const JAMB = /^[0-9]{12}[A-Z]{2,3}$/i;
const APPLICATION = /^APP\/[0-9]{2}\/[0-9]{6}$/i;
/* a postgraduate application number: PG/YY/NNNNNN — the PG applicant's own door (they also sign in on their email) */
const PG_APPLICATION = /^PG\/[0-9]{2}\/[0-9]{6}$/i;
/* a legacy old-portal matriculation number carried over from the old portal — BSU/…, MOAU/…, and the
   like: two-to-six letters, one to four more segments, then digits. It opens the student door too, so a
   migrated student signs in; a rare staff number of the same shape falls back to the staff door. */
const LEGACY_MATRIC = /^[A-Z]{2,6}(\/[A-Z0-9]{2,6}){1,4}\/[0-9]{2,7}$/i;

type Kind = "staff" | "student" | "applicant" | "pgapplicant";

async function upstream(path: string, body: unknown, request: NextRequest): Promise<Response | null> {
  return fetch(`${API_URL}${path}`, {
    method: "POST",
    headers: { "content-type": "application/json", "x-forwarded-for": request.headers.get("x-forwarded-for") ?? "" },
    body: JSON.stringify(body ?? {}),
    cache: "no-store",
  }).catch(() => null);
}

function problem(text: string, status: number, contentType: string | null) {
  return new NextResponse(text, { status, headers: { "content-type": contentType ?? "application/problem+json" } });
}

export async function POST(request: NextRequest) {
  const body = (await request.json().catch(() => null)) as Record<string, unknown> | null;
  const identifier = String(body?.identifier ?? body?.username ?? body?.matricNo ?? "").trim();
  const password = typeof body?.password === "string" ? body.password : "";
  const preferredOffice = typeof body?.office === "string" ? body.office : undefined;

  let kind: Kind = MATRIC.test(identifier) || ADMISSION.test(identifier) ? "student"
    : PG_APPLICATION.test(identifier) ? "pgapplicant"
    : JAMB.test(identifier) || APPLICATION.test(identifier) ? "applicant" : "staff";
  /* a legacy old-portal matric was not matched above (only MOAUM/… is) — route it to the student door,
     and fall back to staff if it turns out to be a staff number of the same shape */
  const legacyMatric = kind === "staff" && !identifier.includes("@") && LEGACY_MATRIC.test(identifier);
  let r: Response | null;
  if (kind === "student") {
    r = await upstream("/api/v1/student-auth/sign-in", { matricNo: identifier, password }, request);
  } else if (kind === "pgapplicant") {
    r = await upstream("/api/v1/pg/sign-in", { identifier, password }, request);
  } else if (legacyMatric) {
    const asStudent = await upstream("/api/v1/student-auth/sign-in", { matricNo: identifier, password }, request);
    if (asStudent && asStudent.ok) {
      r = asStudent;
      kind = "student";
    } else {
      r = await upstream("/api/v1/auth/sign-in", { username: identifier, password, office: preferredOffice }, request);
    }
  } else if (kind === "applicant") {
    /* the same JAMB/application number opens the student dashboard once the candidate is on the
       register; try the student door first, and fall back to the applicant portal if they are not
       a student yet (offer not accepted, or not brought onto the register). */
    const asStudent = await upstream("/api/v1/student-auth/sign-in", { matricNo: identifier, password }, request);
    if (asStudent && asStudent.ok) {
      r = asStudent;
      kind = "student";
    } else {
      r = await upstream("/api/v1/applicant/sign-in", { identifier, password }, request);
    }
  } else {
    r = await upstream("/api/v1/auth/sign-in", { username: identifier, password, office: preferredOffice }, request);
    /* an email address is also how an applicant signs in: the same wrong answer either way, so try the other doors */
    if (r && r.status === 422 && identifier.includes("@")) {
      const again = await upstream("/api/v1/applicant/sign-in", { identifier, password }, request);
      if (again && again.ok) {
        r = again;
        kind = "applicant";
      } else {
        /* and, last, the postgraduate applicant's door — they sign in on the email they applied with */
        const pg = await upstream("/api/v1/pg/sign-in", { identifier, password }, request);
        if (pg && pg.ok) {
          r = pg;
          kind = "pgapplicant";
        }
      }
    }
  }
  if (!r) return NextResponse.json({ status: 503, title: "The portal API is not reachable" }, { status: 503 });
  const text = await r.text();
  if (!r.ok) return problem(text, r.status, r.headers.get("content-type"));

  const signed = JSON.parse(text) as Record<string, unknown>;
  const seconds = Math.max(60, Math.floor((new Date(String(signed.expiresAt)).getTime() - Date.now()) / 1000));
  let office: string;
  let name: string;
  let home: string;
  let mustChange = false;
  if (kind === "student") {
    office = "student";
    name = `${signed.surname}, ${signed.otherNames}`;
    mustChange = signed.mustChange === true;
    home = mustChange ? "/student/profile?change=1" : "/student";
  } else if (kind === "applicant") {
    office = "applicant";
    name = `${signed.surname}, ${signed.otherNames}`;
    home = "/applicant";
  } else if (kind === "pgapplicant") {
    office = "applicant";
    name = `${signed.surname}, ${signed.otherNames}`;
    home = "/pg/portal";
  } else {
    const offices = (signed.offices as { code: string }[] | undefined) ?? [];
    office = preferredOffice && offices.some((o) => o.code === preferredOffice) ? preferredOffice : offices[0]?.code ?? "";
    name = `${signed.surname}, ${signed.givenNames}`;
    mustChange = signed.mustChange === true;
    home = mustChange ? "/account/password" : "/";
  }
  const response = NextResponse.json({ kind, home, mustChange, name, office, offices: signed.offices ?? [] });
  response.cookies.set(SESSION_COOKIE, String(signed.token), cookieOptions(seconds));
  if (office) response.cookies.set(OFFICE_COOKIE, office, { ...cookieOptions(seconds), httpOnly: false });
  return response;
}
