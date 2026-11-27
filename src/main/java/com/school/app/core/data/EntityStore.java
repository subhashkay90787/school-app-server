package com.school.app.core.data;

import com.school.app.core.data.TableRegistry.Column;
import com.school.app.core.data.TableRegistry.Table;
import com.school.app.core.tenant.TenantContext;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;
import tools.jackson.core.type.TypeReference;
import tools.jackson.databind.json.JsonMapper;

import java.sql.*;
import java.time.OffsetDateTime;
import java.util.*;

/**
 * Generic CRUD over the school tables, driven by {@link TableRegistry}. API models (generated from the specs) are
 * converted to and from rows by their camelCase field names, which match the columns one to one.
 *
 * <p>Every call runs in a transaction, so the tenant-aware transaction manager has set the RLS context: rows are
 * limited to the X-School-Id branch without any school_id filter here. Inserts take school_id from the request.
 * Scope rules inside a branch (own children, own classes ...) arrive as {@link Pred}s from the callers.
 *
 * <p>PUT semantics: the fields present (non-null) in the body are written; others keep their value.
 */
@Component
public class EntityStore {

    private static final TypeReference<Map<String, Object>> MAP = new TypeReference<>() {};

    /** Columns filled with the caller's user id on insert when the body doesn't set them. */
    private static final Set<String> ACTOR_COLUMNS = Set.of(
            "created_by_user_id", "requested_by_user_id", "submitted_by_user_id", "reported_by_user_id",
            "logged_by_user_id", "raised_by_user_id", "uploaded_by_user_id", "entered_by_user_id",
            "registered_by_user_id", "recorded_by_user_id", "added_by_user_id", "performed_by_user_id",
            "issued_by_user_id", "sent_by_user_id", "conducted_by_user_id", "inspected_by_user_id",
            "scheduled_by_user_id", "allocated_by_user_id", "assigned_by_user_id", "handled_by_user_id",
            "done_by_user_id", "published_by_user_id", "received_by_user_id", "sold_by_user_id", "marked_by_user_id",
            "updated_by_user_id", "author_user_id", "sender_user_id", "computed_by_user_id");

    /**
     * Server-generated values for required columns the API never takes (document numbers, codes, today's date):
     * table -> column -> SQL expression, used on insert when the column is not set. Numbers are per branch (RLS);
     * two concurrent inserts can collide on the unique key and answer 409, and the client retries.
     */
    private static final Map<String, Map<String, String>> GENERATED = Map.of(
            "records.certificate", Map.of(
                    "serial_number", nextNumber("records.certificate", "serial_number", "CERT-"),
                    "verification_code", "upper(substr(md5(random()::text || clock_timestamp()::text), 1, 10))"),
            "accounts.expense", Map.of("voucher_number", nextNumber("accounts.expense", "voucher_number", "EXP-")),
            "admissions.application", Map.of("application_number", nextNumber("admissions.application", "application_number",
                    "APP-' || to_char(current_date, 'YY') || '-")),
            "inventory.requisition", Map.of("requisition_number", nextNumber("inventory.requisition", "requisition_number", "REQ-")),
            "inventory.purchase_order", Map.of("po_number", nextNumber("inventory.purchase_order", "po_number", "PO-")),
            "inventory.goods_receipt", Map.of("grn_number", nextNumber("inventory.goods_receipt", "grn_number", "GRN-")),
            "assessment.student_behavior_log", Map.of("log_date", "current_date"),
            "records.id_card", Map.of("card_number", nextNumber("records.id_card", "card_number", "ID-")));

    /** prefix + (highest trailing number in the column + 1), at least 4 digits. */
    private static String nextNumber(String table, String column, String prefix) {
        return "(SELECT '" + prefix + "' || lpad((coalesce(max(substring(\"" + column + "\" FROM '(\\d+)$')::bigint), 0) + 1)::text, 4, '0') FROM "
                + table + ")";
    }

    private final TableRegistry registry;
    private final JdbcTemplate jdbc;
    private final JsonMapper json;

