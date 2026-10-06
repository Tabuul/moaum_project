package ng.edu.moaum.portal.jupeb;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * Public verification of a JUPEB paper (V343): the code its QR carries opens the University's record. Unauthenticated (the
 * /api/v1/verify/** rule): a code is 60 random bits, so codes cannot be guessed to harvest records, and the answer holds only
 * what the paper itself printed — whether the record still says it (current), has changed since (superseded) or never did
 * (not genuine, or revoked by the JUPEB Office).
 */
@RestController
@RequestMapping("/api/v1/verify/jupeb")
class JupebVerifyController {

    private final JdbcClient jdbc;
    private final tools.jackson.databind.ObjectMapper json;

    JupebVerifyController(JdbcClient jdbc, tools.jackson.databind.ObjectMapper json) {
        this.jdbc = jdbc;
        this.json = json;
    }

    @GetMapping("/{code}")
    @Transactional(readOnly = true)
    Object verify(@PathVariable String code) {
        String r = jdbc.sql("SELECT jupeb.verify_paper(:c)::text").param("c", code == null ? "" : code).query(String.class).single();
        return json.readValue(r, Object.class);
    }
}
