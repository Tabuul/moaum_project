package ng.edu.moaum.portal.shared;

import java.awt.Color;
import java.awt.Graphics2D;
import java.awt.RenderingHints;
import java.awt.image.BufferedImage;
import java.awt.image.DataBufferInt;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Iterator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.Semaphore;
import java.util.concurrent.TimeUnit;
import java.util.function.DoubleUnaryOperator;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import javax.imageio.IIOImage;
import javax.imageio.ImageIO;
import javax.imageio.ImageReadParam;
import javax.imageio.ImageReader;
import javax.imageio.ImageWriteParam;
import javax.imageio.ImageWriter;
import javax.imageio.stream.ImageInputStream;
import javax.imageio.stream.ImageOutputStream;
import javax.imageio.stream.MemoryCacheImageInputStream;
import javax.imageio.stream.MemoryCacheImageOutputStream;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

/**
 * V749: a member of staff's photograph made fit for the identity card on the server — the University's brief of 12 November 2026
 * ("UPDATE STAFF IDENTITY INFORMATION"): the photograph assessed, then enhanced for brightness, contrast and exposure, white
 * balance, mild noise, sharpness and orientation, and cut to the card's portrait frame, never altering the face; no AI. The rule
 * throughout: an identity photograph must come out looking like the person — when in doubt, less is done.
 *
 * <p>Read safely first: a JPEG or a PNG by its first bytes only, no larger than {@code moaum.photo.max-bytes}, its width and height
 * read from the header and refused past {@code moaum.photo.max-pixels} before a single pixel is decoded, a CMYK (print) JPEG refused
 * in words; each a {@link Refused}, and nothing is kept of it. A JPEG's frame header is read by hand the way the reader finds it
 * (libjpeg's next_marker: stray bytes, fill bytes and a stuffed FF 00 between the segments skipped), and a JPEG is refused as damaged
 * before a reader is made when no single frame header is found, and before a pixel is read when the reader's size is not that frame's
 * — so no stray bytes can hide the frame from this reading and show it to the reader's; one with no end-of-image marker after its
 * image data is refused as truncated before it is decoded (the reader would decode it all and only then warn). A large photograph is decoded at a fraction of
 * its size (it is cut to 600×750 in the end), which bounds the decoded raster; it does not bound a progressive JPEG, nor a sequential
 * one whose first scan codes fewer colours than the frame has (its colours stored in separate scans), whose reader holds the
 * coefficients of the whole image at full size whatever the fraction (about 230 MB of native memory for 40,000,000 pixels at 4:4:4),
 * so such a JPEG is refused past {@link #MULTI_SCAN_MAX_PIXELS} (13,000,000 pixels: a phone's 12-megapixel photograph passes) on that
 * hand-read header. The JDK's reader passes on only the first warning of each pass, so a JPEG's header is put right before the reader
 * is given it wherever the reader would only warn and lose nothing ({@link #normalise}: stray bytes between the header's segments
 * dropped, a JFIF revision other than 1 made 1.02, a sequential scan's Ss/Se/Ah/Al made 0/63/0/0) — the record names each kind of
 * thing put right once, in the reader's words with how many more there were, and the first warning the reader gives is about the
 * image data; a header of more than {@link #HEADER_ODDITIES_MAX} groups of stray bytes or JFIF segments, which no encoder writes, is
 * refused as damaged before a reader is made, and the record keeps no more than {@link #WARNINGS_MAX} warnings in all. The reader's
 * warnings are heard from the header on: one that means image data lost or garbled — a truncated file (no end-of-image marker), the
 * premature end of the file or of a data segment, a bad Huffman code, stray bytes before any marker but the end of the image (before a
 * restart marker, between a progressive JPEG's scans), a marker found instead of a restart marker, an inconsistent progression, stray
 * bytes before the end that are not zero padding, an unknown Adobe colour transform — or one the header put right would not give (it
 * would hide what follows) refuses the photograph as damaged, in the header before a pixel is decoded where it can; an embedded colour
 * profile that is invalid and ignored, and zero bytes padding the end, are kept in the record and the photograph read. At most two
 * photographs are decoded at once, the card's PNG turned into a JPEG ({@link #toJpeg}) included — which waits no more than
 * {@link #TOJPEG_SLOT_WAIT_MILLIS} for a slot, its callers holding a database connection.
 *
 * <p>Assessed (every number in the result): the size, the orientation its EXIF tag gave (read by hand from the JPEG's APP1, and put
 * upright), the brightness of the whole and of the centre (the middle of the frame, inside a portrait's face at any usual framing,
 * so the backdrop is never read as the face's brightness), the spread of the brightness, the highlights (the brightest channel's
 * 99.9th percentile: the eye whites and the brightest of the skin count), the share of clipped shadows and highlights in the whole and
 * of clipped highlights in the centre, the sharpness (the variance of a Laplacian on a grey copy no larger than 512 pixels), the noise
 * (Immerkær's estimate), the aspect, and the background (the top band and the sides above the shoulders — the head left out where it
 * reaches the top band in a tight framing: how even, how bright, how tinted — advisory). The face is not assessed: the server has no
 * face detector, and the result says so rather than claim it. Flags: TOO_DARK (under-exposed, from the whole frame's histogram — which
 * cannot tell an under-exposed frame from a correctly exposed dark face on a dark wall in dark clothes when the eye whites are too
 * small to count, so it asks for a retake in better light and the photograph is lifted only a little), TOO_BRIGHT (the centre washed
 * out: bright, or with its highlights clipped — never the backdrop, so a white backdrop is not too bright), LOW_CONTRAST, BLURRY,
 * LOW_RESOLUTION, LANDSCAPE, BUSY_BACKGROUND (the head traced up into the top band and left out, never what touches it), COLOUR_CAST
 * (advisory, {@link #colourCast}: the background tinted well past a painted wall's own paint ({@link #CAST_WALL_WARM},
 * {@link #CAST_WALL_COOL}), or tinted less and the face or what is off the wall — a white shirt, a collar, the clothes at the chest
 * even where they take the wall's colour under its lamp — tinted alike; never a cream, peach, light-yellow or mid-blue wall's paint
 * alone; never corrected beyond the mild white balance below; the holder is told the background or the light is tinted, a white or
 * light grey wall in daylight best). The verdict: REPLACE when the frame would be smaller than
 * {@code moaum.photo.min-width}×{@code min-height} or the photograph is far from sharp; FAIR when any flag stands; GOOD otherwise.
 *
 * <p>Enhanced by global operations only — the whole photograph adjusted alike, nothing drawn, removed or retouched, and the face's
 * colour and brightness never taken from the backdrop or the clothes: upright by the EXIF tag; cut to the card's 4:5 portrait frame,
 * centred across and nearer the top (a geometric cut: there is no face detection); resized by halving with area averages, then
 * bicubic; a mild 3×3 noise reduction only when the noise is high; a mild white balance (each gain held to [0.95, 1.05]) read from
 * the near-neutral pixels outside the face box only, and only where the wall and what is not the wall (a white or grey shirt, a
 * collar, grey hair) agree on the cast, each gain the smaller of theirs — a pale-blue, beige or cream wall alone never moves the face,
 * nor a cream shirt alone, and a strong cast (no near-neutral pixel left) is flagged, not corrected; levels only where the photograph
 * lacks them — the black point only when it is flat (low in contrast, its darkest tones well above black and its highlights short
 * of white), moved down by no more than {@link #BLACK_MOVE_LIMIT} levels, the white point when it is flat or under-exposed, the stretch
 * no more than 1.8 times; a bounded gamma toward mid-grey when the whole frame is under-exposed (nothing in it, not even the eye
 * whites, reaching {@link #UNDER_HIGHLIGHT}, and its mean low — judged from the histogram, never from the face), the levels and the
 * gamma together raising no pixel's brightness more than {@link #UNDER_GAIN_MAX} times (a tenth: a correctly exposed dark face read
 * as under-exposed moves by no more than 8 levels at a forehead of 80); a bounded gamma down when the centre's highlights are
 * clipped; levels and gammas applied to the brightness only, red, green
 * and blue scaled alike, so every colour keeps its proportions (skin is never made more saturated or changes hue); an unsharp mask
 * (radius 1, amount 0.5, threshold 3); written as a JPEG at {@code moaum.photo.quality}. The record of what was done gives every step
 * with its numbers. (The brief's grey world over every pixel, gains to [0.85, 1.18], and the exposure read at the face box were set
 * aside on the V749 review: they turned brown skin olive on a red backdrop, a white backdrop cyan or cream with a dark suit, and
 * lightened correctly exposed dark skin by 30 to 45 levels; its second round set aside levels on a high-key frame, which darkened a
 * medium face on a white wall by 27 levels and saturated it, and the white balance read from a pale wall alone; its third round the
 * under-exposed lift of up to 2.5 times, which lightened a correctly exposed dark face on a dark wall by 48 to 97 levels.)
 *
 * <p>Pure: bytes in, bytes and numbers out; nothing is read from or written to the database here.
 */
@Component
public class PhotoEnhancer {

    /** what the result says of the face — never a claim the server cannot make */
    public static final String FACE = "not assessed (no face detector on the server)";

    /** the flags an assessment may raise. COLOUR_CAST is advisory, in words: "The background or the light is tinted — a white or light
     *  grey wall in daylight is best" */
    public static final List<String> FLAGS = List.of("TOO_DARK", "TOO_BRIGHT", "LOW_CONTRAST", "BLURRY", "LOW_RESOLUTION", "LANDSCAPE",
            "BUSY_BACKGROUND", "COLOUR_CAST");

