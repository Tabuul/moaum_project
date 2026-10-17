package ng.edu.moaum.portal.platform;

import java.util.Locale;
import java.util.regex.Pattern;

/**
 * V532: what an SMTP failure means, from the exception and the server's answer — Microsoft 365's above all. A failure of the
 * account or the server (the host cannot be reached, the sign-in is refused, the mailbox may not send as the From address,
 * Microsoft has blocked or throttled it) is the same for every message: the dispatcher stops sending e-mail for the rest of
 * the batch and does not count it against the messages. A refused recipient is the message's own.
 */
final class SmtpFailure {

    enum Kind { HOST_UNKNOWN, UNREACHABLE, TLS, BASIC_AUTH_OFF, SIGN_IN, SEND_AS, BLOCKED, LIMIT, SUBMISSION, RECIPIENT, OTHER }

    private static final Pattern SIGN_IN = Pattern.compile("\\b535\\b|5\\.7\\.139|5\\.7\\.3\\b|5\\.7\\.57|authentication unsuccessful|authenticationfailed|mailauthenticationexception");
    private static final Pattern LIMIT = Pattern.compile("submissionquotaexceeded|\\b4\\.4\\.2\\b|\\b4\\.3\\.2\\b|rate limit|throttl|sending limit|message submission rate");
    private static final Pattern RECIPIENT = Pattern.compile("\\b5\\.1\\.(1|3|10)\\b|invalid addresses|recipient address rejected|user unknown|mailbox unavailable");

    private SmtpFailure() {
    }

    /** the exception's whole story, lower case: every message and class name along the cause chain */
    private static String story(Throwable e) {
        StringBuilder b = new StringBuilder();
        for (Throwable c = e; c != null; c = c.getCause() == c ? null : c.getCause()) {
            b.append(c.getClass().getName()).append(": ").append(c.getMessage()).append(" | ");
            if (c instanceof jakarta.mail.MessagingException m && m.getNextException() != null && m.getNextException() != c.getCause()) {
                b.append(m.getNextException().getClass().getName()).append(": ").append(m.getNextException().getMessage()).append(" | ");
            }
            if (c instanceof org.springframework.mail.MailSendException s) {
                for (Exception x : s.getMessageExceptions()) {
                    b.append(x.getClass().getName()).append(": ").append(x.getMessage()).append(" | ");
                }
            }
        }
        return b.toString().toLowerCase(Locale.ROOT);
    }

    static Kind of(Throwable e) {
        String s = story(e);
        if (s.contains("unknownhostexception")) return Kind.HOST_UNKNOWN;
        if (s.contains("5.7.30") || s.contains("basic authentication is not supported")) return Kind.BASIC_AUTH_OFF;
        if (s.contains("sendasdenied") || s.contains("5.2.252") || s.contains("5.7.60")) return Kind.SEND_AS;
        if (s.contains("outboundspam") || s.contains("wascl") || s.contains("5.1.8")) return Kind.BLOCKED;
        if (LIMIT.matcher(s).find()) return Kind.LIMIT;
        if (s.contains("mailconnectexception") || s.contains("connectexception") || s.contains("sockettimeoutexception")
                || s.contains("noroutetohostexception") || s.contains("couldn't connect to host")) return Kind.UNREACHABLE;
        if (SIGN_IN.matcher(s).find()) return Kind.SIGN_IN;
        if (s.contains("storedrv")) return Kind.SUBMISSION;
        if (s.contains("sslexception") || s.contains("sslhandshake") || s.contains("starttls")) return Kind.TLS;
        if (RECIPIENT.matcher(s).find()) return Kind.RECIPIENT;
        return Kind.OTHER;
    }

    /** the account's or the server's failure, the same for every message — not one message's */
    static boolean systemic(Kind k) {
        return k != Kind.RECIPIENT && k != Kind.OTHER;
    }

    /** what it means, in words for the Directorate of ICT */
    static String words(Kind k, String host, int port, String from) {
        return switch (k) {
            case HOST_UNKNOWN -> "The server name " + host + " does not exist. Microsoft 365 is smtp.office365.com.";
            case UNREACHABLE -> "Could not reach " + host + " on port " + port + ". Check the server and port: Microsoft 365 is smtp.office365.com, port 587, STARTTLS.";
            case TLS -> "The secure connection to " + host + " failed. Microsoft 365 is STARTTLS on port 587.";
            case BASIC_AUTH_OFF -> "Microsoft 365 refused password sign-in for this mailbox (basic authentication is switched off). The Microsoft 365 administrator turns it on for the mailbox.";
            case SIGN_IN -> "The server refused the sign-in: the username or password is wrong, or Authenticated SMTP is turned off for this mailbox in Microsoft 365.";
            case SEND_AS -> "Signed in, but this mailbox may not send as " + from + ". Leave the From address empty to send as the mailbox, or have the Microsoft 365 administrator grant it Send As.";
            case BLOCKED -> "Microsoft has blocked this mailbox from sending. The Microsoft 365 administrator releases it under Restricted entities in the Microsoft Defender portal.";
            case LIMIT -> "The mailbox has reached the provider's sending limit. Sending waits and goes on later; lower the pace on the Notices screen if it recurs.";
            case SUBMISSION -> "The server accepted the sign-in but refused to take the message for sending. The error below says why.";
            case RECIPIENT -> "The recipient's address was refused. Other messages are not affected.";
            case OTHER -> "The server refused. The error below says why.";
        };
    }

    /** the stage a connection test reached when it failed */
    static String stage(Kind k) {
        return switch (k) {
            case HOST_UNKNOWN, UNREACHABLE, TLS -> "CONNECTION";
            case BASIC_AUTH_OFF, SIGN_IN -> "SIGN_IN";
            default -> "SEND";
        };
    }

    /** the error as the screen shows it: the server's own words, trimmed */
    static String detail(Throwable e) {
        Throwable root = e;
        StringBuilder b = new StringBuilder(e.getClass().getSimpleName()).append(": ").append(String.valueOf(e.getMessage()));
        if (e instanceof org.springframework.mail.MailSendException s) {
            for (Exception x : s.getMessageExceptions()) {
                b.append(" | ").append(x.getMessage());
            }
        }
        while (root.getCause() != null && root.getCause() != root) {
            root = root.getCause();
        }
        if (root != e && !b.toString().contains(String.valueOf(root.getMessage()))) {
            b.append(" | ").append(root.getClass().getSimpleName()).append(": ").append(root.getMessage());
        }
        String t = b.toString().replaceAll("\\s+", " ").trim();
        return t.length() > 400 ? t.substring(0, 400) : t;
    }
}
