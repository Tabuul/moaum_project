package ng.edu.moaum.portal.shared;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.catchThrowable;

import java.awt.image.BufferedImage;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.List;
import java.util.Random;
import java.util.zip.CRC32;
import java.util.zip.Deflater;

import javax.imageio.IIOImage;
import javax.imageio.ImageIO;
import javax.imageio.ImageTypeSpecifier;
import javax.imageio.ImageWriteParam;
import javax.imageio.ImageWriter;
import javax.imageio.metadata.IIOMetadata;
import javax.imageio.metadata.IIOMetadataNode;
import javax.imageio.stream.ImageOutputStream;
import javax.imageio.stream.MemoryCacheImageOutputStream;

import org.junit.jupiter.api.Test;

/**
 * V749: the staff photograph's assessment and enhancement, on photographs made up here — a dark one comes out brighter, a flat one
 * with a wider spread, a colour cast is reduced, a JPEG whose EXIF says it was taken turned comes out upright, a tiny one is to be
 * replaced, a PNG declaring an enormous canvas is refused before a pixel is decoded, a PNG's transparency comes out white, and a
 * damaged, a print (CMYK) or a non-image file is refused in words. The review of V749: a face's colour never follows the backdrop or
 * the clothes, correctly exposed dark skin is neither brightened nor called too dark, a good portrait comes out nearly unchanged,
 * the background is read above the shoulders, a truncated JPEG and a large progressive one are refused, and a stored PNG is turned
 * into the card's JPEG as safely as an upload is read. Its second round: no stray bytes hide a large progressive JPEG's frame, the
 * reader's warnings that lose nothing are read and those that mean lost data refused, a high-key or a low-key portrait keeps its face,
 * a pale wall never moves the face and a real cast is flagged (COLOUR_CAST), toJpeg waits no more than two seconds for a slot, a white
 * backdrop is not too bright and hair in the top band is not a busy background. Its third round: an under-exposed reading lifts the
 * face by no more than a tenth (a correctly exposed dark face can read so), a large JPEG stored in several scans is refused on its
 * header, a harmless header warning never hides damaged image data, a painted wall in daylight is not a cast, and a picture touching a
 * tightly framed head is still a busy background. Its fourth round: a header of many groups of stray bytes is refused before it is
 * read and what was put right is named once, a lamp on a white wall is flagged again (and a backdrop tinted well past a painted wall
 * is told on the wall alone), a painted wall in daylight still not. No database, no Spring.
 */
class PhotoEnhancerTest {

    private final PhotoEnhancer enhancer = new PhotoEnhancer(PhotoEnhancer.Settings.defaults());

    /** a made-up portrait-shaped photograph: each pixel a base colour, plus texture (stripes and grain) so it has detail to read */
    private static BufferedImage picture(int w, int h, int r, int g, int b, int texture, long seed) {
        Random random = new Random(seed);
        BufferedImage img = new BufferedImage(w, h, BufferedImage.TYPE_INT_RGB);
        for (int y = 0; y < h; y++) {
            for (int x = 0; x < w; x++) {
                int t = ((x / 6 + y / 9) % 2 == 0 ? texture : 0) + random.nextInt(texture / 2 + 1);
                img.setRGB(x, y, (clamp(r + t) << 16) | (clamp(g + t) << 8) | clamp(b + t));
            }
        }
        return img;
    }

    private static int clamp(int v) {
        return Math.max(0, Math.min(255, v));
    }

    private static byte[] write(BufferedImage img, String format) throws Exception {
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        assertThat(ImageIO.write(img, format, out)).isTrue();
        return out.toByteArray();
    }

    private static BufferedImage read(byte[] bytes) throws Exception {
        return ImageIO.read(new ByteArrayInputStream(bytes));
    }

    /** the mean of each channel and of the brightness: {r, g, b, luma} */
    private static double[] means(BufferedImage img) {
        double r = 0, g = 0, b = 0;
        int n = img.getWidth() * img.getHeight();
        for (int y = 0; y < img.getHeight(); y++) {
            for (int x = 0; x < img.getWidth(); x++) {
                int p = img.getRGB(x, y);
                r += (p >> 16) & 0xFF;
                g += (p >> 8) & 0xFF;
                b += p & 0xFF;
            }
        }
        r /= n;
        g /= n;
        b /= n;
        return new double[] {r, g, b, 0.299 * r + 0.587 * g + 0.114 * b};
    }

    private static double lumaSpread(BufferedImage img) {
        int[] y = PhotoEnhancer.luma(PhotoEnhancer.copy(img));
        return PhotoEnhancer.spread(y);
    }

    @Test
    void aDarkPhotographComesOutBrighter() throws Exception {
        byte[] in = write(picture(600, 750, 18, 20, 22, 24, 1), "jpg");
        double before = means(read(in))[3];
        PhotoEnhancer.Enhanced e = enhancer.enhance(in);
        assertThat(e.error()).isNull();
        assertThat(e.width()).isEqualTo(600);
        assertThat(e.height()).isEqualTo(750);
        assertThat(e.assessment().flags()).contains("TOO_DARK");
        assertThat(e.assessment().quality()).isNotEqualTo("REPLACE");
        BufferedImage out = read(e.jpeg());
        assertThat(out.getWidth()).isEqualTo(600);
        assertThat(out.getHeight()).isEqualTo(750);
        // lifted, but by no more than a tenth: the histogram cannot tell an under-exposed frame from a correctly exposed dark face on a
        // dark wall, so TOO_DARK asks for a retake and the lift is small (the review's third round; the second round's test asked for
        // 30 levels more, which the same rule gave a correctly exposed dark face)
        double after = means(out)[3];
        assertThat(after).as("mean brightness %s -> %s", before, after).isBetween(before * 1.05, before * 1.12);
        // the record says what was done, with its numbers
        assertThat(e.enhancement()).containsKeys("method", "steps", "before", "after");
        assertThat(String.valueOf(e.enhancement().get("steps"))).contains("exposure").contains("levels").contains("sharpen");
    }

    @Test
    void aFlatPhotographComesOutWithAWiderSpread() throws Exception {
        byte[] in = write(picture(600, 750, 118, 120, 116, 20, 2), "jpg");
        double before = lumaSpread(read(in));
        PhotoEnhancer.Enhanced e = enhancer.enhance(in);
        assertThat(e.assessment().flags()).contains("LOW_CONTRAST");
        double after = lumaSpread(read(e.jpeg()));
        assertThat(after).as("spread %s -> %s", before, after).isGreaterThan(before * 1.4);
    }

    @Test
    void aColourCastIsReduced() throws Exception {
        // a mild blue cast over a grey scene with a full range of brightness: blue 8% above red throughout. (V749 review: the cast
        // the white balance corrects is a few per cent, read from near-neutral pixels — a strong blue throughout reads as a blue
        // backdrop, which is left as it is; see theFacesColourNeverFollowsTheBackdropOrTheClothes.)
        BufferedImage img = new BufferedImage(600, 750, BufferedImage.TYPE_INT_RGB);
        Random random = new Random(3);
        for (int y = 0; y < 750; y++) {
            for (int x = 0; x < 600; x++) {
                int v = 30 + (y * 180 / 750) + random.nextInt(12) + ((x / 8) % 2 == 0 ? 10 : 0);
                img.setRGB(x, y, (clamp((int) Math.round(v * 0.97)) << 16) | (clamp(v) << 8) | clamp((int) Math.round(v * 1.05)));
            }
        }
        byte[] in = write(img, "jpg");
        double[] before = means(read(in));
        PhotoEnhancer.Enhanced e = enhancer.enhance(in);
        double[] after = means(read(e.jpeg()));
        double castBefore = Math.abs(Math.log(before[2] / before[0])), castAfter = Math.abs(Math.log(after[2] / after[0]));
        assertThat(castAfter).as("blue to red %s -> %s", castBefore, castAfter).isLessThan(castBefore * 0.6);
        assertThat(String.valueOf(e.enhancement().get("steps"))).contains("whiteBalance").contains("grey world");
    }

    /* ── portraits made up here: the face's colour and brightness, the backdrop, the clothes ──────────────────────────────── */

    private static final int[] MEDIUM_SKIN = {165, 118, 88}, DARK_SKIN = {104, 68, 50}, DARKER_SKIN = {78, 50, 37}, LIGHT_SKIN = {226, 182, 152};
    private static final int[] RED = {200, 30, 35}, BLUE = {60, 110, 190}, WHITE = {250, 250, 250}, GREY_WALL = {150, 150, 150},
            LIGHT_BLUE_WALL = {163, 198, 233}, WHITE_WALL = {245, 245, 245}, LIGHT_GREY_WALL = {210, 210, 210};
    private static final int[] BLACK_SUIT = {12, 12, 14}, NAVY = {30, 40, 80}, DARK_SUIT = {35, 35, 45}, WHITE_SHIRT = {230, 230, 230};
    // the second round's: a light kaftan, grey hair, a dark grey wall, a pale-blue and a beige wall, a pure-white backdrop
    private static final int[] KAFTAN = {236, 234, 228}, DARK_HAIR = {30, 24, 20}, GREY_HAIR = {175, 172, 168}, DARK_GREY_WALL = {85, 85, 85},
            PALE_BLUE_WALL = {216, 226, 236}, BEIGE_WALL = {234, 228, 216}, PURE_WHITE = {252, 252, 252}, OFF_WHITE_WALL = {232, 232, 230};

    /** a made-up head-and-shoulders portrait of the card's own size, 600 × 750 (so nothing is cut or resized): a backdrop, clothes
     *  over the shoulders, the neck, dark hair, a shaded face with eyes, brows and a mouth, and a little grain; framing 1 is a loose
     *  passport framing, 1.35 a tight one; every pixel times gain (0.4: under-exposed) */
    private static BufferedImage portrait(int[] backdrop, int[] skin, int[] clothes, double framing, double gain) {
        return portrait(backdrop, skin, clothes, DARK_HAIR, framing, new double[] {gain, gain, gain});
    }

    /** the same portrait with the hair given (the skin's own colour: bald) and each channel times its own factor (a lamp's warm cast,
     *  a shade's cool one) */
    private static BufferedImage portrait(int[] backdrop, int[] skin, int[] clothes, int[] hair, double framing, double[] cast) {
        Random random = new Random(12);
        BufferedImage img = new BufferedImage(600, 750, BufferedImage.TYPE_INT_RGB);
        for (int y = 0; y < 750; y++) {
            for (int x = 0; x < 600; x++) {
                double fx = 0.5 + (x / 600d - 0.5) / framing, fy = 0.42 + (y / 750d - 0.42) / framing;
                int[] c = backdrop;
                if (fy > 0.70 && Math.abs(fx - 0.5) < 0.12 + (fy - 0.70) * 2.2) c = clothes;
                if (fy > 0.55 && fy < 0.74 && Math.abs(fx - 0.5) < 0.07) c = times(skin, 0.85);
                double hx = (fx - 0.5) / 0.21, hy = (fy - 0.30) / 0.17;
                if (hx * hx + hy * hy < 1) c = hair;
                double ex = (fx - 0.5) / 0.18, ey = (fy - 0.40) / 0.22;
                if (ex * ex + ey * ey < 1) c = times(skin, 1.05 - 0.2 * (ex * ex + ey * ey));
                for (double cx : new double[] {0.43, 0.57}) {
                    double ax = (fx - cx) / 0.035, ay = (fy - 0.38) / 0.014;
                    if (ax * ax + ay * ay < 1) c = new int[] {235, 230, 225};
                    ax = (fx - cx) / 0.014;
                    ay = (fy - 0.38) / 0.012;
                    if (ax * ax + ay * ay < 1) c = new int[] {25, 18, 14};
                    if (Math.abs(fx - cx) < 0.04 && Math.abs(fy - 0.355) < 0.005) c = new int[] {25, 20, 18};
                }
                double mx = (fx - 0.5) / 0.05, my = (fy - 0.50) / 0.010;
                if (mx * mx + my * my < 1) c = new int[] {(int) (skin[0] * 0.75), (int) (skin[1] * 0.5), (int) (skin[2] * 0.5)};
                int r = clamp((int) Math.round((c[0] + random.nextGaussian() * 3) * cast[0]));
                int g = clamp((int) Math.round((c[1] + random.nextGaussian() * 3) * cast[1]));
                int b = clamp((int) Math.round((c[2] + random.nextGaussian() * 3) * cast[2]));
                img.setRGB(x, y, (r << 16) | (g << 8) | b);
            }
        }
        return img;
    }

