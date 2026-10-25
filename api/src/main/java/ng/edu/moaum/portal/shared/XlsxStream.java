package ng.edu.moaum.portal.shared;

import java.io.IOException;
import java.io.OutputStream;
import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.List;
import java.util.zip.ZipEntry;
import java.util.zip.ZipOutputStream;

/**
 * V650: a workbook written as it is read from the database — each sheet streamed row by row into the zip, so a list of a hundred
 * thousand rows never sits in memory. The University's heading on every sheet (the crest floating over the corner, the name, the
 * title, the line of facts), the header row frozen and filtered, S/N first and numeric, whole numbers and naira as numbers, dates
 * and moments as dates (Lagos time), every other value as text — so a matriculation or JAMB number, a reference or a phone number is
 * never read as a number. Wide sheets print landscape on A4.
 */
public final class XlsxStream implements AutoCloseable {

    /** how a column's values are written */
    public enum Kind { TEXT, INT, MONEY, DATE, DATETIME }

    public record Col(String header, Kind kind, int width) {
        public static Col text(String h, int w) { return new Col(h, Kind.TEXT, w); }
        public static Col num(String h) { return new Col(h, Kind.INT, Math.max(10, h.length() + 2)); }
        public static Col money(String h) { return new Col(h, Kind.MONEY, Math.max(14, h.length() + 2)); }
        public static Col date(String h) { return new Col(h, Kind.DATE, 12); }
        public static Col moment(String h) { return new Col(h, Kind.DATETIME, 17); }
    }

    /** the sheet being written: its rows go straight to the zip */
    public final class Sheet {
        private final List<Col> cols;
        private final int headerRow;   // 1-based
        private int row;
        private long count;

        private Sheet(List<Col> cols, int headerRow) {
            this.cols = cols;
            this.headerRow = headerRow;
            this.row = headerRow;
        }

        /** a data row: S/N first (numbered here), then the values in the columns' order */
        public void row(Object... values) throws IOException {
            row++;
            count++;
            StringBuilder b = new StringBuilder(64 + values.length * 40);
            b.append("<row r=\"").append(row).append("\">");
            b.append("<c r=\"A").append(row).append("\" s=\"6\"><v>").append(count).append("</v></c>");
            for (int i = 0; i < cols.size(); i++) {
                cell(b, col(i + 1) + row, i < values.length ? values[i] : null, cols.get(i).kind());
            }
            b.append("</row>");
            write(b);
        }

        public long count() {
            return count;
        }
    }

    private final ZipOutputStream zip;
    private final byte[] logo;
    private final int logoW;
    private final int logoH;
    private final List<String> names = new ArrayList<>();
    private Sheet open;

    /** a workbook into the stream; the crest (PNG) on every sheet when given */
    public XlsxStream(OutputStream out, byte[] logoPng) {
        this.zip = new ZipOutputStream(out, StandardCharsets.UTF_8);
        this.zip.setLevel(6);
        this.logo = logoPng != null && logoPng.length > 24 && (logoPng[0] & 0xff) == 0x89 ? logoPng : null;
        this.logoW = logo == null ? 0 : readInt(logo, 16);
        this.logoH = logo == null ? 0 : readInt(logo, 20);
    }

    private static int readInt(byte[] b, int at) {
        return ((b[at] & 0xff) << 24) | ((b[at + 1] & 0xff) << 16) | ((b[at + 2] & 0xff) << 8) | (b[at + 3] & 0xff);
    }

    private void write(CharSequence s) throws IOException {
        zip.write(s.toString().getBytes(StandardCharsets.UTF_8));
    }

