import { api } from "@/lib/api";
import type { OverpaidFigures } from "@/lib/overpaid";
import { OverpaidPanel, type PanelMode } from "./OverpaidApprove";

/**
 * V781: the Bursar's and the Students Account Officer's dashboards — overpaid school fees of the dashboard's session, by cause: who is
 * ready, who waits for a check of the fee setup, who is held and why, what waits for approval, what is credited to wallets and
 * refunded. The figures are a read of the kept list (never the session worked out again), so the dashboard waits on one indexed read;
 * if it cannot be read the panel is left out and the dashboard stands. `mode`: the Bursar approves, the Students Account Officer
 * requests, any other reader reads.
 */
export async function OverpaidFeesDashPanel({ session, mode }: { session: string; mode: PanelMode }) {
  const f = await api<OverpaidFigures>(`/api/v1/finance/overpaid/figures?session=${encodeURIComponent(session)}`);
  if (!f.ok) return null;
  return <OverpaidPanel initial={f.data} mode={mode} />;
}