    private static int[] times(int[] c, double k) {
        return new int[] {(int) (c[0] * k), (int) (c[1] * k), (int) (c[2] * k)};
    }

    /** the spots read: the forehead and the cheek (where the framing puts them), a top corner of the backdrop, the clothes */
    private static double[][] spots(double framing) {
        return new double[][] {{0.5, 0.42 + (0.25 - 0.42) * framing}, {0.5 + (0.40 - 0.5) * framing, 0.42 + (0.45 - 0.42) * framing},
                {0.05, 0.08}, {0.5, 0.97}};
    }

    /** the mean {r, g, b, luma} of the 17 × 17 pixels around a spot (given as shares of the width and the height) */
    private static double[] patch(BufferedImage img, double[] spot) {
        int cx = (int) (spot[0] * img.getWidth()), cy = (int) (spot[1] * img.getHeight());
        double r = 0, g = 0, b = 0;
        for (int y = cy - 8; y <= cy + 8; y++) {
            for (int x = cx - 8; x <= cx + 8; x++) {
                int p = img.getRGB(x, y);
                r += (p >> 16) & 0xFF;
                g += (p >> 8) & 0xFF;
                b += p & 0xFF;
            }
        }
        r /= 289;
        g /= 289;
        b /= 289;
        return new double[] {r, g, b, 0.299 * r + 0.587 * g + 0.114 * b};
    }

    private static String rgb(double[] p) {
        return String.format("(%.0f, %.0f, %.0f) luma %.1f", p[0], p[1], p[2], p[3]);
    }

    /** a portrait through the enhancer: {before, after} at each of the four spots */
    private record Run(PhotoEnhancer.Enhanced enhanced, double[][] before, double[][] after) {
    }

    private Run run(BufferedImage portrait, double framing) throws Exception {
        byte[] in = PhotoEnhancer.jpeg(portrait, 0.95f);
        BufferedImage original = read(in);
        PhotoEnhancer.Enhanced e = enhancer.enhance(in);
        assertThat(e.error()).isNull();
        BufferedImage out = read(e.jpeg());
        double[][] at = spots(framing), before = new double[4][], after = new double[4][];
        for (int i = 0; i < 4; i++) {
            before[i] = patch(original, at[i]);
            after[i] = patch(out, at[i]);
        }
        return new Run(e, before, after);
    }

    @Test
    void theFacesColourNeverFollowsTheBackdropOrTheClothes() throws Exception {
        // the V749 review: grey world over every pixel turned brown skin olive on a red backdrop, orange on a blue one, and a white
        // backdrop cyan over a black suit or cream over a navy shirt. Now: the face keeps its proportions of red, green and blue within
        // 3% and its brightness within 3 levels; a white backdrop stays white (its channels within 3 levels of each other) and a
        // coloured one keeps its colour
        Object[][] scenes = {{"red backdrop, dark suit", RED, DARK_SUIT}, {"blue backdrop, dark suit", BLUE, DARK_SUIT},
                {"white backdrop, black suit", WHITE, BLACK_SUIT}, {"white backdrop, navy shirt", WHITE, NAVY}};
        for (Object[] scene : scenes) {
            for (int[] skin : List.of(MEDIUM_SKIN, DARK_SKIN)) {
                int[] backdrop = (int[]) scene[1];
                Run run = run(portrait(backdrop, skin, (int[]) scene[2], 1, 1), 1);
                String what = scene[0] + ", skin " + Arrays.toString(skin);
                for (int i = 0; i < 2; i++) {
                    double[] b = run.before()[i], a = run.after()[i];
                    String said = what + (i == 0 ? ", forehead " : ", cheek ") + rgb(b) + " -> " + rgb(a);
                    assertThat(a[0] / a[1] / (b[0] / b[1])).as("R/G: " + said).isBetween(0.97, 1.03);
                    assertThat(a[1] / a[2] / (b[1] / b[2])).as("G/B: " + said).isBetween(0.97, 1.03);
                    assertThat(Math.abs(a[3] - b[3])).as("luma: " + said).isLessThanOrEqualTo(3);
                }
                double[] b = run.before()[2], a = run.after()[2];
                String said = what + ", backdrop " + rgb(b) + " -> " + rgb(a);
                for (int c = 0; c < 3; c++) assertThat(Math.abs(a[c] - b[c])).as(said).isLessThanOrEqualTo(3);
                if (backdrop == WHITE) {
                    assertThat(Math.max(a[0], Math.max(a[1], a[2])) - Math.min(a[0], Math.min(a[1], a[2]))).as("neutral: " + said).isLessThanOrEqualTo(3);
                }
            }
        }
    }

    @Test
    void aWellExposedPortraitOnANeutralWallComesOutNearlyUnchanged() throws Exception {
        for (int[] wall : List.of(GREY_WALL, LIGHT_GREY_WALL)) {
            for (int[] clothes : List.of(DARK_SUIT, WHITE_SHIRT)) {
                Run run = run(portrait(wall, MEDIUM_SKIN, clothes, 1, 1), 1);
                for (int i = 0; i < 4; i++) {
                    String said = "wall " + Arrays.toString(wall) + ", clothes " + Arrays.toString(clothes) + ", spot " + i + " "
                            + rgb(run.before()[i]) + " -> " + rgb(run.after()[i]);
                    for (int c = 0; c < 3; c++) assertThat(Math.abs(run.after()[i][c] - run.before()[i][c])).as(said).isLessThanOrEqualTo(3);
                }
                assertThat(run.enhanced().assessment().quality()).as("%s", run.enhanced().assessment().flags()).isEqualTo("GOOD");
                String steps = String.valueOf(run.enhanced().enhancement().get("steps"));
                assertThat(steps).contains("step=whiteBalance, applied=false").contains("step=levels, applied=false")
                        .contains("step=exposure, applied=false");
            }
        }
    }

    @Test
    void correctlyExposedDarkSkinIsNeitherBrightenedNorFlaggedTooDark() throws Exception {
        // the V749 review: the exposure was read at the face box, so a dark face on a grey, light-blue or white wall was lightened by
        // 30 to 45 levels and told "too dark". Now it is judged from the whole frame's histogram: tight framing, the face fills the
        // centre, and the face keeps its brightness within 3 levels
        for (int[] wall : List.of(GREY_WALL, LIGHT_BLUE_WALL, WHITE_WALL)) {
            for (int[] skin : List.of(DARKER_SKIN, DARK_SKIN)) {
                Run run = run(portrait(wall, skin, DARK_SUIT, 1.35, 1), 1.35);
                PhotoEnhancer.Assessment a = run.enhanced().assessment();
                String what = "wall " + Arrays.toString(wall) + ", skin " + Arrays.toString(skin) + ", centre " + Math.round(a.centreLuma())
                        + ", highlights " + a.highlights() + ", mean " + Math.round(a.meanLuma());
                assertThat(a.flags()).as(what).doesNotContain("TOO_DARK");
                assertThat(a.underExposed()).as(what).isFalse();
                for (int i = 0; i < 2; i++) {
                    assertThat(Math.abs(run.after()[i][3] - run.before()[i][3])).as(what + ": " + rgb(run.before()[i]) + " -> " + rgb(run.after()[i]))
                            .isLessThanOrEqualTo(3);
                }
                assertThat(String.valueOf(run.enhanced().enhancement().get("steps"))).contains("step=exposure, applied=false");
            }
        }
    }

    @Test
    void aGenuinelyUnderExposedPhotographIsFlaggedAndLiftedModestly() throws Exception {
        // the same portraits with every pixel at 0.4 of its value: the highlights well below white and the mean low — TOO_DARK, the
        // holder told to retake in better light, and the face lifted by a tenth (the second round's test asked for half as much again,
        // which the same reading gave a correctly exposed dark face on a dark wall: see the test after this one)
        Object[][] scenes = {{WHITE_WALL, DARK_SKIN, WHITE_SHIRT, 1.0}, {GREY_WALL, DARKER_SKIN, DARK_SUIT, 1.35}, {WHITE_WALL, MEDIUM_SKIN, NAVY, 1.0}};
        for (Object[] scene : scenes) {
            double framing = (double) scene[3];
            Run run = run(portrait((int[]) scene[0], (int[]) scene[1], (int[]) scene[2], framing, 0.4), framing);
            PhotoEnhancer.Assessment a = run.enhanced().assessment();
            String what = "skin " + Arrays.toString((int[]) scene[1]) + " at 0.4, highlights " + a.highlights() + ", mean " + Math.round(a.meanLuma());
            assertThat(a.flags()).as(what).contains("TOO_DARK");
            assertThat(a.quality()).as(what).isEqualTo("FAIR");
            assertThat(a.underExposed()).as(what).isTrue();
            for (int i = 0; i < 2; i++) {
                assertThat(run.after()[i][3] / run.before()[i][3]).as(what + ": " + rgb(run.before()[i]) + " -> " + rgb(run.after()[i]))
                        .isBetween(1.05, 1.12);
            }
            assertThat(String.valueOf(run.enhanced().enhancement().get("steps"))).contains("step=levels, applied=true").contains("under-exposed")
                    .contains("stretch=1.1,");
        }
    }

    @Test
    void correctlyExposedDarkSkinReadAsUnderExposedMovesNoMoreThanTenLevels() throws Exception {
        // the review's third round: at a framing a little looser than a passport's, the eye whites fall under a thousandth of the frame
        // and the highlights onto the skin, so a correctly exposed dark face on a dark wall in dark clothes reads under-exposed — and was
        // lightened by 48 to 97 levels. The histogram cannot tell it from an under-exposed frame: it may be called too dark (advisory),
        // but the face moves by no more than 10 levels
        int[] reviewDark = {107, 70, 52};
        int under = 0;
        for (int wall : new int[] {85, 60, 40}) {
            for (int[] skin : List.of(reviewDark, DARKER_SKIN)) {
                for (double framing : new double[] {0.55, 0.6, 0.8, 1.0}) {
                    Run run = run(portrait(new int[] {wall, wall, wall}, skin, BLACK_SUIT, framing, 1), framing);
                    PhotoEnhancer.Assessment a = run.enhanced().assessment();
                    String what = "wall " + wall + ", skin " + Arrays.toString(skin) + ", framing " + framing + ", highlights " + a.highlights()
                            + ", mean " + Math.round(a.meanLuma()) + ", " + a.flags();
                    if (a.underExposed()) under++;
                    assertThat(a.quality()).as(what).isNotEqualTo("REPLACE");
                    for (int i = 0; i < 2; i++) {
                        assertThat(run.after()[i][3] - run.before()[i][3]).as(what + ": " + rgb(run.before()[i]) + " -> " + rgb(run.after()[i]))
                                .isBetween(-3.0, 10.0);
                    }
                    assertFaceKept(run, what, 0.02, 10);
                }
            }
        }
        assertThat(under).as("the cases read as under-exposed (the eye whites under a thousandth of the frame)").isGreaterThanOrEqualTo(6);
    }

