package ng.edu.moaum.portal.shared;

import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.Base64;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Component;

/**
 * A file's bytes go to the object store when one is configured, and the fact of the file to
 * platform.file_object; the owning row keeps the object's id instead of the bytes. Without a store,
 * {@link #store} answers null and the caller writes the bytes to the database as before, so every
 * upload path has exactly one branch: {@code object_id = files.store(...)}, {@code content = object_id
 * == null ? bytes : null}. Reading is the mirror: {@link #resolve} returns the database bytes when
 * they are there and fetches from the store when the row carries an object id.
 *
 * Nothing is uploaded twice: the bytes are hashed first, and an owner that already holds an object
 * with that SHA-256 gets the same object back without a put. An object a row stops pointing at is
 * removed with {@link #forget}, which refuses while any other row still points at it.
 */
@Component
public class FileObjects {

    /** an object's bytes with the type it was stored as */
    public record Typed(byte[] bytes, String contentType) {
    }

    private final FileStore store;
    private final JdbcClient jdbc;

    FileObjects(FileStore store, JdbcClient jdbc) {
        this.store = store;
        this.jdbc = jdbc;
    }

    public boolean enabled() {
        return store.enabled();
    }

    /**
     * The object for these bytes under this owner: the one already held when the owner has an object
     * with the same SHA-256 (no upload), else a new one, put and recorded. Null when there is no
     * store and the bytes are to stay in the database. Called inside the owner's transaction, so a
     * failed owner insert rolls the record back (the object itself is then an orphan nothing can
     * reach).
     */
    public UUID store(String owner, Object ownerId, String filename, String contentType, byte[] bytes) {
        if (!store.enabled()) {
            return null;
        }
        byte[] hash = sha256(bytes);
        Optional<UUID> same = jdbc.sql("SELECT id FROM platform.file_object WHERE owner_table = :o AND owner_id = :oid AND sha256 = :h ORDER BY created_at LIMIT 1")
                .param("o", owner).param("oid", String.valueOf(ownerId)).param("h", hash).query(UUID.class).optional();
        if (same.isPresent()) {
            return same.get();
        }
        UUID id = UUID.randomUUID();
        String type = contentType == null || contentType.isBlank() ? "application/octet-stream" : contentType;
        String key = owner.replace('.', '/') + "/" + ownerId + "/" + id + extensionFor(type, filename);
        store.put(key, bytes, type);
        jdbc.sql("""
                INSERT INTO platform.file_object (id, object_key, content_type, size_bytes, sha256, owner_table, owner_id)
                VALUES (:id, :k, :t, :n, :h, :o, :oid)
                """).param("id", id).param("k", key).param("t", type).param("n", (long) bytes.length)
                .param("h", hash).param("o", owner).param("oid", String.valueOf(ownerId)).update();
        return id;
    }

    /** Whether the object holds exactly these bytes, by SHA-256; false for null. */
    public boolean holds(UUID objectId, byte[] bytes) {
        if (objectId == null) {
            return false;
        }
        return jdbc.sql("SELECT sha256 = :h FROM platform.file_object WHERE id = :id").param("h", sha256(bytes)).param("id", objectId)
                .query(Boolean.class).optional().orElse(false);
    }

    /** The bytes of a stored object, with its type. */
    public Typed typed(UUID objectId) {
        Map<String, Object> r = jdbc.sql("SELECT object_key, content_type FROM platform.file_object WHERE id = :id").param("id", objectId)
                .query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("file object", objectId));
        return new Typed(store.get(String.valueOf(r.get("object_key"))), String.valueOf(r.get("content_type")));
    }

    /** The bytes of a stored object. */
    public byte[] load(UUID objectId) {
        return typed(objectId).bytes();
    }

    /** The row's bytes: from the database when present, else from the store by the row's object id. */
    public byte[] resolve(byte[] content, UUID objectId) {
        if (content != null) {
            return content;
        }
        return objectId == null ? null : load(objectId);
    }

    /** A data URL as the screens expect it: the stored one, or one built from the object. */
    public String dataUrl(String dataUrl, UUID objectId) {
        if (dataUrl != null && !dataUrl.isBlank()) {
            return dataUrl;
        }
        if (objectId == null) {
            return null;
        }
        Typed t = typed(objectId);
        return "data:" + t.contentType() + ";base64," + Base64.getEncoder().encodeToString(t.bytes());
    }

    /**
     * Removes an object no row points at any more: the record first (the foreign keys refuse while
     * another row still holds it, and then the object stays), the bytes in the store second.
     */
    public void forget(UUID objectId) {
        if (objectId == null) {
            return;
        }
        Optional<String> key = jdbc.sql("SELECT object_key FROM platform.file_object WHERE id = :id").param("id", objectId).query(String.class).optional();
        if (key.isEmpty()) {
            return;
        }
        try {
            if (jdbc.sql("DELETE FROM platform.file_object WHERE id = :id").param("id", objectId).update() == 0) {
                return;
            }
        } catch (DataIntegrityViolationException stillReferenced) {
            return;
        }
        store.delete(key.get());
    }

    public static byte[] sha256(byte[] bytes) {
        try {
            return MessageDigest.getInstance("SHA-256").digest(bytes);
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
    }

    static String extensionFor(String contentType, String filename) {
        String t = contentType == null ? "" : contentType.toLowerCase();
        switch (t) {
            case "image/jpeg": return ".jpg";
            case "image/png": return ".png";
            case "application/pdf": return ".pdf";
            case "application/zip": return ".zip";
            case "application/vnd.openxmlformats-officedocument.wordprocessingml.document": return ".docx";
            case "application/vnd.openxmlformats-officedocument.presentationml.presentation": return ".pptx";
            default:
                if (filename != null) {
                    int dot = filename.lastIndexOf('.');
                    if (dot > 0 && dot < filename.length() - 1 && filename.length() - dot <= 6 && filename.substring(dot + 1).matches("[A-Za-z0-9]+")) {
                        return "." + filename.substring(dot + 1).toLowerCase();
                    }
                }
                return "";
        }
    }
}