    // the readings' thresholds (luma 0–255; sharpness on the ≤512-pixel grey copy; noise as Immerkær's sigma on the 600×750 frame)
    /** TOO_BRIGHT: the centre's brightness above this, or more than {@link #CLIPPED_BRIGHT_PCT} per cent of its pixels with a channel
     *  clipped (at 250 or above); TOO_DARK also when more than {@link #CLIPPED_DARK_PCT} per cent of the frame is at 5 or below */
    static final double BRIGHT_CENTRE = 215, CLIPPED_DARK_PCT = 25, CLIPPED_BRIGHT_PCT = 10, LOW_SPREAD = 32;
    static final double BLURRY_BELOW = 30, REPLACE_SHARPNESS_BELOW = 6, BUSY_BACKGROUND_SPREAD = 45, NOISY_ABOVE = 5;
    /** the highlights: this percentile of each pixel's brightest channel — high enough that the eye whites and the brightest of the skin
     *  count (a few hundred pixels of the frame) */
    static final double HIGHLIGHT_PERCENTILE = 0.999;
    /** under-exposed, read from the whole frame: the highlights under this (nothing in the frame, not even the eye whites, reaching
     *  it) AND the mean brightness under {@link #UNDER_MEAN}. A correctly exposed portrait's eye whites are far above it at a passport
     *  framing (a made-up dark face in a black suit on an 85 grey wall reads 227 to 239); but a little looser, the eye whites fall under
     *  a thousandth of the frame and the highlights onto the skin, so a correctly exposed dark face on a dark wall in dark clothes
     *  reads under-exposed (the review's third round: highlights 85 to 118 at framing 0.6 to 0.9). The histogram cannot tell the two
     *  apart: TOO_DARK is advisory, and the brightness is raised no more than {@link #UNDER_GAIN_MAX} times */
    static final int UNDER_HIGHLIGHT = 120;
    static final double UNDER_MEAN = 96;
    /** the background's band: this share of the shorter side deep, its sides read down to this share of the height (above the shoulders) */
    static final double BACKGROUND_BAND = 0.08, BACKGROUND_SIDES_TO = 0.40;
    /** the head where it reaches the top band: pixels this far (or three times the side strips' spread) from the wall's brightness;
     *  traced up row by row, widening by no more than this share of the width past its outermost edge over the last
     *  {@link #HEAD_ROWS} rows (a head narrows as it rises), gaps of as many pixels like the wall bridged (a light strand of hair) */
    static final double HEAD_FROM_WALL = 16, HEAD_WIDEN = 0.005;
    static final int HEAD_ROWS = 8;
    // the enhancement's bounds
    static final double WB_MIN = 0.95, WB_MAX = 1.05, STRETCH_LIMIT = 1.8, GAMMA_MIN = 0.55, GAMMA_MAX = 1.35;
    static final double UNDER_TARGET = 0.45, OVER_TARGET = 0.65;
    /** the levels and the gamma of an under-exposed photograph together raise no pixel's brightness more than this — a tenth: a
     *  correctly exposed dark face read as under-exposed (see {@link #UNDER_HIGHLIGHT}) moves by no more than 8 levels at a forehead
     *  of 80, so it still looks like the person; a frame truly under-exposed is lifted as little, and TOO_DARK asks for a retake in
     *  better light (the review's second round allowed 2.5 times, which lightened such a face by 50 to 97 levels) */
    static final double UNDER_GAIN_MAX = 1.10;
    /** the white balance's near-neutral pixel: channels apart by less than this share of its brightness, brightness at least
     *  {@link #NEUTRAL_MIN_LUMA}, no channel at {@link #NEUTRAL_CLIPPED} or above; and at least this share of the frame such on the
     *  wall, and as much again off it */
    static final double NEUTRAL_CHROMA = 0.10, NEUTRAL_MIN_SHARE = 0.01;
    static final int NEUTRAL_MIN_LUMA = 40, NEUTRAL_CLIPPED = 250;
    /** a pixel of the wall's colour: each channel within this (and two and a half times the background's spread) of the background's */
    static final double WALL_MATCH = 10;
    /** COLOUR_CAST ({@link #colourCast}): the background's tint (its channels' range over its brightness, red over green over blue for a
     *  warm cast, blue over green over red for a cool one) at least {@link #CAST_MIN}, the background at least {@link #CAST_MIN_LUMA}
     *  bright and plain — and either the tint at least {@link #CAST_WALL_WARM} warm or {@link #CAST_WALL_COOL} cool, or the frame
     *  confirming it: the centre's warmth under {@link #CENTRE_WARMTH_MIN} before a cool background or over {@link #CENTRE_WARMTH_MAX}
     *  before a warm one, or the lit pixels off the wall no more saturated than {@link #CAST_OFF_WALL_CHROMA} of their brightness tinted
     *  as it is by at least {@link #CAST_MIN}. A painted wall's own tint (cream 0.17, peach 0.22, light yellow 0.19, mid-blue -0.22)
     *  never raises it alone */
    static final double CAST_MIN = 0.15, CAST_MIN_LUMA = 60, CAST_OFF_WALL_CHROMA = 0.35;
    static final double CENTRE_WARMTH_MIN = 0.20, CENTRE_WARMTH_MAX = 1.0;
    /** the background's tint that raises COLOUR_CAST on the wall alone: well past the painted walls measured (cream 0.17, light yellow
     *  0.19, peach 0.22, mid-blue -0.22), where a strong lamp over a white wall lies (a strong tungsten 0.29 to 0.39). Cool only past
     *  -0.40: a light-blue backdrop chosen for an ID photograph (about -0.37) is a backdrop, not a cast, and is left GOOD; a strong shade
     *  on a grey wall (-0.34) is told when the face or the clothes confirm it, as the milder casts are */
    static final double CAST_WALL_WARM = 0.28, CAST_WALL_COOL = -0.40;
    /** the clothes' place, read off the wall even where it is of the wall's colour: the bottom tenth of the frame, the middle third
     *  across — a head-and-shoulders portrait's chest at any usual framing, never the wall (a white shirt under the lamp that tints a
     *  white wall takes the wall's colour) */
    static final double CLOTHES_BAND = 0.10;
    /** levels move the black point only when the darkest half per cent of the photograph is brighter than this, the photograph is low
     *  in contrast (spread under {@link #LOW_SPREAD}) and its highlights fall short of {@link #FLAT_HIGH} — a flat or hazy one — and
     *  then by no more than {@link #BLACK_MOVE_LIMIT} levels */
    static final int LIFTED_BLACK = 40, FLAT_HIGH = 230, BLACK_MOVE_LIMIT = 16;
    static final double SHARPEN_AMOUNT = 0.5, SHARPEN_THRESHOLD = 3;
    /** the cut, when the photograph is taller than the frame: this share of what is cut away comes off the top, the rest the bottom */
    static final double TOP_SHARE = 0.3;
    /** a photograph larger than this is decoded at a fraction of its size (it ends at 600×750; the readings are scaled back) */
    static final long DECODE_BUDGET_PIXELS = 6_000_000L;
    /** the largest progressive or multi-scan JPEG read ({@link JpegHeader#multiScan}): its reader keeps the whole image's coefficients
     *  whatever the fraction decoded (a phone's 12-megapixel 4032×3024 passes; 13,000,000 pixels at 4:4:4 hold about 80 MB of native
     *  memory while it is read) */
    static final long MULTI_SCAN_MAX_PIXELS = 13_000_000L;
    /** a JPEG header with more groups of stray bytes between its segments than this, or more JFIF segments, is damaged — no encoder
     *  writes them — and refused ({@link #normalise}) before a reader is made (the review's fourth round: a 6 MB file of about two
     *  million such groups, each put right and named, stored two million warnings, 116 MB of JSON, and held a slot for 4.6 s) */
    static final int HEADER_ODDITIES_MAX = 8;
    /** the most warnings the record keeps: what the header's putting right says (a line for each kind), then the reader's own */
    static final int WARNINGS_MAX = 5;
    /** the largest image {@link #toJpeg} decodes; anything larger is served as it is stored */
    static final long DEFAULT_MAX_PIXELS = 40_000_000L;
    /** the largest enhanced copy the card photograph takes (hrm.staff_photo's ck_photo_bytes is 2 MiB) */
    static final int MAX_ENHANCED_BYTES = 2_000_000;

    /** the limits and the frame: moaum.photo.* (defaults: 6 MiB, 40,000,000 pixels, at least 300×375, cut to 600×750, quality 0.9) */
    public record Settings(long maxBytes, long maxPixels, int minWidth, int minHeight, int width, int height, float quality) {
        public static Settings defaults() {
            return new Settings(6L * 1024 * 1024, DEFAULT_MAX_PIXELS, 300, 375, 600, 750, 0.9f);
        }
    }

    /** a photograph refused as it arrived — not a JPEG or a PNG, too large, damaged, a print (CMYK) file; nothing of it is kept */
    public static final class Refused extends DomainRuleViolation {
        Refused(String code, String detail, String remedy) {
            super(code, detail, new Remedy(remedy, "You"));
        }
    }

    /** the readings of one photograph, as uploaded (made upright), and the verdict */
    public record Assessment(int width, int height, String format, int orientation, double meanLuma, double centreLuma, double lumaSpread,
                             int highlights, double clippedDarkPct, double clippedBrightPct, double centreClippedPct, double sharpness,
                             double noise, int cropWidth, int cropHeight, double backgroundBrightness, double backgroundSpread,
                             double backgroundTint, List<String> flags, String quality, List<String> decodeWarnings) {

        /** under-exposed, judged from the whole frame (never the face): its highlights well below white and its mean low */
        public boolean underExposed() {
            return PhotoEnhancer.underExposed(highlights, meanLuma);
        }

        /** over-exposed: the centre's highlights clipped — the only reading on which the brightness is brought down */
        public boolean overExposed() {
            return centreClippedPct > CLIPPED_BRIGHT_PCT;
        }

        public double megapixels() {
            return round((double) width * height / 1_000_000d, 2);
        }

        public double aspect() {
            return round((double) width / Math.max(1, height), 3);
        }

        public boolean orientationCorrected() {
            return orientation > 1 && orientation <= 8;
        }

        /** the readings as the record keeps them (hrm.staff_photo_submission.assessment) and the screen shows them */
        public Map<String, Object> toMap() {
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("width", width);
            m.put("height", height);
            m.put("megapixels", megapixels());
            m.put("format", format);
            m.put("orientation", orientation);
            m.put("orientationCorrected", orientationCorrected());
            m.put("meanLuma", round(meanLuma, 1));
            m.put("centreLuma", round(centreLuma, 1));
            m.put("lumaSpread", round(lumaSpread, 1));
            m.put("highlights", highlights);
            m.put("clippedDarkPct", round(clippedDarkPct, 2));
            m.put("clippedBrightPct", round(clippedBrightPct, 2));
            m.put("centreClippedPct", round(centreClippedPct, 2));
            m.put("sharpness", round(sharpness, 1));
            m.put("sharpnessThreshold", BLURRY_BELOW);
            m.put("noise", round(noise, 2));
            m.put("aspect", aspect());
            m.put("crop", Map.of("width", cropWidth, "height", cropHeight));
            Map<String, Object> bg = new LinkedHashMap<>();
            bg.put("brightness", round(backgroundBrightness, 1));
            bg.put("spread", round(backgroundSpread, 1));
            bg.put("uniformity", round(Math.max(0, Math.min(1, 1 - backgroundSpread / 64d)), 2));
            bg.put("busy", backgroundSpread > BUSY_BACKGROUND_SPREAD);
            bg.put("tint", round(backgroundTint, 3));
            bg.put("note", "Read from the top band and the sides above the shoulders (the top 40%) of the framed photograph, the head left "
                    + "out where it reaches the top band; tint: warm above 0, cool below; advisory only");
            m.put("background", bg);
            m.put("face", FACE);
            m.put("flags", flags);
            m.put("quality", quality);
            if (!decodeWarnings.isEmpty()) m.put("decodeWarnings", decodeWarnings);
            return m;
        }
    }

    /** the enhanced copy (a JPEG of the frame's size) with the assessment of the original and the record of what was done; when the
     *  work failed after the photograph was read, {@code jpeg} is null and {@code error} says why */
    public record Enhanced(byte[] jpeg, int width, int height, Assessment assessment, Map<String, Object> enhancement, String error) {
    }

    private final Settings settings;
    /** at most two photographs are decoded and worked at once — uploaded ones and the card's PNGs turned into JPEGs ({@link #toJpeg})
     *  alike, across every instance: each may take tens of megabytes while it is */
    static final Semaphore SLOTS = new Semaphore(2);
    /** how long an uploaded photograph waits for a slot */
    private static final long SLOT_WAIT_SECONDS = 30;
    /** how long {@link #toJpeg} waits for a slot: its callers read the photograph in a transaction, so it never holds a database
     *  connection long; the image is served as stored when no slot comes */
    static final long TOJPEG_SLOT_WAIT_MILLIS = 2_000;

    @Autowired
    PhotoEnhancer(@Value("${moaum.photo.max-bytes:6291456}") long maxBytes, @Value("${moaum.photo.max-pixels:40000000}") long maxPixels,
                  @Value("${moaum.photo.min-width:300}") int minWidth, @Value("${moaum.photo.min-height:375}") int minHeight,
                  @Value("${moaum.photo.width:600}") int width, @Value("${moaum.photo.height:750}") int height,
                  @Value("${moaum.photo.quality:0.9}") float quality) {
        this(new Settings(maxBytes, maxPixels, minWidth, minHeight, width, height, quality));
    }

    public PhotoEnhancer(Settings settings) {
        if (settings.width() < 1 || settings.height() < 1 || settings.quality() <= 0 || settings.quality() > 1) {
            throw new IllegalArgumentException("moaum.photo: the frame is at least 1×1 and the quality in (0, 1]");
        }
        this.settings = settings;
    }

    public Settings settings() {
        return settings;
    }

    /** the first bytes say JPEG (FF D8 FF) or PNG (its eight-byte signature): "image/jpeg", "image/png", or null for anything else */
    public static String sniff(byte[] b) {
        if (b == null) return null;
        if (b.length > 3 && (b[0] & 0xFF) == 0xFF && (b[1] & 0xFF) == 0xD8 && (b[2] & 0xFF) == 0xFF) return "image/jpeg";
        if (b.length > 8 && (b[0] & 0xFF) == 0x89 && b[1] == 'P' && b[2] == 'N' && b[3] == 'G' && b[4] == 0x0D && b[5] == 0x0A
                && b[6] == 0x1A && b[7] == 0x0A) return "image/png";
        return null;
    }

    /** the photograph's readings and verdict, as {@link #enhance} gives them, without the enhanced copy */
    public Assessment assess(byte[] bytes) {
        return withSlot(() -> frame(decode(bytes)).assessment());
    }

