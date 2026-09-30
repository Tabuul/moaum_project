package ng.edu.moaum.portal.payments;

import java.io.ByteArrayInputStream;
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;

import javax.xml.XMLConstants;
import javax.xml.parsers.DocumentBuilder;
import javax.xml.parsers.DocumentBuilderFactory;

import org.w3c.dom.Document;
import org.w3c.dom.Element;
import org.w3c.dom.Node;
import org.w3c.dom.NodeList;

/**
 * The two messages Interswitch exchanges with a PayDirect biller, read and
 * written: Quickteller's question about a reference (CustomerInformationRequest,
 * answered with CustomerInformationResponse) and its report of a payment
 * (PaymentNotificationRequest, answered with PaymentNotificationResponse).
 *
 * <p>They arrive as XML. They are read by element name without regard to case,
 * namespace or order, so a field Interswitch adds or re-orders does not break
 * the reading; a document type declaration is refused outright (no entity is
 * ever expanded). A request sent as JSON with the same names is read the same
 * way and answered as JSON. Nothing here decides anything: it only reads and
 * writes the envelope.
 */
final class PayDirectMessages {

    private PayDirectMessages() {
    }

    /** a request as read: the fields of its root (credentials, the reference asked about) and, for a notification, each payment */
    record Message(boolean json, Map<String, String> fields, List<Map<String, String>> payments) {
        String field(String name) {
            String v = fields.get(name);
            return v == null ? "" : v.trim();
        }
    }

    /** what the portal answers, and in which form */
    record Answer(boolean json, String body) {
    }

    static String get(Map<String, String> m, String name) {
        String v = m.get(name);
        return v == null ? "" : v.trim();
    }

    /* ── reading ── */

    static Message read(String body) {
        String b = body == null ? "" : body.strip();
        if (b.startsWith("﻿")) {
            b = b.substring(1);
        }
        if (b.isEmpty()) {
            throw new IllegalArgumentException("the request is empty");
        }
        return b.startsWith("{") ? readJson(b) : readXml(b);
    }

    private static Map<String, String> ci() {
        return new TreeMap<>(String.CASE_INSENSITIVE_ORDER);
    }

    private static String localName(Node n) {
        String name = n.getLocalName() != null ? n.getLocalName() : n.getNodeName();
        int colon = name.indexOf(':');
        return colon >= 0 ? name.substring(colon + 1) : name;
    }

    private static List<Element> children(Element e) {
        List<Element> out = new ArrayList<>();
        NodeList nl = e.getChildNodes();
        for (int i = 0; i < nl.getLength(); i++) {
            if (nl.item(i) instanceof Element c) {
                out.add(c);
            }
        }
        return out;
    }

    /** the leaf elements directly under e, by name; the first of a name wins */
    private static Map<String, String> leaves(Element e) {
        Map<String, String> m = ci();
        for (Element c : children(e)) {
            if (children(c).isEmpty()) {
                m.putIfAbsent(localName(c), c.getTextContent() == null ? "" : c.getTextContent().trim());
            }
        }
        return m;
    }

    private static void payments(Element e, List<Map<String, String>> out) {
        for (Element c : children(e)) {
            if ("Payment".equalsIgnoreCase(localName(c)) && !children(c).isEmpty()) {
                out.add(leaves(c));
            } else {
                payments(c, out);
            }
        }
    }

