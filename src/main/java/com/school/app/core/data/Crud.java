package com.school.app.core.data;

import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;
import tools.jackson.core.type.TypeReference;
import tools.jackson.databind.json.JsonMapper;

import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Scoped CRUD for the generated {@code <Tag>Crud} base classes: {@link EntityStore} plus the actor's
 * {@link ScopeService} rules. Keys (path parameters by API field name) and scope-relevant fields of filters and
 * bodies are checked against the actor's scope first, so out-of-scope ids answer 404. Each call is one
 * transaction (the scope checks see the same RLS context as the statement).
 */
@Component
public class Crud {

    private static final TypeReference<Map<String, Object>> MAP = new TypeReference<>() {};

    private final org.springframework.jdbc.core.JdbcTemplate jdbc;
    private final EntityStore store;
    private final ScopeService scope;
    private final JsonMapper json;

    public Crud(EntityStore store, ScopeService scope, JsonMapper json, org.springframework.jdbc.core.JdbcTemplate jdbc) {
        this.jdbc = jdbc;
        this.store = store;
        this.scope = scope;
        this.json = json;
    }

    /** Builds a key map from alternating field names and values; null values are dropped. */
    public static Map<String, Object> keys(Object... kv) {
        Map<String, Object> m = new LinkedHashMap<>();
        for (int i = 0; i + 1 < kv.length; i += 2) {
            if (kv[i + 1] != null) m.put((String) kv[i], kv[i + 1]);
        }
        return m;
    }

    private Query scoped(String actor, String table, boolean mine, Map<String, Object> keys, Query q) {
        Query query = q == null ? Query.create() : q;
        keys.forEach((k, v) -> {
            scope.check(actor, k, v);
            query.eq(k, v);
        });
        scope.checkBody(actor, query.filters);
        return query.where(scope.rows(actor, table, mine));
    }

    @Transactional(readOnly = true)
    public <T> T one(String actor, String table, Class<T> type, boolean mine, Map<String, Object> keys) {
        return store.get(table, type, scoped(actor, table, mine, keys, null));
    }

    @Transactional(readOnly = true)
    public <T> List<T> list(String actor, String table, Class<T> type, boolean mine, Map<String, Object> keys, Query q) {
        return store.list(table, type, scoped(actor, table, mine, keys, q));
    }

    @Transactional(readOnly = true)
    public <P> P page(String actor, String table, Class<P> pageType, Class<?> itemType, boolean mine,
                      Map<String, Object> keys, Query q) {
        PageResult<?> r = store.page(table, itemType, scoped(actor, table, mine, keys, q));
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("items", r.items());
        m.put("page", r.page());
        m.put("size", r.size());
        m.put("total", r.total());
        return json.convertValue(m, pageType);
    }

    /**
     * Insert. A student's rows always belong to the student (studentId is theirs whatever the body says); with
     * {@code mine} the row's user_id is the caller (self-service: my leave, my requests).
     */
    @Transactional
    public <T> T create(String actor, String table, Class<T> type, boolean mine, Object body, Map<String, Object> fixed) {
        Map<String, Object> values = new LinkedHashMap<>(fixed);
        if (actor.equals("student") && store.table(table).has("student_id")) {
            Long me = jdbc.queryForObject("SELECT api.my_student()", Long.class);
            if (me == null) throw new java.util.NoSuchElementException("No student record for this login");
            values.put("studentId", me);
        }
        if (mine && store.table(table).has("user_id")) {
            values.put("userId", com.school.app.core.tenant.TenantContext.require().userId());
        }
        checkFields(actor, body, values);
        return store.insert(table, type, body, values);
    }

    @Transactional
    public <T> T update(String actor, String table, Class<T> type, boolean mine, Map<String, Object> keys, Object body) {
        checkFields(actor, body, Map.of());
        return store.update(table, type, scoped(actor, table, mine, keys, null), body, Map.of());
    }

    @Transactional
    public <T> T upsert(String actor, String table, Class<T> type, Object body, Map<String, Object> fixed) {
        checkFields(actor, body, fixed);
        return store.upsert(table, type, body, fixed);
    }

    @Transactional
    public void delete(String actor, String table, boolean mine, Map<String, Object> keys) {
        store.delete(table, scoped(actor, table, mine, keys, null));
    }

    private void checkFields(String actor, Object body, Map<String, Object> fixed) {
        Map<String, Object> fields = new HashMap<>();
        if (body != null) fields.putAll(json.convertValue(body, MAP));
        fields.putAll(fixed);
        scope.checkBody(actor, fields);
    }
}
