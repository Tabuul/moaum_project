import { api } from "@/lib/api";
import { defaultSession, sessionRows } from "@/lib/sessions-server";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import {
  ALL_SESSIONS, TRANSFER_FEES_API, readTransferFeeFilters, sessionWord, snakeKeys, transferFeeQuery, type TransferFeeOptions, type TransferFeeRow,
  type TransferFeeSummary,
} from "@/lib/transfer-fees";
import { TransferFees } from "./TransferFees";

export const dynamic = "force-dynamic";

const SIZE = 50;

/** t/transferfees — the inter-departmental transfer fee monitor (V727): every application of a session with the fee as the
 *  Bursary states it now, what is paid on this portal and on the old one, the balance, the standing and the desk it waits at, and
 *  the students whose old-portal payments wait for an application — filtered and counted on the server within the office's
 *  scope, and downloaded as a workbook */
export default async function TransferFeesPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const filters = readTransferFeeFilters(p);
  const page = typeof p.page === "string" && /^\d{1,5}$/.test(p.page) ? Number(p.page) : 0;
  const [me, sessions, current, options] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    sessionRows(),
    defaultSession(),
    api<TransferFeeOptions>(`${TRANSFER_FEES_API}/options`),
  ]);
  // the University's current session when the address names none, never a year written into the code
  if (!filters.session) filters.session = current;
  const [summary, list] = await Promise.all([
    // the band and what it awaits left out, so each figure stays a door
    api<TransferFeeSummary>(`${TRANSFER_FEES_API}/summary?${transferFeeQuery({ ...filters, band: "", awaiting: "" })}`),
    api<{ rows?: Record<string, unknown>[]; total?: number; page?: number; size?: number }>(`${TRANSFER_FEES_API}?${transferFeeQuery(filters, { page, size: SIZE })}`),
  ]);
  const opts: TransferFeeOptions = options.ok ? options.data : { faculties: [], departments: [] };
  const names = [...sessions.map((s) => s.name), ...(opts.sessions ?? [])];
  return (
    <Shell route="t/transferfees" me={me.ok ? me.data : null} sub={filters.session === ALL_SESSIONS ? sessionWord(ALL_SESSIONS) : `${filters.session} session`}>
      {!summary.ok ? <ProblemNotice problem={summary.problem} />
        : !list.ok ? <ProblemNotice problem={list.problem} />
        : <TransferFees filters={filters} summary={summary.data} options={opts} actingOffice={me.ok ? me.data.activeOffice : null}
            list={{ rows: (list.data.rows ?? []).map((r) => snakeKeys<TransferFeeRow>(r)), total: list.data.total ?? (list.data.rows ?? []).length,
              page: list.data.page ?? page, size: list.data.size ?? SIZE }}
            sessions={[...new Set([filters.session, current, ...names])].filter((s) => s && s !== ALL_SESSIONS).sort().reverse()} />}
    </Shell>
  );
}