    /** the photograph assessed and enhanced — refused ({@link Refused}) when it cannot be read safely */
    public Enhanced enhance(byte[] bytes) {
        return withSlot(() -> {
            Framed f = frame(decode(bytes));
            try {
                return improve(f);
            } catch (RuntimeException e) {
                String why = e.getMessage() == null || e.getMessage().isBlank() ? e.getClass().getSimpleName() : e.getMessage();
                return new Enhanced(null, 0, 0, f.assessment(), Map.of("steps", f.steps()), "The photograph could not be enhanced: " + why);
            }
        });
    }

    private <T> T withSlot(java.util.function.Supplier<T> work) {
        if (!slot(SLOT_WAIT_SECONDS, TimeUnit.SECONDS)) {
            throw new Refused("PHOTO_BUSY", "The portal is working on other photographs just now.", "Upload the photograph again in a minute.");
        }
        try {
            return work.get();
        } finally {
            SLOTS.release();
        }
    }

    /** one of the two slots, waited for up to the time given; false when none came (the caller releases a true one) */
    private static boolean slot(long wait, TimeUnit unit) {
        try {
            return SLOTS.tryAcquire(wait, unit);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            return false;
        }
    }

    /* ── reading safely ────────────────────────────────────────────────────────────────────────────────────────────────────── */

    /** the photograph decoded (possibly at a fraction of its size), on white, upright; with its size as uploaded (made upright) */
    record Decoded(BufferedImage image, int width, int height, String format, int orientation, int subsample, List<String> warnings) {
    }

    Decoded decode(byte[] bytes) {
        if (bytes == null || bytes.length == 0) {
            throw new Refused("PHOTO_EMPTY", "No photograph was received.", "Choose the photograph again and upload it.");
        }
        if (bytes.length > settings.maxBytes()) {
            throw new Refused("PHOTO_SIZE", "The photograph is " + megabytes(bytes.length) + "; the portal takes one of up to "
                    + megabytes(settings.maxBytes()) + ".", "Upload a smaller copy of the photograph (a phone's 'medium' size is enough).");
        }
        String type = sniff(bytes);
        if (type == null) {
            throw new Refused("PHOTO_FORMAT", "The file is not a JPEG or a PNG photograph.", "Choose a .jpg or .png photograph.");
        }
        boolean jpeg = "image/jpeg".equals(type);
        int orientation = 1;
        JpegHeader header = null;
        if (jpeg) {
            header = jpegHeader(bytes);
            // no single frame header where the reader looks for one (none, two, or one of no size): damaged — refused before a reader is
            // made, so that the limits below are always read from the frame the reader will decode
            if (header.width() <= 0 || header.height() <= 0) {
                throw corrupt();
            }
            if (header.components() == 4) {
                throw new Refused("PHOTO_CMYK", "The photograph is a CMYK JPEG — a file made for printing, which the card cannot use.",
                        "Save it as an ordinary (RGB) JPEG or a PNG and upload that.");
            }
            // a progressive JPEG's reader holds the whole image's coefficients, whatever fraction of it is decoded, and so does a
            // sequential one whose colours are stored in separate scans: refused past the multi-scan limit on the frame header's own
            // size, before the reader is asked
            if (header.multiScan() && (long) header.width() * header.height() > MULTI_SCAN_MAX_PIXELS) {
                String size = header.width() + " × " + header.height() + " pixels";
                throw new Refused("PHOTO_DIMENSIONS", (header.progressive() ? "The photograph is a progressive JPEG of " + size
                        + "; the portal reads a progressive JPEG" : "The photograph is a JPEG of " + size + " stored in several scans; the "
                        + "portal reads such a JPEG") + " of up to " + String.format("%,d", MULTI_SCAN_MAX_PIXELS) + " pixels.",
                        "Upload a smaller copy of the photograph (a phone's 'medium' size is enough), or save it again as an ordinary JPEG.");
            }
            // no end-of-image marker after the image data: a truncated file — the reader would decode all there is, warn "Truncated
            // File - Missing EOI marker" and be refused for it; refused here before that work is done
            if (endOfImage(bytes) < 0) {
                throw corrupt();
            }
            orientation = header.orientation();
        }
        // a JPEG's header put right where the reader would only warn (its first warning would hide any that follow); the record keeps
        // what was put right, in the reader's words
        Normalised read = jpeg ? normalise(bytes, header.progressive()) : new Normalised(bytes, List.of());
        byte[] input = read.bytes();
        Iterator<ImageReader> readers = ImageIO.getImageReadersByFormatName(jpeg ? "jpeg" : "png");
        if (!readers.hasNext()) {
            throw new IllegalStateException("the JDK's " + (jpeg ? "JPEG" : "PNG") + " reader is missing");
        }
        ImageReader reader = readers.next();
        // the reader's warnings, heard from the header on: kept for the record (at most five in all, each once, after what the header's
        // putting right says) and judged as they come — one that means image data lost or garbled, or one the header put right would
        // not give (it would hide any that follow), marks the photograph damaged
        List<String> warnings = new ArrayList<>(read.warnings().subList(0, Math.min(WARNINGS_MAX, read.warnings().size())));
        boolean[] damaged = {false};
        reader.addIIOReadWarningListener((source, message) -> {
            String warning = String.valueOf(message);
            if (dataLoss(warning, input)) damaged[0] = true;
            if (warnings.size() < WARNINGS_MAX && !warnings.contains(warning)) warnings.add(warning);
        });
        try (ImageInputStream in = new MemoryCacheImageInputStream(new ByteArrayInputStream(input))) {
            reader.setInput(in, true, true);
            // the size from the header, before a pixel is read: a small file can declare an enormous canvas
            int w = reader.getWidth(0), h = reader.getHeight(0);
            if (w <= 0 || h <= 0 || damaged[0]) {
                throw corrupt();
            }
            // the frame the reader found is the one read by hand (else the limits above were read from another)
            if (header != null && (w != header.width() || h != header.height())) {
                throw corrupt();
            }
            if ((long) w * h > settings.maxPixels()) {
                throw new Refused("PHOTO_DIMENSIONS", "The photograph is " + w + " × " + h + " pixels; the portal reads one of up to "
                        + String.format("%,d", settings.maxPixels()) + " pixels.", "Upload a smaller copy of the photograph.");
            }
            int sub = subsampling(w, h);
            ImageReadParam param = reader.getDefaultReadParam();
            if (sub > 1) param.setSourceSubsampling(sub, sub, 0, 0);
            BufferedImage raw = reader.read(0, param);
            if (raw == null || raw.getWidth() < 1 || raw.getHeight() < 1) {
                throw corrupt();
            }
            // the reader decodes what it can of a truncated or corrupt file and only warns ("Truncated File - Missing EOI marker",
            // "Corrupt JPEG data: premature end of data segment", a bad Huffman code …), filling the rest flat grey: refused as damaged
            if (damaged[0]) {
                throw corrupt();
            }
            BufferedImage upright = orient(onWhite(raw), orientation);
            boolean swap = orientation >= 5 && orientation <= 8;
            return new Decoded(upright, swap ? h : w, swap ? w : h, jpeg ? "JPEG" : "PNG", orientation, sub, List.copyOf(warnings));
        } catch (Refused r) {
            throw r;
        } catch (IOException | RuntimeException e) {
            String m = String.valueOf(e.getMessage());
            if (m.contains("Unsupported Image Type") || m.contains("CMYK")) {
                throw new Refused("PHOTO_CMYK", "The photograph is a CMYK JPEG — a file made for printing, which the card cannot use.",
                        "Save it as an ordinary (RGB) JPEG or a PNG and upload that.");
            }
            throw corrupt();
        } finally {
            reader.dispose();
        }
    }

    private static Refused corrupt() {
        return new Refused("PHOTO_CORRUPT", "The photograph could not be read: the file is damaged or incomplete.",
                "Take or export the photograph again and upload the new file.");
    }

    /** "Corrupt JPEG data: N extraneous bytes before marker 0xNN", as the JPEG reader (libjpeg) says it */
    private static final Pattern EXTRANEOUS = Pattern.compile("(\\d+) extraneous bytes before marker 0x([0-9a-f]{2})");

    /** whether a reader's warning, heard while it reads the photograph with its header put right ({@link #normalise}; {@code bytes}),
     *  marks the photograph damaged: one that means image data lost or garbled — a truncated file (no end-of-image marker), the
     *  premature end of the file or of a data segment, a bad Huffman code, a marker found instead of a restart marker, an inconsistent
     *  progression, an unknown Adobe colour transform (the colours guessed), stray bytes before any marker but the end-of-image (before a
     *  restart marker: inside the image data; between a progressive JPEG's scans: the scan before them garbled; between the header's
     *  segments the header put right has none), stray bytes before the end-of-image marker unless they are zeros (padding some
     *  cameras and apps add after the last of the image data; any other bytes there are image data the decoder did not use — the
     *  V749 review found such files more than a fifth damaged) — and one that loses nothing but which the header put right would not
     *  give: an unknown JFIF revision or odd SOS parameters, from a segment past the first scan — the JDK's reader passes on only the
     *  first warning of each pass, so it would hide any warning of lost data that follows (the review's third round: a damaged file
     *  with an odd header read as whole). Not: an invalid embedded colour profile (ignored), a JFIF marker in a thumbnail (both said by
     *  the Java reader, which hide nothing), and any warning not named here */
    static boolean dataLoss(String warning, byte[] bytes) {
        String w = warning == null ? "" : warning.toLowerCase(Locale.ROOT);
        if (w.contains("truncated") || w.contains("premature end") || w.contains("bad huffman") || w.contains("instead of rst")
                || w.contains("inconsistent progression") || w.contains("adobe color transform") || w.contains("unknown jfif revision")
                || w.contains("invalid sos parameters")) {
            return true;
        }
        Matcher m = EXTRANEOUS.matcher(w);
        if (!m.find()) return false;
        int marker = Integer.parseInt(m.group(2), 16);
        return marker != 0xD9 || !zeroPadded(bytes, Long.parseLong(m.group(1)));
    }

    /** whether the {@code n} bytes the reader skipped before the end-of-image marker that ends the image data are all zeros */
    static boolean zeroPadded(byte[] b, long n) {
        int end = endOfImage(b);
        if (b == null || end < 0 || n <= 0) return false;
        int j = end - 1;
        while (j >= 2 && (b[j] & 0xFF) == 0xFF) j--;   // fill bytes before the marker
        if (j + 1 - n < 2) return false;
        for (long k = 0; k < n; k++) {
            if (b[(int) (j - k)] != 0) return false;
        }
        return true;
    }

    /** where a JPEG's image data ends: the index of the 0xFF of the first end-of-image marker the reader meets (the segments skipped by
     *  their length, the image data read byte by byte, its stuffed FF 00 and restart markers passed); -1 when there is none */
    static int endOfImage(byte[] b) {
        if (b == null) return -1;
        int i = 2;
        while (i + 1 < b.length) {
            if ((b[i] & 0xFF) != 0xFF) {
                i++;
                continue;
            }
            int c = b[i + 1] & 0xFF;
            if (c == 0xFF) {
                i++;
            } else if (c == 0xD9) {
                return i;
            } else if (c == 0x00 || c == 0x01 || c == 0xD8 || (c >= 0xD0 && c <= 0xD7)) {
                i += 2;
            } else {
                if (i + 4 > b.length) return -1;
                int len = ((b[i + 2] & 0xFF) << 8) | (b[i + 3] & 0xFF);
                if (len < 2) return -1;
                i += 2 + len;
            }
        }
        return -1;
    }

    /** the fraction a photograph is decoded at: 1 in {@code sub} pixels across and down, so that no more than
     *  {@link #DECODE_BUDGET_PIXELS} are decoded */
    static int subsampling(int w, int h) {
        return (int) Math.max(1, Math.ceil(Math.sqrt((double) w * h / DECODE_BUDGET_PIXELS)));
    }

    private static String megabytes(long n) {
        return String.format("%.1f MB", n / (1024d * 1024d));
    }

