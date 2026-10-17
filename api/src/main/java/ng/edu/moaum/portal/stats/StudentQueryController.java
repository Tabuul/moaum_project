package ng.edu.moaum.portal.stats;

import java.util.Map;

import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.ModelAttribute;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * The Student Query (V469): one query builder for every office that asks "which students are we talking about?" —
 * the list, the figures by programme type and the filter options, all from StudentQueryService over people.learner.
 *
 * <p>University-wide: the Registry, the Academic Office, Exams and Records, the Directorate of ICT, the Vice-Chancellor
 * and the Deputy, the Bursary, the platform. Faculty: the Dean and the Faculty Officer. Department: the Head and the
 * Examinations Officer. The College's offices: the College. One programme type: the School of Postgraduate Studies,
 * the Centre for Continuing Education, the JUPEB, Preliminary and Sandwich offices. The GST and EPS offices, the
 * hostel and the ICT Support Desk keep their own screens, each limited to what it serves.
 */
@RestController
@RequestMapping("/api/v1/stats/students/query")
class StudentQueryController {

    static final String READERS = "hasAnyAuthority('OFFICE_registrar','OFFICE_dregistrar','OFFICE_academic','OFFICE_records',"
            + "'OFFICE_ict','OFFICE_admin','OFFICE_super','OFFICE_vc','OFFICE_dvc','OFFICE_bursar','OFFICE_studentaccounts',"
            + "'OFFICE_dean','OFFICE_facultyofficer','OFFICE_hod','OFFICE_exams',"
            + "'OFFICE_provost','OFFICE_collegesecretary','OFFICE_financecontroller',"
            + "'OFFICE_pgschool','OFFICE_pgsecretary','OFFICE_cce','OFFICE_jupeb','OFFICE_prelim','OFFICE_sandwich')";

    private final StudentQueryService query;

    StudentQueryController(StudentQueryService query) {
        this.query = query;
    }

    /** a page of the learners the filters select, within the office's scope, names A–Z */
    @GetMapping
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> list(@ModelAttribute StudentQueryRequest filters,
                             @RequestParam(defaultValue = "0") int page, @RequestParam(defaultValue = "50") int size) {
        return query.page(filters, page, size);
    }

    /** the learners by programme type for the same filters: the cards every dashboard and the query itself show */
    @GetMapping("/summary")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> summary(@ModelAttribute StudentQueryRequest filters) {
        return query.summary(filters);
    }

    /** what the filter bar may offer for the type chosen, within the office's scope */
    @GetMapping("/options")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> options(@ModelAttribute StudentQueryRequest filters) {
        return query.options(filters);
    }
}