    @Test
    void theBackgroundIsReadAboveTheShouldersOnly() throws Exception {
        // a plain white backdrop over a navy shirt or a black suit is plain: the shoulders are not the background
        for (int[] clothes : List.of(NAVY, BLACK_SUIT)) {
            for (int[] skin : List.of(MEDIUM_SKIN, DARK_SKIN)) {
                PhotoEnhancer.Assessment a = enhancer.assess(PhotoEnhancer.jpeg(portrait(WHITE, skin, clothes, 1, 1), 0.95f));
                assertThat(a.flags()).as("clothes %s, spread %s", Arrays.toString(clothes), a.backgroundSpread()).doesNotContain("BUSY_BACKGROUND");
                assertThat(a.backgroundSpread()).isLessThan(10);
            }
        }
        // a cluttered wall behind the head (dark and light bars across the top) still reads busy
        BufferedImage cluttered = portrait(WHITE, DARK_SKIN, NAVY, 1, 1);
        for (int y = 0; y < 60; y++) {
            for (int x = 0; x < 600; x++) {
                if ((x / 25) % 2 == 0) cluttered.setRGB(x, y, (40 << 16) | (35 << 8) | 30);
            }
        }
        PhotoEnhancer.Assessment busy = enhancer.assess(PhotoEnhancer.jpeg(cluttered, 0.95f));
        assertThat(busy.flags()).as("spread %s", busy.backgroundSpread()).contains("BUSY_BACKGROUND");
        assertThat(busy.toMap().get("background").toString()).contains("above the shoulders");
    }

    @Test
    void aTruncatedJpegIsRefusedAsDamaged() throws Exception {
        // an interrupted upload: the reader decodes what it has and fills the rest flat grey, with only a warning
        byte[] whole = PhotoEnhancer.jpeg(portrait(GREY_WALL, DARK_SKIN, DARK_SUIT, 1, 1), 0.9f);
        assertThat(enhancer.enhance(whole).assessment().decodeWarnings()).isEmpty();
        for (double kept : new double[] {0.45, 0.90}) {
            assertThat(refusal(Arrays.copyOf(whole, (int) (whole.length * kept)), enhancer)).as("the first %s", kept).isEqualTo("PHOTO_CORRUPT");
        }
        // with no end-of-image marker after the image data, it is refused before it is decoded (the review's second round: a 39 MP
        // file with only its end marker dropped took 0.5 to 0.7 s of a slot before it was refused); every byte of the image present
        byte[] noEnd = Arrays.copyOf(whole, whole.length - 2);
        assertThat(PhotoEnhancer.endOfImage(noEnd)).isEqualTo(-1);
        assertThat(PhotoEnhancer.endOfImage(whole)).isEqualTo(whole.length - 2);
        assertThat(refusal(noEnd, enhancer)).isEqualTo("PHOTO_CORRUPT");
        // bytes left over between the last of the image data and the end marker lose nothing: read, the warning kept in the record
        byte[] padded = new byte[whole.length + 40];
        System.arraycopy(whole, 0, padded, 0, whole.length - 2);
        padded[padded.length - 2] = (byte) 0xFF;
        padded[padded.length - 1] = (byte) 0xD9;
        PhotoEnhancer.Enhanced e = enhancer.enhance(padded);
        assertThat(e.assessment().decodeWarnings()).singleElement().asString().contains("extraneous bytes before marker 0xd9");
        assertThat(e.jpeg()).isNotNull();
    }

    private static byte[] progressiveJpeg(BufferedImage img) throws Exception {
        ImageWriter writer = ImageIO.getImageWritersByFormatName("jpeg").next();
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        try (ImageOutputStream ios = new MemoryCacheImageOutputStream(out)) {
            writer.setOutput(ios);
            ImageWriteParam p = writer.getDefaultWriteParam();
            p.setProgressiveMode(ImageWriteParam.MODE_DEFAULT);
            writer.write(null, new IIOImage(img, null, null), p);
        } finally {
            writer.dispose();
        }
        return out.toByteArray();
    }

    /** a JPEG of a start marker and a frame header only (6000 × 6666, three components): SOF0 baseline, SOF2 progressive */
    private static byte[] frameHeaderOnly(int sof) {
        return new byte[] {(byte) 0xFF, (byte) 0xD8, (byte) 0xFF, (byte) sof, 0, 17, 8, 0x1A, 0x0A, 0x17, 0x70, 3, 1, 0x11, 0, 2, 0x11, 1, 3, 0x11, 1,
                (byte) 0xFF, (byte) 0xD9};
    }

    @Test
    void aLargeProgressiveJpegIsRefusedOnItsHeader() throws Exception {
        // a progressive JPEG's reader keeps every coefficient of the whole image whatever fraction is decoded (233 MB for the
        // review's 40-megapixel file of 470 KB): refused past 13,000,000 pixels from the frame header, before the reader is asked
        byte[] progressive = frameHeaderOnly(0xC2);
        assertThat(PhotoEnhancer.jpegHeader(progressive)).isEqualTo(new PhotoEnhancer.JpegHeader(1, 3, true, 6000, 6666, 0));
        Throwable t = catchThrowable(() -> enhancer.enhance(progressive));
        assertThat(t).isInstanceOf(PhotoEnhancer.Refused.class);
        assertThat(((PhotoEnhancer.Refused) t).code()).isEqualTo("PHOTO_DIMENSIONS");
        assertThat(t.getMessage()).contains("progressive JPEG of 6000 × 6666 pixels");
        // the same size baseline is not refused for its size (it is read at a fraction): this one has no image data, so it is damaged
        assertThat(PhotoEnhancer.jpegHeader(frameHeaderOnly(0xC0)).progressive()).isFalse();
        assertThat(refusal(frameHeaderOnly(0xC0), enhancer)).isEqualTo("PHOTO_CORRUPT");
        // a progressive photograph of an ordinary size is read
        byte[] small = progressiveJpeg(portrait(GREY_WALL, DARK_SKIN, DARK_SUIT, 1, 1));
        assertThat(PhotoEnhancer.jpegHeader(small).progressive()).isTrue();
        assertThat(enhancer.enhance(small).jpeg()).isNotNull();
    }

    /** a sequential (SOF0) JPEG of w × h pixels, three components at 4:4:4, every block flat grey, coded in the scans given (each the
     *  component numbers it codes, 1 to 3): {{1, 2, 3}} is one interleaved scan, {{1}, {2}, {3}} each colour in a scan of its own.
     *  Its Huffman tables have one code each, so every block is two bits and a 40-megapixel file is under half a megabyte */
    private static byte[] sequentialJpeg(int w, int h, int[][] scans) {
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        out.writeBytes(new byte[] {(byte) 0xFF, (byte) 0xD8});
        out.writeBytes(segment(0xE0, new byte[] {'J', 'F', 'I', 'F', 0, 1, 1, 0, 0, 1, 0, 1, 0, 0}));
        byte[] dqt = new byte[65];
        Arrays.fill(dqt, 1, 65, (byte) 1);
        out.writeBytes(segment(0xDB, dqt));
        byte[] dc = new byte[18], ac = new byte[18];                              // one code ("0") each: DC difference 0, AC end of block
        dc[1] = 1;
        ac[0] = 0x10;
        ac[1] = 1;
        out.writeBytes(segment(0xC4, dc));
        out.writeBytes(segment(0xC4, ac));
        out.writeBytes(segment(0xC0, new byte[] {8, (byte) (h >> 8), (byte) h, (byte) (w >> 8), (byte) w, 3, 1, 0x11, 0, 2, 0x11, 0, 3, 0x11, 0}));
        long blocks = (long) ((w + 7) / 8) * ((h + 7) / 8);
        for (int[] scan : scans) {
            byte[] sos = new byte[1 + 2 * scan.length + 3];
            sos[0] = (byte) scan.length;
            for (int k = 0; k < scan.length; k++) sos[1 + 2 * k] = (byte) scan[k];   // tables 0 and 0
            sos[sos.length - 2] = 63;                                                // Ss 0, Se 63, Ah/Al 0
            out.writeBytes(segment(0xDA, sos));
            out.writeBytes(new byte[(int) ((blocks * scan.length * 2 + 7) / 8)]);   // two zero bits a block
        }
        out.writeBytes(new byte[] {(byte) 0xFF, (byte) 0xD9});
        return out.toByteArray();
    }

    private static byte[] segment(int marker, byte[] data) {
        byte[] s = new byte[4 + data.length];
        s[0] = (byte) 0xFF;
        s[1] = (byte) marker;
        s[2] = (byte) ((data.length + 2) >> 8);
        s[3] = (byte) (data.length + 2);
        System.arraycopy(data, 0, s, 4, data.length);
        return s;
    }

    @Test
    void aLargeMultiScanJpegIsRefusedOnItsHeader() throws Exception {
        // the review's third round: a sequential JPEG whose colours are stored in separate scans makes its reader keep the whole image's
        // coefficients, as a progressive one does (233 MB of native memory for 40 megapixels, the file accepted). Now refused past
        // 13,000,000 pixels on its header, whether its first scan codes one of the three colours or two
        int[][][] layouts = {{{1}, {2}, {3}}, {{1, 2}, {3}}, {{1}, {2, 3}}};
        for (int[][] layout : layouts) {
            String what = Arrays.deepToString(layout);
            byte[] large = sequentialJpeg(6320, 6320, layout);
            assertThat(large.length).as(what).isLessThan(500_000);
            PhotoEnhancer.JpegHeader header = PhotoEnhancer.jpegHeader(large);
            assertThat(header).as(what).isEqualTo(new PhotoEnhancer.JpegHeader(1, 3, false, 6320, 6320, layout[0].length));
            assertThat(header.multiScan()).as(what).isTrue();
            long t0 = System.nanoTime();
            Throwable t = catchThrowable(() -> enhancer.enhance(large));
            long ms = (System.nanoTime() - t0) / 1_000_000;
            assertThat(t).as(what).isInstanceOf(PhotoEnhancer.Refused.class);
            assertThat(((PhotoEnhancer.Refused) t).code()).as(what).isEqualTo("PHOTO_DIMENSIONS");
            assertThat(t.getMessage()).as(what).contains("JPEG of 6320 × 6320 pixels stored in several scans");
            assertThat(ms).as("%s: refused on the header in %s ms, never decoded", what, ms).isLessThan(1000);
        }
        // a phone's photograph so stored, 3600 × 3600 (12,960,000 pixels), is read, whatever its scans
        for (int[][] layout : List.of(layouts[0], layouts[1])) {
            PhotoEnhancer.Enhanced e = enhancer.enhance(sequentialJpeg(3600, 3600, layout));
            assertThat(e.jpeg()).as(Arrays.deepToString(layout)).isNotNull();
            assertThat(e.assessment().width()).isEqualTo(3600);
            assertThat(e.assessment().decodeWarnings()).as(Arrays.deepToString(layout)).isEmpty();
        }
        // the 40-megapixel image in one interleaved scan is decoded a fraction at a time, as any baseline JPEG: not refused for its size
        byte[] interleaved = sequentialJpeg(6320, 6320, new int[][] {{1, 2, 3}});
        assertThat(PhotoEnhancer.jpegHeader(interleaved).multiScan()).isFalse();
        assertThat(enhancer.assess(interleaved).width()).isEqualTo(6320);
    }