    /** a JPEG's orientation (EXIF 0x0112, 1 when none), and from the frame header its number of colour components, whether it is
     *  progressive (SOF2, SOF6, SOF10 or SOF14) and its width and height (0 when there is no frame header, or more than one); and from
     *  the first scan's header the number of components that scan codes (0 when no scan was found) — read by hand */
    record JpegHeader(int orientation, int components, boolean progressive, int width, int height, int scanComponents) {

        /** whether its reader keeps the coefficients of the whole image, whatever fraction of it is decoded: a progressive JPEG, or one
         *  of several components whose first scan codes fewer of them (its colours stored in separate scans — libjpeg's
         *  has_multiple_scans, which buffers the whole image as a progressive JPEG does) */
        boolean multiScan() {
            return progressive || (components > 1 && scanComponents > 0 && scanComponents < components);
        }
    }

    /** the header read as the JPEG reader (libjpeg) reads it, up to the first scan: each marker found as libjpeg's next_marker finds it
     *  — any byte that is not 0xFF skipped, fill bytes (0xFF) swallowed, a stuffed FF 00 skipped — so that no stray bytes before the
     *  frame header hide it from this reading while the reader decodes it */
    static JpegHeader jpegHeader(byte[] b) {
        int orientation = 1, components = 0, width = 0, height = 0, frames = 0, scanComponents = 0;
        boolean progressive = false;
        int i = 2;
        while (true) {
            int marker = -1;
            while (i < b.length) {
                if ((b[i] & 0xFF) != 0xFF) {
                    i++;
                    continue;
                }
                while (i < b.length && (b[i] & 0xFF) == 0xFF) i++;
                if (i >= b.length) break;
                int c = b[i++] & 0xFF;
                if (c != 0) {
                    marker = c;
                    break;
                }
            }
            if (marker < 0 || marker == 0xD9) break;                             // the end, or end of image: no headers after it
            if (marker == 0xDA) {                                                // the first scan: its number of components (Ns), then
                if (i + 2 < b.length) scanComponents = b[i + 2] & 0xFF;         // no headers after it
                break;
            }
            if (marker == 0xD8 || marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) continue;   // no length
            if (i + 2 > b.length) break;
            int len = ((b[i] & 0xFF) << 8) | (b[i + 1] & 0xFF);
            if (len < 2 || i + len > b.length) break;
            int seg = i + 2, segEnd = i + len;
            if (marker == 0xE1 && orientation == 1 && segEnd - seg >= 14 && b[seg] == 'E' && b[seg + 1] == 'x' && b[seg + 2] == 'i' && b[seg + 3] == 'f'
                    && b[seg + 4] == 0 && b[seg + 5] == 0) {
                orientation = exifOrientation(b, seg + 6, segEnd);
            }
            boolean frame = marker >= 0xC0 && marker <= 0xCF && marker != 0xC4 && marker != 0xC8 && marker != 0xCC;
            if (frame && ++frames == 1 && seg + 6 <= segEnd) {
                // the frame header: precision, height (2 bytes), width (2 bytes), components
                height = ((b[seg + 1] & 0xFF) << 8) | (b[seg + 2] & 0xFF);
                width = ((b[seg + 3] & 0xFF) << 8) | (b[seg + 4] & 0xFF);
                components = b[seg + 5] & 0xFF;
                progressive = marker == 0xC2 || marker == 0xC6 || marker == 0xCA || marker == 0xCE;
            }
            i = segEnd;
        }
        if (frames > 1) {
            width = 0;   // two frame headers: the reader refuses such a file; so is it here, before the reader is asked
            height = 0;
        }
        return new JpegHeader(orientation, components, progressive, width, height, scanComponents);
    }

    /** the bytes the reader is given, and what the photograph's own header would have made the reader say */
    record Normalised(byte[] bytes, List<String> warnings) {
    }

    /** the JPEG with its header put right where the reader would only warn and lose nothing — so that the first warning the reader
     *  gives while decoding is one about the image data (the JDK's reader passes on only the first warning of each pass, so a
     *  harmless one would hide any that follow: a damaged file with an odd header was read as whole). Up to and including the first
     *  scan's header, each marker found as libjpeg's next_marker finds it: stray bytes (and a stuffed FF 00) between the segments
     *  dropped, a JFIF APP0 of another major revision given the revision 1.02, a sequential JPEG's scan given Ss 0, Se 63 and Ah/Al 0
     *  (which its decoder never reads); the image data after it as it is. Each kind of change is named once, as the reader would have
     *  said it the first time, with how many more there were (they lose nothing; the record keeps them); the bytes themselves when
     *  nothing needs putting right. A header of more than {@link #HEADER_ODDITIES_MAX} groups of stray bytes or JFIF segments is
     *  refused as damaged ({@link Refused} PHOTO_CORRUPT) as soon as it is found, before a reader is made: no encoder writes them */
    static Normalised normalise(byte[] b, boolean progressive) {
        ByteArrayOutputStream out = new ByteArrayOutputStream(Math.min(b.length, 1 << 16));
        out.write(b, 0, 2);
        // what was put right, each kind once in the order first met: the stray bytes (their groups, their bytes in all, the reader's
        // words for the first group), the JFIF revision (the segments of another revision, the reader's words for the first), the scan
        List<String> kinds = new ArrayList<>();
        int strayGroups = 0, jfifSegments = 0, jfifOdd = 0;
        long strayBytes = 0;
        String firstStray = null, firstJfif = null;
        int i = 2;
        while (true) {
            int discarded = 0, marker = -1;
            while (i < b.length) {
                if ((b[i] & 0xFF) != 0xFF) {
                    discarded++;
                    i++;
                    continue;
                }
                while (i < b.length && (b[i] & 0xFF) == 0xFF) i++;
                if (i >= b.length) break;
                int c = b[i++] & 0xFF;
                if (c != 0) {
                    marker = c;
                    break;
                }
                discarded += 2;                                                  // a stuffed FF 00, which libjpeg counts as two
            }
            if (marker < 0) return new Normalised(b, List.of());                 // no marker left: the reader refuses it as it is
            if (discarded > 0) {
                if (++strayGroups > HEADER_ODDITIES_MAX) throw corrupt();
                strayBytes += discarded;
                if (firstStray == null) {
                    firstStray = String.format("Corrupt JPEG data: %d extraneous bytes before marker 0x%02x", discarded, marker);
                    kinds.add("stray");
                }
            }
            out.write(0xFF);
            out.write(marker);
            if (marker == 0xD8 || marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) continue;   // no length
            int len = marker == 0xD9 || i + 2 > b.length ? -1 : ((b[i] & 0xFF) << 8) | (b[i + 1] & 0xFF);
            if (len < 2 || i + len > b.length) {                                 // the end of the image, or a segment the reader refuses
                if (kinds.isEmpty()) return new Normalised(b, List.of());
                out.write(b, i, b.length - i);
                break;
            }
            byte[] seg = Arrays.copyOfRange(b, i, i + len);                     // the length, then the segment's data
            if (marker == 0xE0 && len - 2 >= 14 && seg[2] == 'J' && seg[3] == 'F' && seg[4] == 'I' && seg[5] == 'F' && seg[6] == 0) {
                if (++jfifSegments > HEADER_ODDITIES_MAX) throw corrupt();
                if ((seg[7] & 0xFF) != 1) {
                    if (jfifOdd++ == 0) {
                        firstJfif = String.format("Warning: unknown JFIF revision number %d.%02d", seg[7] & 0xFF, seg[8] & 0xFF);
                        kinds.add("jfif");
                    }
                    seg[7] = 1;
                    seg[8] = 2;
                }
            }
            if (marker == 0xDA && !progressive && len > 2) {
                int at = 3 + 2 * (seg[2] & 0xFF);                                // Ss, Se, Ah/Al after the components
                if (at + 2 < len && (seg[at] != 0 || (seg[at + 1] & 0xFF) != 63 || seg[at + 2] != 0)) {
                    kinds.add("sos");
                    seg[at] = 0;
                    seg[at + 1] = 63;
                    seg[at + 2] = 0;
                }
            }
            out.write(seg, 0, len);
            i += len;
            if (marker == 0xDA) {                                                // the first scan's data on, as it is
                if (kinds.isEmpty()) return new Normalised(b, List.of());
                out.write(b, i, b.length - i);
                break;
            }
        }
        List<String> said = new ArrayList<>();
        for (String kind : kinds) {
            switch (kind) {
                case "stray" -> said.add(strayGroups == 1 ? firstStray : String.format("%s (and before %d more of the header's markers: %,d "
                        + "bytes in all)", firstStray, strayGroups - 1, strayBytes));
                case "jfif" -> said.add(jfifOdd == 1 ? firstJfif : String.format("%s (in %d JFIF segments)", firstJfif, jfifOdd));
                default -> said.add("Invalid SOS parameters for sequential JPEG");
            }
        }
        return new Normalised(out.toByteArray(), List.copyOf(said));
    }

    /** the Orientation tag (0x0112) of IFD0 in the TIFF structure an EXIF APP1 carries; 1 when absent or unreadable */
    static int exifOrientation(byte[] b, int tiff, int end) {
        if (tiff + 8 > end) return 1;
        boolean little;
        if (b[tiff] == 'I' && b[tiff + 1] == 'I') little = true;
        else if (b[tiff] == 'M' && b[tiff + 1] == 'M') little = false;
        else return 1;
        if (u16(b, tiff + 2, little) != 42) return 1;
        long ifd = u32(b, tiff + 4, little);
        if (ifd < 8 || tiff + ifd + 2 > end) return 1;
        int at = (int) (tiff + ifd);
        int n = u16(b, at, little);
        for (int k = 0; k < n; k++) {
            int e = at + 2 + k * 12;
            if (e + 12 > end) return 1;
            if (u16(b, e, little) == 0x0112) {
                int type = u16(b, e + 2, little);
                int v = type == 3 ? u16(b, e + 8, little) : type == 4 ? (int) u32(b, e + 8, little) : 1;
                return v >= 1 && v <= 8 ? v : 1;
            }
        }
        return 1;
    }

    private static int u16(byte[] b, int at, boolean little) {
        return little ? (b[at] & 0xFF) | ((b[at + 1] & 0xFF) << 8) : ((b[at] & 0xFF) << 8) | (b[at + 1] & 0xFF);
    }

    private static long u32(byte[] b, int at, boolean little) {
        return little ? (b[at] & 0xFFL) | ((b[at + 1] & 0xFFL) << 8) | ((b[at + 2] & 0xFFL) << 16) | ((b[at + 3] & 0xFFL) << 24)
                : ((b[at] & 0xFFL) << 24) | ((b[at + 1] & 0xFFL) << 16) | ((b[at + 2] & 0xFFL) << 8) | (b[at + 3] & 0xFFL);
    }

    /** any decoded raster as packed RGB, transparency flattened onto white (a JPEG has no alpha; a card's frame is white) */
    static BufferedImage onWhite(BufferedImage src) {
        BufferedImage rgb = new BufferedImage(src.getWidth(), src.getHeight(), BufferedImage.TYPE_INT_RGB);
        Graphics2D g = rgb.createGraphics();
        try {
            g.setColor(Color.WHITE);
            g.fillRect(0, 0, rgb.getWidth(), rgb.getHeight());
            g.drawImage(src, 0, 0, null);
        } finally {
            g.dispose();
        }
        return rgb;
    }

    /** the photograph put upright as its EXIF orientation says (2: mirrored; 3: upside down; 4: flipped; 5: transposed; 6: turned a
     *  quarter clockwise; 7: transversed; 8: turned a quarter anticlockwise) */
    static BufferedImage orient(BufferedImage src, int o) {
        if (o <= 1 || o > 8) return src;
        int w = src.getWidth(), h = src.getHeight();
        boolean swap = o >= 5;
        int dw = swap ? h : w, dh = swap ? w : h;
        BufferedImage dst = new BufferedImage(dw, dh, BufferedImage.TYPE_INT_RGB);
        int[] s = pixels(src), d = pixels(dst);
        for (int y = 0; y < h; y++) {
            for (int x = 0; x < w; x++) {
                int dx, dy;
                switch (o) {
                    case 2 -> { dx = w - 1 - x; dy = y; }
                    case 3 -> { dx = w - 1 - x; dy = h - 1 - y; }
                    case 4 -> { dx = x; dy = h - 1 - y; }
                    case 5 -> { dx = y; dy = x; }
                    case 6 -> { dx = h - 1 - y; dy = x; }
                    case 7 -> { dx = h - 1 - y; dy = w - 1 - x; }
                    default -> { dx = y; dy = w - 1 - x; }
                }
                d[dy * dw + dx] = s[y * w + x];
            }
        }
        return dst;
    }

