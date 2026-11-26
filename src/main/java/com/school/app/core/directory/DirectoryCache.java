package com.school.app.core.directory;

import com.school.app.core.security.AuthUser;
import com.school.app.core.security.SchoolAccess;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;
import tools.jackson.databind.json.JsonMapper;

import java.time.Duration;
import java.time.Instant;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Keeps directory.school / directory.app_user (the thin cache of auth ids) in step with verified token claims.
 * Writes go through the SECURITY DEFINER upsert functions; at most once per 5 minutes per branch / user per
 * instance (the functions themselves also only rewrite last_seen_at every 5 minutes).
 */
@Component
public class DirectoryCache {

    private static final Logger log = LoggerFactory.getLogger(DirectoryCache.class);
    private static final Duration INTERVAL = Duration.ofMinutes(5);

    private final JdbcTemplate jdbc;
    private final JsonMapper jsonMapper;
    private final Map<String, Instant> lastWrite = new ConcurrentHashMap<>();

    public DirectoryCache(JdbcTemplate jdbc, JsonMapper jsonMapper) {
        this.jdbc = jdbc;
        this.jsonMapper = jsonMapper;
    }

    public void touch(AuthUser user, SchoolAccess school) {
        Instant now = Instant.now();
        if (due("s:" + school.schoolId() + ":" + school.permVersion(), now)) {
            upsertSchool(school.schoolId(), school.organizationId(), school.schoolCode(), school.schoolName(),
                    school.branchCode(), school.branchName(), school.institutionType(), school.terminology(),
                    school.timezone(), school.status());
        }
        if (due("u:" + user.userId(), now)) {
            upsertUser(user.userId(), user.firstName(), user.lastName(), user.phoneNumber(), user.email(),
                    user.userCategory(), user.active());
        }
    }

    public void upsertSchool(long schoolId, long organizationId, String code, String name, String branchCode,
                             String branchName, String institutionType, Map<String, Object> terminology,
                             String timezone, String status) {
        jdbc.query("SELECT directory.upsert_school_from_token(?, ?, ?, ?, ?, ?, ?, ?::jsonb, ?, ?)",
                rs -> null, schoolId, organizationId, code, name, branchCode, branchName, institutionType,
                jsonMapper.writeValueAsString(terminology == null ? Map.of() : terminology), timezone, status);
    }

    public void upsertUser(long userId, String first, String last, String phone, String email, String category, boolean active) {
        jdbc.query("SELECT directory.upsert_user_from_token(?, ?, ?, ?, ?, ?, ?)", rs -> null,
                userId, first == null ? "" : first, last, phone, email, category == null ? "STAFF" : category, active);
    }

    private boolean due(String key, Instant now) {
        Instant previous = lastWrite.get(key);
        if (previous != null && previous.plus(INTERVAL).isAfter(now)) {
            return false;
        }
        lastWrite.put(key, now);
        return true;
    }

    /** Test / ops hook: forget throttling (e.g. after a rename pushed by the nightly refresh). */
    public void reset() {
        lastWrite.clear();
        log.debug("Directory cache throttle reset");
    }
}