    /** the sheet's letterhead (three lines) and its header row (S/N, then the columns); its rows follow through the returned Sheet */
    public Sheet sheet(String name, String school, String title, String facts, List<Col> cols) throws IOException {
        finishSheet();
        String safe = name.replaceAll("[\\\\/?*\\[\\]:]", "-");
        safe = safe.length() > 31 ? safe.substring(0, 31) : safe;
        String unique = safe;
        for (int i = 2; names.contains(unique); i++) unique = (safe.length() > 28 ? safe.substring(0, 28) : safe) + " " + i;
        names.add(unique);
        zip.putNextEntry(new ZipEntry("xl/worksheets/sheet" + names.size() + ".xml"));
        int header = 6;
        StringBuilder b = new StringBuilder(4096);
        b.append("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" ")
         .append("xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\">")
         .append("<sheetViews><sheetView workbookViewId=\"0\"><pane ySplit=\"").append(header).append("\" topLeftCell=\"A").append(header + 1)
         .append("\" activePane=\"bottomLeft\" state=\"frozen\"/></sheetView></sheetViews><cols>")
         .append("<col min=\"1\" max=\"1\" width=\"7\" customWidth=\"1\"/>");
        for (int i = 0; i < cols.size(); i++) {
            b.append("<col min=\"").append(i + 2).append("\" max=\"").append(i + 2).append("\" width=\"").append(Math.min(Math.max(cols.get(i).width(), 6), 60))
             .append("\" customWidth=\"1\"/>");
        }
        b.append("</cols><sheetData>");
        b.append("<row r=\"1\" ht=\"22\" customHeight=\"1\">").append(str("B1", school, 3)).append("</row>");
        b.append("<row r=\"2\" ht=\"18\" customHeight=\"1\">").append(str("B2", title, 4)).append("</row>");
        b.append("<row r=\"3\">").append(str("B3", facts, 5)).append("</row>");
        b.append("<row r=\"").append(header).append("\">").append(str("A" + header, "S/N", 1));
        for (int i = 0; i < cols.size(); i++) b.append(str(col(i + 1) + header, cols.get(i).header(), 1));
        b.append("</row>");
        write(b);
        open = new Sheet(cols, header);
        return open;
    }

    private void finishSheet() throws IOException {
        if (open == null) return;
        String last = col(open.cols.size());
        StringBuilder b = new StringBuilder("</sheetData>");
        b.append("<autoFilter ref=\"A").append(open.headerRow).append(':').append(last).append(open.headerRow + Math.max(open.count, 1)).append("\"/>");
        b.append("<pageMargins left=\"0.4\" right=\"0.4\" top=\"0.5\" bottom=\"0.5\" header=\"0.3\" footer=\"0.3\"/>");
        b.append("<pageSetup paperSize=\"9\" orientation=\"").append(open.cols.size() > 7 ? "landscape" : "portrait").append("\"/>");
        if (logo != null) b.append("<drawing r:id=\"rId1\"/>");
        b.append("</worksheet>");
        write(b);
        zip.closeEntry();
        open = null;
    }

    /** the column letters of a 0-based index past S/N (0 is A) */
    static String col(int i) {
        StringBuilder s = new StringBuilder();
        int n = i + 1;
        while (n > 0) {
            int m = (n - 1) % 26;
            s.insert(0, (char) ('A' + m));
            n = (n - 1) / 26;
        }
        return s.toString();
    }

    private static String esc(String s) {
        StringBuilder b = new StringBuilder(s.length() + 8);
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            switch (c) {
                case '&' -> b.append("&amp;");
                case '<' -> b.append("&lt;");
                case '>' -> b.append("&gt;");
                case '"' -> b.append("&quot;");
                default -> {
                    if (c >= 0x20 || c == '\t' || c == '\n' || c == '\r') b.append(c);
                }
            }
        }
        return b.toString();
    }

    private static String str(String ref, String v, int style) {
        return "<c r=\"" + ref + "\" s=\"" + style + "\" t=\"inlineStr\"><is><t xml:space=\"preserve\">" + esc(v == null ? "" : v) + "</t></is></c>";
    }

    private static final LocalDateTime EPOCH = LocalDateTime.of(1899, 12, 30, 0, 0);
    private static final ZoneOffset LAGOS = ZoneOffset.ofHours(1);

    private static void cell(StringBuilder b, String ref, Object v, Kind kind) {
        if (v == null || (v instanceof String s && s.isEmpty())) {
            b.append("<c r=\"").append(ref).append("\" s=\"2\"/>");
            return;
        }
        switch (kind) {
            case INT, MONEY -> {
                if (v instanceof Number n) {
                    b.append("<c r=\"").append(ref).append("\" s=\"").append(kind == Kind.INT ? 6 : 7).append("\"><v>")
                     .append(n instanceof BigDecimal d ? d.toPlainString() : String.valueOf(n)).append("</v></c>");
                    return;
                }
            }
            case DATE, DATETIME -> {
                Double serial = serial(v);
                if (serial != null) {
                    b.append("<c r=\"").append(ref).append("\" s=\"").append(kind == Kind.DATE ? 8 : 9).append("\"><v>")
                     .append(kind == Kind.DATE ? String.valueOf(Math.floor(serial)) : String.format(java.util.Locale.ROOT, "%.6f", serial)).append("</v></c>");
                    return;
                }
            }
            default -> {
                // text below
            }
        }
        b.append(str(ref, String.valueOf(v), 2));
    }

