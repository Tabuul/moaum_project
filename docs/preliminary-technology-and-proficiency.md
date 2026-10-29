# Preliminary Technology & Industrial Studies, and the Adikpo Campus proficiency certificate courses (V701)

The University's master prompt of 29 October 2026 asks for two more offerings. Neither is an undergraduate degree.

- **Preliminary Technology & Industrial Studies** is a preliminary / remedial programme. It prepares candidates for the UTME and
  for later admission into three programmes of the Faculty of Technology and Industrial Studies. Choosing a target is an
  **intended progression**, never admission into that degree.
- **The proficiency certificate courses of Adikpo Campus** are 30 skill certificates of nine months each, in three categories.

Both run on the stack V446 built for Preliminary Science ([preliminary-science.md](preliminary-science.md)): one application
system, fee and gateway path, O'Level record, document store, notification engine, window register and audit trail. V701 adds
two routes to it. It adds no second application, payment, eligibility or student system.

```
Preliminary Technology  = route PRELIMINARY_TECHNOLOGY  (programme type PRELIMINARY, entry mode PRELIMINARY, session 2026/2027)
Proficiency courses     = route PROFICIENCY_CERTIFICATE (programme type PROFICIENCY_CERTIFICATE, entry mode PROFICIENCY,
                                                         campus Adikpo, 9 months, session 2026/2027)
Both                    = reviewed and recommended by the Preliminary Vocational and Technical Education Office (prelimtech);
                          approved and published by the Academic Office, never by the office that recommended
```

The University's choices on 29 October 2026:

- Industrial Technology progresses to **C00096 B.Sc. (ED) Technology**.
- The offerings have their own office, **prelimtech**. It is the HR unit V253 already named, Preliminary Vocational & Technical
  Education.
- The session is **2026/2027**.

---

## 1. What each route holds

Everything below is data in `admissions.prelim_programme` and its tables. The Academic Office changes it on the settings page,
with a reason. Every open application is read again under the new rule.