    static String orientationWords(int o) {
        return switch (o) {
            case 2 -> "mirrored left to right";
            case 3 -> "turned upside down";
            case 4 -> "flipped top to bottom";
            case 5 -> "turned a quarter clockwise and mirrored";
            case 6 -> "turned a quarter clockwise";
            case 7 -> "turned a quarter anticlockwise and mirrored";
            case 8 -> "turned a quarter anticlockwise";
            default -> "already upright";
        };
    }

    /* ── the frame and the readings ────────────────────────────────────────────────────────────────────────────────────────── */

    /** the photograph cut to the frame and sized to it (before any correction), with the readings and the steps so far */
    record Framed(BufferedImage frame, Assessment assessment, List<Map<String, Object>> steps) {
    }

    Framed frame(Decoded d) {
        BufferedImage img = d.image();
        int w = img.getWidth(), h = img.getHeight();
        double aspect = (double) settings.width() / settings.height();
        int cw, ch, cx, cy;
        if ((double) w / h > aspect) {
            ch = h;
            cw = Math.max(1, (int) Math.round(h * aspect));
            cx = (w - cw) / 2;
            cy = 0;
        } else {
            cw = w;
            ch = Math.max(1, (int) Math.round(w / aspect));
            cx = 0;
            cy = (int) Math.round((h - ch) * TOP_SHARE);
        }
        BufferedImage crop = copy(img.getSubimage(cx, cy, Math.min(cw, w - cx), Math.min(ch, h - cy)));
        BufferedImage frame = resize(crop, settings.width(), settings.height());
        // the readings: brightness, the highlights, clipping, the centre, the background and the noise on the frame; sharpness on a
        // grey copy ≤512
        int[] fy = luma(frame), fp = pixels(frame);
        int fw = frame.getWidth(), fh = frame.getHeight();
        double mean = 0, sq = 0;
        long dark = 0, bright = 0;
        for (int v : fy) {
            mean += v;
            sq += (double) v * v;
            if (v <= 5) dark++;
            if (v >= 250) bright++;
        }
        mean /= fy.length;
        double spread = Math.sqrt(Math.max(0, sq / fy.length - mean * mean));
        int highlights = percentile(brightestChannel(fp), fy.length, HIGHLIGHT_PERCENTILE);
        double centre = centreLuma(fy, fw, fh), centreClipped = centreClippedPct(fp, fw, fh);
        Background background = background(fp, fy, fw, fh);
        boolean cast = colourCast(fp, fw, fh, background);
        double noise = noise(fy, fw, fh);
        double longest = Math.max(crop.getWidth(), crop.getHeight());
        BufferedImage grey = longest > 512 ? resize(crop, (int) Math.round(crop.getWidth() * 512 / longest), (int) Math.round(crop.getHeight() * 512 / longest)) : crop;
        double sharpness = laplacianVariance(luma(grey), grey.getWidth(), grey.getHeight());
        // the frame's size in the photograph's own pixels (a large one was decoded at a fraction)
        int cropW = Math.min(d.width(), crop.getWidth() * d.subsample()), cropH = Math.min(d.height(), crop.getHeight() * d.subsample());
        // TOO_DARK from the whole frame's histogram, never the centre: a correctly exposed dark face reads dark at the centre; TOO_BRIGHT
        // from the centre only, never the backdrop: a white backdrop is meant to be white
        List<String> flags = new ArrayList<>();
        if (underExposed(highlights, mean) || 100d * dark / fy.length > CLIPPED_DARK_PCT) flags.add("TOO_DARK");
        if (centre > BRIGHT_CENTRE || centreClipped > CLIPPED_BRIGHT_PCT) flags.add("TOO_BRIGHT");
        if (spread < LOW_SPREAD) flags.add("LOW_CONTRAST");
        if (sharpness < BLURRY_BELOW) flags.add("BLURRY");
        if (cropW < settings.width() || cropH < settings.height()) flags.add("LOW_RESOLUTION");
        if (d.width() > d.height()) flags.add("LANDSCAPE");
        if (background.spread() > BUSY_BACKGROUND_SPREAD) flags.add("BUSY_BACKGROUND");
        if (cast) flags.add("COLOUR_CAST");
        String quality = cropW < settings.minWidth() || cropH < settings.minHeight() || sharpness < REPLACE_SHARPNESS_BELOW ? "REPLACE"
                : flags.isEmpty() ? "GOOD" : "FAIR";
        Assessment a = new Assessment(d.width(), d.height(), d.format(), d.orientation(), mean, centre, spread, highlights,
                100d * dark / fy.length, 100d * bright / fy.length, centreClipped, sharpness, noise, cropW, cropH, background.brightness(),
                background.spread(), background.tint(), List.copyOf(flags), quality, List.copyOf(d.warnings()));
        List<Map<String, Object>> steps = new ArrayList<>();
        steps.add(step("read", true, "format", d.format(), "width", d.width(), "height", d.height(), "decodedAtOneIn", d.subsample()));
        steps.add(step("orientation", a.orientationCorrected(), "exif", d.orientation(), "operation", orientationWords(d.orientation())));
        steps.add(step("crop", true, "x", cx * d.subsample(), "y", cy * d.subsample(), "width", cropW, "height", cropH,
                "aspect", settings.width() + ":" + settings.height(),
                "basis", "centred across, nearer the top; a geometric cut (no face detection on the server)"));
        steps.add(step("resize", true, "from", List.of(cropW, cropH), "to", List.of(settings.width(), settings.height()),
                "method", crop.getWidth() >= settings.width() ? "halved with area averages, then bicubic" : "enlarged, bicubic"));
        return new Framed(frame, a, steps);
    }

    /* ── the enhancement: global operations only ───────────────────────────────────────────────────────────────────────────── */

    Enhanced improve(Framed f) {
        BufferedImage img = copy(f.frame());
        int w = img.getWidth(), h = img.getHeight();
        int[] px = pixels(img);
        List<Map<String, Object>> steps = new ArrayList<>(f.steps());
        int[] y0 = luma(img);
        double meanBefore = mean(y0), spreadBefore = spread(y0), centreBefore = centreLuma(y0, w, h);

        // 1 · mild noise reduction, only when the noise is high: half the pixel, half its 3×3 median
        double noise = f.assessment().noise();
        if (noise > NOISY_ABOVE) {
            denoise(px, w, h);
            steps.add(step("denoise", true, "noise", round(noise, 2), "threshold", NOISY_ABOVE, "after", round(noise(luma(img), w, h), 2),
                    "method", "3×3 median, blended half and half with the original"));
        } else {
            steps.add(step("denoise", false, "noise", round(noise, 2), "threshold", NOISY_ABOVE));
        }

        // 2 · white balance read from the near-neutral pixels only: outside the centre box (where a portrait's face is), no channel
        //     clipped, not in deep shadow, the channels apart by less than a tenth of the brightness. Two readings: the wall's (the
        //     near-neutral pixels of the background's colour) and what is not the wall (a white or grey shirt, a collar, grey hair).
        //     A wall's own pale tint cannot be told from a cast, nor a shirt's cream from one: a gain is given only where the two agree,
        //     the smaller of theirs, held to [0.95, 1.05]; nothing done when either has under 1% of the frame. The skin, a coloured
        //     backdrop and coloured clothes are never read, so the face's colour cannot follow them; a strong cast leaves no pixel
        //     near-neutral and is flagged (COLOUR_CAST), not corrected
        Background bg = background(px, luma(img), w, h);
        double match = WALL_MATCH + 2.5 * bg.spread();
        int[] box = centreBox(w, h);
        double[] wall = new double[4], off = new double[4];   // the sums of red, green and blue, and the count
        for (int r = 0; r < h; r++) {
            boolean rowInBox = r >= box[2] && r < box[3];
            for (int c = 0; c < w; c++) {
                if (rowInBox && c >= box[0] && c < box[1]) continue;
                int p = px[r * w + c];
                int red = (p >> 16) & 0xFF, g = (p >> 8) & 0xFF, b = p & 0xFF;
                int max = Math.max(red, Math.max(g, b)), min = Math.min(red, Math.min(g, b));
                int yv = (299 * red + 587 * g + 114 * b) / 1000;
                if (max >= NEUTRAL_CLIPPED || yv < NEUTRAL_MIN_LUMA || max - min >= NEUTRAL_CHROMA * yv) continue;
                double[] into = Math.abs(red - bg.r()) <= match && Math.abs(g - bg.g()) <= match && Math.abs(b - bg.b()) <= match ? wall : off;
                into[0] += red;
                into[1] += g;
                into[2] += b;
                into[3]++;
            }
        }
        double minimum = NEUTRAL_MIN_SHARE * px.length;
        String wbMethod = "grey world on the near-neutral pixels outside the face box, where the wall and what is not the wall agree";
        Map<String, Object> wbShares = Map.of("wallPct", round(100d * wall[3] / px.length, 1), "offWallPct", round(100d * off[3] / px.length, 1));
        if (wall[3] >= minimum && off[3] >= minimum) {
            double[] gw = greyWorld(wall), go = greyWorld(off), gain = new double[3];
            for (int c = 0; c < 3; c++) {
                boolean agree = (gw[c] - 1) * (go[c] - 1) > 0;
                gain[c] = agree ? clamp(Math.abs(gw[c] - 1) < Math.abs(go[c] - 1) ? gw[c] : go[c], WB_MIN, WB_MAX) : 1;
            }
            boolean visible = Math.abs(gain[0] - 1) > 0.01 || Math.abs(gain[1] - 1) > 0.01 || Math.abs(gain[2] - 1) > 0.01;
            if (visible) {
                int[][] lut = new int[3][256];
                for (int c = 0; c < 3; c++) for (int v = 0; v < 256; v++) lut[c][v] = clampByte(v * gain[c]);
                apply(px, lut[0], lut[1], lut[2]);
            }
            steps.add(step("whiteBalance", visible, "method", wbMethod,
                    "gains", Map.of("r", round(gain[0], 3), "g", round(gain[1], 3), "b", round(gain[2], 3)), "limits", List.of(WB_MIN, WB_MAX),
                    "neutral", wbShares, "wallGains", Map.of("r", round(gw[0], 3), "g", round(gw[1], 3), "b", round(gw[2], 3)),
                    "offWallGains", Map.of("r", round(go[0], 3), "g", round(go[1], 3), "b", round(go[2], 3))));
        } else {
            steps.add(step("whiteBalance", false, "method", wbMethod, "neutral", wbShares, "reason",
                    wall[3] < minimum && off[3] < minimum ? "too few near-neutral pixels (a wall, a white or grey shirt) to tell a colour cast from the colours themselves"
                            : off[3] < minimum ? "the only near-neutral pixels are the wall's: its own tint cannot be told from a colour cast, so nothing is changed"
                            : "no near-neutral wall to confirm the clothes' colour against: a cream or grey-blue shirt is left as it is"));
        }

        // 3 · luminance levels, only where the photograph lacks them: the black point when it is flat (low in contrast, its darkest half
        //     per cent well above black and its highlights short of white — a hazy photograph, never a high-key one), moved down by no
        //     more than 16 levels; the white point (the brightest channel's 99.5% point) when it is flat or under-exposed; a photograph
        //     that is neither keeps its tones, dark skin and a light face on a white wall included. No more than 1.8 times when flat, and
        //     no more than 1.1 times when under-exposed (a correctly exposed dark face on a dark wall can read so: see UNDER_HIGHLIGHT);
        //     on the brightness only: red, green and blue scaled alike, so every colour keeps its proportions and skin never saturates
        int[] hist = new int[256];
        for (int v : luma(img)) hist[v]++;
        int[] top = brightestChannel(px);
        int lo = percentile(hist, px.length, 0.005), hi = percentile(top, px.length, 0.995);
        boolean under = f.assessment().underExposed();
        boolean flat = !under && f.assessment().lumaSpread() < LOW_SPREAD && lo > LIFTED_BLACK && hi < FLAT_HIGH;
        int black = flat ? lo : 0, white = flat || under ? hi : 255;
        double floor = flat ? Math.max(0, black - BLACK_MOVE_LIMIT) : 0, stretchLimit = under ? UNDER_GAIN_MAX : STRETCH_LIMIT;
        double stretch = (flat || under) && white - black >= 16 ? Math.min(stretchLimit, (255 - floor) / (white - black)) : 1;
        double levelsGain = 1;
        if (stretch > 1.01) {
            double b0 = black, s0 = stretch, f0 = floor;
            brightness(px, v -> f0 + (v - b0) * s0, Double.MAX_VALUE);
            levelsGain = flat ? 1 : stretch;
            steps.add(step("levels", true, "low", black, "high", white, "stretch", round(stretch, 3), "limit", stretchLimit,
                    "to", List.of(clampByte(floor), clampByte(floor + (white - black) * stretch)), "blackMoveLimit", BLACK_MOVE_LIMIT,
                    "method", "on the brightness only: red, green and blue scaled alike, so every colour keeps its proportions",
                    "reading", flat ? "flat (low in contrast, its darkest tones well above black and its highlights short of white)"
                            : "under-exposed (raised no more than " + UNDER_GAIN_MAX + " times: a dark face on a dark wall can read so; TOO_DARK asks for a retake)"));
        } else {
            steps.add(step("levels", false, "low", lo, "high", hi, "spread", round(f.assessment().lumaSpread(), 1), "limit", stretchLimit,
                    "reason", !flat && !under ? "the photograph is neither flat nor under-exposed: its tones are kept"
                            : white - black < 16 ? "the photograph is nearly one tone" : "the brightness already spans black to white"));
        }

        // 4 · exposure, judged from the whole frame's histogram (step 3's reading), never from the face: when under-exposed, a bounded
        //     gamma brings the frame's mean toward mid-grey, the levels and the gamma together raising no pixel more than 1.1 times — a
        //     correctly exposed dark face read as under-exposed still looks like the person; when the centre's highlights are clipped,
        //     a bounded gamma brings the centre down. On the brightness only, as the levels
        boolean over = !under && f.assessment().overExposed();
        int[] y3 = luma(img);
        double m = (under ? mean(y3) : centreLuma(y3, w, h)) / 255d;
        double gamma = 1, limit = under ? UNDER_GAIN_MAX / levelsGain : 1;
        if (m > 0.02 && m < 0.98) {
            if (under && m < UNDER_TARGET) gamma = clamp(Math.log(UNDER_TARGET) / Math.log(m), GAMMA_MIN, 1);
            else if (over && m > OVER_TARGET) gamma = clamp(Math.log(OVER_TARGET) / Math.log(m), 1, GAMMA_MAX);
        }
        if (Math.abs(gamma - 1) > 0.01 && (!under || limit > 1.01)) {
            double g0 = gamma;
            brightness(px, v -> 255 * Math.pow(v / 255d, g0), limit);
            int[] y4 = luma(img);
            steps.add(step("exposure", true, under ? "meanLuma" : "centreLuma", round(m * 255, 1), "gamma", round(gamma, 3),
                    "limits", List.of(GAMMA_MIN, GAMMA_MAX), "gainLimit", round(under ? UNDER_GAIN_MAX : 1, 2),
                    "after", round(under ? mean(y4) : centreLuma(y4, w, h), 1),
                    "method", "on the brightness only: red, green and blue scaled alike, so every colour keeps its proportions",
                    "reading", under ? "under-exposed (highlights " + f.assessment().highlights() + ", mean " + round(f.assessment().meanLuma(), 1) + ")"
                            : "over-exposed (" + round(f.assessment().centreClippedPct(), 1) + "% of the centre clipped)"));
        } else {
            steps.add(step("exposure", false, "meanLuma", round(mean(y3), 1), "highlights", f.assessment().highlights(), "reading",
                    !under && !over ? "within range" : over ? "the centre's highlights are clipped, but it is not bright enough to bring down"
                            : m <= 0.02 ? "under-exposed, too dark to bring up"
                            : m >= UNDER_TARGET ? "under-exposed; the levels brought it near mid-grey" : "under-exposed; the levels took all the gain allowed"));
        }

        // 5 · sharpening: an unsharp mask of radius one pixel, half strength, leaving differences of three levels or fewer alone
        unsharp(px, w, h);
        steps.add(step("sharpen", true, "method", "unsharp mask", "radius", 1, "amount", SHARPEN_AMOUNT, "threshold", SHARPEN_THRESHOLD));

        // 6 · written as a JPEG (no EXIF: it is upright already)
        float q = settings.quality();
        byte[] jpeg = jpeg(img, q);
        while (jpeg.length > MAX_ENHANCED_BYTES && q > 0.55f) {
            q -= 0.1f;
            jpeg = jpeg(img, q);
        }
        steps.add(step("encode", true, "format", "JPEG", "quality", round(q, 2), "bytes", jpeg.length, "width", w, "height", h));

        int[] y1 = luma(img);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("method", "Global corrections only: the whole photograph is adjusted alike — nothing is drawn, removed or retouched, and the "
                + "face is neither detected nor altered.");
        out.put("steps", steps);
        out.put("before", Map.of("meanLuma", round(meanBefore, 1), "lumaSpread", round(spreadBefore, 1), "centreLuma", round(centreBefore, 1)));
        out.put("after", Map.of("meanLuma", round(mean(y1), 1), "lumaSpread", round(spread(y1), 1), "centreLuma", round(centreLuma(y1, w, h), 1)));
        return new Enhanced(jpeg, w, h, f.assessment(), out, null);
    }

