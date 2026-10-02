package ng.edu.moaum.portal.shared;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;

import software.amazon.awssdk.core.ResponseBytes;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.http.urlconnection.UrlConnectionHttpClient;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.DeleteObjectRequest;
import software.amazon.awssdk.services.s3.model.GetObjectRequest;
import software.amazon.awssdk.services.s3.model.GetObjectResponse;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;

/**
 * The object store on Amazon S3. Credentials come from the runtime (the ECS task role on AWS, the
 * default chain elsewhere); nothing is configured in code. The bucket is private; every read goes
 * through the API, after its own authorisation, so no object URL is ever handed to a browser.
 */
@Component
@ConditionalOnProperty(name = "moaum.files.provider", havingValue = "S3")
public class S3FileStore implements FileStore {

    private static final Logger LOG = LoggerFactory.getLogger(S3FileStore.class);
    private final S3Client s3;
    private final String bucket;

    S3FileStore(@Value("${moaum.files.bucket}") String bucket, @Value("${moaum.files.region}") String region) {
        if (bucket == null || bucket.isBlank()) {
            throw new IllegalStateException("MOAUM_FILES_PROVIDER=S3 needs MOAUM_FILES_BUCKET");
        }
        this.bucket = bucket;
        this.s3 = S3Client.builder().region(Region.of(region)).httpClientBuilder(UrlConnectionHttpClient.builder()).build();
        LOG.info("files: S3 bucket {} in {}", bucket, region);
    }

    @Override
    public boolean enabled() {
        return true;
    }

    @Override
    public void put(String key, byte[] bytes, String contentType) {
        s3.putObject(PutObjectRequest.builder().bucket(bucket).key(key).contentType(contentType).contentLength((long) bytes.length).build(),
                RequestBody.fromBytes(bytes));
    }

    @Override
    public byte[] get(String key) {
        ResponseBytes<GetObjectResponse> r = s3.getObjectAsBytes(GetObjectRequest.builder().bucket(bucket).key(key).build());
        return r.asByteArray();
    }

    @Override
    public void delete(String key) {
        s3.deleteObject(DeleteObjectRequest.builder().bucket(bucket).key(key).build());
    }
}
