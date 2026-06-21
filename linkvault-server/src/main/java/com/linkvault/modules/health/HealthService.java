package com.linkvault.modules.health;

import com.linkvault.modules.storage.service.StorageProperties;
import io.minio.BucketExistsArgs;
import io.minio.MinioClient;
import java.time.Instant;
import java.util.LinkedHashMap;
import javax.sql.DataSource;
import org.springframework.data.redis.connection.RedisConnectionFactory;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

@Service
public class HealthService {
    private final JdbcTemplate jdbcTemplate;
    private final RedisConnectionFactory redisConnectionFactory;
    private final MinioClient minioClient;
    private final StorageProperties storageProperties;

    public HealthService(
            DataSource dataSource,
            RedisConnectionFactory redisConnectionFactory,
            MinioClient minioClient,
            StorageProperties storageProperties
    ) {
        this.jdbcTemplate = new JdbcTemplate(dataSource);
        this.redisConnectionFactory = redisConnectionFactory;
        this.minioClient = minioClient;
        this.storageProperties = storageProperties;
    }

    public HealthResponse check() {
        var dependencies = new LinkedHashMap<String, String>();
        dependencies.put("postgresql", checkPostgresql());
        dependencies.put("redis", checkRedis());
        dependencies.put("minio", checkMinio());
        var status = dependencies.values().stream().allMatch("UP"::equals) ? "UP" : "DOWN";
        return new HealthResponse(status, "linkvault-server", Instant.now(), dependencies);
    }

    private String checkPostgresql() {
        try {
            jdbcTemplate.queryForObject("select 1", Integer.class);
            return "UP";
        } catch (Exception ex) {
            return "DOWN";
        }
    }

    private String checkRedis() {
        try (var connection = redisConnectionFactory.getConnection()) {
            var pong = connection.ping();
            return "PONG".equalsIgnoreCase(pong) ? "UP" : "DOWN";
        } catch (Exception ex) {
            return "DOWN";
        }
    }

    private String checkMinio() {
        try {
            var exists = minioClient.bucketExists(BucketExistsArgs.builder()
                    .bucket(storageProperties.bucket())
                    .build());
            return exists ? "UP" : "DOWN";
        } catch (Exception ex) {
            return "DOWN";
        }
    }
}
