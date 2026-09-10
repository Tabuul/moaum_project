package ng.edu.moaum.portal.platform;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;

import org.springframework.stereotype.Component;

/**
 * Sends one SMS through eBulkSMS with the account the ICT Directorate supplied
 * (V065). A fresh request is built per send from the stored credentials, so a
 * change on the SMS settings screen takes effect without a restart. Nigerian
 * numbers are normalised to the 234XXXXXXXXXX form eBulkSMS expects.
 */
@Component
class EbulkSmsSender {

    private static final String ENDPOINT = "https://api.ebulksms.com/sendsms.json";
    private final HttpClient http = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(10)).build();

    /** send the message to one recipient; returns eBulkSMS's own words (its response body) for the log */
    String send(SmsService.Creds c, String recipient, String message) throws Exception {
        String gsm = normalise(recipient);
        if (gsm.isEmpty()) {
            throw new IllegalArgumentException("no usable phone number");
        }
        String body = "{\"SMS\":{\"auth\":{\"username\":" + quote(c.username()) + ",\"apikey\":" + quote(c.apiKey()) + "},"
                + "\"message\":{\"sender\":" + quote(c.sender()) + ",\"messagetext\":" + quote(message) + ",\"flash\":\"0\"},"
                + "\"recipients\":{\"gsm\":[{\"msidn\":" + quote(gsm) + ",\"msgid\":" + quote(java.util.UUID.randomUUID().toString()) + "}]}}}";
        HttpRequest req = HttpRequest.newBuilder(URI.create(ENDPOINT))
                .timeout(Duration.ofSeconds(20))
                .header("Content-Type", "application/json")
                .header("Accept", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(body))
                .build();
        HttpResponse<String> r = http.send(req, HttpResponse.BodyHandlers.ofString());
        String text = r.body() == null ? "" : r.body().trim();
        if (r.statusCode() / 100 != 2) {
            throw new IllegalStateException("eBulkSMS HTTP " + r.statusCode() + ": " + left(text, 200));
        }
        // eBulkSMS returns {"response":{"status":"SUCCESS",...}} on success
        if (!text.toUpperCase().contains("SUCCESS")) {
            throw new IllegalStateException("eBulkSMS did not accept the message: " + left(text, 200));
        }
        return "ebulksms " + left(text, 120);
    }

    /** a Nigerian number in the 234XXXXXXXXXX form eBulkSMS expects; empty if it cannot be read */
    static String normalise(String raw) {
        if (raw == null) {
            return "";
        }
        String d = raw.replaceAll("\\D", "");
        if (d.startsWith("234") && d.length() == 13) {
            return d;
        }
        if (d.startsWith("0") && d.length() == 11) {
            return "234" + d.substring(1);
        }
        if (d.length() == 10) {
            return "234" + d;
        }
        return d.startsWith("234") ? d : "";
    }

    private static String left(String s, int n) {
        return s == null ? "" : (s.length() <= n ? s : s.substring(0, n));
    }

    private static String quote(String s) {
        StringBuilder b = new StringBuilder("\"");
        for (int i = 0; i < (s == null ? "" : s).length(); i++) {
            char ch = s.charAt(i);
            switch (ch) {
                case '"' -> b.append("\\\"");
                case '\\' -> b.append("\\\\");
                case '\n' -> b.append("\\n");
                case '\r' -> b.append("\\r");
                case '\t' -> b.append("\\t");
                default -> b.append(ch);
            }
        }
        return b.append('"').toString();
    }
}