    /** a raw deflate of the bytes given, ended by a full flush: it stands alone, so copies of it can follow one another */
    private static byte[] rawDeflate(byte[] data) {
        Deflater d = new Deflater(Deflater.BEST_COMPRESSION, true);
        try {
            d.setInput(data);
            ByteArrayOutputStream out = new ByteArrayOutputStream();
            byte[] buf = new byte[8192];
            int k;
            while ((k = d.deflate(buf, 0, buf.length, Deflater.FULL_FLUSH)) > 0) out.write(buf, 0, k);
            return out.toByteArray();
        } finally {
            d.end();
        }
    }

    /** a black 8-bit grey PNG of w × h pixels, made without ever holding its pixels: the zlib stream of its (w + 1) × h zero bytes
     *  is one full-flushed block of a mebibyte of zeros repeated, the rest, an empty final block, and the Adler-32 of n zeros
     *  (a = 1, b = n mod 65521). 20,000 × 20,000 comes to about 400 KB */
    private static byte[] blackPng(int w, int h) throws Exception {
        long n = (long) (w + 1) * h;
        int mebibyte = 1 << 20;
        ByteArrayOutputStream z = new ByteArrayOutputStream();
        z.write(new byte[] {0x78, 0x01});
        byte[] block = rawDeflate(new byte[mebibyte]);
        long left = n;
        for (; left >= mebibyte; left -= mebibyte) z.write(block);
        if (left > 0) z.write(rawDeflate(new byte[(int) left]));
        z.write(new byte[] {0x03, 0x00});
        z.write(ByteBuffer.allocate(4).putInt((int) (((n % 65521) << 16) | 1)).array());
        ByteArrayOutputStream png = new ByteArrayOutputStream();
        png.write(new byte[] {(byte) 0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A});
        png.write(chunk("IHDR", ByteBuffer.allocate(13).putInt(w).putInt(h).put((byte) 8).put((byte) 0).put((byte) 0).put((byte) 0).put((byte) 0).array()));
        png.write(chunk("IDAT", z.toByteArray()));
        png.write(chunk("IEND", new byte[0]));
        return png.toByteArray();
    }

    @Test
    void toJpegReadsAStoredPngAsSafelyAsAnUpload() throws Exception {
        // a PNG of a few hundred kilobytes, every row present, declaring 20,000 × 20,000 pixels (gigabytes once decoded): served as
        // it is stored, its size read from the header and never decoded
        byte[] huge = blackPng(20_000, 20_000);
        assertThat(huge.length).isLessThan(1_000_000);
        assertThat(PhotoEnhancer.toJpeg(huge, 0.9f)).isSameAs(huge);
        // the same kind of file of 3000 × 2500 (7,500,000 pixels) is turned, decoded at one in two
        byte[] large = blackPng(3000, 2500);
        byte[] jpeg = PhotoEnhancer.toJpeg(large, 0.9f);
        assertThat(PhotoEnhancer.sniff(jpeg)).isEqualTo("image/jpeg");
        BufferedImage out = read(jpeg);
        assertThat(out.getWidth()).isEqualTo(1500);
        assertThat(out.getHeight()).isEqualTo(1250);
        // a JPEG, and anything that is neither a JPEG nor a PNG, are served as they are
        byte[] other = "GIF89a not a photograph".getBytes(StandardCharsets.US_ASCII);
        assertThat(PhotoEnhancer.toJpeg(other, 0.9f)).isSameAs(other);
    }

    /** the APP1 an EXIF-tagged camera writes, holding only the Orientation tag; big-endian (MM) or little-endian (II) */
    private static byte[] exif(int orientation, boolean little) {
        ByteBuffer t = ByteBuffer.allocate(26).order(little ? java.nio.ByteOrder.LITTLE_ENDIAN : java.nio.ByteOrder.BIG_ENDIAN);
        t.put((byte) (little ? 'I' : 'M')).put((byte) (little ? 'I' : 'M')).putShort((short) 42).putInt(8);
        t.putShort((short) 1);                                                   // one entry
        t.putShort((short) 0x0112).putShort((short) 3).putInt(1).putShort((short) orientation).putShort((short) 0);
        t.putInt(0);                                                             // no next IFD
        byte[] tiff = t.array();
        byte[] payload = new byte[6 + tiff.length];
        System.arraycopy("Exif\0\0".getBytes(StandardCharsets.ISO_8859_1), 0, payload, 0, 6);
        System.arraycopy(tiff, 0, payload, 6, tiff.length);
        int len = payload.length + 2;
        byte[] seg = new byte[4 + payload.length];
        seg[0] = (byte) 0xFF;
        seg[1] = (byte) 0xE1;
        seg[2] = (byte) (len >> 8);
        seg[3] = (byte) len;
        System.arraycopy(payload, 0, seg, 4, payload.length);
        return seg;
    }

    /** the JPEG with the APP1 put after its JFIF APP0, where a camera's file would carry it */
    private static byte[] withExif(byte[] jpeg, byte[] app1) {
        int at = 2;
        if ((jpeg[2] & 0xFF) == 0xFF && (jpeg[3] & 0xFF) == 0xE0) at = 4 + (((jpeg[4] & 0xFF) << 8) | (jpeg[5] & 0xFF));
        byte[] out = new byte[jpeg.length + app1.length];
        System.arraycopy(jpeg, 0, out, 0, at);
        System.arraycopy(app1, 0, out, at, app1.length);
        System.arraycopy(jpeg, at, out, at + app1.length, jpeg.length - at);
        return out;
    }

    private static boolean red(int p) {
        int r = (p >> 16) & 0xFF, g = (p >> 8) & 0xFF;
        return r > g + 60;
    }

    @Test
    void aJpegTakenTurnedComesOutUpright() throws Exception {
        // stored landscape, 800 × 600, red down the left edge; EXIF 6: shown turned a quarter clockwise, the left edge at the top
        BufferedImage stored = picture(800, 600, 110, 115, 120, 40, 4);
        for (int y = 0; y < 600; y++) for (int x = 0; x < 120; x++) stored.setRGB(x, y, (220 << 16) | (30 << 8) | 30);
        byte[] plain = write(stored, "jpg");
        byte[] turned = withExif(plain, exif(6, false));
        assertThat(PhotoEnhancer.jpegHeader(turned).orientation()).isEqualTo(6);

        PhotoEnhancer.Enhanced e = enhancer.enhance(turned);
        assertThat(e.assessment().orientation()).isEqualTo(6);
        assertThat(e.assessment().orientationCorrected()).isTrue();
        assertThat(e.assessment().width()).isEqualTo(600);
        assertThat(e.assessment().height()).isEqualTo(800);
        assertThat(e.assessment().flags()).doesNotContain("LANDSCAPE");
        BufferedImage out = read(e.jpeg());
        assertThat(red(out.getRGB(300, 30))).as("the top is the red edge").isTrue();
        assertThat(red(out.getRGB(300, 700))).as("the bottom is not").isFalse();

        // the same photograph without the tag is read as it is stored: landscape, cut across the middle, no red at the top
        PhotoEnhancer.Enhanced flat = enhancer.enhance(plain);
        assertThat(flat.assessment().orientation()).isEqualTo(1);
        assertThat(flat.assessment().flags()).contains("LANDSCAPE");
        assertThat(red(read(flat.jpeg()).getRGB(300, 30))).isFalse();

        // the tag little-endian, and turned the other way
        assertThat(PhotoEnhancer.jpegHeader(withExif(plain, exif(8, true))).orientation()).isEqualTo(8);
        assertThat(PhotoEnhancer.jpegHeader(plain).orientation()).isEqualTo(1);
    }

    @Test
    void aTinyPhotographIsToBeReplaced() throws Exception {
        PhotoEnhancer.Enhanced e = enhancer.enhance(write(picture(100, 125, 120, 110, 100, 40, 5), "jpg"));
        assertThat(e.assessment().quality()).isEqualTo("REPLACE");
        assertThat(e.assessment().flags()).contains("LOW_RESOLUTION");
        assertThat(e.assessment().cropWidth()).isEqualTo(100);
        assertThat(e.assessment().cropHeight()).isEqualTo(125);
        // still enhanced and framed, so the holder sees why
        assertThat(e.jpeg()).isNotNull();
        assertThat(enhancer.assess(write(picture(100, 125, 120, 110, 100, 40, 5), "jpg")).quality()).isEqualTo("REPLACE");
    }

    private static byte[] chunk(String type, byte[] data) {
        ByteBuffer b = ByteBuffer.allocate(12 + data.length);
        b.putInt(data.length);
        byte[] t = type.getBytes(StandardCharsets.US_ASCII);
        b.put(t).put(data);
        CRC32 crc = new CRC32();
        crc.update(t);
        crc.update(data);
        b.putInt((int) crc.getValue());
        return b.array();
    }

    @Test
    void aHugeDeclaredCanvasIsRefusedBeforeItIsDecoded() throws Exception {
        // a PNG of a few dozen bytes whose header declares 30,000 × 30,000 pixels and which holds no image data at all: refused on
        // the header's size (PHOTO_DIMENSIONS), not on the missing data (which would read as damaged)
        ByteArrayOutputStream png = new ByteArrayOutputStream();
        png.write(new byte[] {(byte) 0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A});
        png.write(chunk("IHDR", ByteBuffer.allocate(13).putInt(30_000).putInt(30_000).put((byte) 8).put((byte) 2).put((byte) 0).put((byte) 0).put((byte) 0).array()));
        png.write(chunk("IEND", new byte[0]));
        Throwable t = catchThrowable(() -> enhancer.enhance(png.toByteArray()));
        assertThat(t).isInstanceOf(PhotoEnhancer.Refused.class);
        assertThat(((PhotoEnhancer.Refused) t).code()).isEqualTo("PHOTO_DIMENSIONS");
        assertThat(t.getMessage()).contains("30000 × 30000");
    }

    @Test
    void aPngsTransparencyComesOutWhite() throws Exception {
        BufferedImage img = new BufferedImage(600, 750, BufferedImage.TYPE_INT_ARGB);   // transparent black everywhere …
        Random random = new Random(7);
        for (int y = 220; y < 560; y++) {
            for (int x = 180; x < 420; x++) {                                                // … but an opaque, textured figure in the middle
                int v = 60 + random.nextInt(40) + ((x / 5) % 2 == 0 ? 20 : 0);
                img.setRGB(x, y, 0xFF000000 | (v << 16) | (v << 8) | v);
            }
        }
        PhotoEnhancer.Enhanced e = enhancer.enhance(write(img, "png"));
        assertThat(e.assessment().format()).isEqualTo("PNG");
        BufferedImage out = read(e.jpeg());
        int corner = out.getRGB(10, 10);
        assertThat((corner >> 16) & 0xFF).isGreaterThan(240);
        assertThat((corner >> 8) & 0xFF).isGreaterThan(240);
        assertThat(corner & 0xFF).isGreaterThan(240);
        assertThat(means(out)[3]).isLessThan(250);   // the figure is still there
    }

    private static String refusal(byte[] bytes, PhotoEnhancer enhancer) {
        Throwable t = catchThrowable(() -> enhancer.enhance(bytes));
        assertThat(t).as("refused").isInstanceOf(PhotoEnhancer.Refused.class);
        return ((PhotoEnhancer.Refused) t).code();
    }

