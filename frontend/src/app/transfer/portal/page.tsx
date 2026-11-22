import { api } from "@/lib/api";
import type { PublicOptions } from "@/lib/transfer-application";
import { TransferPortal } from "./TransferPortal";

export const dynamic = "force-dynamic";

/** iut/portal — V766: the transfer applicant's own portal (signed in as an applicant on the account of admissions.iut_account). The open
 *  window's programmes and the list of universities are read as the public reads them, for the draft's edit and for applying again. */
export default async function Page() {
  const options = await api<PublicOptions>("/api/v1/public/inter-university-transfer", { anonymous: true });
  return <TransferPortal options={options.ok ? options.data : null} />;
}