    public EntityStore(TableRegistry registry, JdbcTemplate jdbc, JsonMapper json) {
        this.registry = registry;
        this.jdbc = jdbc;
        this.json = json;
    }

    public Table table(String name) {
        return registry.table(name);
    }

    // ------------------------------------------------------------------ reads

    @Transactional(readOnly = true)
    public <T> PageResult<T> page(String tableName, Class<T> type, Query q) {
        Table t = registry.table(tableName);
        List<Object> params = new ArrayList<>();
        String where = where(t, q, params);
        long total = Optional.ofNullable(jdbc.queryForObject("SELECT count(*) FROM " + t.qualified() + where, Long.class,
                params.toArray())).orElse(0L);
        List<Object> pageParams = new ArrayList<>(params);
        pageParams.add(q.size);
        pageParams.add((long) q.page * q.size);
        List<T> items = jdbc.query("SELECT * FROM " + t.qualified() + where + orderBy(t) + " LIMIT ? OFFSET ?",
                (rs, i) -> toModel(t, rs, type), pageParams.toArray());
        return new PageResult<>(items, q.page, q.size, total);
    }

    @Transactional(readOnly = true)
    public <T> List<T> list(String tableName, Class<T> type, Query q) {
        return page(tableName, type, q.page == 0 && q.size == 50 ? q.unpaged() : q).items();
    }

    @Transactional(readOnly = true)
    public <T> Optional<T> find(String tableName, Class<T> type, Query q) {
        Table t = registry.table(tableName);
        List<Object> params = new ArrayList<>();
        String where = where(t, q, params);
        List<T> rows = jdbc.query("SELECT * FROM " + t.qualified() + where + orderBy(t) + " LIMIT 1",
                (rs, i) -> toModel(t, rs, type), params.toArray());
        return rows.stream().findFirst();
    }

    @Transactional(readOnly = true)
    public <T> T get(String tableName, Class<T> type, Query q) {
        return find(tableName, type, q).orElseThrow(() ->
                new NoSuchElementException("Not found in this branch: " + registry.table(tableName).model()));
    }

    // ------------------------------------------------------------------ writes

    /**
     * Inserts a row from an API body. {@code fixed} (API field name -> value) wins over the body: path parameters
     * and server-set values.
     */
    @Transactional
    public <T> T insert(String tableName, Class<T> type, Object body, Map<String, Object> fixed) {
        Table t = registry.table(tableName);
        Map<String, Object> values = bodyValues(t, body, fixed, true);
        long schoolId = currentSchool();
        List<String> cols = new ArrayList<>(List.of("\"school_id\""));
        List<String> marks = new ArrayList<>(List.of("?"));
        List<Object> params = new ArrayList<>(List.of(schoolId));
        values.forEach((col, value) -> {
            Column c = t.column(col).orElseThrow();
            cols.add("\"" + col + "\"");
            marks.add("?" + c.cast());
            params.add(bind(c, value));
        });
        GENERATED.getOrDefault(tableName, Map.of()).forEach((col, expr) -> {
            if (!values.containsKey(col) && t.has(col)) {
                cols.add("\"" + col + "\"");
                marks.add(expr);
            }
        });
        String sql = "INSERT INTO " + t.qualified() + " (" + String.join(", ", cols) + ") VALUES (" + String.join(", ", marks)
                + ") RETURNING *";
        return jdbc.query(sql, rs -> {
            rs.next();
            return toModel(t, rs, type);
        }, params.toArray());
    }