    @Test
    void aDamagedAPrintOrANonImageFileIsRefusedInWords() throws Exception {
        // damaged: a JPEG's first bytes and nothing a reader can decode
        byte[] damaged = new byte[400];
        new Random(8).nextBytes(damaged);
        damaged[0] = (byte) 0xFF;
        damaged[1] = (byte) 0xD8;
        damaged[2] = (byte) 0xFF;
        damaged[3] = (byte) 0xDB;
        assertThat(refusal(damaged, enhancer)).isEqualTo("PHOTO_CORRUPT");
        // a print file: a frame header of four components (CMYK), refused before the reader is asked
        byte[] cmyk = {(byte) 0xFF, (byte) 0xD8, (byte) 0xFF, (byte) 0xC0, 0, 20, 8, 0, 16, 0, 16, 4, 1, 0x11, 0, 2, 0x11, 0, 3, 0x11, 0, 4, 0x11, 0,
                (byte) 0xFF, (byte) 0xD9};
        assertThat(PhotoEnhancer.jpegHeader(cmyk).components()).isEqualTo(4);
        assertThat(refusal(cmyk, enhancer)).isEqualTo("PHOTO_CMYK");
        // not a JPEG or a PNG, whatever it is called
        assertThat(refusal("GIF89a not a photograph".getBytes(StandardCharsets.US_ASCII), enhancer)).isEqualTo("PHOTO_FORMAT");
        assertThat(refusal(new byte[0], enhancer)).isEqualTo("PHOTO_EMPTY");
        // larger than the portal takes
        PhotoEnhancer small = new PhotoEnhancer(new PhotoEnhancer.Settings(1000, 40_000_000L, 300, 375, 600, 750, 0.9f));
        assertThat(refusal(write(picture(600, 750, 100, 100, 100, 40, 9), "jpg"), small)).isEqualTo("PHOTO_SIZE");
    }

    @Test
    void theAssessmentSaysWhatItReadsAndNeverClaimsTheFace() throws Exception {
        PhotoEnhancer.Enhanced e = enhancer.enhance(write(picture(900, 1200, 120, 105, 95, 50, 10), "jpg"));
        java.util.Map<String, Object> a = e.assessment().toMap();
        assertThat(a).containsEntry("face", PhotoEnhancer.FACE).containsEntry("width", 900).containsEntry("height", 1200)
                .containsKeys("megapixels", "meanLuma", "lumaSpread", "clippedDarkPct", "clippedBrightPct", "sharpness", "noise", "aspect",
                        "background", "flags", "quality", "orientation", "orientationCorrected");
        assertThat(PhotoEnhancer.FLAGS).containsAll(e.assessment().flags());
        assertThat(e.assessment().quality()).isIn("GOOD", "FAIR");
        assertThat(e.jpeg().length).isLessThan(2_000_000);
        assertThat(PhotoEnhancer.sniff(e.jpeg())).isEqualTo("image/jpeg");
        assertThat(String.valueOf(e.enhancement().get("method"))).contains("Global corrections only");
        assertThat(String.valueOf(e.enhancement().get("steps"))).contains("no face detection");
        // a PNG served for the card is turned into a JPEG; a JPEG passes through untouched
        byte[] png = write(picture(60, 75, 120, 120, 120, 20, 11), "png");
        assertThat(PhotoEnhancer.sniff(PhotoEnhancer.toJpeg(png, 0.9f))).isEqualTo("image/jpeg");
        assertThat(PhotoEnhancer.toJpeg(e.jpeg(), 0.9f)).isSameAs(e.jpeg());
    }

    /* ── the review's second round ────────────────────────────────────────────────────────────────────────────────────────── */

    /** the index of the 0xFF of the first segment with the marker given, walking the header's segments by their lengths; -1 if none */
    private static int segment(byte[] jpeg, int marker) {
        int i = 2;
        while (i + 4 <= jpeg.length) {
            int m = jpeg[i + 1] & 0xFF;
            if (m == marker) return i;
            if (m == 0xDA || m == 0xD9) return -1;
            i += 2 + (((jpeg[i + 2] & 0xFF) << 8) | (jpeg[i + 3] & 0xFF));
        }
        return -1;
    }

    /** the bytes with {@code extra} put in at the index given */
    private static byte[] insert(byte[] b, int at, int... extra) {
        byte[] out = new byte[b.length + extra.length];
        System.arraycopy(b, 0, out, 0, at);
        for (int k = 0; k < extra.length; k++) out[at + k] = (byte) extra[k];
        System.arraycopy(b, at, out, at + extra.length, b.length - at);
        return out;
    }

    /** the index of the 0xFF of the first marker after the first scan's data (a progressive JPEG's next table or scan, or the end) */
    private static int afterFirstScan(byte[] jpeg) {
        int sos = segment(jpeg, 0xDA), i = sos + 2 + (((jpeg[sos + 2] & 0xFF) << 8) | (jpeg[sos + 3] & 0xFF));
        while (i + 1 < jpeg.length) {
            int c = jpeg[i + 1] & 0xFF;
            if ((jpeg[i] & 0xFF) == 0xFF && c != 0x00 && c != 0xFF && (c < 0xD0 || c > 0xD7)) return i;
            i++;
        }
        return -1;
    }

    /** a JPEG with a restart marker every {@code interval} MCUs (a DRI segment in its metadata) */
    private static byte[] withRestarts(BufferedImage img, int interval) throws Exception {
        ImageWriter writer = ImageIO.getImageWritersByFormatName("jpeg").next();
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        try (ImageOutputStream ios = new MemoryCacheImageOutputStream(out)) {
            writer.setOutput(ios);
            ImageWriteParam p = writer.getDefaultWriteParam();
            IIOMetadata meta = writer.getDefaultImageMetadata(ImageTypeSpecifier.createFromRenderedImage(img), p);
            String format = "javax_imageio_jpeg_image_1.0";
            IIOMetadataNode root = (IIOMetadataNode) meta.getAsTree(format);
            IIOMetadataNode markers = (IIOMetadataNode) root.getElementsByTagName("markerSequence").item(0);
            IIOMetadataNode dri = new IIOMetadataNode("dri");
            dri.setAttribute("interval", String.valueOf(interval));
            markers.insertBefore(dri, markers.getFirstChild());
            meta.setFromTree(format, root);
            writer.write(null, new IIOImage(img, null, meta), p);
        } finally {
            writer.dispose();
        }
        return out.toByteArray();
    }

    @Test
    void noStrayBytesHideALargeProgressiveJpegsFrame() throws Exception {
        // the review's second round: the frame header was read until the first byte that was not 0xFF, so two zero bytes, four stray
        // bytes or a stuffed FF 00 before the SOF2 hid it — and the reader, which skips them, decoded a 40-megapixel progressive JPEG in
        // full (233 MB of native memory, four to seven seconds). A small progressive JPEG whose frame header says 6320 × 6320: its
        // reader would hold the coefficients of the whole declared image, as the review's did
        byte[] progressive = progressiveJpeg(picture(64, 64, 120, 110, 100, 30, 21));
        int sof = segment(progressive, 0xC2);
        assertThat(sof).isPositive();
        progressive[sof + 5] = (byte) (6320 >> 8);
        progressive[sof + 6] = (byte) (6320 & 0xFF);
        progressive[sof + 7] = (byte) (6320 >> 8);
        progressive[sof + 8] = (byte) (6320 & 0xFF);
        Object[][] hidden = {{"two zero bytes", new int[] {0, 0}}, {"four stray bytes", new int[] {0x00, 0x11, 0x22, 0x33}},
                {"a stuffed FF 00", new int[] {0xFF, 0x00}}, {"FF 00 among stray bytes", new int[] {0x7A, 0xFF, 0x00, 0x7B}}};
        for (Object[] h : hidden) {
            byte[] file = insert(progressive, sof, (int[]) h[1]);
            assertThat(PhotoEnhancer.jpegHeader(file)).as((String) h[0]).isEqualTo(new PhotoEnhancer.JpegHeader(1, 3, true, 6320, 6320, 3));
            long t0 = System.nanoTime();
            Throwable t = catchThrowable(() -> enhancer.enhance(file));
            long ms = (System.nanoTime() - t0) / 1_000_000;
            assertThat(t).as((String) h[0]).isInstanceOf(PhotoEnhancer.Refused.class);
            assertThat(((PhotoEnhancer.Refused) t).code()).as((String) h[0]).isEqualTo("PHOTO_DIMENSIONS");
            assertThat(ms).as("%s: refused on the header in %s ms, never decoded", h[0], ms).isLessThan(1000);
        }
        // no single frame header where the reader looks for one, refused before a reader is made: a tables-only stream in front of the
        // image (the reader would decode the image after it), and two frame headers
        byte[] plain = write(picture(64, 64, 120, 110, 100, 30, 22), "jpg");
        int dqt = segment(plain, 0xDB), dqtLength = 2 + (((plain[dqt + 2] & 0xFF) << 8) | (plain[dqt + 3] & 0xFF));
        byte[] tablesFirst = new byte[2 + dqtLength + 2 + plain.length];
        System.arraycopy(plain, 0, tablesFirst, 0, 2);
        System.arraycopy(plain, dqt, tablesFirst, 2, dqtLength);
        tablesFirst[2 + dqtLength] = (byte) 0xFF;
        tablesFirst[3 + dqtLength] = (byte) 0xD9;
        System.arraycopy(plain, 0, tablesFirst, 4 + dqtLength, plain.length);
        assertThat(PhotoEnhancer.jpegHeader(tablesFirst).width()).isZero();
        assertThat(refusal(tablesFirst, enhancer)).isEqualTo("PHOTO_CORRUPT");
        int sof0 = segment(plain, 0xC0), sofLength = 2 + (((plain[sof0 + 2] & 0xFF) << 8) | (plain[sof0 + 3] & 0xFF));
        byte[] twoFrames = new byte[plain.length + sofLength];
        System.arraycopy(plain, 0, twoFrames, 0, sof0 + sofLength);
        System.arraycopy(plain, sof0, twoFrames, sof0 + sofLength, plain.length - sof0);
        assertThat(PhotoEnhancer.jpegHeader(twoFrames).width()).isZero();
        assertThat(refusal(twoFrames, enhancer)).isEqualTo("PHOTO_CORRUPT");
        // stray bytes before the frame header of an ordinary photograph lose nothing: it is read, the warning kept in the record
        byte[] small = progressiveJpeg(portrait(GREY_WALL, DARK_SKIN, DARK_SUIT, 1, 1));
        PhotoEnhancer.Enhanced e = enhancer.enhance(insert(small, segment(small, 0xC2), 0x00, 0x11, 0x22, 0x33));
        assertThat(e.jpeg()).isNotNull();
        assertThat(e.assessment().decodeWarnings()).singleElement().asString().contains("4 extraneous bytes before marker 0xc2");
    }

