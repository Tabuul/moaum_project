# The Central Document System — Branding, Print and PDF (V320)

Every document the portal prints, downloads or exports carries one official identity, read from one
place, dressed by one set of document profiles, through one PDF engine and one browser-print engine.
No screen types the University's name itself any more.

## A. The audit of what existed

| Path | Count | What it was |
|---|---|---|
| Server PDF routes (`frontend/src/app/**/pdf/route.ts`) | 13 | Course form, semester results, receipt, broadsheet, exam card, student and staff ID cards, applicant form, PG offer and summary, certificates/transcripts (3 routes over `document-pdf.ts`), each drawing its own page with `brandHeader` and a hard-coded name |
| PDF builders (`lib/*-pdf.ts`, `report-pdf.ts`, `marked-sheet.ts`, `deferment-letter.ts`) | 8 | Admission letter and receipt, screening forms, ID cards, certificates and transcripts, kept returns, marked score sheets, deferment letters — each with the University's name as a literal and the crest from `/public/crest.jpg` |
| `brandedPrint` / `brandedXlsx` (`lib/exportbrand.ts`) | 46 / 53 call sites | The branded browser print and the branded workbook of a list, with the name as a constant and `/crest.png` |
| Other workbooks (`buildXlsx` direct) | 38 call sites | Workbooks headed by a literal name |
| `DTable` Print, `printNode` | every table / 4 | A table or a panel printed from a clone, headed by a literal line |
| Designed print sheets (`ReportDoc`, FileReturn, TransferLetter, MemoBar, HallList, Batch, Broadsheet ERS) | 7 | `window.print()` over a designed `.rpt`/`.docsheet` page with inline `@media print` |
| Print CSS | `globals.css`, `prototype.css`, 3 inline blocks | `.shell` hidden, `.no-print`, paper rules |
| Identity | 54 frontend files, 13 API files | "Rev. Fr. Moses Orshio Adasu University, Makurdi" typed in each; the crest a static file; no institution profile anywhere |
| Storage, audit, references | `platform.file_object` + `FileObjects` (S3 or local), `audit.attach` row triggers, `platform.number_series`, `docSerial` | Reused, not duplicated |

## B. The central system

```
MODULE → central document service → document profile → institution profile → template → PDF / print / workbook
```

- **Institution profile** — `platform.institution_profile` (one audited row): name, short name, motto,
  address, city, state, country, phone, e-mail, website, logo (object id in the file store, with a JPEG
  derivative for the PDF engine, versioned), footer note, show-generated-by, show-page-numbers, date
  style. Seeded with what the code carried, so nothing changed on migration. `platform.institution()`
  serves it; `platform.set_institution_profile` and `platform.set_institution_logo` change it with the
  rules (name required, e-mail and website checked) and the audit trail. API:
  `GET /api/v1/public/institution`, `GET /api/v1/public/institution/logo[?format=jpeg]` (public, cached),
  `PUT /api/v1/platform/institution`, `PUT|DELETE /api/v1/platform/institution/logo` (ICT, Super
  Administrator, Administrator, Registrar, Deputy Registrar). The services name the University through
  `Branding.name()` (cached a minute): every notice, mail header and report subject follows the profile.
- **Document profiles** — `lib/document/profiles.ts`: STANDARD_REPORT, BROADSHEET (landscape,
  CONFIDENTIAL), RECEIPT, INVOICE, LETTER, FORM, RESULT (STUDENT COPY), CERTIFICATE (dresses itself),
  TRANSCRIPT (CONFIDENTIAL), STUDENT_PROFILE, ID_CARD (no header or footer), STATEMENT. Each says the
  orientation, margins, the first-page header (full letterhead) and the continuation band, whether
  there is a footer and page numbers, whether tables lead with S/N, the copy label and the
  confidentiality label. `documentTitle` derives the title from the profile; `periodSubtitle` the
  session/semester line.
- **PDF** — `lib/document/pdf.ts` on the portal's own engine (`pdf-write`): `PdfDocument` (header, compact
  continuation band, tables whose header repeats on every page with S/N running on, key–value blocks,
  paragraphs, signature lines kept together, QR, footer with the University, the title, the generation
  line, the reference, the label and "Page X of Y", optional watermark); `finishPdf(pages, title,
  profile)` stamps the footer on pages a route drew itself. `brandHeader` now reads the profile (name,
  motto, address/contact line, logo), so every existing route is branded without rewriting it; every
  route awaits `loadInstitution()` first.
- **Browser print** — `lib/document/html.ts`: `documentHtml` (pure, tested), `printDocument`,
  `previewDocument`, `printElement`. The same header and footer, a serial column, `thead` repeated on
  each printed page, rows that do not split, A4 portrait or landscape by profile, a running footer, the
  watermark. `brandedPrint`, `printNode` and the table Print button are now thin wrappers over it.
- **Workbooks** — `brandedXlsx` heads the sheet with the profile's name and logo, leads with a numeric
  S/N (unless the rows already carry one), freezes the header row and gives it an auto-filter
  (`buildXlsx` option `filter`). `ReportToolbar` and the kept-return download use it.
- **Issued documents** — `platform.document_issue` (audited) and `POST /api/v1/documents/issued`: a
  receipt downloaded, a statement printed, a broadsheet exported, in the actor's name with the reference
  and the options used. Authorisation is the data's: a PDF route reads through the API under the user's
  token, so a document is never issued to someone the API would not show the record to.
- **Administration** — Administration → Institution Profile (`/platform/institution`): the fields, the
  logo (upload, replace, back to the crest; PNG or JPEG ≤ 2 MB; the file store keeps it, the documents
  reference it), a live header/footer preview, a sample printed report and a sample PDF.

## C. Where the identity lives, and what stays the same

- A document already issued keeps the identity it was issued under: the PDFs are generated on request
  from the record, and the kept copies (returns, certificates) hold their own statement; a change of
  logo or name reaches only what is issued from now on.
- Certificates and ID cards keep their specialised layouts; they take the name and the logo from the
  profile and nothing else changes. Letters keep their letter form.
- The payment gateway's merchant descriptor (`PaymentsService.SCHOOL_NAME`) is not a document and was
  left as the gateway expects it.
- Where a page is a designed print sheet (`ReportDoc`, the transfer letter, the memo, hall lists), the
  sheet still prints as designed; its name is read through the profile where it builds a document.

## D. Tests

- `lib/document/pdf.test.ts` — a 150-row report runs over pages with the letterhead first and the band
  after, the table header repeated on every page of rows, S/N 1…150, "Page X of Y" on every page,
  signature lines, the generated-by line, the confidentiality label; `finishPdf` foots a route's pages
  and stamps a watermark; an ID card gets no footer.
- `lib/document/html.test.ts` — the printed document carries the header, motto, address and contact
  lines, the title in capitals, the filters, S/N, formatted numbers, the running footer; a result is a
  STUDENT COPY, a broadsheet prints landscape, a receipt has no S/N; the helpers never print
  undefined, null or a scheme.
- `InstitutionIT` — read by anyone, changed by the keepers alone, a blank name and a malformed e-mail
  refused, the change audited, `Branding.name()` following the profile; the logo kept with its JPEG
  derivative and served, or refused with FILES_NOT_CONFIGURED where there is no store; an issued
  document on the record in the actor's name.
- `db/check.sql` 164–165 — one profile row, its rules and audit; an issued document in the actor's name.
