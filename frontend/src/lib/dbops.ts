/**
 * V640: the Database Operations query builder — the sources and fields the server offers, the operators each type takes, the
 * definition sent (never SQL: the server validates every name and binds every value), the presets, and the data quality words.
 */
export type FieldType = "TEXT" | "ENUM" | "INT" | "NUM" | "DATE" | "BOOL";

export interface QField { key: string; label: string; type: FieldType; options?: string[]; money: boolean }
export interface QSource { key: string; label: string; note: string; period: boolean; columns: string[]; sort: string; sortDir: string; required: string | null; fields: QField[] }
export interface Cond { field: string; op: string; value?: string; value2?: string; values?: string[] }
export interface Definition {
  source: string; session?: string; semester?: number; rule?: string; filters: Cond[]; columns: string[];
  sort?: { field: string; dir: string } | null; group?: { field: string; sum?: string | null } | null;
}
export interface QueryResult { columns: { key: string; label: string; type: FieldType; money: boolean }[]; rows: Record<string, unknown>[]; total: number; page: number; size: number; grouped: boolean; scope: string; at: string }

const BY_TYPE: Record<FieldType, string[]> = {
  TEXT: ["contains", "eq", "ne", "starts", "in", "empty", "notempty"],
  ENUM: ["eq", "ne", "in", "empty", "notempty"],
  INT: ["eq", "ne", "gt", "gte", "lt", "lte", "between", "in", "empty", "notempty"],
  NUM: ["eq", "gt", "gte", "lt", "lte", "between", "empty", "notempty"],
  DATE: ["eq", "gte", "lte", "between", "empty", "notempty"],
  BOOL: ["is"],
};

export const OP_WORDS: Record<string, string> = {
  eq: "is", ne: "is not", in: "is one of", contains: "contains", starts: "starts with", gt: "is more than", gte: "is at least",
  lt: "is less than", lte: "is at most", between: "is between", empty: "is empty", notempty: "is not empty", is: "is",
};

export function opsFor(t: FieldType): string[] {
  return BY_TYPE[t] ?? ["eq"];
}

/** whether an operator takes a value, two values, or a list */
export function arity(op: string): 0 | 1 | 2 | "list" {
  if (op === "empty" || op === "notempty") return 0;
  if (op === "between") return 2;
  if (op === "in") return "list";
  return 1;
}

/** a condition is complete when it has what its operator takes */
export function complete(c: Cond): boolean {
  const a = arity(c.op);
  if (a === 0) return true;
  if (a === 2) return !!c.value?.trim() && !!c.value2?.trim();
  if (a === "list") return (c.values ?? []).filter((v) => v.trim()).length > 0;
  return !!c.value?.trim();
}

/** the definition sent: complete conditions only, an "in" list split from what was typed, nothing else */
export function definition(src: QSource, d: Partial<Definition>): Definition {
  const filters = (d.filters ?? []).map((c) => (c.op === "in" && !c.values?.length && c.value ? { ...c, values: c.value.split(/[,\n]/).map((v) => v.trim()).filter(Boolean) } : c))
    .filter(complete)
    .map((c) => ({ field: c.field, op: c.op, ...(arity(c.op) === 1 ? { value: c.value } : {}), ...(arity(c.op) === 2 ? { value: c.value, value2: c.value2 } : {}),
      ...(arity(c.op) === "list" ? { values: c.values } : {}) }));
  return {
    source: src.key,
    ...(src.period ? { session: d.session, semester: d.semester, rule: d.rule ?? "CARD" } : {}),
    filters,
    columns: d.columns && d.columns.length ? d.columns : src.columns,
    sort: d.sort ?? null,
    group: d.group && d.group.field ? d.group : null,
  };
}

/** the query presets the quick reports open */
export const QUERY_PRESETS: Record<string, Partial<Definition> & { source: string; title: string }> = {
  payments: { source: "PAYMENTS", title: "Student payment status", filters: [{ field: "purpose_code", op: "eq", value: "SCHOOL_FEES" }], sort: { field: "paid_on", dir: "desc" } },
  registrations: { source: "REGISTRATIONS", title: "Student registration status", filters: [] },
  spillover: { source: "STUDENTS", title: "Spillover students", filters: [{ field: "academic_status", op: "starts", value: "SP" }] },
  graduated: { source: "STUDENTS", title: "Graduated students", filters: [{ field: "status", op: "eq", value: "GRADUATED" }] },
};

export const DQ_AREAS = ["Academic structure", "Academic record", "Identity", "Classification", "Status", "Payment and registration"];

/** a cell for the screen and the export: dates and timestamps as dates, booleans as Yes/No, amounts as numbers */
export function cell(v: unknown, type: FieldType): string | number {
  if (v == null) return "";
  if (type === "BOOL") return v === true ? "Yes" : v === false ? "No" : String(v);
  if (type === "INT" || type === "NUM") return Number(v);
  if (type === "DATE") return String(v).slice(0, 10);
  return String(v);
}
