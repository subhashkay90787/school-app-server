package com.school.app.core.directory;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.util.LinkedMultiValueMap;
import org.springframework.web.client.RestClient;

import java.util.List;
import java.util.Map;

/**
 * Nightly refresh of the directory cache from school-auth's internal API (client_credentials, scope
 * directory.read): picks up renames, branch status changes and deactivations of users who haven't signed in.
 * Only branches this server has already seen (directory.school) are refreshed, so a self-hosted server asks
 * only about its own branches.
 */
@Component
@ConditionalOnProperty(name = "app.directory-sync.enabled", havingValue = "true")
public class DirectorySyncJob {

    private static final Logger log = LoggerFactory.getLogger(DirectorySyncJob.class);

    private final JdbcTemplate jdbc;
    private final DirectoryCache cache;
    private final RestClient rest;
    private final String clientId;
    private final String clientSecret;

    public DirectorySyncJob(JdbcTemplate jdbc, DirectoryCache cache,
                            @Value("${app.auth.base-url}") String authBaseUrl,
                            @Value("${app.directory-sync.client-id}") String clientId,
                            @Value("${app.directory-sync.client-secret}") String clientSecret) {
        this.jdbc = jdbc;
        this.cache = cache;
        this.rest = RestClient.builder().baseUrl(authBaseUrl).build();
        this.clientId = clientId;
        this.clientSecret = clientSecret;
    }

    @Scheduled(cron = "${app.directory-sync.cron:0 30 1 * * *}", zone = "${app.directory-sync.zone:Asia/Kolkata}")
    public void run() {
        List<Long> schoolIds = jdbc.queryForList("SELECT school_id FROM directory.school ORDER BY school_id", Long.class);
        if (schoolIds.isEmpty()) {
            return;
        }
        String token = accessToken();
        Map<?, ?> schools = rest.get().uri(u -> u.path("/internal/v1/directory/schools").queryParam("ids", schoolIds.toArray()).build())
                .header("Authorization", "Bearer " + token).retrieve().body(Map.class);
        for (Object o : (List<?>) schools.get("schools")) {
            Map<?, ?> s = (Map<?, ?>) o;
            long schoolId = ((Number) s.get("schoolId")).longValue();
            try {
                @SuppressWarnings("unchecked")
                Map<String, Object> terminology = (Map<String, Object>) s.get("terminology");
                cache.upsertSchool(schoolId, ((Number) s.get("organizationId")).longValue(), (String) s.get("schoolCode"),
                        (String) s.get("schoolName"), (String) s.get("branchCode"), (String) s.get("branchName"),
                        (String) s.get("institutionTypeCode"), terminology, (String) s.get("timezone"), (String) s.get("status"));
                Map<?, ?> page = rest.get().uri("/internal/v1/directory/schools/{id}/users", schoolId)
                        .header("Authorization", "Bearer " + token).retrieve().body(Map.class);
                int n = 0;
                for (Object uo : (List<?>) page.get("users")) {
                    Map<?, ?> u = (Map<?, ?>) uo;
                    jdbc.query("SELECT directory.refresh_user(?, ?, ?, ?, ?, ?, ?)", rs -> null,
                            ((Number) u.get("userId")).longValue(), u.get("firstName"), u.get("lastName"), u.get("phoneNumber"),
                            u.get("email"), u.get("userCategory"), u.get("active"));
                    n++;
                }
                record(schoolId, "OK", null, n);
            } catch (RuntimeException ex) {
                log.warn("Directory refresh failed for school {}: {}", schoolId, ex.getMessage());
                record(schoolId, "FAILED", ex.getMessage(), null);
            }
        }
        cache.reset();
    }

    private String accessToken() {
        var form = new LinkedMultiValueMap<String, String>();
        form.add("grant_type", "client_credentials");
        form.add("scope", "directory.read");
        Map<?, ?> body = rest.post().uri("/oauth2/token").contentType(MediaType.APPLICATION_FORM_URLENCODED)
                .headers(h -> h.setBasicAuth(clientId, clientSecret)).body(form).retrieve().body(Map.class);
        return (String) body.get("access_token");
    }

    private void record(long schoolId, String status, String error, Integer users) {
        jdbc.update("""
                INSERT INTO directory.sync_state (school_id, last_synced_at, last_status, last_error, users_refreshed)
                VALUES (?, now(), ?, ?, ?)
                ON CONFLICT (school_id) DO UPDATE SET last_synced_at = now(), last_status = EXCLUDED.last_status,
                    last_error = EXCLUDED.last_error, users_refreshed = EXCLUDED.users_refreshed
                """, schoolId, status, error, users);
    }
}
