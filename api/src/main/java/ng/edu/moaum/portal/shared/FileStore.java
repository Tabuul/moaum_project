package ng.edu.moaum.portal.shared;

/**
 * Where a file's bytes live when they do not live in the database: an object store, addressed by key.
 * The database keeps the fact of the file (platform.file_object: key, type, size, hash, owner); the
 * store keeps the bytes. With no store configured (MOAUM_FILES_PROVIDER=DB) the bytes stay in the
 * database as they always did, and nothing here is called.
 */
public interface FileStore {

    boolean enabled();

    void put(String key, byte[] bytes, String contentType);

    byte[] get(String key);

    void delete(String key);
}