| | Preliminary Technology & Industrial Studies | Proficiency certificate courses |
|---|---|---|
| Programme type | `PRELIMINARY` (Preliminary / Remedial) | `PROFICIENCY_CERTIFICATE` (new; never preliminary, never a degree) |
| Campus | not named (main) | Adikpo Campus (`ref.campus`, new) |
| Duration | **not configured** (not given) | 9 months |
| Entry rule (`rule_kind`) | `OLEVEL_CREDITS`: at least 4 credits (C6 or better) in at most 2 sittings. **English Language must be credited**, plus 3 credits among the chosen area's own subjects. An awaiting result is refused. | `ATTEMPTED_CERTIFICATE`: the secondary school certificate examination was sat and its results given. No grade is asked. |
| Completion | 5 credits in the **relevant** subjects (`completion_scope RELEVANT`: English and the area's subjects). With 4, the applicant is eligible with remediation. | A certificate on completing the course. None is issued before completion is configured. |
| Qualifications accepted | SSCE, GCE, NABTEB NTC, NABTEB NBC, City & Guilds Part I, City & Guilds Part II, Federal Craft Training Certificate, TC II, another the University approves (`admissions.qualification_type`, new; `screening_olevel.exam_type` now refers to it) | the same |
| Targets | 3 areas, each an existing programme of the register | 30 certificate courses in 3 categories |
| Options | specialisations within a target programme (`admissions.prelim_specialisation`, new) | none |
| Documents | 3 passport photographs (JPEG), O'Level result per sitting, LGA certificate, birth certificate | passport, certificate or result, second sitting if any, LGA and birth certificates (optional) |
| Application fee | ₦5,000, non-refundable (`route_fee`, 2026/2027) | **FEE NOT CONFIGURED**. The form stays shut until the Bursary sets a fee and it is paid. |
| Window | `PRELIMINARY_TECHNOLOGY_APPLICATION`: closed until the Director of ICT opens it | `PROFICIENCY_CERTIFICATE_APPLICATION`: the same |

### Preliminary Technology's areas

| Area | Target programme (register) | Subjects, three of which must be credited | Specialisations |
|---|---|---|---|
| Agricultural Technology and Consumer Science | C78876 B.Sc. Ed. Home Economics | Chemistry, Biology, Agricultural Science, Food and Nutrition, Clothing and Textiles, Economics, Geography | none |
| Business Technology & Entrepreneurship Education | C67773 B.Sc. Ed. Business Education | Mathematics, Economics, Financial Accounting, Marketing, Commerce, ICT / Computer Studies / Data Processing | Accounting Education, Entrepreneurship Education, Marketing and Distribution Education, Office Management |
| Industrial Technology | C00096 B.Sc. (ED) Technology (named "B.Tech. Ed. Industrial Technology" in the prompt) | Mathematics, Technical Drawing, Physics, Chemistry, ICT / Computer Studies / Data Processing | Automobile, Building, Electrical/Electronic, Metal Work, Wood Work, Refrigeration and Air Conditioning |

Each target is checked against the register when the migration runs. A code that is not a current undergraduate programme is
written as **MISSING**, and the Academic Office resolves it on the settings page. No programme is created.

The eligibility of an applicant who has not chosen an area waits as **PENDING_REVIEW**. Once the area is chosen, its subjects
count. A programme with specialisations needs one chosen before the application can be submitted. A specialisation of another
programme is refused.

### The certificate courses (Adikpo Campus)

- **Agricultural Technology and Consumer Science:**
  - Salon and Beauty Therapy
  - Fashion Design
  - Baking and Confectioneries
- **Business Technology and Entrepreneurship Education:**
  - Word Processing
  - Computer Application
  - Information Technology
  - Office Management
  - Financial Accounting
- **Industrial Technology:**
  - Auto-body Repairs, Finishing and Maintenance
  - Automobile Repair and Maintenance
  - Auto-Electrician Work
  - Vulcanizing
  - Masonry and Block Laying
  - Tiling and Land Scraping
  - Paraflex and POP
  - Domestic Wiring and Installation
  - Piping and Plumbing
  - AC/DC Generator/Motors Repair
  - Radio and Television Repairs
  - Satellite Installation
  - CCTV Installation
  - Mobile Phone Repairs
  - Electrical Power Distribution
  - Solar System Installations
  - Photography
  - Welding and Fabrication
  - Machining Technology
  - Refrigeration and Air-Conditioning
  - Woodwork
  - Upholstery

A course is never a programme of the register. The Academic Office adds or withdraws courses, and reinstates withdrawn ones, on
the settings page.

---

## 2. Who does what

| Office | Preliminary Science | Preliminary Technology | Proficiency courses |
|---|---|---|---|
| Preliminary Science Office (`prelim`) | reviews, recommends | refused | refused |
| Preliminary Vocational and Technical Education Office (`prelimtech`, new) | refused | reviews, recommends | reviews, recommends |
| Academic Office | approves, publishes, configures | the same | the same |
| Bursary | states the fees | the same | the same (sets the fee) |
| Director of ICT | opens and closes the window | its own window | its own window |
| Head of Department / Dean | reads their targets | reads their targets | none (a course has no department) |

Both offices' home page is their desk. A route's own office opens on its first route (prelimtech on Preliminary Technology),
and it switches to the other route from the desk. The central offices see one **Preliminary & Proficiency Programmes** desk with a programme switch.

---

## 3. The screens

- **Public pages:** `/preliminary-technology` and `/proficiency-certificate`, each with its own `/apply`. They are one shared
  page (`components/preliminary/PrelimProgrammePage`) that reads the route's configuration from
  `GET /api/v1/public/preliminary/{slug}`. They show:
  - the description, programme type, campus and duration (or "Not configured"), and the window;
  - the entry requirement in words;
  - the targets with their subjects and options, or the courses by category;
  - the fee (or "To be announced by the Bursary"), the procedure and the documents.

  `/preliminary-science` uses the same page.
- **Applicant:** one form for every route (`/applicant/preliminary`). It shows:
  - the qualification list the route accepts;
  - the area, then its specialisation, or the category, then its course;
  - the subjects the chosen area asks for;
  - three passport photographs where the route asks for them;
  - every heading and note in the route's own words.

  The application form and admission letter (PDF) name the programme, campus and duration, and either the target with its area
  and specialisation (with the target notice) or the certificate course.
- **Desk** (`/preliminary?route=…`):
  - the figures and list of the chosen programme;
  - filters by target or course and by area or category;
  - the detail with the route's requirement (an attempted certificate needs no remediation);
  - a change of target and specialisation, with a reason;
  - exports with the route's own serial (PRESCI, PRETECH, PROFCERT);
  - publishing per route.
- **Reports** (`/preliminary/reports?route=…`): counts by target or course, by area or category, by specialisation, by sitting,
  by sex and by state, and the payment report.
- **Settings** (`/preliminary/config?route=…`):
  - the rule (required subjects, completion scope, qualifications, duration, certificate, entry and target wording);
  - each area's subjects and specialisations;
  - the certificate courses;
  - documents and fees.

Notices use the central templates, with each route's own words (copied from Preliminary Science's). A proficiency admission is
into a certificate course, never an intended progression.

