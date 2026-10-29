package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.math.BigDecimal;
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
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.transaction.PlatformTransactionManager;

/**
 * V701 — Preliminary Technology & Industrial Studies and the Adikpo Campus proficiency certificate courses through the API. The
 * public application page lists both beside Preliminary Science, by programme type; Preliminary Technology's page has three areas
 * with their options, the proficiency page thirty certificate courses at Adikpo Campus, nine months, the fee not yet set. A
 * Preliminary Technology applicant starts online on its own window, pays the ₦5,000, gives an NTC sitting, chooses B.Sc. (Ed)
 * Business Education with Accounting Education (another programme's option refused) and is eligible; the desk of the route is the
 * Vocational and Technical Office's — the Preliminary Science Office is refused it, and the Vocational and Technical Office is
 * refused Preliminary Science's. A proficiency applicant is entry mode PROFICIENCY, can raise no fee reference until the Bursary
 * sets one, and chooses a certificate course. Both programmes' application fees are paid on Quickteller as every applicant's are.
 * Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class PreliminaryTechnologyIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    final String tech = ItSupport.token("prelimtech");
    final String science = ItSupport.token("prelim");

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        // both windows open for the test, as the Director of ICT opens them, whatever an earlier run left
        for (String[] w : new String[][] {{"PRELIMINARY_TECHNOLOGY_APPLICATION", "PRELIMINARY_TECHNOLOGY"}, {"PROFICIENCY_CERTIFICATE_APPLICATION", "PROFICIENCY_CERTIFICATE"}}) {
            it.db(() -> jdbc.sql("""
                    SELECT CASE WHEN (SELECT x.state FROM policy.window_state(:t, policy.route_session(:r), NULL) x) = 'OPEN' THEN NULL
                                ELSE policy.window_act(:t, policy.route_session(:r), NULL, 'OPEN', NULL, NULL, NULL, false, 'integration test: open', gen_random_uuid(), 'ict') END
                    """).param("t", w[0]).param("r", w[1]).query().listOfRows());
        }
    }

    private Map<String, Object> ok(ResponseEntity<Map> r) {
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        return r.getBody();
    }

    private static String code(ResponseEntity<Map> r) {
        return r.getBody() == null ? null : String.valueOf(r.getBody().get("code"));
    }

    private Map<String, Object> register(String route, String tag, String sex) {
        return ok(it.anon(HttpMethod.POST, "/api/v1/applicant/preliminary/register", Map.of("surname", "Tech" + tag, "firstName", "Ada" + tag, "sex", sex,
                "dateOfBirth", "2006-03-01", "email", "tech" + tag + "@example.com", "phone", "0806" + tag.substring(0, 7), "password", "a-long-password-" + tag, "route", route)));
    }

    private static String tag() {
        return String.valueOf(Math.abs(UUID.randomUUID().getMostSignificantBits() % 9_000_000_000L) + 1_000_000_000L);
    }

    @Test
    void thePublicPagesListBothProgrammesTheirAreasOptionsAndCourses() {
        List<Map<String, Object>> routes = (List<Map<String, Object>>) (List) org.springframework.web.client.RestClient.create("http://localhost:" + port)
                .get().uri("/api/v1/public/preliminary").retrieve().toEntity(List.class).getBody();
        assertThat(routes).extracting(r -> r.get("route")).contains("PRELIMINARY_SCIENCE", "PRELIMINARY_TECHNOLOGY", "PROFICIENCY_CERTIFICATE");
        assertThat(routes).filteredOn(r -> "PROFICIENCY_CERTIFICATE".equals(r.get("route"))).singleElement()
                .satisfies(r -> assertThat(r).containsEntry("programmeType", "PROFICIENCY_CERTIFICATE").containsEntry("campus", "Adikpo Campus"));

        Map<String, Object> tech = ok(it.anon(HttpMethod.GET, "/api/v1/public/preliminary/preliminary-technology", null));
        assertThat(tech.get("name")).isEqualTo("Preliminary Technology & Industrial Studies");
        assertThat(((Map) tech.get("rules")).get("requiredSubjects")).isEqualTo(List.of("English Language"));
        List<Map<String, Object>> areas = (List<Map<String, Object>>) tech.get("targets");
        assertThat(areas).extracting(t -> t.get("programmeCode")).containsExactly("C78876", "C67773", "C00096");
        assertThat((List<Map<String, Object>>) areas.get(1).get("specialisations")).extracting(s -> s.get("name"))
                .containsExactly("Accounting Education", "Entrepreneurship Education", "Marketing and Distribution Education", "Office Management");
        assertThat((List<Map<String, Object>>) areas.get(2).get("specialisations")).hasSize(6);

        Map<String, Object> prof = ok(it.anon(HttpMethod.GET, "/api/v1/public/preliminary/proficiency-certificate", null));
        assertThat((List<Map<String, Object>>) prof.get("targets")).hasSize(30).allSatisfy(t -> assertThat(t).containsEntry("kind", "COURSE"));
        assertThat(((Map) prof.get("campus")).get("code")).isEqualTo("ADIKPO");
        assertThat(prof.get("durationMonths")).isEqualTo(9);
        assertThat(it.anon(HttpMethod.GET, "/api/v1/public/preliminary/no-such-programme", null).getStatusCode().value()).isEqualTo(422);
    }

    @Test
    void aPreliminaryTechnologyApplicantChoosesAnAreaAndOptionAndIsReviewedByItsOwnOffice() {
        String tag = tag();
        Map<String, Object> signed = register("preliminary-technology", tag, "F");
        String applicant = String.valueOf(signed.get("token"));
        Map<String, Object> me = ok(it.get(applicant, "/api/v1/applicant/me/preliminary"));
        assertThat(me.get("route")).isEqualTo("PRELIMINARY_TECHNOLOGY");
        assertThat(me.get("preliminary")).isNotNull();
        assertThat(ok(it.get(applicant, "/api/v1/applicant/me")).get("preliminaryProgramme")).isEqualTo(true);
        String ref = String.valueOf(ok(it.call(applicant, HttpMethod.POST, "/api/v1/applicant/me/fee-references", Map.of("kind", "APPLICATION"))).get("reference"));
        assertThat(it.db(() -> jdbc.sql("SELECT amount FROM admissions.fee_reference WHERE reference = :r").param("r", ref).query(java.math.BigDecimal.class).single()))
                .isEqualByComparingTo("5000");
        it.db(() -> jdbc.sql("SELECT admissions.confirm_fee(:r, 'WEBPAY', 'integration test')").param("r", ref).query(String.class).single());

        // an NTC sitting; English and three of Business Education's subjects, and a fifth relevant credit: eligible once the area is chosen
        Map<String, Object> olevel = ok(it.call(applicant, HttpMethod.PUT, "/api/v1/applicant/me/preliminary/olevel", Map.of("sittings", List.of(
                Map.of("sitting", 1, "exam_body", "NABTEB", "exam_type", "NTC", "exam_number", "NTC" + tag, "exam_year", "2024", "subjects", List.of(
                        Map.of("subject", "English Language", "grade", "C6"), Map.of("subject", "Mathematics", "grade", "C5"), Map.of("subject", "Economics", "grade", "C4"),
                        Map.of("subject", "Commerce", "grade", "B3"), Map.of("subject", "Financial Accounting", "grade", "C5")))))));
        assertThat(((Map) ((Map) olevel.get("preliminary")).get("eligibility")).get("status")).isEqualTo("PENDING_REVIEW");
        Map<String, Object> pub = ok(it.anon(HttpMethod.GET, "/api/v1/public/preliminary/PRELIMINARY_TECHNOLOGY", null));
        List<Map<String, Object>> areas = (List<Map<String, Object>>) pub.get("targets");
        String business = String.valueOf(areas.get(1).get("id"));
        String accounting = String.valueOf(((List<Map<String, Object>>) areas.get(1).get("specialisations")).get(0).get("id"));
        String automobile = String.valueOf(((List<Map<String, Object>>) areas.get(2).get("specialisations")).get(0).get("id"));
        assertThat(code(it.call(applicant, HttpMethod.PUT, "/api/v1/applicant/me/preliminary/target", Map.of("targetId", business, "specialisationId", automobile))))
                .isEqualTo("PRELIM_SPECIALISATION_NOT_OFFERED");
        Map<String, Object> chosen = (Map<String, Object>) ok(it.call(applicant, HttpMethod.PUT, "/api/v1/applicant/me/preliminary/target",
                Map.of("targetId", business, "specialisationId", accounting))).get("preliminary");
        assertThat(chosen.get("specialisationName")).isEqualTo("Accounting Education");
        assertThat(chosen.get("targetGroup")).isEqualTo("Business Technology & Entrepreneurship Education");
        assertThat(((Map) chosen.get("eligibility")).get("status")).isEqualTo("ELIGIBLE");
        UUID app = UUID.fromString(String.valueOf(ok(it.get(applicant, "/api/v1/applicant/me")).get("id")));

        // the desk of the route is the Vocational and Technical Office's; each office reads its own routes only
        Map<String, Object> summary = ok(it.get(tech, "/api/v1/admissions/preliminary/summary?route=PRELIMINARY_TECHNOLOGY"));
        assertThat(summary.get("route")).isEqualTo("PRELIMINARY_TECHNOLOGY");
        assertThat(((Map) summary.get("may")).get("recommend")).isEqualTo(true);
        assertThat(it.get(science, "/api/v1/admissions/preliminary/summary?route=PRELIMINARY_TECHNOLOGY").getStatusCode().value()).isEqualTo(403);
        // naming no route, an office of a route opens on its own first route, never Preliminary Science's
        assertThat(ok(it.get(tech, "/api/v1/admissions/preliminary/summary")).get("route")).isEqualTo("PRELIMINARY_TECHNOLOGY");
        assertThat(it.get(tech, "/api/v1/admissions/preliminary/summary?route=PRELIMINARY_SCIENCE").getStatusCode().value()).isEqualTo(403);
        assertThat(it.get(science, "/api/v1/admissions/preliminary/applications/" + app).getStatusCode().value()).isEqualTo(404);
        Map<String, Object> list = ok(it.get(tech, "/api/v1/admissions/preliminary/applications?route=PRELIMINARY_TECHNOLOGY&size=500&q=" + tag));
        assertThat((List<Map<String, Object>>) list.get("rows")).singleElement()
                .satisfies(r -> assertThat(r).containsEntry("specialisation_name", "Accounting Education").containsEntry("target_programme", "C67773"));
        List<Map<String, Object>> mine = (List<Map<String, Object>>) (List) it.getList(tech, "/api/v1/admissions/preliminary/routes").getBody();
        assertThat(mine).extracting(r -> r.get("route")).containsExactlyInAnyOrder("PRELIMINARY_TECHNOLOGY", "PROFICIENCY_CERTIFICATE");
    }

    @Test
    void aProficiencyApplicantIsHisOwnProgrammeTypeAndPaysNoFeeTheBursaryHasNotSet() {
        String tag = tag();
        String applicant = String.valueOf(register("proficiency-certificate", tag, "M").get("token"));
        Map<String, Object> me = ok(it.get(applicant, "/api/v1/applicant/me/preliminary"));
        assertThat(me.get("route")).isEqualTo("PROFICIENCY_CERTIFICATE");
        UUID app = UUID.fromString(String.valueOf(ok(it.get(applicant, "/api/v1/applicant/me")).get("id")));
        assertThat(it.db(() -> jdbc.sql("SELECT c.entry_mode FROM admissions.application a JOIN admissions.candidate c ON c.id = a.candidate_id WHERE a.id = :a")
                .param("a", app).query(String.class).single())).isEqualTo("PROFICIENCY");
        boolean feeSet = it.db(() -> jdbc.sql("SELECT EXISTS (SELECT 1 FROM admissions.route_fee_rule(policy.route_session('PROFICIENCY_CERTIFICATE'), 'PROFICIENCY_CERTIFICATE'))")
                .query(Boolean.class).single());
        if (!feeSet) {
            assertThat(code(it.call(applicant, HttpMethod.POST, "/api/v1/applicant/me/fee-references", Map.of("kind", "APPLICATION")))).isEqualTo("PRELIM_FEE_NOT_CONFIGURED");
        }
        // the form opens once a fee is paid (here confirmed directly); a certificate course is chosen, never a Preliminary Technology area
        it.db(() -> jdbc.sql("UPDATE admissions.application SET fee_confirmed_at = now() WHERE id = :a").param("a", app).update());
        Map<String, Object> pub = ok(it.anon(HttpMethod.GET, "/api/v1/public/preliminary/proficiency-certificate", null));
        String welding = ((List<Map<String, Object>>) pub.get("targets")).stream().filter(t -> "Certificate in Welding and Fabrication".equals(t.get("name")))
                .map(t -> String.valueOf(t.get("id"))).findFirst().orElseThrow();
        String area = String.valueOf(((List<Map<String, Object>>) ok(it.anon(HttpMethod.GET, "/api/v1/public/preliminary/preliminary-technology", null)).get("targets")).get(0).get("id"));
        assertThat(code(it.call(applicant, HttpMethod.PUT, "/api/v1/applicant/me/preliminary/target", Map.of("targetId", area)))).isEqualTo("PRELIM_TARGET_NOT_OFFERED");
        Map<String, Object> chosen = (Map<String, Object>) ok(it.call(applicant, HttpMethod.PUT, "/api/v1/applicant/me/preliminary/target", Map.of("targetId", welding))).get("preliminary");
        assertThat(chosen.get("targetKind")).isEqualTo("COURSE");
        assertThat(chosen.get("targetName")).isEqualTo("Certificate in Welding and Fabrication");
        // an attempted certificate, every grade a fail, is all the course asks
        Map<String, Object> olevel = ok(it.call(applicant, HttpMethod.PUT, "/api/v1/applicant/me/preliminary/olevel", Map.of("sittings", List.of(
                Map.of("sitting", 1, "exam_body", "NECO", "exam_type", "SSCE", "exam_number", "PRF" + tag, "exam_year", "2022", "subjects", List.of(
                        Map.of("subject", "English Language", "grade", "F9"), Map.of("subject", "Mathematics", "grade", "F9")))))));
        assertThat(((Map) ((Map) olevel.get("preliminary")).get("eligibility")).get("status")).isEqualTo("ELIGIBLE");
    }

    /**
     * Pay on Quickteller for both programmes, as for every applicant: the application-fee reference a Preliminary Technology
     * applicant raises, and a proficiency applicant's once the Bursary has stated the fee, are offered Quickteller and sent there
     * with the portal's reference and the amount; Quickteller's question about each is answered with the applicant's name,
     * application number and fee; Interswitch's notification confirms it on Quickteller's channel, once. The University's biller,
     * the notification credentials and the proficiency fee are put back as they were.
     */
    @Test
    void bothProgrammesApplicationFeesArePaidOnQuickteller() {
        String bursar = ItSupport.token("bursar");
        String ict = ItSupport.token("ict");
        org.springframework.web.client.RestClient open = org.springframework.web.client.RestClient.builder().baseUrl("http://localhost:" + port)
                .defaultStatusHandler(s -> true, (q, r) -> { }).build();
        java.util.function.Function<String, String> xml = body -> open.post().uri("/api/v1/payments/paydirect/interswitch").contentType(MediaType.TEXT_XML)
                .body(body).retrieve().body(String.class);
        Map<String, Object> main = ((List<Map<String, Object>>) ok(it.get(bursar, "/api/v1/payments/paydirect")).get("billers")).stream()
                .filter(b -> "MAIN".equals(b.get("scope"))).findFirst().orElseThrow();
        String session = it.db(() -> jdbc.sql("SELECT policy.route_session('PROFICIENCY_CERTIFICATE')").query(String.class).single());
        boolean proficiencyFeeSet = it.db(() -> jdbc.sql("SELECT EXISTS (SELECT 1 FROM admissions.route_fee WHERE session = :s AND route = 'PROFICIENCY_CERTIFICATE')")
                .param("s", session).query(Boolean.class).single());
        try {
            ok(it.call(bursar, HttpMethod.PUT, "/api/v1/payments/paydirect/billers/MAIN", Map.of("code", String.valueOf(main.get("biller_code")),
                    "name", String.valueOf(main.get("name")), "link", "https://quickteller.com/bsum", "active", true, "redirect", true, "withAmount", true)));
            ok(it.call(ict, HttpMethod.PUT, "/api/v1/payments/gateways/paydirect/key",
                    Map.of("secret", "{\"serviceUsername\":\"moaum-it-prelim\",\"servicePassword\":\"an-invented-password\"}")));
            if (!proficiencyFeeSet) {
                ok(it.call(bursar, HttpMethod.PUT, "/api/v1/admissions/preliminary/config/fee?route=PROFICIENCY_CERTIFICATE", Map.of("applicationFee", 3000)));
            }
            for (String slug : List.of("preliminary-technology", "proficiency-certificate")) {
                String tag = tag();
                String applicant = String.valueOf(register(slug, tag, "F").get("token"));
                String reference = String.valueOf(ok(it.call(applicant, HttpMethod.POST, "/api/v1/applicant/me/fee-references", Map.of("kind", "APPLICATION"))).get("reference"));
                Map<String, Object> row = it.db(() -> jdbc.sql("""
                        SELECT f.amount, a.application_no FROM admissions.fee_reference f JOIN admissions.application a ON a.id = f.application_id WHERE f.reference = :r
                        """).param("r", reference).query().singleRow());
                BigDecimal amount = (BigDecimal) row.get("amount");
                if (slug.startsWith("proficiency") && !proficiencyFeeSet) {
                    assertThat(amount).as("the fee the Bursary stated").isEqualByComparingTo("3000");
                }
                String amountInLink = amount.stripTrailingZeros().scale() <= 0 ? amount.toBigInteger().toString() : amount.setScale(2).toPlainString();

                // the pay block offers Quickteller, and the payer is sent there with the portal's own reference and the amount
                assertThat(ok(it.get(applicant, "/api/v1/payments/gateways?reference=" + reference)).get("paydirect")).as(slug).isEqualTo(true);
                assertThat(ok(it.call(applicant, HttpMethod.POST, "/api/v1/payments/checkout", Map.of("reference", reference, "gateway", "paydirect"))).get("url"))
                        .as(slug).isEqualTo("https://quickteller.com/bsum?cid=" + reference + "&amount=" + amountInLink);

                // Quickteller asks after the reference: the applicant, the application number and the fee
                assertThat(xml.apply("<CustomerInformationRequest><ServiceUsername></ServiceUsername><ServicePassword></ServicePassword><MerchantReference>6405</MerchantReference>"
                        + "<CustReference>" + reference + "</CustReference><PaymentItemCode>01</PaymentItemCode><ThirdPartyCode></ThirdPartyCode></CustomerInformationRequest>"))
                        .as(slug).contains("<Status>0</Status>").containsIgnoringCase("<LastName>Tech" + tag + "</LastName>")
                        .contains("(" + row.get("application_no") + ")</FirstName>").contains("<Amount>" + amount.setScale(2).toPlainString() + "</Amount>");

                // Interswitch reports the payment: confirmed on Quickteller's channel, and the application form opens
                String logId = String.valueOf(1_000_000 + new Random().nextInt(8_000_000));
                assertThat(xml.apply(PaymentsIT.notification("moaum-it-prelim", "an-invented-password", reference, logId, amount.toPlainString(), false, false)))
                        .as(slug).contains("<PaymentLogId>" + logId + "</PaymentLogId><Status>0</Status>");
                assertThat(ok(it.get(applicant, "/api/v1/applicant/me")).get("feeConfirmedAt")).as(slug).isNotNull();
                assertThat(it.db(() -> jdbc.sql("SELECT channel FROM admissions.fee_reference WHERE reference = :r").param("r", reference).query(String.class).single()))
                        .as(slug).isEqualTo("Quickteller · WEB");
                // paid: Quickteller is told so if it asks again
                assertThat(xml.apply("<CustomerInformationRequest><CustReference>" + reference + "</CustReference></CustomerInformationRequest>")).as(slug).contains("<Status>1</Status>");
            }
        } finally {
            ResponseEntity<Map> back = it.call(bursar, HttpMethod.PUT, "/api/v1/payments/paydirect/billers/MAIN", Map.of("code", String.valueOf(main.get("biller_code")),
                    "name", String.valueOf(main.get("name")), "link", main.get("pay_link") == null ? "" : String.valueOf(main.get("pay_link")),
                    "active", Boolean.TRUE.equals(main.get("active")), "redirect", Boolean.TRUE.equals(main.get("redirect")),
                    "withAmount", !Boolean.FALSE.equals(main.get("with_amount"))));
            assertThat(back.getStatusCode().value()).as("the biller as it was: " + back.getBody()).isEqualTo(200);
            it.call(ict, HttpMethod.POST, "/api/v1/payments/gateways/paydirect/clear-key", Map.of());
            if (!proficiencyFeeSet) {
                it.db(() -> jdbc.sql("DELETE FROM admissions.route_fee WHERE session = :s AND route = 'PROFICIENCY_CERTIFICATE'").param("s", session).update());
            }
        }
    }
}
