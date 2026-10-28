# A failed elective is an F, never a carry-over (V689)

The University's word of 28 October 2026: PHL 114 and BSU-HIS 112 are electives for B.A. English students. A student who fails
them does not carry them over: elective courses are never counted as carry-overs, and a failed one is calculated as F.

## The rule

A failed course is owed (a carry-over) only when it is not an elective to the student. `registration.is_elective_for` decides,
in this order:

1. **As the student registered it.** This applies where the registration carries the programme's basis for the course (Core,
   Elective, Borrowed …) or was made as an elective or a GST course.
2. **The programme's structure today.** If the programme binds the course as an elective at any level, it is an elective.
3. **The course's own kind** in the catalogue.

Before V689, a registration without a programme basis counted as core whatever the course was. Such registrations were:
* a course the programme does not bind (a B.A. English student's PHL 114 or BSU-HIS 112);
* an elective of a lower level taken late;
* a registration migrated before the structure was uploaded.

Its F was then owed. On the copy of 21 October 2026 that held 141 failed courses of 105 students that are electives by the
programme's structure or by the course itself (PSY 103, BSU-PSY 109, POL 103, BSU-ACC 105 …). They are no longer owed.

A course the student's programme makes core stays owed. B.A. History's BSU-HIS 112 and B.A. Philosophy's PHL 114 are core
courses of those programmes, so their students who fail them still carry them over.

## The F still counts

A failed elective is an F. Its units are attempted and earn no points, so it counts in the GPA and the CGPA as before. On the
broadsheet the remark names it **Fail: …**, not **CO: …**. The broadsheet now judges an elective the same way the carry-overs
do (per student, as above) rather than by the course's kind alone.

## B.A. English

For B.A. English (C00002), B.A. English Studies (C69405) and B.A. English Literature (C95933), V689 makes PHL 114 and
BSU-HIS 112 electives. Any binding of either that says otherwise becomes Elective, and every registration of either by those
programmes' students carries the basis Elective. In a rolled-back trial on the copy, with English Studies' PHL 114 recorded as
core, the 15 students who had failed it owed it; after V689 none did, while B.A. History's 7 students still owe BSU-HIS 112.

## Who follows

Every reader of `registration.carryovers` and `registration.carryovers_at`:
* the carry-overs listed and placed on a registration, and the carry-over picker;
* the dashboard and the full record;
* spillover (`finance.spillover_students`) and completion (`people.lifecycle_completion_rows`);
* the transcript, the reports, and the broadsheet's remark.