    /** the gains that make the mean of the sums given ({r, g, b, n}) grey */
    private static double[] greyWorld(double[] sums) {
        double grey = (sums[0] + sums[1] + sums[2]) / 3;
        return new double[] {grey / sums[0], grey / sums[1], grey / sums[2]};
    }

    /** each pixel's brightness (Rec. 601) taken through the curve, its red, green and blue scaled alike by the one factor — so every
     *  colour keeps its proportions (skin is never made more saturated, nor changes hue) — the factor no more than {@code maxGain}, nor
     *  past the point where the pixel's brightest channel would clip */
    static void brightness(int[] px, DoubleUnaryOperator curve, double maxGain) {
        for (int i = 0; i < px.length; i++) {
            int p = px[i], r = (p >> 16) & 0xFF, g = (p >> 8) & 0xFF, b = p & 0xFF;
            double y = 0.299 * r + 0.587 * g + 0.114 * b;
            if (y < 0.5) continue;
            double k = Math.min(maxGain, Math.max(0, curve.applyAsDouble(y)) / y);
            int most = Math.max(r, Math.max(g, b));
            if (most * k > 255) k = 255d / most;
            px[i] = (clampByte(r * k) << 16) | (clampByte(g * k) << 8) | clampByte(b * k);
        }
    }

    /* ── the raster helpers ────────────────────────────────────────────────────────────────────────────────────────────────── */

    static int[] pixels(BufferedImage img) {
        return ((DataBufferInt) img.getRaster().getDataBuffer()).getData();
    }

    /** a packed-RGB copy of its own (a sub-image shares its parent's pixels) */
    static BufferedImage copy(BufferedImage src) {
        BufferedImage out = new BufferedImage(src.getWidth(), src.getHeight(), BufferedImage.TYPE_INT_RGB);
        Graphics2D g = out.createGraphics();
        try {
            g.drawImage(src, 0, 0, null);
        } finally {
            g.dispose();
        }
        return out;
    }

    /** resized to w×h: halved with 2×2 area averages while it is at least twice the size, then bicubic the rest of the way */
    static BufferedImage resize(BufferedImage src, int w, int h) {
        BufferedImage cur = src.getType() == BufferedImage.TYPE_INT_RGB ? src : copy(src);
        while (cur.getWidth() >= 2 * w && cur.getHeight() >= 2 * h) {
            cur = halve(cur);
        }
        if (cur.getWidth() == w && cur.getHeight() == h) return cur == src ? copy(src) : cur;
        BufferedImage out = new BufferedImage(w, h, BufferedImage.TYPE_INT_RGB);
        Graphics2D g = out.createGraphics();
        try {
            g.setRenderingHint(RenderingHints.KEY_INTERPOLATION, RenderingHints.VALUE_INTERPOLATION_BICUBIC);
            g.setRenderingHint(RenderingHints.KEY_RENDERING, RenderingHints.VALUE_RENDER_QUALITY);
            g.drawImage(cur, 0, 0, w, h, null);
        } finally {
            g.dispose();
        }
        return out;
    }

    static BufferedImage halve(BufferedImage src) {
        int w = src.getWidth() / 2, h = src.getHeight() / 2, sw = src.getWidth();
        BufferedImage out = new BufferedImage(w, h, BufferedImage.TYPE_INT_RGB);
        int[] s = pixels(src), d = pixels(out);
        for (int y = 0; y < h; y++) {
            int r0 = 2 * y * sw, r1 = r0 + sw;
            for (int x = 0; x < w; x++) {
                int a = s[r0 + 2 * x], b = s[r0 + 2 * x + 1], c = s[r1 + 2 * x], e = s[r1 + 2 * x + 1];
                int r = (((a >> 16) & 0xFF) + ((b >> 16) & 0xFF) + ((c >> 16) & 0xFF) + ((e >> 16) & 0xFF) + 2) / 4;
                int g = (((a >> 8) & 0xFF) + ((b >> 8) & 0xFF) + ((c >> 8) & 0xFF) + ((e >> 8) & 0xFF) + 2) / 4;
                int bl = ((a & 0xFF) + (b & 0xFF) + (c & 0xFF) + (e & 0xFF) + 2) / 4;
                d[y * w + x] = (r << 16) | (g << 8) | bl;
            }
        }
        return out;
    }

    /** the brightness of each pixel (Rec. 601), 0–255 */
    static int[] luma(BufferedImage img) {
        BufferedImage rgb = img.getType() == BufferedImage.TYPE_INT_RGB && img.getRaster().getDataBuffer() instanceof DataBufferInt
                && img.getRaster().getSampleModelTranslateX() == 0 && img.getRaster().getSampleModelTranslateY() == 0 ? img : copy(img);
        int[] px = pixels(rgb), y = new int[px.length];
        for (int i = 0; i < px.length; i++) {
            int p = px[i];
            y[i] = (299 * ((p >> 16) & 0xFF) + 587 * ((p >> 8) & 0xFF) + 114 * (p & 0xFF)) / 1000;
        }
        return y;
    }

    static double mean(int[] v) {
        double s = 0;
        for (int x : v) s += x;
        return s / Math.max(1, v.length);
    }

    static double spread(int[] v) {
        double m = mean(v), s = 0;
        for (int x : v) s += (x - m) * (x - m);
        return Math.sqrt(s / Math.max(1, v.length));
    }

    /** the centre box, where a portrait's face is: the middle half across, from 15% to 70% down — {x0, x1, y0, y1}, the ends excluded */
    static int[] centreBox(int w, int h) {
        int x0 = w / 4, y0 = (int) (h * 0.15);
        return new int[] {x0, Math.min(w, Math.max(x0 + 1, 3 * w / 4)), y0, Math.min(h, Math.max(y0 + 1, (int) (h * 0.70)))};
    }

    /** the centre, read for the brightness and the clipped highlights: the middle quarter across, from 25% to 55% down — inside a
     *  portrait's face at any usual framing, so a white or bright backdrop is never read as the face's brightness — {x0, x1, y0, y1} */
    static int[] innerBox(int w, int h) {
        int x0 = 3 * w / 8, y0 = (int) (h * 0.25);
        return new int[] {x0, Math.min(w, Math.max(x0 + 1, 5 * w / 8)), y0, Math.min(h, Math.max(y0 + 1, (int) (h * 0.55)))};
    }

