package ng.edu.moaum.portal.shared;

import java.net.URI;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;

import software.amazon.awssdk.auth.credentials.AwsBasicCredentials;
import software.amazon.awssdk.auth.credentials.StaticCredentialsProvider;
import software.amazon.awssdk.core.ResponseBytes;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.http.urlconnection.UrlConnectionHttpClient;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.S3ClientBuilder;
import software.amazon.awssdk.services.s3.S3Configuration;
import software.amazon.awssdk.services.s3.model.DeleteObjectRequest;
import software.amazon.awssdk.services.s3.model.GetObjectRequest;
import software.amazon.awssdk.services.s3.model.GetObjectResponse;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;

/**
 * The object store, over the S3 API. On AWS the bucket is Amazon S3 and the credentials are the ECS
 * task role (nothing configured). Anywhere else — a Railway Bucket, or any S3-compatible service —
 * MOAUM_FILES_ENDPOINT names the service and MOAUM_FILES_ACCESS_KEY_ID / _SECRET_ACCESS_KEY its key
 * pair. The bucket is private either way; every read goes through the API after its own
 * authorisation, so no object URL is ever handed to a browser.
 */
@Component
@ConditionalOnProperty(name = "moaum.files.provider", havingValue = "S3")
public class S3FileStore implements FileStore {

    private static final Logger LOG = LoggerFactory.getLogger(S3FileStore.class);
    private final S3Client s3;
    private final String bucket;

    S3FileStore(@Value("${moaum.files.bucket}") String bucket,
                @Value("${moaum.files.region}") String region,
                @Value("${moaum.files.endpoint:}") String endpoint,
                @Value("${moaum.files.access-key-id:}") String accessKeyId,
                @Value("${moaum.files.secret-access-key:}") String secretAccessKey,
                @Value("${moaum.files.path-style:false}") boolean pathStyle) {
        if (bucket == null || bucket.isBlank()) {
            throw new IllegalStateException("MOAUM_FILES_PROVIDER=S3 needs MOAUM_FILES_BUCKET");
        }
        this.bucket = bucket;
        S3ClientBuilder b = S3Client.builder()
                .region(Region.of(region == null || region.isBlank() ? "auto" : region))
                .httpClientBuilder(UrlConnectionHttpClient.builder());
        if (endpoint != null && !endpoint.isBlank()) {
            b = b.endpointOverride(URI.create(endpoint))
                 .serviceConfiguration(S3Configuration.builder().pathStyleAccessEnabled(pathStyle).build());
        }
        if (accessKeyId != null && !accessKeyId.isBlank()) {
            b = b.credentialsProvider(StaticCredentialsProvider.create(AwsBasicCredentials.create(accessKeyId, secretAccessKey)));
        }
        this.s3 = b.build();
        LOG.info("files: bucket {} at {} ({} credentials)", bucket,
                endpoint == null || endpoint.isBlank() ? "Amazon S3 " + region : endpoint,
                accessKeyId == null || accessKeyId.isBlank() ? "runtime" : "configured");
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