    /** a date or a moment as Excel's serial day, a moment in Lagos time */
    static Double serial(Object v) {
        LocalDateTime t;
        if (v instanceof java.sql.Timestamp ts) t = ts.toInstant().atOffset(LAGOS).toLocalDateTime();
        else if (v instanceof OffsetDateTime o) t = o.withOffsetSameInstant(LAGOS).toLocalDateTime();
        else if (v instanceof Instant i) t = i.atOffset(LAGOS).toLocalDateTime();
        else if (v instanceof java.sql.Date d) t = d.toLocalDate().atStartOfDay();
        else if (v instanceof LocalDate d) t = d.atStartOfDay();
        else if (v instanceof LocalDateTime l) t = l;
        else return null;
        return ChronoUnit.SECONDS.between(EPOCH, t) / 86400.0;
    }

    @Override
    public void close() throws IOException {
        finishSheet();
        int n = names.size();
        if (n == 0) {
            sheet("Report", "", "", "", List.of(Col.text("Nothing to list", 20)));
            finishSheet();
            n = 1;
        }
        StringBuilder ct = new StringBuilder("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\">"
                + "<Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/>");
        if (logo != null) ct.append("<Default Extension=\"png\" ContentType=\"image/png\"/>");
        ct.append("<Override PartName=\"/xl/workbook.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"/>")
          .append("<Override PartName=\"/xl/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml\"/>");
        for (int i = 1; i <= n; i++) {
            ct.append("<Override PartName=\"/xl/worksheets/sheet").append(i).append(".xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>");
            if (logo != null) ct.append("<Override PartName=\"/xl/drawings/drawing").append(i).append(".xml\" ContentType=\"application/vnd.openxmlformats-officedocument.drawing+xml\"/>");
        }
        ct.append("</Types>");
        entry("[Content_Types].xml", ct.toString());
        entry("_rels/.rels", "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
                + "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"xl/workbook.xml\"/></Relationships>");
        StringBuilder wb = new StringBuilder("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><workbook xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" "
                + "xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"><sheets>");
        StringBuilder rels = new StringBuilder("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">");
        for (int i = 1; i <= n; i++) {
            wb.append("<sheet name=\"").append(esc(names.get(i - 1))).append("\" sheetId=\"").append(i).append("\" r:id=\"rId").append(i).append("\"/>");
            rels.append("<Relationship Id=\"rId").append(i).append("\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet").append(i).append(".xml\"/>");
        }
        wb.append("</sheets>");
        // every sheet's filter is a defined name Excel keeps with it
        wb.append("</workbook>");
        rels.append("<Relationship Id=\"rId").append(n + 1).append("\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/></Relationships>");
        entry("xl/workbook.xml", wb.toString());
        entry("xl/_rels/workbook.xml.rels", rels.toString());
        entry("xl/styles.xml", STYLES);
        if (logo != null) {
            zip.putNextEntry(new ZipEntry("xl/media/image1.png"));
            zip.write(logo);
            zip.closeEntry();
            // the crest about four rows tall, its proportions kept (EMU: 9525 a pixel)
            long h = 64L * 9525, w = logoH > 0 ? Math.round(64.0 * logoW / logoH) * 9525L : h;
            for (int i = 1; i <= n; i++) {
                entry("xl/worksheets/_rels/sheet" + i + ".xml.rels", "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
                        + "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/drawing\" Target=\"../drawings/drawing" + i + ".xml\"/></Relationships>");
                entry("xl/drawings/_rels/drawing" + i + ".xml.rels", "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
                        + "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\" Target=\"../media/image1.png\"/></Relationships>");
                entry("xl/drawings/drawing" + i + ".xml", "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><xdr:wsDr xmlns:xdr=\"http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing\" "
                        + "xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\">"
                        + "<xdr:oneCellAnchor><xdr:from><xdr:col>0</xdr:col><xdr:colOff>0</xdr:colOff><xdr:row>0</xdr:row><xdr:rowOff>0</xdr:rowOff></xdr:from>"
                        + "<xdr:ext cx=\"" + w + "\" cy=\"" + h + "\"/><xdr:pic><xdr:nvPicPr><xdr:cNvPr id=\"2\" name=\"Crest\"/><xdr:cNvPicPr><a:picLocks noChangeAspect=\"1\"/></xdr:cNvPicPr></xdr:nvPicPr>"
                        + "<xdr:blipFill><a:blip r:embed=\"rId1\"/><a:stretch><a:fillRect/></a:stretch></xdr:blipFill>"
                        + "<xdr:spPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"" + w + "\" cy=\"" + h + "\"/></a:xfrm><a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom></xdr:spPr>"
                        + "</xdr:pic><xdr:clientData/></xdr:oneCellAnchor></xdr:wsDr>");
            }
        }
        zip.finish();
        zip.flush();
    }

    private void entry(String name, String text) throws IOException {
        zip.putNextEntry(new ZipEntry(name));
        write(text);
        zip.closeEntry();
    }

    // fonts: 0 normal · 1 white bold · 2 navy bold 15 · 3 navy bold 12 · 4 grey 10
    // cellXfs: 0 normal · 1 header · 2 text · 3 school name · 4 title · 5 facts · 6 whole number · 7 naira · 8 date · 9 date and time
    private static final String STYLES = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><styleSheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\">"
            + "<numFmts count=\"4\"><numFmt numFmtId=\"164\" formatCode=\"#,##0\"/><numFmt numFmtId=\"165\" formatCode=\"#,##0.00\"/>"
            + "<numFmt numFmtId=\"166\" formatCode=\"dd/mm/yyyy\"/><numFmt numFmtId=\"167\" formatCode=\"dd/mm/yyyy hh:mm\"/></numFmts>"
            + "<fonts count=\"5\"><font><sz val=\"11\"/><name val=\"Calibri\"/></font><font><b/><sz val=\"11\"/><color rgb=\"FFFFFFFF\"/><name val=\"Calibri\"/></font>"
            + "<font><b/><sz val=\"15\"/><color rgb=\"FF0E3F55\"/><name val=\"Calibri\"/></font><font><b/><sz val=\"12\"/><color rgb=\"FF0E3F55\"/><name val=\"Calibri\"/></font>"
            + "<font><sz val=\"10\"/><color rgb=\"FF6B7B85\"/><name val=\"Calibri\"/></font></fonts>"
            + "<fills count=\"3\"><fill><patternFill patternType=\"none\"/></fill><fill><patternFill patternType=\"gray125\"/></fill>"
            + "<fill><patternFill patternType=\"solid\"><fgColor rgb=\"FF0E3F55\"/><bgColor indexed=\"64\"/></patternFill></fill></fills>"
            + "<borders count=\"2\"><border><left/><right/><top/><bottom/><diagonal/></border><border><left style=\"thin\"><color rgb=\"FFB4C2CC\"/></left>"
            + "<right style=\"thin\"><color rgb=\"FFB4C2CC\"/></right><top style=\"thin\"><color rgb=\"FFB4C2CC\"/></top><bottom style=\"thin\"><color rgb=\"FFB4C2CC\"/></bottom><diagonal/></border></borders>"
            + "<cellStyleXfs count=\"1\"><xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\"/></cellStyleXfs><cellXfs count=\"10\">"
            + "<xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\" xfId=\"0\"/>"
            + "<xf numFmtId=\"0\" fontId=\"1\" fillId=\"2\" borderId=\"1\" xfId=\"0\" applyFont=\"1\" applyFill=\"1\" applyBorder=\"1\" applyAlignment=\"1\"><alignment horizontal=\"center\" vertical=\"center\" wrapText=\"1\"/></xf>"
            + "<xf numFmtId=\"49\" fontId=\"0\" fillId=\"0\" borderId=\"1\" xfId=\"0\" applyNumberFormat=\"1\" applyBorder=\"1\" applyAlignment=\"1\"><alignment vertical=\"center\"/></xf>"
            + "<xf numFmtId=\"0\" fontId=\"2\" fillId=\"0\" borderId=\"0\" xfId=\"0\" applyFont=\"1\"/>"
            + "<xf numFmtId=\"0\" fontId=\"3\" fillId=\"0\" borderId=\"0\" xfId=\"0\" applyFont=\"1\"/>"
            + "<xf numFmtId=\"0\" fontId=\"4\" fillId=\"0\" borderId=\"0\" xfId=\"0\" applyFont=\"1\"/>"
            + "<xf numFmtId=\"164\" fontId=\"0\" fillId=\"0\" borderId=\"1\" xfId=\"0\" applyNumberFormat=\"1\" applyBorder=\"1\"/>"
            + "<xf numFmtId=\"165\" fontId=\"0\" fillId=\"0\" borderId=\"1\" xfId=\"0\" applyNumberFormat=\"1\" applyBorder=\"1\"/>"
            + "<xf numFmtId=\"166\" fontId=\"0\" fillId=\"0\" borderId=\"1\" xfId=\"0\" applyNumberFormat=\"1\" applyBorder=\"1\"/>"
            + "<xf numFmtId=\"167\" fontId=\"0\" fillId=\"0\" borderId=\"1\" xfId=\"0\" applyNumberFormat=\"1\" applyBorder=\"1\"/>"
            + "</cellXfs><cellStyles count=\"1\"><cellStyle name=\"Normal\" xfId=\"0\" builtinId=\"0\"/></cellStyles></styleSheet>";
}
