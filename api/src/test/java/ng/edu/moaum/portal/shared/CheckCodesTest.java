package ng.edu.moaum.portal.shared;

import static org.assertj.core.api.Assertions.assertThat;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.HexFormat;

import org.junit.jupiter.api.Test;

/** V360: the signed check code, and the old one recognised for what came before */
class CheckCodesTest {

    private static String old(String payload) throws Exception {
        return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(payload.getBytes(StandardCharsets.UTF_8))).substring(0, 12).toUpperCase();
    }

    @Test
    void theCodeDependsOnTheKeyAndTheFactsAndIsNotTheOldDigest() throws Exception {
        CheckCodes a = new CheckCodes("", "a-secret-of-at-least-thirty-two-bytes-long");
        CheckCodes b = new CheckCodes("", "another-secret-of-at-least-thirty-two-bytes");
        String code = a.sign(CheckCodes.Kind.EXAM, "MOAUM/MTC/26/0001", "2026/2027", "1");
        assertThat(code).matches("[0-9A-F]{12}");
        assertThat(a.signed(code.toLowerCase(), CheckCodes.Kind.EXAM, "MOAUM/MTC/26/0001", "2026/2027", "1")).isTrue();
        assertThat(a.signed(code, CheckCodes.Kind.EXAM, "MOAUM/MTC/26/0002", "2026/2027", "1")).isFalse();
        assertThat(a.signed(code, CheckCodes.Kind.REG, "MOAUM/MTC/26/0001", "2026/2027", "1")).isFalse();
        assertThat(b.signed(code, CheckCodes.Kind.EXAM, "MOAUM/MTC/26/0001", "2026/2027", "1")).isFalse();
        assertThat(code).isNotEqualTo(old("EXAM|MOAUM/MTC/26/0001|2026/2027|1"));
        // a key of its own, when set, is the key
        assertThat(new CheckCodes("qr-own-secret", "a-secret-of-at-least-thirty-two-bytes-long").sign(CheckCodes.Kind.EXAM, "X", "2026/2027", "1"))
                .isNotEqualTo(a.sign(CheckCodes.Kind.EXAM, "X", "2026/2027", "1"));
        assertThat(a.signed(null, CheckCodes.Kind.EXAM, "X")).isFalse();
    }

    @Test
    void theOldCodesAreRecognisedByTheirOwnFormulas() throws Exception {
        assertThat(CheckCodes.legacy(old("EXAM|M1|2026/2027|1"), CheckCodes.Kind.EXAM, "M1", "2026/2027", "1")).isTrue();
        assertThat(CheckCodes.legacy(old("REG|M1|2026/2027|2"), CheckCodes.Kind.REG, "M1", "2026/2027", "2")).isTrue();
        assertThat(CheckCodes.legacy(old("RESULT|M1|2026/2027|1"), CheckCodes.Kind.RESULT, "M1", "2026/2027", "1")).isTrue();
        assertThat(CheckCodes.legacy(old("REF1|RCT1"), CheckCodes.Kind.RECEIPT, "REF1", "RCT1")).isTrue();
        assertThat(CheckCodes.legacy(old("PG/26/0001|MOAUM-PG-OFFER"), CheckCodes.Kind.PG_OFFER, "PG/26/0001")).isTrue();
        assertThat(CheckCodes.legacy(old("EXAM|M1|2026/2027|1"), CheckCodes.Kind.REG, "M1", "2026/2027", "1")).isFalse();
    }
}
