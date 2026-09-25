import type { PayFilters } from "./PaymentReport";

/** the report's filters as the address carries them; anything malformed is dropped rather than sent */
export function paymentFilters(p: Record<string, string | string[] | undefined>): PayFilters {
  const s = (k: string) => (typeof p[k] === "string" ? (p[k] as string) : "");
  return {
    session: /^\d{4}\/\d{4}$/.test(s("session")) ? s("session") : "",
    semester: /^[12]$/.test(s("semester")) ? s("semester") : "",
    programme: s("programme").slice(0, 20),
    dept: s("dept").slice(0, 20),
    level: /^\d{3}$/.test(s("level")) ? s("level") : "",
    status: ["FULLY_PAID", "PART_PAYMENT", "NOT_PAID", "NO_CHARGE"].includes(s("status")) ? s("status") : "",
    q: s("q").slice(0, 80),
  };
}

export function paymentQuery(f: PayFilters): string {
  const q = new URLSearchParams();
  for (const [k, v] of Object.entries(f)) if (v) q.set(k, v);
  return q.toString();
}

const ROLE: Record<string, string> = { provost: "Provost", collegesecretary: "College Secretary", financecontroller: "Finance Controller", bursar: "Bursar" };
export const roleWord = (office: string | null) => ROLE[office ?? ""] ?? "Officer";
