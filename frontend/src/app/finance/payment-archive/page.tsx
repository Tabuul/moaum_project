import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { archiveQuery, readArchiveFilters, type ArchiveDetail, type ArchiveList, type Catalogue, type Figures } from "@/lib/payment-archive";
import { PaymentArchive } from "./PaymentArchive";

export const dynamic = "force-dynamic";

/** t/paymentarchive — payments archived for review (V670): a duplicate, wrongly credited or unverified payment kept as it stood
 *  and counted nowhere until the Bursary settles it — archived and investigated by the Students Account Officer or the Bursar,
 *  settled on the approval of another Bursar officer; Internal Audit reads. ?id= opens one. */
export default async function PaymentArchivePage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const filters = readArchiveFilters(p);
  const page = typeof p.page === "string" && /^\d{1,5}$/.test(p.page) ? Number(p.page) : 0;
  const id = typeof p.id === "string" && /^[0-9a-f-]{36}$/i.test(p.id) ? p.id : null;
  const figureSession = filters.session ? `?session=${encodeURIComponent(filters.session)}` : "";
  const [me, list, catalogue, figures, detail] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<ArchiveList>(`/api/v1/finance/payment-archive?${archiveQuery(filters, { page })}`),
    api<Catalogue>("/api/v1/finance/payment-archive/catalogue"),
    api<Figures>(`/api/v1/finance/payment-archive/figures${figureSession}`),
    id ? api<ArchiveDetail>(`/api/v1/finance/payment-archive/${id}`) : Promise.resolve(null),
  ]);
  return (
    <Shell route="t/paymentarchive" me={me.ok ? me.data : null}>
      {list.ok
        ? <PaymentArchive filters={filters} list={list.data} catalogue={catalogue.ok ? catalogue.data : { reasons: [], evidenceKinds: [], sessions: [], channels: [] }}
            figures={figures.ok ? figures.data : null} office={me.ok ? me.data.activeOffice ?? null : null} initial={detail && detail.ok ? detail.data : null} />
        : <ProblemNotice problem={list.problem} />}
    </Shell>
  );
}