    @Test
    void theReadersWarningsThatLoseNothingAreReadAndThoseThatLoseDataRefused() throws Exception {
        byte[] whole = PhotoEnhancer.jpeg(portrait(GREY_WALL, DARK_SKIN, DARK_SUIT, 1, 1), 0.9f);
        // lose nothing: odd SOS parameters in a sequential JPEG, an embedded colour profile that is invalid (ignored), an unknown JFIF
        // revision — each read, its warning kept in the record (the review's second round found them refused as damaged)
        byte[] sos = whole.clone();
        int q = segment(sos, 0xDA), at = q + 5 + 2 * (sos[q + 4] & 0xFF);
        sos[at + 2] = 0x01;                                                      // Ah/Al 0/1 in a baseline scan
        byte[] icc = new byte[200];
        new Random(23).nextBytes(icc);
        byte[] tag = "ICC_PROFILE\0".getBytes(StandardCharsets.ISO_8859_1);
        int length = 2 + tag.length + 2 + icc.length;
        ByteArrayOutputStream app2 = new ByteArrayOutputStream();
        app2.write(new byte[] {(byte) 0xFF, (byte) 0xE2, (byte) (length >> 8), (byte) length});
        app2.write(tag);
        app2.write(new byte[] {1, 1});
        app2.write(icc);
        byte[] profile = new byte[whole.length + app2.size()];
        System.arraycopy(whole, 0, profile, 0, 2);
        System.arraycopy(app2.toByteArray(), 0, profile, 2, app2.size());
        System.arraycopy(whole, 2, profile, 2 + app2.size(), whole.length - 2);
        byte[] jfif = whole.clone();
        assertThat(new String(jfif, 6, 4, StandardCharsets.ISO_8859_1)).isEqualTo("JFIF");
        jfif[11] = 2;                                                            // JFIF 2.xx
        Object[][] harmless = {{"SOS parameters", sos, "Invalid SOS parameters"}, {"colour profile", profile, "color profile is invalid"},
                {"JFIF revision", jfif, "unknown JFIF revision"}};
        for (Object[] h : harmless) {
            PhotoEnhancer.Enhanced e = enhancer.enhance((byte[]) h[1]);
            assertThat(e.jpeg()).as((String) h[0]).isNotNull();
            assertThat(e.assessment().decodeWarnings()).as((String) h[0]).anyMatch(w -> w.contains((String) h[2]));
        }
        // lost or garbled: bytes before the end that are not zero padding (the review's fuzz admitted 65 files through the old
        // exemption, 37 of them more than a fifth damaged) — zeros there are still padding, and read
        byte[] tail = new byte[whole.length + 10];
        System.arraycopy(whole, 0, tail, 0, whole.length - 2);
        Arrays.fill(tail, whole.length - 2, whole.length + 8, (byte) 0x5A);
        tail[tail.length - 2] = (byte) 0xFF;
        tail[tail.length - 1] = (byte) 0xD9;
        assertThat(refusal(tail, enhancer)).as("stray bytes before the end").isEqualTo("PHOTO_CORRUPT");
        Arrays.fill(tail, whole.length - 2, whole.length + 8, (byte) 0);
        assertThat(enhancer.enhance(tail).jpeg()).as("zero padding before the end").isNotNull();
        // lost or garbled: stray bytes before a restart marker, a restart marker missing
        byte[] restarts = withRestarts(portrait(GREY_WALL, DARK_SKIN, DARK_SUIT, 1, 1), 8);
        assertThat(enhancer.enhance(restarts).assessment().decodeWarnings()).isEmpty();
        int rst = -1;
        for (int i = segment(restarts, 0xDA) + 2; i + 1 < restarts.length && rst < 0; i++) {
            if ((restarts[i] & 0xFF) == 0xFF && (restarts[i + 1] & 0xFF) == 0xD3) rst = i;
        }
        assertThat(rst).as("a restart marker RST3").isPositive();
        assertThat(refusal(insert(restarts, rst, 0x12, 0x34, 0x56), enhancer)).as("stray bytes before RST3").isEqualTo("PHOTO_CORRUPT");
        byte[] missing = new byte[restarts.length - 2];
        System.arraycopy(restarts, 0, missing, 0, rst);
        System.arraycopy(restarts, rst + 2, missing, rst, restarts.length - rst - 2);
        assertThat(refusal(missing, enhancer)).as("RST3 missing").isEqualTo("PHOTO_CORRUPT");
        // lost or garbled: stray bytes between a progressive JPEG's scans (the scan before them garbled)
        byte[] progressive = progressiveJpeg(portrait(GREY_WALL, DARK_SKIN, DARK_SUIT, 1, 1));
        assertThat(refusal(insert(progressive, afterFirstScan(progressive), 0x11, 0x22, 0x33), enhancer)).as("between scans").isEqualTo("PHOTO_CORRUPT");
        // the reader's words, judged as they are heard while it reads the photograph with its header put right
        for (String lost : List.of("Truncated File - Missing EOI marker", "Premature end of JPEG file", "Corrupt JPEG data: premature end of data segment",
                "Corrupt JPEG data: bad Huffman code", "Corrupt JPEG data: 3 extraneous bytes before marker 0xd5",
                "Corrupt JPEG data: found marker 0xd4 instead of RST3", "Inconsistent progression sequence for component 0 coefficient 1",
                "Unknown Adobe color transform code 7", "Corrupt JPEG data: 4 extraneous bytes before marker 0xc4",
                "Corrupt JPEG data: 7 extraneous bytes before marker 0xd9")) {
            assertThat(PhotoEnhancer.dataLoss(lost, whole)).as(lost).isTrue();
        }
        // the review's third round: the harmless ones from the header are put right before the reader is asked, so heard from it they
        // come from past the first scan — and the JDK's reader passes on only the first warning of each pass, so they would hide any
        // warning of lost data that follows. (The second round read them as harmless wherever they were heard.)
        for (String hiding : List.of("Invalid SOS parameters for sequential JPEG", "Warning: unknown JFIF revision number 2.02",
                "Corrupt JPEG data: 4 extraneous bytes before marker 0xc0")) {
            assertThat(PhotoEnhancer.dataLoss(hiding, whole)).as(hiding).isTrue();
        }
        // said by the Java reader, which hides nothing
        for (String kept : List.of("Embedded color profile is invalid; ignored", "JFIF markers not allowed in JFIF JPEG thumbnail; ignored")) {
            assertThat(PhotoEnhancer.dataLoss(kept, whole)).as(kept).isFalse();
        }
    }

    @Test
    void aHarmlessHeaderWarningNeverHidesDamagedImageData() throws Exception {
        // the review's third round: the JDK's reader passes on only the first warning of each pass, so a file whose header made the
        // reader warn harmlessly (JFIF 2.02, stray bytes between the header's segments, odd SOS parameters) and whose image data was cut
        // at 40% was read as GOOD, more than half of it flat grey. Now the header is put right before the reader is asked, and the damage
        // is the first thing it reports
        byte[] whole = PhotoEnhancer.jpeg(portrait(GREY_WALL, DARK_SKIN, DARK_SUIT, 1, 1), 0.9f);
        assertThat(PhotoEnhancer.normalise(whole, false).bytes()).as("nothing to put right").isSameAs(whole);
        byte[] jfif = whole.clone();
        jfif[11] = 2;                                                            // JFIF 2.02
        int dqt = segment(whole, 0xDB);
        byte[] stray = insert(whole, dqt, 0x11, 0x22, 0x33);                     // three stray bytes before the DQT
        byte[] sos = whole.clone();
        int q = segment(sos, 0xDA);
        sos[q + 5 + 2 * (sos[q + 4] & 0xFF) + 2] = 0x01;                         // Al 1 in a baseline scan
        Object[][] odd = {{"JFIF 2.02", jfif, "Warning: unknown JFIF revision number 2.02"},
                {"stray bytes before the DQT", stray, "Corrupt JPEG data: 3 extraneous bytes before marker 0xdb"},
                {"SOS Al 1", sos, "Invalid SOS parameters for sequential JPEG"}};
        for (Object[] o : odd) {
            byte[] file = (byte[]) o[1];
            PhotoEnhancer.Normalised n = PhotoEnhancer.normalise(file, false);
            assertThat(n.warnings()).as((String) o[0]).containsExactly((String) o[2]);
            assertThat(n.bytes()).as((String) o[0] + ": put right, it is the photograph as it was written").isEqualTo(whole);
            // whole: read, the warning kept in the record
            PhotoEnhancer.Enhanced e = enhancer.enhance(file);
            assertThat(e.jpeg()).as((String) o[0]).isNotNull();
            assertThat(e.assessment().decodeWarnings()).as((String) o[0]).containsExactly((String) o[2]);
            // its image data cut at 40%, the end marker kept: damaged
            int data = q + 2 + (((whole[q + 2] & 0xFF) << 8) | (whole[q + 3] & 0xFF)) + (file.length - whole.length);
            byte[] cut = new byte[data + (file.length - 2 - data) * 4 / 10 + 2];
            System.arraycopy(file, 0, cut, 0, cut.length - 2);
            cut[cut.length - 2] = (byte) 0xFF;
            cut[cut.length - 1] = (byte) 0xD9;
            assertThat(refusal(cut, enhancer)).as((String) o[0] + ", cut at 40%").isEqualTo("PHOTO_CORRUPT");
            // stray bytes before its end marker that are not zero padding: damaged
            byte[] tail = new byte[file.length + 10];
            System.arraycopy(file, 0, tail, 0, file.length - 2);
            Arrays.fill(tail, file.length - 2, file.length + 8, (byte) 0x5A);
            tail[tail.length - 2] = (byte) 0xFF;
            tail[tail.length - 1] = (byte) 0xD9;
            assertThat(refusal(tail, enhancer)).as((String) o[0] + ", stray bytes before the end").isEqualTo("PHOTO_CORRUPT");
        }
    }

    /** the JPEG with, after its start marker, a restart marker RST0 (the third byte 0xFF, as the sniff wants) and then {@code groups}
     *  copies of {@code unit} */
    private static byte[] withHeaderGroups(byte[] jpeg, int groups, int... unit) {
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        out.write(jpeg, 0, 2);
        out.write(0xFF);
        out.write(0xD0);
        for (int k = 0; k < groups; k++) for (int v : unit) out.write(v);
        out.write(jpeg, 2, jpeg.length - 2);
        return out.toByteArray();
    }

    private static int[] unsigned(byte[] b) {
        int[] out = new int[b.length];
        for (int k = 0; k < b.length; k++) out[k] = b[k] & 0xFF;
        return out;
    }

