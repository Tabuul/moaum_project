# The University's figures on the website

The public website shows the University's counters — faculties and colleges, academic departments,
courses of study, degree programme types, enrolled students, academic and support staff. They are read
live from the portal, so they follow the register, the catalogue and the nominal roll without anyone
retyping a number.

## The endpoint

```
GET https://moaum-portal-production.up.railway.app/api/v1/public/statistics
```

Open (no token), answers any origin (CORS, GET only, no credentials), cached for five minutes
(`Cache-Control: public, max-age=300`). It carries no personal data — only counts.

```json
{
  "university": "Rev. Fr. Moses Orshio Adasu University, Makurdi",
  "session": "2025/2026",
  "asAt": "2026-09-27T14:03:11.412+01:00",
  "figures": {
    "facultiesAndColleges": 13, "faculties": 12, "colleges": 1,
    "academicDepartments": 50,
    "coursesOfStudy": 281, "undergraduateProgrammes": 92, "postgraduateProgrammes": 189,
    "degreeProgrammeTypes": 14,
    "enrolledStudents": 21600, "undergraduates": 18900, "postgraduates": 2700,
    "academicStaff": 960, "supportStaff": 1000, "academicAndSupportStaff": 1960
  },
  "display": { "enrolledStudents": "21,600", "...": "the same figures with thousands separators" },
  "awards": [ { "award": "BACHELOR", "programmes": 92 }, { "award": "MSC", "programmes": 71 }, { "award": "PHD", "programmes": 76 } ],
  "definitions": { "enrolledStudents": "Students on the register in good standing: active, on probation or deferred", "...": "..." }
}
```

`figures` are exact integers; `display` the same with thousands separators; `awards` lists each award
offered with its programme count; `definitions` says what each figure counts, so a caption can say so.

| Figure | Counts |
|---|---|
| `facultiesAndColleges` | faculties on the reference list plus the Colleges that group them |
| `academicDepartments` | departments on the reference list |
| `coursesOfStudy` | programmes offered (not archived), undergraduate and postgraduate |
| `degreeProgrammeTypes` | distinct awards offered: the undergraduate degree and each postgraduate award (PGD, MA, MSc, MBA, PhD, …) |
| `enrolledStudents` | students on the register in good standing: ACTIVE, PROBATION or DEFERRED |
| `academicAndSupportStaff` | staff in active employment on the nominal roll (people loaded on the roll without an employment record still count) |

## Putting it on the website

Give each counter a `data-stat` attribute naming the figure, and one script fills them when the page
loads. The numbers already in the markup stay as the fallback if the portal cannot be reached.

```html
<div class="stat"><b data-stat="facultiesAndColleges">14</b><span>Faculties &amp; Colleges</span></div>
<div class="stat"><b data-stat="academicDepartments">61</b><span>Academic Departments</span></div>
<div class="stat"><b data-stat="coursesOfStudy">310</b><span>Courses of Study</span></div>
<div class="stat"><b data-stat="degreeProgrammeTypes">1</b><span>Degree Programme Types</span></div>
<div class="stat"><b data-stat="enrolledStudents">21,600</b><span>Enrolled Students</span></div>
<div class="stat"><b data-stat="academicAndSupportStaff">1,960</b><span>Academic &amp; Support Staff</span></div>

<script>
fetch("https://moaum-portal-production.up.railway.app/api/v1/public/statistics")
  .then(function (r) { return r.ok ? r.json() : null; })
  .then(function (s) {
    if (!s) return;
    document.querySelectorAll("[data-stat]").forEach(function (el) {
      var v = s.display[el.getAttribute("data-stat")];
      if (v !== undefined) el.textContent = v;
    });
  })
  .catch(function () { /* the numbers in the markup stand */ });
</script>
```

A site built with React or Next.js does the same in a hook — `rportal-next-main/src/lib/portalStatistics.ts`
is one, and its home page's metrics row uses it. The endpoint's origin is the portal's; a staging site
points the fetch at the staging portal instead.