    /** Updates the row matched by {@code q} with the non-null fields of {@code body}; 404 when no row matches. */
    @Transactional
    public <T> T update(String tableName, Class<T> type, Query q, Object body, Map<String, Object> fixed) {
        Table t = registry.table(tableName);
        Map<String, Object> values = bodyValues(t, body, fixed, false);
        if (t.pk() != null) values.remove(t.pk());
        t.pkc().forEach(values::remove);
        if (values.isEmpty()) {
            return get(tableName, type, q);
        }
        List<Object> params = new ArrayList<>();
        List<String> sets = new ArrayList<>();
        values.forEach((col, value) -> {
            Column c = t.column(col).orElseThrow();
            sets.add("\"" + col + "\" = ?" + c.cast());
            params.add(bind(c, value));
        });
        String where = where(t, q, params);
        List<T> rows = jdbc.query("UPDATE " + t.qualified() + " SET " + String.join(", ", sets) + where + " RETURNING *",
                (rs, i) -> toModel(t, rs, type), params.toArray());
        if (rows.isEmpty()) {
            throw new NoSuchElementException("Not found in this branch: " + t.model());
        }
        return rows.get(0);
    }

    /** Insert or update by the table's composite key (school_id + pkc columns), for one-per-person records. */
    @Transactional
    public <T> T upsert(String tableName, Class<T> type, Object body, Map<String, Object> fixed) {
        Table t = registry.table(tableName);
        List<String> key = new ArrayList<>(List.of("school_id"));
        key.addAll(t.pkSchool() ? List.of() : t.pkc());
        Map<String, Object> values = bodyValues(t, body, fixed, true);
        List<String> cols = new ArrayList<>(List.of("\"school_id\""));
        List<String> marks = new ArrayList<>(List.of("?"));
        List<Object> params = new ArrayList<>(List.of(currentSchool()));
        List<String> sets = new ArrayList<>();
        values.forEach((col, value) -> {
            Column c = t.column(col).orElseThrow();
            cols.add("\"" + col + "\"");
            marks.add("?" + c.cast());
            params.add(bind(c, value));
            if (!key.contains(col)) sets.add("\"" + col + "\" = EXCLUDED.\"" + col + "\"");
        });
        String conflict = key.stream().map(k -> "\"" + k + "\"").reduce((a, b) -> a + ", " + b).orElseThrow();
        String sql = "INSERT INTO " + t.qualified() + " (" + String.join(", ", cols) + ") VALUES (" + String.join(", ", marks)
                + ") ON CONFLICT (" + conflict + ") DO " + (sets.isEmpty() ? "NOTHING" : "UPDATE SET " + String.join(", ", sets))
                + " RETURNING *";
        List<T> rows = jdbc.query(sql, (rs, i) -> toModel(t, rs, type), params.toArray());
        if (rows.isEmpty()) {
            Query q = Query.create();
            values.forEach((col, v) -> {
                if (key.contains(col)) q.eq(t.column(col).orElseThrow().camel(), v);
            });
            return get(tableName, type, q);
        }
        return rows.get(0);
    }

    @Transactional
    public void delete(String tableName, Query q) {
        Table t = registry.table(tableName);
        List<Object> params = new ArrayList<>();
        String where = where(t, q, params);
        if (q.filters.isEmpty() && q.preds.isEmpty()) {
            throw new IllegalArgumentException("Refusing to delete without a key");
        }
        int n = jdbc.update("DELETE FROM " + t.qualified() + where, params.toArray());
        if (n == 0) {
            throw new NoSuchElementException("Not found in this branch: " + t.model());
        }
    }

    // ------------------------------------------------------------------ SQL helpers

    private String where(Table t, Query q, List<Object> params) {
        List<String> parts = new ArrayList<>();
        q.filters.forEach((field, value) -> {
            Column c = t.byCamel(field).orElse(null);
            if (c == null) {
                return; // a filter this table doesn't have: ignored
            }
            parts.add("\"" + c.name() + "\" = ?" + c.cast());
            params.add(bind(c, value));
        });
        if (q.search != null && !t.searchColumns().isEmpty()) {
            List<String> like = new ArrayList<>();
            for (String col : t.searchColumns()) {
                like.add("\"" + col + "\"::text ILIKE ?");
                params.add("%" + q.search + "%");
            }
            parts.add("(" + String.join(" OR ", like) + ")");
        }
        if (t.dateColumn() != null) {
            String dc = "\"" + t.dateColumn() + "\"::date";
            if (q.date != null) {
                parts.add(dc + " = ?::date");
                params.add(q.date.toString());
            }
            if (q.from != null) {
                parts.add(dc + " >= ?::date");
                params.add(q.from.toString());
            }
            if (q.to != null) {
                parts.add(dc + " <= ?::date");
                params.add(q.to.toString());
            }
        }
        for (Pred p : q.preds) {
            parts.add("(" + p.sql() + ")");
            params.addAll(p.params());
        }
        return parts.isEmpty() ? "" : " WHERE " + String.join(" AND ", parts);
    }

