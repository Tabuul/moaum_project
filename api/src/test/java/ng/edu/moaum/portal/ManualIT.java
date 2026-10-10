package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import java.util.Map;
import java.util.Random;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.HttpMethod;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.transaction.PlatformTransactionManager;

/**
 * The Quick Operational Manual (V387), through the API: a student reads a manual of student and everyone procedures and nothing of
 * ICT's or the Bursary's; the postgraduate sidebar adds the School's; a search narrows it; a page's own help is the procedures bound
 * to its route; readings are recorded and an unknown kind refused; an ICT Support Agent without a posting does not read a
 * capability-bound procedure; Manual Management is the administrators' — a draft is unseen until published, an edit keeps the
 * version, unpublish, archive (then no edit), restore, the refusals, the order, the preview as an office and the edition's release.
 * Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class ManualIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    final String student = TestTokens.token(UUID.randomUUID(), List.of("student"));
    final String bursar = ItSupport.token("bursar");
    final String agent = ItSupport.token("ictagent");
    final String superAdmin = ItSupport.token("super");

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
    }

    private static List<Map<String, Object>> procedures(ResponseEntity<Map> r) {
        return (List<Map<String, Object>>) r.getBody().get("procedures");
    }

    private static List<String> slugs(ResponseEntity<Map> r) {
        return procedures(r).stream().map(p -> String.valueOf(p.get("slug"))).toList();
    }

    private static int[] edition(ResponseEntity<Map> r) {
        String[] v = String.valueOf(((Map<String, Object>) r.getBody().get("edition")).get("version")).split("\\.");
        return new int[] {Integer.parseInt(v[0]), Integer.parseInt(v[1])};
    }

    @Test
    void theReaderSeesTheirOwnOfficeAndNothingElse() {
        ResponseEntity<Map> s = it.get(student, "/api/v1/manual");
        assertThat(s.getStatusCode().value()).as(String.valueOf(s.getBody())).isEqualTo(200);
        assertThat(s.getBody().get("office")).isEqualTo("student");
        List<Map<String, Object>> rows = procedures(s);
        assertThat(rows.size()).isGreaterThanOrEqualTo(20);
        for (Map<String, Object> p : rows) {
            List<String> offices = (List<String>) p.get("offices");
            assertThat(offices).as(p.get("slug") + " " + offices).anyMatch(o -> o.equals("student") || o.equals("everyone"));
            assertThat(offices).doesNotContain("ict", "bursar", "academic");
            assertThat((List<String>) p.get("steps")).isNotEmpty();
        }
        assertThat(slugs(s)).contains("sign-in", "student-pay-fees", "student-register").doesNotContain("pg-progress", "bursar-refunds");
        // the postgraduate sidebar adds the School's procedures; a sidebar of another family is ignored
        assertThat(slugs(it.get(student, "/api/v1/manual?menu=pgstudent"))).contains("pg-progress", "student-pay-fees");
        assertThat(slugs(it.get(student, "/api/v1/manual?menu=bursar"))).doesNotContain("bursar-refunds");
        // a search narrows it over the resolved words
        ResponseEntity<Map> q = it.get(student, "/api/v1/manual?q=fees");
        assertThat(q.getBody().get("q")).isEqualTo("fees");
        assertThat(slugs(q)).contains("student-pay-fees").doesNotContain("student-exam-card");
        // a page's own help
        ResponseEntity<List> ctx = it.getList(student, "/api/v1/manual/context?route=s/register");
        assertThat(ctx.getStatusCode().value()).isEqualTo(200);
        assertThat(ctx.getBody().stream().map(x -> ((Map) x).get("slug"))).contains("student-register");
        // the Bursar reads the Bursary's and everyone's
        assertThat(slugs(it.get(bursar, "/api/v1/manual"))).contains("sign-in", "bursar-refunds", "bursar-fee-schedule").doesNotContain("ict-users", "student-register");
        // an ICT Support Agent with no posting reads the desk's procedures but not a capability-bound one
        assertThat(slugs(it.get(agent, "/api/v1/manual"))).contains("cpo-tickets").doesNotContain("cpo-add-course", "cpo-find-student");
        // readings
        UUID first = UUID.fromString(String.valueOf(rows.get(0).get("id")));
        ResponseEntity<Map> v = it.call(student, HttpMethod.POST, "/api/v1/manual/views", Map.of("kind", "PROCEDURE", "procedureId", first.toString()));
        assertThat(v.getStatusCode().value()).as(String.valueOf(v.getBody())).isEqualTo(200);
        ResponseEntity<Map> bad = it.call(student, HttpMethod.POST, "/api/v1/manual/views", Map.of("kind", "WHATEVER"));
        assertThat(bad.getStatusCode().value()).isEqualTo(422);
        assertThat(String.valueOf(bad.getBody())).contains("MANUAL_VIEW_KIND");
        // Manual Management is not the reader's
        assertThat(it.get(bursar, "/api/v1/manual/admin").getStatusCode().value()).isEqualTo(403);
        assertThat(it.get(student, "/api/v1/manual/admin").getStatusCode().value()).isEqualTo(403);
    }

    @Test
    void manualManagementDraftsPublishesVersionsArchivesRestoresOrdersAndReleases() {
        String slug = "it-manual-" + (new Random().nextInt(900000) + 100000);
        ResponseEntity<Map> before = it.get(superAdmin, "/api/v1/manual/admin");
        assertThat(before.getStatusCode().value()).as(String.valueOf(before.getBody())).isEqualTo(200);
        assertThat(procedures(before).size()).isGreaterThanOrEqualTo(200);
        assertThat((List<String>) before.getBody().get("keys")).contains("bursar", "student", "pgstudent", "everyone");
        int[] ed0 = edition(before);

        // a draft: the Bursar does not read it
        Map<String, Object> body = Map.of("slug", slug, "title", "IT procedure", "purpose", "An integration test's procedure.", "category", "PAYMENTS",
                "offices", List.of("bursar"), "capabilities", List.of(), "menuId", "t/payments", "steps", List.of("Open {menu:t/payments}.", "Click `Export Excel`."),
                "expected", "The list is exported.", "sortOrder", 5);
        ResponseEntity<Map> created = it.call(superAdmin, HttpMethod.POST, "/api/v1/manual/admin/procedures", body);
        assertThat(created.getStatusCode().value()).as(String.valueOf(created.getBody())).isEqualTo(200);
        assertThat(created.getBody().get("state")).isEqualTo("DRAFT");
        assertThat((List<String>) created.getBody().get("steps")).hasSize(2);
        String id = String.valueOf(created.getBody().get("id"));
        assertThat(slugs(it.get(bursar, "/api/v1/manual"))).doesNotContain(slug);

        // the refusals: an unknown office, a taken key, an action that is not one
        ResponseEntity<Map> unknown = it.call(superAdmin, HttpMethod.POST, "/api/v1/manual/admin/procedures",
                Map.of("slug", slug + "-b", "title", "x", "purpose", "x", "category", "PAYMENTS", "offices", List.of("nobody"), "steps", List.of("x"), "expected", "x"));
        assertThat(unknown.getStatusCode().value()).isEqualTo(422);
        assertThat(String.valueOf(unknown.getBody())).contains("MANUAL_OFFICE_UNKNOWN");
        ResponseEntity<Map> taken = it.call(superAdmin, HttpMethod.POST, "/api/v1/manual/admin/procedures",
                Map.of("slug", slug, "title", "x", "purpose", "x", "category", "PAYMENTS", "offices", List.of("bursar"), "steps", List.of("x"), "expected", "x"));
        assertThat(taken.getStatusCode().value()).isEqualTo(422);
        assertThat(String.valueOf(taken.getBody())).contains("MANUAL_SLUG_TAKEN");
        assertThat(it.call(superAdmin, HttpMethod.POST, "/api/v1/manual/admin/procedures/" + id + "/DELETE", Map.of()).getStatusCode().value()).isEqualTo(422);

        // published: the Bursar reads it; the edition stepped
        ResponseEntity<Map> published = it.call(superAdmin, HttpMethod.POST, "/api/v1/manual/admin/procedures/" + id + "/PUBLISH", Map.of());
        assertThat(published.getStatusCode().value()).as(String.valueOf(published.getBody())).isEqualTo(200);
        assertThat(published.getBody().get("state")).isEqualTo("PUBLISHED");
        assertThat(slugs(it.get(bursar, "/api/v1/manual"))).contains(slug);
        int[] ed1 = edition(it.get(superAdmin, "/api/v1/manual/admin"));
        assertThat(ed1[0]).isEqualTo(ed0[0]);
        assertThat(ed1[1]).isEqualTo(ed0[1] + 1);

        // an edit keeps the version and the publication
        Map<String, Object> edit = new java.util.LinkedHashMap<>(body);
        edit.put("title", "IT procedure, edited");
        edit.put("steps", List.of("Open {menu:t/payments}.", "Click `Export Excel`.", "File it."));
        edit.put("note", "a third step");
        ResponseEntity<Map> edited = it.call(superAdmin, HttpMethod.PUT, "/api/v1/manual/admin/procedures/" + id, edit);
        assertThat(edited.getStatusCode().value()).as(String.valueOf(edited.getBody())).isEqualTo(200);
        assertThat(edited.getBody().get("version")).isEqualTo(2);
        assertThat(edited.getBody().get("state")).isEqualTo("PUBLISHED");
        ResponseEntity<Map> versions = it.get(superAdmin, "/api/v1/manual/admin/procedures/" + id + "/versions");
        assertThat(versions.getStatusCode().value()).isEqualTo(200);
        List<Map<String, Object>> vs = (List<Map<String, Object>>) versions.getBody().get("versions");
        assertThat(vs).hasSize(1);
        assertThat(vs.get(0).get("version")).isEqualTo(1);
        assertThat(String.valueOf(vs.get(0).get("snapshot"))).contains("IT procedure").doesNotContain("edited");
        assertThat(vs.get(0).get("note")).isEqualTo("a third step");

        // unpublished, archived (no edit), restored; the order; the preview as an office with and without a capability; the release
        assertThat(it.call(superAdmin, HttpMethod.POST, "/api/v1/manual/admin/procedures/" + id + "/UNPUBLISH", Map.of()).getBody().get("state")).isEqualTo("DRAFT");
        assertThat(slugs(it.get(bursar, "/api/v1/manual"))).doesNotContain(slug);
        assertThat(it.call(superAdmin, HttpMethod.POST, "/api/v1/manual/admin/procedures/" + id + "/ARCHIVE", Map.of("note", "old")).getBody().get("state")).isEqualTo("ARCHIVED");
        ResponseEntity<Map> onArchived = it.call(superAdmin, HttpMethod.PUT, "/api/v1/manual/admin/procedures/" + id, edit);
        assertThat(onArchived.getStatusCode().value()).isEqualTo(422);
        assertThat(String.valueOf(onArchived.getBody())).contains("MANUAL_ARCHIVED");
        assertThat(it.call(superAdmin, HttpMethod.POST, "/api/v1/manual/admin/procedures/" + id + "/RESTORE", Map.of()).getBody().get("state")).isEqualTo("DRAFT");
        ResponseEntity<Map> admin = it.get(superAdmin, "/api/v1/manual/admin?state=DRAFT");
        assertThat(slugs(admin)).contains(slug);
        List<String> payments = procedures(it.get(superAdmin, "/api/v1/manual/admin?q=refund")).stream().map(p -> String.valueOf(p.get("id"))).toList();
        ResponseEntity<Map> ordered = it.call(superAdmin, HttpMethod.PUT, "/api/v1/manual/admin/order", Map.of("ids", payments));
        assertThat(ordered.getStatusCode().value()).as(String.valueOf(ordered.getBody())).isEqualTo(200);
        assertThat(slugs(it.get(superAdmin, "/api/v1/manual/admin/preview?office=ictagent"))).doesNotContain("cpo-add-course");
        assertThat(slugs(it.get(superAdmin, "/api/v1/manual/admin/preview?office=ictagent&capabilities=MANAGE_REGISTRATION"))).contains("cpo-add-course", "cpo-tickets");
        assertThat(slugs(it.get(superAdmin, "/api/v1/manual/admin/preview?office=student&menu=pgstudent"))).contains("pg-progress");
        ResponseEntity<Map> released = it.call(superAdmin, HttpMethod.POST, "/api/v1/manual/admin/edition", Map.of("note", "the IT's edition"));
        assertThat(released.getStatusCode().value()).isEqualTo(200);
        int[] ed2 = edition(it.get(superAdmin, "/api/v1/manual/admin"));
        assertThat(ed2[0]).isEqualTo(ed1[0] + 1);
        assertThat(ed2[1]).isEqualTo(0);

        it.db(() -> jdbc.sql("DELETE FROM manual.procedure WHERE slug LIKE 'it-manual-%'").update());
    }
}