    @Test
    void aHeaderOfManyStrayByteGroupsIsRefusedBeforeItIsRead() throws Exception {
        // the review's fourth round: each group of stray bytes between the header's segments was put right and named in the record, so
        // a 6 MB file of about two million groups (a stray byte, then RST0) stored two million warnings, 116 MB of JSON, in the
        // assessment, and held a slot for 4.6 s. No encoder writes more than a handful: more than eight groups, or more than eight JFIF
        // segments, are damage, refused on the header before a reader is made
        byte[] whole = PhotoEnhancer.jpeg(portrait(GREY_WALL, DARK_SKIN, DARK_SUIT, 1, 1), 0.9f);
        Object[][] bloated = {{"a stray byte, then RST0", new int[] {0x00, 0xFF, 0xD0}},
                {"a stray byte, then an empty APP5", new int[] {0x00, 0xFF, 0xE5, 0x00, 0x02}}};
        for (Object[] b : bloated) {
            String what = (String) b[0];
            byte[] file = withHeaderGroups(whole, 100_000, (int[]) b[1]);
            long t0 = System.nanoTime();
            String code = refusal(file, enhancer);
            long ms = (System.nanoTime() - t0) / 1_000_000;
            assertThat(code).as(what).isEqualTo("PHOTO_CORRUPT");
            assertThat(ms).as("%s: 100,000 groups refused on the header in %s ms, never decoded", what, ms).isLessThan(1000);
            // eight are put right and read, named once with how many; the ninth is damage
            PhotoEnhancer.Enhanced eight = enhancer.enhance(withHeaderGroups(whole, 8, (int[]) b[1]));
            assertThat(eight.jpeg()).as(what + ", eight").isNotNull();
            assertThat(eight.assessment().decodeWarnings()).as(what + ", eight").singleElement().asString()
                    .contains("1 extraneous bytes before marker").contains("and before 7 more of the header's markers: 8 bytes in all");
            assertThat(refusal(withHeaderGroups(whole, 9, (int[]) b[1]), enhancer)).as(what + ", nine").isEqualTo("PHOTO_CORRUPT");
        }
        // nine JFIF segments
        int app0 = segment(whole, 0xE0), app0Length = 2 + (((whole[app0 + 2] & 0xFF) << 8) | (whole[app0 + 3] & 0xFF));
        int[] jfifSegment = unsigned(Arrays.copyOfRange(whole, app0, app0 + app0Length));
        byte[] nine = whole;
        for (int k = 0; k < 8; k++) nine = insert(nine, app0 + app0Length, jfifSegment);
        assertThat(refusal(nine, enhancer)).as("nine JFIF segments").isEqualTo("PHOTO_CORRUPT");
        // a header with two groups of stray bytes (before the DQT and the frame header) is put right and read: the stray bytes named
        // once, with how many
        int dqt = segment(whole, 0xDB), sof = segment(whole, 0xC0);
        byte[] two = insert(insert(whole, sof, 0x44, 0x55), dqt, 0x11, 0x22, 0x33);
        String stray = "Corrupt JPEG data: 3 extraneous bytes before marker 0xdb (and before 1 more of the header's markers: 5 bytes in all)";
        assertThat(PhotoEnhancer.normalise(two, false).bytes()).as("put right, it is the photograph as it was written").isEqualTo(whole);
        PhotoEnhancer.Enhanced e = enhancer.enhance(two);
        assertThat(e.jpeg()).isNotNull();
        assertThat(e.assessment().decodeWarnings()).containsExactly(stray);
        // each kind of thing put right named once, in the order met — two JFIF 2.02 segments, the stray bytes, a baseline scan's Al 1 —
        // and never more than five warnings in all
        byte[] odd = two.clone();
        odd[11] = 2;                                                             // JFIF 2.02
        int q = segment(whole, 0xDA) + 5;                                        // the scan header, past the five stray bytes
        odd[q + 5 + 2 * (odd[q + 4] & 0xFF) + 2] = 0x01;
        int[] oddJfif = unsigned(Arrays.copyOfRange(odd, app0, app0 + app0Length));
        odd = insert(odd, app0 + app0Length, oddJfif);
        PhotoEnhancer.Enhanced all = enhancer.enhance(odd);
        assertThat(all.jpeg()).isNotNull();
        assertThat(all.assessment().decodeWarnings()).hasSizeLessThanOrEqualTo(PhotoEnhancer.WARNINGS_MAX)
                .containsExactly("Warning: unknown JFIF revision number 2.02 (in 2 JFIF segments)", stray, "Invalid SOS parameters for sequential JPEG");
    }

    /** a portrait's face kept: at the forehead and the cheek, red over green and green over blue within {@code ratio} (a share) of
     *  what they were, the brightness within {@code levels} */
    private static void assertFaceKept(Run run, String what, double ratio, double levels) {
        for (int i = 0; i < 2; i++) {
            double[] b = run.before()[i], a = run.after()[i];
            String said = what + (i == 0 ? ", forehead " : ", cheek ") + rgb(b) + " -> " + rgb(a) + "; " + run.enhanced().assessment().flags();
            assertThat(a[0] / a[1] / (b[0] / b[1])).as("R/G: " + said).isBetween(1 - ratio, 1 + ratio);
            assertThat(a[1] / a[2] / (b[1] / b[2])).as("G/B: " + said).isBetween(1 - ratio, 1 + ratio);
            assertThat(Math.abs(a[3] - b[3])).as("luma: " + said).isLessThanOrEqualTo(levels);
        }
    }

    @Test
    void aHighKeyOrALowKeyPortraitKeepsItsFace() throws Exception {
        // the review's second round: a frame with no dark hair or clothes read as hazy (its darkest half per cent above 40), and the
        // levels took the black point off each channel — a medium face on a white wall in a light kaftan darkened by 27 levels and
        // saturated (R/G ×1.21, G/B ×1.35); and a low-key frame read as under-exposed — dark skin in a black suit on an 85 grey wall
        // stretched ×1.8 and called too dark. Now: high-key, bald or grey-haired, in a kaftan or a white shirt on a white wall
        for (int[] hair : List.of(MEDIUM_SKIN, GREY_HAIR)) {
            for (int[] clothes : List.of(KAFTAN, WHITE_SHIRT)) {
                for (int[] skin : List.of(MEDIUM_SKIN, DARK_SKIN)) {
                    Run run = run(portrait(WHITE_WALL, skin, clothes, hair, 1, new double[] {1, 1, 1}), 1);
                    String what = (hair == MEDIUM_SKIN ? "bald" : "grey hair") + ", " + Arrays.toString(clothes) + ", skin " + Arrays.toString(skin);
                    assertFaceKept(run, what, 0.02, 3);
                    assertThat(String.valueOf(run.enhanced().enhancement().get("steps"))).as(what).contains("step=levels, applied=false")
                            .contains("step=exposure, applied=false");
                    assertThat(run.enhanced().assessment().flags()).as(what).doesNotContain("TOO_BRIGHT", "TOO_DARK");
                }
            }
        }
        // low-key: dark skin in a black suit on a dark grey wall — the eye whites are far above the under-exposed highlights
        for (double framing : new double[] {1, 1.35}) {
            for (int[] skin : List.of(DARK_SKIN, MEDIUM_SKIN)) {
                Run run = run(portrait(DARK_GREY_WALL, skin, BLACK_SUIT, DARK_HAIR, framing, new double[] {1, 1, 1}), framing);
                PhotoEnhancer.Assessment a = run.enhanced().assessment();
                String what = "85 wall, black suit, skin " + Arrays.toString(skin) + ", framing " + framing + ", highlights " + a.highlights()
                        + ", mean " + Math.round(a.meanLuma());
                assertThat(a.underExposed()).as(what).isFalse();
                assertThat(a.flags()).as(what).doesNotContain("TOO_DARK");
                assertFaceKept(run, what, 0.02, 3);
            }
        }
    }

    @Test
    void aPaleWallNeverMovesTheFaceAndARealCastIsFlaggedNotCorrected() throws Exception {
        // the review's second round: a pale-blue wall (216, 226, 236) sat inside the near-neutral window, so the white balance made it
        // grey and moved the face with it (R/G ×1.053, G/B ×1.045); a beige wall the other way. Now the wall's tint alone moves nothing
        for (int[] wall : List.of(PALE_BLUE_WALL, BEIGE_WALL)) {
            for (int[] clothes : List.of(BLACK_SUIT, WHITE_SHIRT)) {
                for (int[] skin : List.of(DARK_SKIN, MEDIUM_SKIN)) {
                    Run run = run(portrait(wall, skin, clothes, 1, 1), 1);
                    String what = "wall " + Arrays.toString(wall) + ", " + Arrays.toString(clothes) + ", skin " + Arrays.toString(skin);
                    assertFaceKept(run, what, 0.015, 3);
                    assertThat(run.enhanced().assessment().flags()).as(what).doesNotContain("COLOUR_CAST");
                }
            }
        }
        // a lamp's warm cast and a shade's cool one over a grey or a light grey wall, a white shirt tinted with it: no pixel is
        // near-neutral, so the white balance does nothing — it is flagged for the holder to retake, and the face is left as it is. (The
        // second round flagged the wall's tint alone, over a dark suit; the third round found that flags every cream, peach,
        // light-yellow or mid-blue wall in daylight — see the test after this one — so short of a tint well past such a wall the shirt,
        // the collar or the face must show the tint too)
        for (double[] cast : List.of(new double[] {1.10, 1, 0.82}, new double[] {0.92, 1, 1.10})) {
            for (int[] wall : List.of(GREY_WALL, LIGHT_GREY_WALL)) {
                for (int[] skin : List.of(DARK_SKIN, MEDIUM_SKIN)) {
                    Run run = run(portrait(wall, skin, WHITE_SHIRT, DARK_HAIR, 1, cast), 1);
                    String what = "cast " + Arrays.toString(cast) + ", wall " + Arrays.toString(wall) + ", skin " + Arrays.toString(skin) + ", tint "
                            + run.enhanced().assessment().backgroundTint();
                    assertThat(run.enhanced().assessment().flags()).as(what).contains("COLOUR_CAST");
                    assertThat(run.enhanced().assessment().quality()).as(what).isEqualTo("FAIR");
                    assertThat(String.valueOf(run.enhanced().enhancement().get("steps"))).as(what).contains("step=whiteBalance, applied=false");
                    assertFaceKept(run, what, 0.02, 3);
                }
            }
        }
        // a light-blue backdrop chosen as such (tint about -0.37), as ID photographs often use, is a backdrop and not a cast: GOOD, no
        // flag, nothing moved — the wall alone is told only past CAST_WALL_COOL (-0.40). The same blue made by a strong cast over an
        // off-white wall is flagged
        for (int[] skin : List.of(DARK_SKIN, MEDIUM_SKIN, DARKER_SKIN)) {
            Run run = run(portrait(LIGHT_BLUE_WALL, skin, DARK_SUIT, 1, 1), 1);
            PhotoEnhancer.Assessment chosen = run.enhanced().assessment();
            String what = "light-blue backdrop, skin " + Arrays.toString(skin) + ", tint " + chosen.backgroundTint();
            assertThat(chosen.backgroundTint()).as(what).isGreaterThan(PhotoEnhancer.CAST_WALL_COOL).isLessThan(-0.30);
            assertThat(chosen.flags()).as(what).doesNotContain("COLOUR_CAST");
            assertFaceKept(run, what, 0.015, 3);
            for (int c = 0; c < 3; c++) assertThat(Math.abs(run.after()[2][c] - run.before()[2][c])).as(what + ", backdrop").isLessThanOrEqualTo(3);
        }
        PhotoEnhancer.Assessment strong = enhancer.assess(PhotoEnhancer.jpeg(portrait(OFF_WHITE_WALL, MEDIUM_SKIN, NAVY, DARK_HAIR, 1,
                new double[] {0.78, 0.95, 1.25}), 0.95f));
        assertThat(strong.flags()).as("tint %s", strong.backgroundTint()).contains("COLOUR_CAST");
        assertThat(PhotoEnhancer.FLAGS).contains("COLOUR_CAST");
    }

    @Test
    void aPaintedWallInDaylightIsNotACast() throws Exception {
        // the review's third round: a cream, peach, light-yellow or mid-blue wall (tint 0.17 to 0.22, inside the window a lamp or a shade
        // gives a white wall) was flagged on every correctly lit portrait, and the words blamed the light. The wall alone cannot tell
        // its own paint from a cast: in daylight the face keeps its warmth and a white shirt stays white, so nothing confirms it
        int[][] walls = {{240, 228, 200}, {245, 222, 196}, {242, 236, 196}, {190, 210, 235}};
        for (int[] wall : walls) {
            for (int[] skin : List.of(DARKER_SKIN, DARK_SKIN, MEDIUM_SKIN, LIGHT_SKIN)) {
                for (int[] clothes : List.of(DARK_SUIT, WHITE_SHIRT)) {
                    Run run = run(portrait(wall, skin, clothes, 1, 1), 1);
                    PhotoEnhancer.Assessment a = run.enhanced().assessment();
                    String what = "wall " + Arrays.toString(wall) + ", skin " + Arrays.toString(skin) + ", " + Arrays.toString(clothes) + ", tint "
                            + a.backgroundTint();
                    assertThat(Math.abs(a.backgroundTint())).as(what).isGreaterThanOrEqualTo(PhotoEnhancer.CAST_MIN);
                    assertThat(a.flags()).as(what).doesNotContain("COLOUR_CAST");
                    assertThat(a.quality()).as(what).isEqualTo("GOOD");
                    assertFaceKept(run, what, 0.015, 3);
                }
            }
        }
    }