Payments are classified by programme type:

- Preliminary Technology's are under the `PRELIMINARY` type with Preliminary Science's. The type is now read by both `prelim`
  and `prelimtech`.
- The proficiency courses' are `PROFICIENCY_CERTIFICATE` (entry mode PROFICIENCY, office prelimtech), apart from the
  preliminary and undergraduate figures.

The receipt and its public verification page name the programme paid for ("Preliminary Technology & Industrial Studies
application receipt"), not the entry mode Preliminary Science and Preliminary Technology share. The Director of ICT's
Application Registration page lists both windows.

Neither offering appears on Post-UTME lists, status checking or the UTME applicant desk.

---

## 4. Not done: the University's word is needed

Nothing below is invented. Each shows as "Not configured" or stays shut until the University gives it.

1. **The proficiency application fee.** The Bursary sets it on the settings page. Until then, the applicant can start but not
   pay or continue.
2. **The duration of Preliminary Technology.** The prompt does not give it.
3. **The windows' dates.** Both windows are closed. The Director of ICT opens each on Application Registration.
4. **Acceptance and school fees, the identity number, the move onto the student register, courses, attendance, results and
   certificates** for either offering.
5. **Wording to confirm:**
   - "Tiling and Land Scraping" (perhaps "Landscaping");
   - "Paraflex and POP";
   - whether ICT, Computer Studies and Data Processing are one subject;
   - whether Textile and Clothing and Clothing and Textiles are one subject (both are accepted).
6. **The areas' subject lists and the Business Education and Technology options.** They are written as the prompt gives them.
   The Academic Office can change each on the settings page.
7. **NABTEB NTC / NBC and City & Guilds results.** They are read on the same A1–F9 scale as the school certificate. If the
   University grades them otherwise, the rule needs its word.
8. **Physical submission:** where the printed form is taken, if anywhere.

---

## 5. Checked

- **check.sql V701** (EXPECTED 525). It covers:
  - three routes read by the public;
  - Preliminary Technology:
    - its own window;
    - the ₦5,000 fee before the form;
    - NTC accepted and an unknown qualification refused;
    - English required;
    - PENDING_REVIEW until an area is chosen, then the area's three subjects;
    - four credits give eligible with remediation, five give eligible;
    - an option required, and another programme's option refused;
    - one examination number per person;
    - prelimtech reviews, the Preliminary Science Office is refused, the Academic Office approves and publishes;
    - the letter names the programme, its type, the target and the option;
  - the proficiency courses:
    - FEE NOT CONFIGURED shuts the form;
    - an attempted certificate (all F9) is eligible;
    - a course is never a Preliminary Technology target;
    - the letter names the course, Adikpo Campus and nine months;
    - the payment is classified `PROFICIENCY_CERTIFICATE`;
  - both kept apart from Post-UTME.
- **`PreliminaryTechnologyIT`:**
  - the public pages;
  - the Preliminary Technology flow end to end, with the office walls;
  - the proficiency flow.
- **`PreliminaryScienceIT`** still passes.
- **Frontend:** `lib/preliminary.test.ts` and `lib/applicant-receipt.test.ts`.
- **In the browser,** on a scratch database with made-up applicants:
  - both public pages;
  - registration for each programme;
  - the proficiency form shut with "fee not configured";
  - the paid Preliminary Technology form with the area, specialisation and qualification lists;
  - prelimtech's desk opening on its own programmes;
  - the application's detail and both printed forms;
  - the settings (an option added) and the reports.