    private static Message readXml(String b) {
        try {
            DocumentBuilderFactory f = DocumentBuilderFactory.newInstance();
            f.setNamespaceAware(true);
            f.setFeature(XMLConstants.FEATURE_SECURE_PROCESSING, true);
            f.setFeature("http://apache.org/xml/features/disallow-doctype-decl", true);
            f.setFeature("http://xml.org/sax/features/external-general-entities", false);
            f.setFeature("http://xml.org/sax/features/external-parameter-entities", false);
            f.setFeature("http://apache.org/xml/features/nonvalidating/load-external-dtd", false);
            f.setXIncludeAware(false);
            f.setExpandEntityReferences(false);
            DocumentBuilder db = f.newDocumentBuilder();
            // a malformed message is refused by the exception it raises, not printed to the log's standard error
            db.setErrorHandler(new org.xml.sax.helpers.DefaultHandler());
            Document doc = db.parse(new ByteArrayInputStream(b.getBytes(StandardCharsets.UTF_8)));
            Element root = doc.getDocumentElement();
            // a SOAP envelope, should one come, is looked through to the message in its body
            if ("Envelope".equalsIgnoreCase(localName(root))) {
                for (Element c : children(root)) {
                    if ("Body".equalsIgnoreCase(localName(c)) && !children(c).isEmpty()) {
                        root = children(c).get(0);
                    }
                }
            }
            List<Map<String, String>> pays = new ArrayList<>();
            payments(root, pays);
            return new Message(false, leaves(root), pays);
        } catch (Exception e) {
            throw new IllegalArgumentException("the request is not the XML it should be: " + e.getMessage(), e);
        }
    }

    private static final tools.jackson.databind.ObjectMapper JSON = new tools.jackson.databind.ObjectMapper();

    private static Map<String, String> scalars(Map<?, ?> m) {
        Map<String, String> out = ci();
        m.forEach((k, v) -> {
            if (k != null && v != null && !(v instanceof Map) && !(v instanceof List)) {
                out.putIfAbsent(String.valueOf(k), String.valueOf(v).trim());
            }
        });
        return out;
    }

    private static Object pick(Map<?, ?> m, String name) {
        for (Map.Entry<?, ?> e : m.entrySet()) {
            if (name.equalsIgnoreCase(String.valueOf(e.getKey()))) {
                return e.getValue();
            }
        }
        return null;
    }

    private static Message readJson(String b) {
        Map<String, Object> root;
        try {
            root = JSON.readValue(b, new tools.jackson.core.type.TypeReference<Map<String, Object>>() { });
        } catch (RuntimeException e) {
            throw new IllegalArgumentException("the request is not the JSON it should be: " + e.getMessage(), e);
        }
        Map<?, ?> r = root;
        // {"CustomerInformationRequest": {...}} is read as its contents
        if (r.size() == 1 && r.values().iterator().next() instanceof Map<?, ?> inner) {
            r = inner;
        }
        List<Map<String, String>> pays = new ArrayList<>();
        Object p = pick(r, "Payments");
        if (p instanceof Map<?, ?> pm) {
            p = pick(pm, "Payment");
        }
        if (p instanceof List<?> list) {
            for (Object o : list) {
                if (o instanceof Map<?, ?> om) {
                    pays.add(scalars(om));
                }
            }
        } else if (p instanceof Map<?, ?> one) {
            pays.add(scalars(one));
        } else if (pick(r, "PaymentLogId") != null) {
            pays.add(scalars(r));
        }
        return new Message(true, scalars(r), pays);
    }

    /* ── writing ── */

    static String xml(String s) {
        if (s == null) {
            return "";
        }
        StringBuilder out = new StringBuilder(s.length());
        for (char ch : s.toCharArray()) {
            switch (ch) {
                case '&' -> out.append("&amp;");
                case '<' -> out.append("&lt;");
                case '>' -> out.append("&gt;");
                case '"' -> out.append("&quot;");
                case '\'' -> out.append("&apos;");
                default -> {
                    // characters XML 1.0 cannot carry are left out
                    if (ch == '\t' || ch == '\n' || ch == '\r' || ch >= 0x20) {
                        out.append(ch);
                    }
                }
            }
        }
        return out.toString();
    }

    /** an amount as PayDirect writes one: naira with two places */
    static String amount(BigDecimal a) {
        return a == null ? "0.00" : a.setScale(2, RoundingMode.HALF_UP).toPlainString();
    }

