package ng.edu.moaum.portal.platform;

import java.util.Properties;

import jakarta.mail.internet.MimeMessage;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.mail.javamail.JavaMailSenderImpl;
import org.springframework.mail.javamail.MimeMessageHelper;
import org.springframework.stereotype.Component;

/**
 * Sends a branded email over SMTP with the mail settings the ICT Directorate
 * supplied (V057) — Microsoft 365 by default. The message carries the University
 * crest and name; a plain-text alternative is included for clients that prefer
 * it. A fresh sender is built per send from the stored parameters, so a change
 * on the Mail server screen takes effect without a restart.
 */
@Component
class SmtpMailer {

    private final String portalUrl;

    SmtpMailer(@Value("${moaum.portal-url:https://moaum-portal-production.up.railway.app}") String portalUrl) {
        this.portalUrl = portalUrl == null ? "" : portalUrl.replaceAll("/+$", "");
    }

    void send(MailService.Smtp s, String to, String subject, String body) throws Exception {
        send(s, to, subject, body, java.util.List.of());
    }

    void send(MailService.Smtp s, String to, String subject, String body, java.util.List<NoticeRepository.Attachment> files) throws Exception {
        JavaMailSenderImpl sender = new JavaMailSenderImpl();
        sender.setHost(s.host());
        sender.setPort(s.port());
        sender.setUsername(s.username());
        sender.setPassword(s.password());
        Properties p = sender.getJavaMailProperties();
        p.put("mail.transport.protocol", "smtp");
        p.put("mail.smtp.auth", "true");
        if ("STARTTLS".equalsIgnoreCase(s.encryption())) {
            p.put("mail.smtp.starttls.enable", "true");
            p.put("mail.smtp.starttls.required", "true");
        } else if ("SSL".equalsIgnoreCase(s.encryption())) {
            p.put("mail.smtp.ssl.enable", "true");
        }
        p.put("mail.smtp.connectiontimeout", "15000");
        p.put("mail.smtp.timeout", "20000");
        p.put("mail.smtp.writetimeout", "20000");
        MimeMessage mime = sender.createMimeMessage();
        MimeMessageHelper h = new MimeMessageHelper(mime, true, "UTF-8");   // multipart: text + HTML
        h.setFrom(s.from());
        h.setTo(to);
        h.setSubject(subject);
        h.setText(body, html(subject, body));   // plain first, then the branded HTML
        for (NoticeRepository.Attachment f : files) {
            h.addAttachment(f.filename(), new org.springframework.core.io.ByteArrayResource(f.content()), f.contentType());
        }
        sender.send(mime);   // throws on failure; the dispatcher records it
    }

    /** the branded HTML: the crest, the University name, the subject and the message */
    private String html(String subject, String body) {
        String logo = portalUrl.isEmpty() ? "" :
                "<div style=\"text-align:center;padding:8px 0 4px\"><img src=\"" + portalUrl + "/crest.png\" alt=\"MOAUM\" height=\"56\" style=\"height:56px;width:auto\"></div>";
        return "<div style=\"background:#f4f6f5;padding:24px 12px;margin:0\">"
                + "<div style=\"max-width:560px;margin:0 auto;background:#ffffff;border:1px solid #e6eae8;border-radius:12px;overflow:hidden;font-family:'Segoe UI',system-ui,Arial,sans-serif;color:#1c2a22\">"
                + "<div style=\"padding:18px 24px 0\">" + logo
                + "<div style=\"text-align:center;font-weight:700;font-size:15px;color:#0a4d2c\">Rev. Fr. Moses Orshio Adasu University, Makurdi</div>"
                + "<div style=\"text-align:center;font-size:12px;color:#7a8a80;margin-top:2px\">Unified University Portal</div>"
                + "<div style=\"border-top:3px solid #0a7d3f;margin:14px 0 0\"></div></div>"
                + "<div style=\"padding:18px 24px 8px\">"
                + "<h1 style=\"font-size:17px;margin:0 0 10px;color:#122019\">" + esc(subject) + "</h1>"
                + "<div style=\"white-space:pre-wrap;line-height:1.6;font-size:14.5px;color:#2a3a30\">" + esc(body) + "</div></div>"
                + "<div style=\"padding:12px 24px 20px;color:#8a9a90;font-size:12px;border-top:1px solid #eef2f0;margin-top:12px\">"
                + "An automated message from the MOAUM Unified University Portal. Please do not reply to this email.</div>"
                + "</div></div>";
    }

    private static String esc(String s) {
        return s == null ? "" : s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;");
    }
}
