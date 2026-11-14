package ng.edu.moaum.portal.credentials;

import java.awt.Color;
import java.awt.Graphics2D;
import java.awt.RenderingHints;
import java.awt.image.BufferedImage;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.util.Base64;
import java.util.Iterator;

import javax.imageio.ImageIO;
import javax.imageio.ImageReader;
import javax.imageio.stream.ImageInputStream;

import ng.edu.moaum.portal.shared.PhotoEnhancer;

/**
 * A signature uploaded for the University's documents, read one way for every one of them: the identity cards' (V622,
 * CardSignatoryController) and a document signatory's, printed on the admission letter (V759, SignatorySignatureController). The
 * upload comes in base64 (a browser's data: address allowed); it is a PNG or a JPEG by its first bytes, at most a megabyte, and
 * decodes — its size in pixels read from its header before a pixel is decoded, so a small file that claims a vast picture is
 * refused rather than filling the server's memory — and a JPEG is put upright as its EXIF orientation says (PhotoEnhancer reads it).
 * The PDF engine embeds a JPEG, so the signature is also drawn on white (a transparent PNG's background becomes the paper's) at most
 * 800 pixels a side. Each controller words its own refusals.
 */
final class SignatureImages {

    static final int MAX_BYTES = 1_000_000;
    static final int JPEG_MAX_SIDE = 800;
    /** a picture whose header claims more pixels than this is refused undecoded: a scan of a signature is a few million at most */
    static final long MAX_PIXELS = 16_000_000L;

    private SignatureImages() {
    }

    /** the picture and the size its header states; image null when it could not be decoded or claims more than MAX_PIXELS */
    record Decoded(BufferedImage image, long width, long height) {
        boolean tooManyPixels() {
            return width * height > MAX_PIXELS;
        }
    }

    /** the upload's bytes from base64, a data: prefix allowed; null when it is not base64 */
    static byte[] bytesOf(String contentBase64) {
        String b64 = contentBase64 == null ? "" : contentBase64.trim();
        int comma = b64.indexOf(',');
        if (b64.startsWith("data:") && comma > 0) b64 = b64.substring(comma + 1);
        try {
            return Base64.getDecoder().decode(b64);
        } catch (IllegalArgumentException bad) {
            return null;
        }
    }

    /** "image/png" or "image/jpeg" by the file's first bytes, or null for anything else */
    static String typeOf(byte[] bytes) {
        if (bytes.length > 3 && (bytes[0] & 0xFF) == 0x89 && bytes[1] == 'P' && bytes[2] == 'N' && bytes[3] == 'G') return "image/png";
        if (bytes.length > 2 && (bytes[0] & 0xFF) == 0xFF && (bytes[1] & 0xFF) == 0xD8) return "image/jpeg";
        return null;
    }

    /** the picture, its size read from the header first; a reader's failure on a damaged file is an undecodable file, never a 500 */
    static Decoded decode(byte[] bytes) {
        try (ImageInputStream in = ImageIO.createImageInputStream(new ByteArrayInputStream(bytes))) {
            Iterator<ImageReader> readers = in == null ? null : ImageIO.getImageReaders(in);
            if (readers == null || !readers.hasNext()) return new Decoded(null, 0, 0);
            ImageReader reader = readers.next();
            try {
                reader.setInput(in, true, true);
                long w = reader.getWidth(0), h = reader.getHeight(0);
                if (w <= 0 || h <= 0 || w * h > MAX_PIXELS) return new Decoded(null, w, h);
                BufferedImage img = reader.read(0);
                // a phone stores a JPEG's pixels on their side and says which way is up only in the EXIF tag, which every viewer (the
                // settings screen's preview among them) obeys: put upright here too, or the letter prints the signature turned a
                // quarter, a sliver above the name
                int orientation = "image/jpeg".equals(typeOf(bytes)) ? PhotoEnhancer.jpegOrientation(bytes) : 1;
                return new Decoded(img == null ? null : PhotoEnhancer.upright(img, orientation), w, h);
            } finally {
                reader.dispose();
            }
        } catch (IOException | RuntimeException unreadable) {
            return new Decoded(null, 0, 0);
        }
    }

    /** the JPEG the PDF engine embeds, with its size in pixels */
    record Jpeg(byte[] bytes, int width, int height) {
    }

    /** the signature drawn on white, no larger than 800 pixels on its longest side, as a JPEG the PDF engine embeds */
    static byte[] jpegOnWhite(BufferedImage img) {
        return jpegOf(img).bytes();
    }

    /** the JPEG on white, and its size: a letter fits it to its space without decoding it */
    static Jpeg jpegOf(BufferedImage img) {
        int w = img.getWidth(), h = img.getHeight();
        double k = Math.min(1.0, (double) JPEG_MAX_SIDE / Math.max(w, h));
        int tw = Math.max(1, (int) Math.round(w * k)), th = Math.max(1, (int) Math.round(h * k));
        // halved in steps (keeping the transparency) to within twice the size: one bilinear step down from a far larger scan drops
        // the thin strokes of the ink
        BufferedImage src = img;
        while (src.getWidth() >= tw * 2 && src.getHeight() >= th * 2) {
            int hw = src.getWidth() / 2, hh = src.getHeight() / 2;
            BufferedImage half = new BufferedImage(hw, hh, BufferedImage.TYPE_INT_ARGB);
            draw(half, src, hw, hh);
            src = half;
        }
        BufferedImage rgb = new BufferedImage(tw, th, BufferedImage.TYPE_INT_RGB);
        Graphics2D white = rgb.createGraphics();
        try {
            white.setColor(Color.WHITE);
            white.fillRect(0, 0, tw, th);
        } finally {
            white.dispose();
        }
        draw(rgb, src, tw, th);
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        try {
            ImageIO.write(rgb, "jpeg", out);
        } catch (IOException impossible) {
            throw new IllegalStateException("the JPEG writer is part of the JDK", impossible);
        }
        return new Jpeg(out.toByteArray(), tw, th);
    }

    private static void draw(BufferedImage onto, BufferedImage src, int w, int h) {
        Graphics2D g = onto.createGraphics();
        try {
            g.setRenderingHint(RenderingHints.KEY_INTERPOLATION, RenderingHints.VALUE_INTERPOLATION_BILINEAR);
            g.setRenderingHint(RenderingHints.KEY_RENDERING, RenderingHints.VALUE_RENDER_QUALITY);
            g.drawImage(src, 0, 0, w, h, null);
        } finally {
            g.dispose();
        }
    }
}