    /** the brightness of the centre ({@link #innerBox}) */
    static double centreLuma(int[] y, int w, int h) {
        int[] box = innerBox(w, h);
        double s = 0;
        long n = 0;
        for (int r = box[2]; r < box[3]; r++) {
            for (int c = box[0]; c < box[1]; c++) {
                s += y[r * w + c];
                n++;
            }
        }
        return n == 0 ? mean(y) : s / n;
    }

    /** the tint of the centre's mean colour ({@link #innerBox}; see {@link Background#tint}) */
    static double centreTint(int[] px, int w, int h) {
        int[] box = innerBox(w, h);
        double r = 0, g = 0, b = 0;
        long n = 0;
        for (int row = box[2]; row < box[3]; row++) {
            for (int c = box[0]; c < box[1]; c++) {
                int p = px[row * w + c];
                r += (p >> 16) & 0xFF;
                g += (p >> 8) & 0xFF;
                b += p & 0xFF;
                n++;
            }
        }
        return n == 0 ? 0 : tint(r / n, g / n, b / n);
    }

    /** the share of the centre's pixels ({@link #innerBox}) with a channel clipped — at 250 or above — in per cent */
    static double centreClippedPct(int[] px, int w, int h) {
        int[] box = innerBox(w, h);
        long n = 0, clipped = 0;
        for (int r = box[2]; r < box[3]; r++) {
            for (int c = box[0]; c < box[1]; c++) {
                int p = px[r * w + c];
                if (Math.max((p >> 16) & 0xFF, Math.max((p >> 8) & 0xFF, p & 0xFF)) >= 250) clipped++;
                n++;
            }
        }
        return n == 0 ? 0 : 100d * clipped / n;
    }

    /** the background's readings: its brightness and spread, and its mean red, green and blue */
    record Background(double brightness, double spread, double r, double g, double b) {

        /** how tinted it is, along the line a lamp or shade tints a light wall: its channels' range over its brightness, above 0 when
         *  warm (red over green over blue), below 0 when cool (blue over green over red), 0 for any other colour */
        double tint() {
            return PhotoEnhancer.tint(r, g, b);
        }
    }

    /** the background, above the shoulders only: the top band (8% of the shorter side deep) and the side strips of the same width down
     *  to 40% of the height — never the bottom strip or the lower sides, where a portrait's shoulders and clothes are, nor the head
     *  where a tight framing brings it into the top band ({@link #headInBand}) */
    static Background background(int[] px, int[] y, int w, int h) {
        int t = Math.max(1, (int) Math.round(Math.min(w, h) * BACKGROUND_BAND));
        int sidesTo = Math.min(h, Math.max(t, (int) Math.round(h * BACKGROUND_SIDES_TO)));
        boolean[] head = headInBand(y, w, h, t, sidesTo);
        double s = 0, sq = 0, sr = 0, sg = 0, sb = 0;
        long n = 0;
        for (int r = 0; r < sidesTo; r++) {
            for (int c = 0; c < w; c++) {
                if (r >= t && c >= t && c < w - t) continue;
                if (head != null && r < t && head[r * w + c]) continue;
                int i = r * w + c, v = y[i], p = px[i];
                s += v;
                sq += (double) v * v;
                sr += (p >> 16) & 0xFF;
                sg += (p >> 8) & 0xFF;
                sb += p & 0xFF;
                n++;
            }
        }
        double k = Math.max(1, n), m = s / k;
        return new Background(m, Math.sqrt(Math.max(0, sq / k - m * m)), sr / k, sg / k, sb / k);
    }

    /** the head where a tight framing brings it into the top band, and nothing that touches it there (a picture, a clock or a shelf
     *  hung above the head is the background, and may be busy). Pixels unlike the wall are further from the side strips' median
     *  brightness than {@link #HEAD_FROM_WALL}, or three times their spread. The head is traced up from the centre box's top edge, row
     *  by row: on that edge, the run of unlike pixels through the middle quarter (the hair or the head); in each row above, the unlike
     *  pixels within the columns the head held in the row below, and the run on from them to either side (gaps of a light strand
     *  bridged). A head narrows as it rises: where that run reaches more than {@link #HEAD_WIDEN} of the width past the head's
     *  outermost edge over the last {@link #HEAD_ROWS} rows, something else touches the head, and that side is carried on at the rate
     *  the head was narrowing in the rows below. Null when the head does not reach the band, or when on the edge it reaches a side
     *  strip (then the background itself is not plain) */
    static boolean[] headInBand(int[] y, int w, int h, int t, int sidesTo) {
        int[] hist = new int[256];
        double s = 0, sq = 0;
        int n = 0;
        for (int r = 0; r < sidesTo; r++) {
            for (int c = 0; c < w; c++) {
                if (c >= t && c < w - t) continue;
                int v = y[r * w + c];
                hist[v]++;
                s += v;
                sq += (double) v * v;
                n++;
            }
        }
        if (n == 0) return null;
        int wall = percentile(hist, n, 0.5);
        double m = s / n, tolerance = Math.max(HEAD_FROM_WALL, 3 * Math.sqrt(Math.max(0, sq / n - m * m)));
        int edge = centreBox(w, h)[2];
        if (edge < t || edge >= h) return null;
        int widen = Math.max(2, (int) Math.round(w * HEAD_WIDEN));
        // the head on the centre box's top edge: the unlike pixels through the middle quarter, and on from them to either side
        int a = -1, b = -1;
        for (int c = 3 * w / 8; c < 5 * w / 8; c++) {
            if (Math.abs(y[edge * w + c] - wall) > tolerance) {
                if (a < 0) a = c;
                b = c;
            }
        }
        if (a < 0) return null;
        a = reach(y, edge * w, a, -1, w, wall, tolerance, widen);
        b = reach(y, edge * w, b, 1, w, wall, tolerance, widen);
        if (a < t || b >= w - t) return null;
        boolean[] head = new boolean[t * w];
        boolean reachesBand = false;
        // the head's columns in the row below, its outermost edges over the last few rows (a light strand of hair at its edge may hide
        // it for a row or two), and how fast it narrowed
        double left = a, right = b, narrowLeft = -1, narrowRight = -1;
        double[] lefts = new double[HEAD_ROWS], rights = new double[HEAD_ROWS];
        Arrays.fill(lefts, a);
        Arrays.fill(rights, b);
        for (int r = edge - 1, k = 0; r >= 0 && left <= right; r--, k++) {
            int lo = (int) Math.ceil(left), hi = (int) Math.floor(right), row = r * w;
            int first = -1, last = -1;
            for (int c = lo; c <= hi; c++) {
                if (Math.abs(y[row + c] - wall) > tolerance) {
                    if (first < 0) first = c;
                    last = c;
                }
            }
            if (first < 0) break;                                              // above the head
            int outLeft = reach(y, row, first, -1, w, wall, tolerance, widen), outRight = reach(y, row, last, 1, w, wall, tolerance, widen);
            double edgeLeft = Arrays.stream(lefts).min().orElse(a), edgeRight = Arrays.stream(rights).max().orElse(b);
            // past the head's edge by more than it can widen in a row: something else touches it there
            boolean carriedLeft = outLeft < edgeLeft - widen, carriedRight = outRight > edgeRight + widen;
            double nextLeft = carriedLeft ? left + Math.max(0, narrowLeft) : outLeft;
            double nextRight = carriedRight ? right - Math.max(0, narrowRight) : outRight;
            // how fast the head narrows, from the rows where its own edge was seen (a short running mean)
            if (!carriedLeft) narrowLeft = narrowLeft < 0 ? Math.max(0, nextLeft - left) : 0.75 * narrowLeft + 0.25 * Math.max(0, nextLeft - left);
            if (!carriedRight) narrowRight = narrowRight < 0 ? Math.max(0, right - nextRight) : 0.75 * narrowRight + 0.25 * Math.max(0, right - nextRight);
            left = nextLeft;
            right = nextRight;
            lefts[k % HEAD_ROWS] = left;
            rights[k % HEAD_ROWS] = right;
            if (r < t) {
                for (int c = (int) Math.ceil(left); c <= (int) Math.floor(right); c++) {
                    if (Math.abs(y[row + c] - wall) > tolerance) {
                        head[row + c] = true;
                        reachesBand = true;
                    }
                }
            }
        }
        return reachesBand ? head : null;
    }

    /** the furthest column of a pixel unlike the wall reached along a row ({@code row}: its first index) from {@code from}, in the
     *  direction given, through gaps of no more than {@code gap} pixels like the wall */
    private static int reach(int[] y, int row, int from, int dir, int w, int wall, double tolerance, int gap) {
        int end = from, like = 0;
        for (int c = from + dir; c >= 0 && c < w; c += dir) {
            if (Math.abs(y[row + c] - wall) > tolerance) {
                end = c;
                like = 0;
            } else if (++like > gap) {
                break;
            }
        }
        return end;
    }

    /** the tint of a colour along the line a lamp or shade tints a light wall (see {@link Background#tint}) */
    static double tint(double r, double g, double b) {
        double y = 0.299 * r + 0.587 * g + 0.114 * b;
        if (y < 1) return 0;
        if (r >= g && g >= b) return (r - b) / y;
        if (b >= g && g >= r) return -(b - r) / y;
        return 0;
    }

    /** COLOUR_CAST: the background plain, lit and tinted warm or cool by at least {@link #CAST_MIN}; and either tinted well past a painted
     *  wall's own paint (at least {@link #CAST_WALL_WARM} warm or {@link #CAST_WALL_COOL} cool: a strong lamp or shade over a white or
     *  grey wall, or a strongly coloured backdrop — the flag's words say the background or the light is tinted, true of either), the
     *  side strips tinted the same way too ({@link #sidesTintedAs}: a lamp tints the whole wall, where a warm head-tie or hat reaching
     *  the top band of a passport framing colours that band alone; at a framing of 1.75 or tighter a wide gele can reach the side strips
     *  and still be told — advisory only, no pixel changed), or
     *  the rest of the frame tinted alike — for a wall painted cream, peach, light yellow or mid-blue in daylight cannot be told from a
     *  white wall under a lamp or in shade by the wall alone (the review's third round: every correctly lit portrait before such a wall
     *  was flagged; its fourth: a lamp on a white wall, tint 0.20 to 0.28, was then flagged only over a light kaftan). Confirmed by the
     *  centre (a portrait's face) with little warmth before a cool background or a great deal before a warm one — skin of every tone is
     *  warm, its tint 0.25 to 0.75 in daylight ({@link #CENTRE_WARMTH_MIN}, {@link #CENTRE_WARMTH_MAX}) — or by the lit, unsaturated
     *  pixels off the wall ({@link #offWallTint}: a white or grey shirt, a collar, a light kaftan, grey hair, and the clothes at the
     *  chest even where they take the wall's colour under its lamp) tinted as the background is, by at least {@link #CAST_MIN}. A mild
     *  cast only the wall shows is not flagged (dark clothes with no white at the chest, the face within its daylight range); nor is
     *  any cast corrected beyond the mild white balance. Advisory, and so the known misses go the way of doing less; the known false
     *  flags: a light-blue or other strongly coloured backdrop chosen as such (told that a white or light grey wall is best), a pale
     *  face over clothes with nothing white or grey before a warm-painted wall (its neck reads as tinted as the wall), a garment of a
     *  tinted wall's own colour at the chest, a face warmer than {@link #CENTRE_WARMTH_MAX} before a warm wall, a very pale face — or,
     *  at a very loose framing, the hair in the centre — before a blue one */
    /** whether the side strips of the background (below the top band, down to {@link #BACKGROUND_SIDES_TO} of the height) are tinted
     *  the way {@code t} is, by at least {@link #CAST_MIN} */
    static boolean sidesTintedAs(int[] px, int w, int h, double t) {
        int band = Math.max(1, (int) Math.round(Math.min(w, h) * BACKGROUND_BAND));
        int sidesTo = Math.min(h, Math.max(band, (int) Math.round(h * BACKGROUND_SIDES_TO)));
        double sr = 0, sg = 0, sb = 0;
        long n = 0;
        for (int r = band; r < sidesTo; r++) {
            for (int c = 0; c < w; c++) {
                if (c >= band && c < w - band) continue;
                int p = px[r * w + c];
                sr += (p >> 16) & 0xFF;
                sg += (p >> 8) & 0xFF;
                sb += p & 0xFF;
                n++;
            }
        }
        if (n == 0) return false;
        double sides = tint(sr / n, sg / n, sb / n);
        return Math.abs(sides) >= CAST_MIN && Math.signum(sides) == Math.signum(t);
    }