    /** a payment's amount as written in the message; null when there is none or it is not a number */
    static BigDecimal parseAmount(String s) {
        String t = s == null ? "" : s.replace(",", "").replace("₦", "").replace("NGN", "").trim();
        if (t.isEmpty()) {
            return null;
        }
        try {
            return new BigDecimal(t);
        } catch (NumberFormatException e) {
            return null;
        }
    }

    static boolean yes(String s) {
        String t = s == null ? "" : s.trim();
        return t.equalsIgnoreCase("true") || t.equals("1") || t.equalsIgnoreCase("yes");
    }

    /**
     * The answer to Quickteller's question about a reference: Status 0 and the
     * payer's name and the amount owed for a reference that may be paid, Status 1
     * for one that may not (unknown, paid, expired, or not payable now).
     */
    static String customerAnswer(boolean json, String merchantReference, String thirdPartyCode, String reference, boolean valid,
                                 String firstName, String lastName, String alternate, BigDecimal amount) {
        if (json) {
            Map<String, Object> customer = new LinkedHashMap<>();
            customer.put("Status", valid ? 0 : 1);
            customer.put("CustReference", reference == null ? "" : reference);
            customer.put("CustomerReferenceAlternate", valid && alternate != null ? alternate : "");
            customer.put("FirstName", valid && firstName != null ? firstName : "");
            customer.put("LastName", valid && lastName != null ? lastName : "");
            customer.put("Email", "");
            customer.put("Phone", "");
            customer.put("ThirdPartyCode", thirdPartyCode == null ? "" : thirdPartyCode);
            customer.put("Amount", valid ? amount(amount) : "0.00");
            Map<String, Object> out = new LinkedHashMap<>();
            out.put("MerchantReference", merchantReference == null ? "" : merchantReference);
            out.put("Customers", List.of(customer));
            return JSON.writeValueAsString(out);
        }
        return "<?xml version=\"1.0\" encoding=\"utf-8\"?>"
                + "<CustomerInformationResponse>"
                + "<MerchantReference>" + xml(merchantReference) + "</MerchantReference>"
                + "<Customers><Customer>"
                + "<Status>" + (valid ? 0 : 1) + "</Status>"
                + "<CustReference>" + xml(reference) + "</CustReference>"
                + "<CustomerReferenceAlternate>" + (valid ? xml(alternate) : "") + "</CustomerReferenceAlternate>"
                + "<FirstName>" + (valid ? xml(firstName) : "") + "</FirstName>"
                + "<LastName>" + (valid ? xml(lastName) : "") + "</LastName>"
                + "<Email></Email><Phone></Phone>"
                + "<ThirdPartyCode>" + xml(thirdPartyCode) + "</ThirdPartyCode>"
                + "<Amount>" + (valid ? amount(amount) : "0.00") + "</Amount>"
                + "</Customer></Customers>"
                + "</CustomerInformationResponse>";
    }

    /** the answer to a payment notification: for each payment, 0 received and kept, 1 not accepted (Interswitch sends it again) */
    static String notificationAnswer(boolean json, List<String[]> results) {
        if (json) {
            List<Map<String, Object>> pays = new ArrayList<>();
            for (String[] r : results) {
                Map<String, Object> p = new LinkedHashMap<>();
                p.put("PaymentLogId", r[0] == null ? "" : r[0]);
                p.put("Status", Integer.parseInt(r[1]));
                pays.add(p);
            }
            return JSON.writeValueAsString(Map.of("Payments", pays));
        }
        StringBuilder out = new StringBuilder("<?xml version=\"1.0\" encoding=\"utf-8\"?><PaymentNotificationResponse><Payments>");
        for (String[] r : results) {
            out.append("<Payment><PaymentLogId>").append(xml(r[0])).append("</PaymentLogId><Status>").append(r[1]).append("</Status></Payment>");
        }
        return out.append("</Payments></PaymentNotificationResponse>").toString();
    }
}