    private static String orderBy(Table t) {
        List<String> order = new ArrayList<>();
        if (t.dateColumn() != null) order.add("\"" + t.dateColumn() + "\" DESC NULLS LAST");
        if (t.pk() != null) order.add("\"" + t.pk() + "\" DESC");
        else t.pkc().forEach(c -> order.add("\"" + c + "\""));
        return order.isEmpty() ? "" : " ORDER BY " + String.join(", ", order);
    }

    private Map<String, Object> bodyValues(Table t, Object body, Map<String, Object> fixed, boolean insert) {
        Map<String, Object> values = new LinkedHashMap<>();
        if (body != null) {
            Map<String, Object> m = body instanceof Map<?, ?> raw ? castMap(raw) : json.convertValue(body, MAP);
            m.forEach((field, value) -> {
                if (value == null || field.equals("schoolId")) return;
                t.byCamel(field).ifPresent(c -> {
                    if (insert && c.name().equals(t.pk())) return; // identity
                    values.put(c.name(), value);
                });
            });
        }
        if (fixed != null) {
            fixed.forEach((field, value) -> {
                if (value != null) t.byCamel(field).ifPresent(c -> values.put(c.name(), value));
            });
        }
        if (insert) {
            long me = TenantContext.require().userId();
            for (Column c : t.columns()) {
                if (ACTOR_COLUMNS.contains(c.name()) && !values.containsKey(c.name())) {
                    values.put(c.name(), me);
                }
            }
        }
        return values;
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> castMap(Map<?, ?> raw) {
        return (Map<String, Object>) raw;
    }

    private Object bind(Column c, Object value) {
        if (value == null) return null;
        return switch (c.type()) {
            case "j" -> value instanceof String s ? s : json.writeValueAsString(value);
            case "a" -> value instanceof Collection<?> col ? col.stream().map(String::valueOf).toArray(String[]::new) : value;
            case "d", "dt", "tm", "u" -> value.toString();
            case "b" -> value instanceof Number n ? n.longValue() : Long.valueOf(value.toString());
            case "i" -> value instanceof Number n ? n.intValue() : Integer.valueOf(value.toString());
            case "bo" -> value instanceof Boolean ? value : Boolean.valueOf(value.toString());
            default -> value instanceof Enum<?> e ? e.toString() : value;
        };
    }

    <T> T toModel(Table t, ResultSet rs, Class<T> type) throws SQLException {
        Map<String, Object> m = new LinkedHashMap<>();
        Object school = rs.getObject("school_id");
        if (school != null) m.put("schoolId", ((Number) school).longValue());
        for (Column c : t.columns()) {
            m.put(c.camel(), read(c, rs));
        }
        return json.convertValue(m, type);
    }

    private Object read(Column c, ResultSet rs) throws SQLException {
        String col = c.name();
        Object v = rs.getObject(col);
        if (v == null) return null;
        return switch (c.type()) {
            case "dt" -> rs.getObject(col, OffsetDateTime.class).toString();
            case "d" -> rs.getDate(col).toLocalDate().toString();
            case "tm" -> rs.getTime(col).toLocalTime().toString();
            case "j" -> json.readValue(rs.getString(col), Object.class);
            case "a" -> Arrays.asList((Object[]) ((Array) v).getArray());
            default -> v;
        };
    }

    private static long currentSchool() {
        return TenantContext.require().currentSchool()
                .orElseThrow(() -> new IllegalStateException("X-School-Id is required for this operation"))
                .schoolId();
    }
}