    static boolean colourCast(int[] px, int w, int h, Background bg) {
        double t = bg.tint();
        if (bg.spread() > BUSY_BACKGROUND_SPREAD || bg.brightness() < CAST_MIN_LUMA || Math.abs(t) < CAST_MIN) return false;
        // on the wall alone only when the side strips are tinted the same way too: a lamp or a shade tints the whole wall, where a
        // head-tie (gele) or a hat reaching the top band of a tight framing colours that band alone
        if ((t >= CAST_WALL_WARM || t <= CAST_WALL_COOL) && sidesTintedAs(px, w, h, t)) return true;
        double centre = centreTint(px, w, h);
        if (t < 0 ? centre < CENTRE_WARMTH_MIN : centre > CENTRE_WARMTH_MAX) return true;
        double off = offWallTint(px, w, h, bg);
        return Math.abs(off) >= CAST_MIN && Math.signum(off) == Math.signum(t);
    }

    /** the tint ({@link #tint}) of the lit, unsaturated pixels off the wall outside the face box — a white or grey shirt, a collar, a
     *  light kaftan, grey hair; NaN when they are fewer than {@link #NEUTRAL_MIN_SHARE} of the frame. Off the wall: not of its colour,
     *  or in the clothes' place ({@link #CLOTHES_BAND}: the bottom tenth, the middle third across), where a head-and-shoulders portrait
     *  shows the chest and never the wall — so a white shirt before a white wall under the same lamp, which takes the wall's colour, is
     *  read there (beside the shoulders the wall may show, and a pixel of its colour is left out) */
    static double offWallTint(int[] px, int w, int h, Background bg) {
        double match = WALL_MATCH + 2.5 * bg.spread();
        int[] box = centreBox(w, h);
        int clothesTop = h - Math.max(1, (int) Math.round(h * CLOTHES_BAND)), clothesLeft = w / 3, clothesRight = w - w / 3;
        double sr = 0, sg = 0, sb = 0;
        long n = 0;
        for (int r = 0; r < h; r++) {
            boolean rowInBox = r >= box[2] && r < box[3], rowInClothes = r >= clothesTop;
            for (int c = 0; c < w; c++) {
                if (rowInBox && c >= box[0] && c < box[1]) continue;
                int p = px[r * w + c];
                int red = (p >> 16) & 0xFF, g = (p >> 8) & 0xFF, b = p & 0xFF;
                boolean clothes = rowInClothes && c >= clothesLeft && c < clothesRight;
                if (!clothes && Math.abs(red - bg.r()) <= match && Math.abs(g - bg.g()) <= match && Math.abs(b - bg.b()) <= match) continue;
                double yv = 0.299 * red + 0.587 * g + 0.114 * b;
                int max = Math.max(red, Math.max(g, b)), min = Math.min(red, Math.min(g, b));
                if (yv < CAST_MIN_LUMA || max - min > CAST_OFF_WALL_CHROMA * yv) continue;
                sr += red;
                sg += g;
                sb += b;
                n++;
            }
        }
        return n < NEUTRAL_MIN_SHARE * px.length ? Double.NaN : tint(sr / n, sg / n, sb / n);
    }

    /** the histogram of each pixel's brightest channel (a saturated red is near white in its red channel, though dark in luma) */
    static int[] brightestChannel(int[] px) {
        int[] top = new int[256];
        for (int p : px) {
            top[Math.max((p >> 16) & 0xFF, Math.max((p >> 8) & 0xFF, p & 0xFF))]++;
        }
        return top;
    }

    /** under-exposed, judged from the whole frame: the highlights (the brightest channel's 99.9th percentile: the eye whites and the
     *  brightest of the skin count) under {@link #UNDER_HIGHLIGHT} and the mean brightness low — never the face's brightness, which is
     *  low for a correctly exposed dark face */
    static boolean underExposed(int highlights, double meanLuma) {
        return highlights < UNDER_HIGHLIGHT && meanLuma < UNDER_MEAN;
    }

    /** Immerkær's fast estimate of the noise's standard deviation (1996): the absolute response to a Laplacian-difference kernel */
    static double noise(int[] y, int w, int h) {
        if (w < 3 || h < 3) return 0;
        double s = 0;
        for (int r = 1; r < h - 1; r++) {
            for (int c = 1; c < w - 1; c++) {
                int i = r * w + c;
                int v = y[i - w - 1] - 2 * y[i - w] + y[i - w + 1] - 2 * y[i - 1] + 4 * y[i] - 2 * y[i + 1] + y[i + w - 1] - 2 * y[i + w] + y[i + w + 1];
                s += Math.abs(v);
            }
        }
        return s * Math.sqrt(Math.PI / 2) / (6d * (w - 2) * (h - 2));
    }

    /** the variance of the 4-neighbour Laplacian: how much fine detail the photograph holds */
    static double laplacianVariance(int[] y, int w, int h) {
        if (w < 3 || h < 3) return 0;
        double s = 0, sq = 0;
        long n = 0;
        for (int r = 1; r < h - 1; r++) {
            for (int c = 1; c < w - 1; c++) {
                int i = r * w + c;
                int v = y[i - w] + y[i + w] + y[i - 1] + y[i + 1] - 4 * y[i];
                s += v;
                sq += (double) v * v;
                n++;
            }
        }
        double m = s / n;
        return sq / n - m * m;
    }

    static int percentile(int[] hist, int total, double p) {
        long want = (long) Math.ceil(total * p), seen = 0;
        for (int v = 0; v < 256; v++) {
            seen += hist[v];
            if (seen >= Math.max(1, want)) return v;
        }
        return 255;
    }

    private static void apply(int[] px, int[] r, int[] g, int[] b) {
        for (int i = 0; i < px.length; i++) {
            int p = px[i];
            px[i] = (r[(p >> 16) & 0xFF] << 16) | (g[(p >> 8) & 0xFF] << 8) | b[p & 0xFF];
        }
    }

    /** half each pixel, half the median of its 3×3 neighbourhood, channel by channel (the edge pixels kept) */
    static void denoise(int[] px, int w, int h) {
        int[] src = Arrays.copyOf(px, px.length);
        int[] win = new int[9];
        for (int r = 1; r < h - 1; r++) {
            for (int c = 1; c < w - 1; c++) {
                int i = r * w + c, out = 0;
                for (int shift = 16; shift >= 0; shift -= 8) {
                    int k = 0;
                    for (int dy = -1; dy <= 1; dy++) for (int dx = -1; dx <= 1; dx++) win[k++] = (src[i + dy * w + dx] >> shift) & 0xFF;
                    Arrays.sort(win);
                    int v = (((src[i] >> shift) & 0xFF) + win[4] + 1) / 2;
                    out |= v << shift;
                }
                px[i] = out;
            }
        }
    }

    /** the unsharp mask: each channel plus half its difference from a 3×3 Gaussian blur, where the difference passes the threshold */
    static void unsharp(int[] px, int w, int h) {
        int[] src = Arrays.copyOf(px, px.length);
        for (int r = 1; r < h - 1; r++) {
            for (int c = 1; c < w - 1; c++) {
                int i = r * w + c, out = 0;
                for (int shift = 16; shift >= 0; shift -= 8) {
                    int v = (src[i] >> shift) & 0xFF;
                    int blur = (((src[i - w - 1] >> shift) & 0xFF) + 2 * ((src[i - w] >> shift) & 0xFF) + ((src[i - w + 1] >> shift) & 0xFF)
                            + 2 * ((src[i - 1] >> shift) & 0xFF) + 4 * v + 2 * ((src[i + 1] >> shift) & 0xFF)
                            + ((src[i + w - 1] >> shift) & 0xFF) + 2 * ((src[i + w] >> shift) & 0xFF) + ((src[i + w + 1] >> shift) & 0xFF) + 8) / 16;
                    int diff = v - blur;
                    out |= (Math.abs(diff) > SHARPEN_THRESHOLD ? clampByte(v + SHARPEN_AMOUNT * diff) : v) << shift;
                }
                px[i] = out;
            }
        }
    }

    /** a JPEG at the quality given, through ImageWriteParam (the JDK's writer defaults to 0.75 otherwise) */
    static byte[] jpeg(BufferedImage img, float quality) {
        Iterator<ImageWriter> writers = ImageIO.getImageWritersByFormatName("jpeg");
        if (!writers.hasNext()) throw new IllegalStateException("the JDK's JPEG writer is missing");
        ImageWriter writer = writers.next();
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        try (ImageOutputStream ios = new MemoryCacheImageOutputStream(out)) {
            writer.setOutput(ios);
            ImageWriteParam p = writer.getDefaultWriteParam();
            p.setCompressionMode(ImageWriteParam.MODE_EXPLICIT);
            p.setCompressionQuality(quality);
            writer.write(null, new IIOImage(img, null, null), p);
        } catch (IOException e) {
            throw new IllegalStateException("the JPEG could not be written: " + e.getMessage(), e);
        } finally {
            writer.dispose();
        }
        return out.toByteArray();
    }

    /** an image as a JPEG on white, whatever it was stored as (a JPEG passes through): the staff card's PDF embeds JPEG only. Read as
     *  safely as an upload: only a PNG is decoded (anything else that is not a JPEG is served as stored), its width and height read
     *  from the header first and one past {@link #DEFAULT_MAX_PIXELS} served as stored, never decoded (a PNG of a few hundred
     *  kilobytes can declare 20,000 × 20,000 pixels — gigabytes once decoded); one past {@link #DECODE_BUDGET_PIXELS} decoded at a
     *  fraction of its size (the card prints at most 600×750); and the work done in one of the two slots an upload takes, the image
     *  served as stored when no slot comes within {@link #TOJPEG_SLOT_WAIT_MILLIS} milliseconds — its callers read the photograph in a
     *  read-only transaction, so it never holds their database connection long. Never throws: what cannot be turned is served as it
     *  is rather than nothing. */
    public static byte[] toJpeg(byte[] img, float quality) {
        if (img == null || img.length < 2 || !"image/png".equals(sniff(img))) return img;
        if (!slot(TOJPEG_SLOT_WAIT_MILLIS, TimeUnit.MILLISECONDS)) return img;
        try {
            return pngToJpeg(img, quality);
        } finally {
            SLOTS.release();
        }
    }

    private static byte[] pngToJpeg(byte[] img, float quality) {
        Iterator<ImageReader> readers = ImageIO.getImageReadersByFormatName("png");
        if (!readers.hasNext()) return img;
        ImageReader reader = readers.next();
        try (ImageInputStream in = new MemoryCacheImageInputStream(new ByteArrayInputStream(img))) {
            reader.setInput(in, true, true);
            // the size from the header, before a pixel is read
            int w = reader.getWidth(0), h = reader.getHeight(0);
            if (w <= 0 || h <= 0 || (long) w * h > DEFAULT_MAX_PIXELS) return img;
            int sub = subsampling(w, h);
            ImageReadParam param = reader.getDefaultReadParam();
            if (sub > 1) param.setSourceSubsampling(sub, sub, 0, 0);
            BufferedImage src = reader.read(0, param);
            return src == null ? img : jpeg(onWhite(src), quality);
        } catch (IOException | RuntimeException e) {
            return img;   // not decodable: served as it is rather than nothing
        } finally {
            reader.dispose();
        }
    }

    private static Map<String, Object> step(String name, boolean applied, Object... kv) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("step", name);
        m.put("applied", applied);
        for (int i = 0; i + 1 < kv.length; i += 2) m.put(String.valueOf(kv[i]), kv[i + 1]);
        return m;
    }

    private static double clamp(double v, double lo, double hi) {
        return Math.max(lo, Math.min(hi, v));
    }

    private static int clampByte(double v) {
        return (int) Math.max(0, Math.min(255, Math.round(v)));
    }

    static double round(double v, int places) {
        if (Double.isNaN(v) || Double.isInfinite(v)) return 0;   // never a NaN into the record's JSON
        double k = Math.pow(10, places);
        return Math.round(v * k) / k;
    }
}
