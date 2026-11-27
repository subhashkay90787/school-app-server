package com.school.app.core.data;

import com.school.app.core.tenant.TenantContext;
import jakarta.annotation.PostConstruct;
import org.springframework.core.io.Resource;
import org.springframework.core.io.support.PathMatchingResourcePatternResolver;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;
import tools.jackson.core.type.TypeReference;
import tools.jackson.databind.JavaType;
import tools.jackson.databind.json.JsonMapper;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.sql.Types;
import java.time.temporal.TemporalAccessor;
import java.util.*;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Screen queries: one SQL statement per operation in {@code classpath:views/<actor>.sql}, each returning one row
 * with one JSON column that is the whole response body (built with jsonb_build_object / jsonb_agg and the api.*
 * helpers from V5). Blocks start with {@code -- name: <operationId>} and may add {@code write} for statements
 * that change data (a data-modifying CTE ending in the response JSON).
 *
 * <p>Parameters are bound by name as text, so the SQL casts them ({@code :studentId::bigint}, {@code :from::date});
 * absent ones are NULL. Always available: {@code :me} (caller's user id), {@code :school} (X-School-Id) and, for
 * writes, {@code :body} (the request body as JSON text, read with {@code :body::jsonb ->> 'field'}). Ids that
 * identify a family's or class's records are checked against the actor's scope first (404 outside it), and RLS
 * keeps every statement inside the branch.
 *
 * <p>A write whose response must show the changed rows (rows changed by a data-modifying CTE are not visible to
 * the rest of that statement) is split by a line {@code -- then}: the first statement makes the change and returns
 * one value in a column named {@code result} (usually the id), the second builds the response with it as
 * {@code :result}.
 */
@Component
public class Views {

    private static final Pattern BLOCK = Pattern.compile("^--\\s*name:\\s*(\\w+)(\\s+write)?\\s*$", Pattern.MULTILINE);
    private static final TypeReference<Map<String, Object>> MAP = new TypeReference<>() {};

    record Stmt(String sql, boolean write) {}

    private final NamedParameterJdbcTemplate jdbc;
    private final ScopeService scope;
    private final JsonMapper json;
    private final Map<String, Stmt> statements = new HashMap<>();

    public Views(NamedParameterJdbcTemplate jdbc, ScopeService scope, JsonMapper json) {
        this.jdbc = jdbc;
        this.scope = scope;
        this.json = json;
    }

    @PostConstruct
    void load() throws IOException {
        for (Resource r : new PathMatchingResourcePatternResolver().getResources("classpath:views/*.sql")) {
            String actor = Objects.requireNonNull(r.getFilename()).replace(".sql", "");
            String text = r.getContentAsString(StandardCharsets.UTF_8);
            Matcher m = BLOCK.matcher(text);
            List<int[]> starts = new ArrayList<>();
            List<String[]> heads = new ArrayList<>();
            while (m.find()) {
                starts.add(new int[]{m.start(), m.end()});
                heads.add(new String[]{m.group(1), m.group(2)});
            }
            for (int i = 0; i < starts.size(); i++) {
                int end = i + 1 < starts.size() ? starts.get(i + 1)[0] : text.length();
                String sql = text.substring(starts.get(i)[1], end).trim().replaceAll(";\\s*$", "");
                statements.put(actor + "." + heads.get(i)[0], new Stmt(sql, heads.get(i)[1] != null));
            }
        }
    }

    public boolean has(String actor, String opId) {
        return statements.containsKey(actor + "." + opId);
    }

    @Transactional(readOnly = true)
    public <T> T one(String actor, String opId, Class<T> type, Map<String, Object> params) {
        return json.readValue(body(actor, opId, params, null), type);
    }

    @Transactional(readOnly = true)
    public <T> List<T> list(String actor, String opId, Class<T> type, Map<String, Object> params) {
        JavaType listType = json.getTypeFactory().constructCollectionType(List.class, type);
        return json.readValue(body(actor, opId, params, null), listType);
    }

    /** A statement marked {@code write}: runs in a read-write transaction with {@code :body}. */
    @Transactional
    public <T> T write(String actor, String opId, Class<T> type, Map<String, Object> params, Object requestBody) {
        String out = body(actor, opId, params, requestBody);
        return type == Void.class ? null : json.readValue(out, type);
    }

    private String body(String actor, String opId, Map<String, Object> params, Object requestBody) {
        Stmt stmt = statements.get(actor + "." + opId);
        if (stmt == null) {
            throw new IllegalStateException("No view query " + actor + "." + opId);
        }
        params.forEach((k, v) -> scope.check(actor, k, v));
        MapSqlParameterSource src = new MapSqlParameterSource();
        params.forEach((k, v) -> src.addValue(k, text(v), Types.VARCHAR));
        var ctx = TenantContext.require();
        src.addValue("me", String.valueOf(ctx.userId()), Types.VARCHAR);
        src.addValue("school", ctx.currentSchool().map(s -> String.valueOf(s.schoolId())).orElse(null), Types.VARCHAR);
        if (requestBody != null) {
            // an object, or a list of objects for bulk bodies (PUT .../policies)
            Object tree = json.convertValue(requestBody, Object.class);
            List<?> items = tree instanceof List<?> l ? l : List.of(tree);
            for (Object item : items) {
                if (item instanceof Map<?, ?> m) scope.checkBody(actor, json.convertValue(m, MAP));
            }
            src.addValue("body", json.writeValueAsString(tree), Types.VARCHAR);
        } else {
            src.addValue("body", "{}", Types.VARCHAR);
        }
        // a named parameter the statement uses but the operation doesn't have is bound as NULL
        Matcher m = Pattern.compile("(?<![:\\w]):(\\w+)").matcher(stmt.sql());
        while (m.find()) {
            if (!src.hasValue(m.group(1)) && !m.group(1).equals("result")) src.addValue(m.group(1), null, Types.VARCHAR);
        }
        String[] parts = stmt.sql().split("\\n--\\s*then\\s*\\n", 2);
        String out = single(parts[0], src);
        if (parts.length == 2) {
            src.addValue("result", out, Types.VARCHAR);
            out = single(parts[1], src);
        }
        return out;
    }

    private String single(String sql, MapSqlParameterSource src) {
        List<String> rows = jdbc.query(sql.trim().replaceAll(";\\s*$", ""), src, (rs, i) -> rs.getString(1));
        if (rows.isEmpty() || rows.get(0) == null) {
            throw new NoSuchElementException("Not found in this branch");
        }
        return rows.get(0);
    }

    private String text(Object v) {
        if (v == null) return null;
        if (v instanceof Enum<?> || v instanceof Number || v instanceof CharSequence || v instanceof Boolean
                || v instanceof TemporalAccessor || v instanceof UUID) {
            return v.toString();
        }
        return json.writeValueAsString(v);
    }
}