    /** a warm or bright head-tie (gele) reaching the top band of a usual passport framing, before a light or mid grey wall in daylight,
     *  colours that band alone: no COLOUR_CAST — the wall alone is told only when its side strips are tinted the same way too */
    @Test
    void aGeleInTheTopBandIsNotACast() throws Exception {
        int[][] geles = {{212, 160, 40}, {240, 110, 80}, {230, 140, 30}, {150, 90, 40}};
        int[][] walls = {{185, 185, 185}, {200, 200, 200}, {150, 150, 150}};
        for (int[] wall : walls) {
            for (int[] gele : geles) {
                for (double framing : new double[] {1.5, 1.6}) {
                    for (int[] skin : List.of(DARK_SKIN, MEDIUM_SKIN)) {
                        PhotoEnhancer.Assessment a = enhancer.assess(PhotoEnhancer.jpeg(
                                portrait(wall, skin, WHITE_SHIRT, gele, framing, new double[] {1, 1, 1}), 0.95f));
                        assertThat(a.flags()).as("wall %s, gele %s, framing %s, tint %s", Arrays.toString(wall), Arrays.toString(gele), framing,
                                a.backgroundTint()).doesNotContain("COLOUR_CAST");
                    }
                }
            }
        }
    }

    @Test
    void aLampOnAWhiteWallIsFlaggedAgain() throws Exception {
        // the review's fourth round: the third round's confirmation wanted the face (its tint over 1.0) or what is off the wall to show
        // the cast too — and a white shirt under the lamp that tints a white wall takes the wall's colour, so a lamp on a white office
        // wall, the commonest cast indoors, was GOOD with no flag (10 of 180 flagged; the second round 180). Now a tint well past a painted
        // wall's (strong tungsten: 0.29 to 0.33 here) is flagged on the wall alone, a dark suit and all; a milder one (tungsten 0.22 to
        // 0.26, a warm LED 0.18 to 0.21 — among the painted walls' 0.17 to 0.22) where the clothes at the chest show it, of the wall's
        // colour or not. Told, never corrected beyond the mild white balance: the face is left as it is
        Object[][] lamps = {{"tungsten", new double[] {1.10, 1, 0.82}}, {"strong tungsten", new double[] {1.15, 1, 0.75}},
                {"warm LED", new double[] {1.07, 1, 0.86}}};
        for (Object[] lamp : lamps) {
            boolean strong = lamp[0].equals("strong tungsten");
            for (int[] wall : List.of(new int[] {235, 235, 235}, WHITE_WALL)) {
                for (int[] skin : List.of(DARK_SKIN, MEDIUM_SKIN)) {
                    for (int[] clothes : strong ? List.of(WHITE_SHIRT, KAFTAN, DARK_SUIT) : List.of(WHITE_SHIRT, KAFTAN)) {
                        Run run = run(portrait(wall, skin, clothes, DARK_HAIR, 1, (double[]) lamp[1]), 1);
                        PhotoEnhancer.Assessment a = run.enhanced().assessment();
                        String what = lamp[0] + ", wall " + wall[0] + ", skin " + Arrays.toString(skin) + ", " + Arrays.toString(clothes)
                                + ", tint " + a.backgroundTint();
                        if (strong) {
                            assertThat(a.backgroundTint()).as(what).isGreaterThanOrEqualTo(PhotoEnhancer.CAST_WALL_WARM);
                        } else {
                            assertThat(a.backgroundTint()).as(what).isBetween(PhotoEnhancer.CAST_MIN, PhotoEnhancer.CAST_WALL_WARM);
                        }
                        assertThat(a.flags()).as(what).containsExactly("COLOUR_CAST");
                        assertThat(a.quality()).as(what).isEqualTo("FAIR");
                        assertFaceKept(run, what, 0.02, 3);
                    }
                }
            }
        }
        // the review's warm sample (cast_warm.jpg: red ×1.2 and blue ×0.7 over an off-white wall and a navy shirt; tint 0.42) is flagged
        PhotoEnhancer.Assessment sample = enhancer.assess(PhotoEnhancer.jpeg(portrait(OFF_WHITE_WALL, MEDIUM_SKIN, NAVY, DARK_HAIR, 1,
                new double[] {1.2, 1.0, 0.7}), 0.95f));
        assertThat(sample.backgroundTint()).isGreaterThan(0.35);
        assertThat(sample.flags()).contains("COLOUR_CAST");
        // the painted walls in daylight still are not, a white shirt or a light kaftan at the chest before them (not of the wall's colour,
        // and white), tightly framed or not
        int[][] painted = {{240, 228, 200}, {245, 222, 196}, {242, 236, 196}, {190, 210, 235}};
        for (int[] wall : painted) {
            for (int[] clothes : List.of(WHITE_SHIRT, KAFTAN)) {
                for (int[] skin : List.of(DARK_SKIN, MEDIUM_SKIN)) {
                    for (double framing : new double[] {1, 1.35}) {
                        PhotoEnhancer.Assessment a = enhancer.assess(PhotoEnhancer.jpeg(portrait(wall, skin, clothes, framing, 1), 0.95f));
                        String what = "wall " + Arrays.toString(wall) + ", " + Arrays.toString(clothes) + ", skin " + Arrays.toString(skin)
                                + ", framing " + framing + ", tint " + a.backgroundTint();
                        assertThat(a.flags()).as(what).doesNotContain("COLOUR_CAST");
                        assertThat(a.quality()).as(what).isEqualTo("GOOD");
                    }
                }
            }
        }
    }

    @Test
    void toJpegWaitsNoMoreThanTwoSecondsForASlot() throws Exception {
        // the review's second round: toJpeg waited up to 30 s for a slot inside read-only transactions (the card's photograph and
        // /photo/current), holding a database connection. With both slots taken, the PNG is served as stored after two seconds
        byte[] png = write(picture(200, 250, 120, 110, 100, 20, 24), "png");
        PhotoEnhancer.SLOTS.acquire(2);
        long ms;
        byte[] served;
        try {
            long t0 = System.nanoTime();
            served = PhotoEnhancer.toJpeg(png, 0.9f);
            ms = (System.nanoTime() - t0) / 1_000_000;
        } finally {
            PhotoEnhancer.SLOTS.release(2);
        }
        assertThat(served).isSameAs(png);
        assertThat(ms).as("waited %s ms", ms).isBetween(1_800L, 4_000L);
        assertThat(PhotoEnhancer.sniff(PhotoEnhancer.toJpeg(png, 0.9f))).isEqualTo("image/jpeg");
    }

    @Test
    void aWhiteBackdropIsNotTooBrightAndHairInTheTopBandIsNotBusy() throws Exception {
        // the review's second round: on a pure-white (252) backdrop more than 30% of the frame is clipped, so every portrait was
        // TOO_BRIGHT and none GOOD; now the clipped highlights are read at the centre, never the backdrop
        for (int[] skin : List.of(DARK_SKIN, MEDIUM_SKIN)) {
            for (int[] clothes : List.of(BLACK_SUIT, NAVY)) {
                PhotoEnhancer.Assessment a = enhancer.assess(PhotoEnhancer.jpeg(portrait(PURE_WHITE, skin, clothes, 1, 1), 0.95f));
                assertThat(a.clippedBrightPct()).isGreaterThan(30);
                assertThat(a.quality()).as("skin %s, clothes %s: %s", Arrays.toString(skin), Arrays.toString(clothes), a.flags()).isEqualTo("GOOD");
            }
        }
        // an over-exposed face is still too bright, and brought down
        Run over = run(portrait(GREY_WALL, MEDIUM_SKIN, DARK_SUIT, 1, 1.6), 1);
        assertThat(over.enhanced().assessment().flags()).contains("TOO_BRIGHT");
        assertThat(String.valueOf(over.enhanced().enhancement().get("steps"))).contains("step=exposure, applied=true").contains("over-exposed");
        assertThat(over.after()[0][3]).isLessThan(over.before()[0][3]);
        // a tight framing brings the hair into the top band: the head, not a busy background (the review: spread 65, BUSY at 1.6×)
        for (double framing : new double[] {1.35, 1.6}) {
            PhotoEnhancer.Assessment a = enhancer.assess(PhotoEnhancer.jpeg(portrait(WHITE_WALL, DARK_SKIN, BLACK_SUIT, framing, 1), 0.95f));
            assertThat(a.flags()).as("framing %s, spread %s", framing, a.backgroundSpread()).doesNotContain("BUSY_BACKGROUND");
            assertThat(a.backgroundSpread()).isLessThan(10);
        }
        // a cluttered wall behind the head is still busy, the hair touching it or not
        for (double framing : new double[] {1, 1.6}) {
            BufferedImage cluttered = portrait(WHITE_WALL, DARK_SKIN, NAVY, framing, 1);
            for (int y = 0; y < 60; y++) {
                for (int x = 0; x < 600; x++) {
                    if ((x / 25) % 2 == 0) cluttered.setRGB(x, y, (40 << 16) | (35 << 8) | 30);
                }
            }
            PhotoEnhancer.Assessment busy = enhancer.assess(PhotoEnhancer.jpeg(cluttered, 0.95f));
            assertThat(busy.flags()).as("framing %s, spread %s", framing, busy.backgroundSpread()).contains("BUSY_BACKGROUND");
        }
    }

    @Test
    void aPictureHungAboveATightlyFramedHeadIsStillBusy() throws Exception {
        // the review's third round: everything unlike the wall joined to the head was left out as the head, so a framed picture on the
        // wall in the top band, touching the hair of a tightly framed head, was lost (GOOD at framing 1.6, BUSY at 1). Now the head is
        // traced up row by row, and what touches it is the background. A picture of coloured bands, 15% to 85% across and the top 45
        // rows down, painted on the wall only (behind the head)
        int[][] bands = {{90, 50, 25}, {200, 170, 60}, {30, 60, 120}, {150, 30, 30}};
        for (double framing : new double[] {1, 1.35, 1.6}) {
            for (int[] skin : List.of(DARK_SKIN, MEDIUM_SKIN)) {
                BufferedImage img = portrait(WHITE_WALL, skin, BLACK_SUIT, framing, 1);
                boolean touches = false;
                for (int y = 0; y < 45; y++) {
                    for (int x = 90; x < 510; x++) {
                        int p = img.getRGB(x, y), r = (p >> 16) & 0xFF;
                        if (Math.abs(r - WHITE_WALL[0]) < 20) {
                            int[] c = bands[(x / 30) % 4];
                            img.setRGB(x, y, (c[0] << 16) | (c[1] << 8) | c[2]);
                        } else {
                            touches = true;                                               // the hair, inside the picture's bounds
                        }
                    }
                }
                PhotoEnhancer.Assessment a = enhancer.assess(PhotoEnhancer.jpeg(img, 0.95f));
                String what = "framing " + framing + ", skin " + Arrays.toString(skin) + ", the hair " + (touches ? "touching it" : "below it")
                        + ", spread " + a.backgroundSpread();
                assertThat(touches).as(what).isEqualTo(framing > 1);
                assertThat(a.flags()).as(what).contains("BUSY_BACKGROUND");
            }
        }
    }
}
