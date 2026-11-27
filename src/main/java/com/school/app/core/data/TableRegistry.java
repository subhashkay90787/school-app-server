package com.school.app.core.data;

import org.springframework.core.io.ClassPathResource;
import org.springframework.stereotype.Component;
import tools.jackson.core.type.TypeReference;
import tools.jackson.databind.json.JsonMapper;

import java.io.IOException;
import java.io.InputStream;
import java.util.*;

/**
 * Table metadata of the school database (schema/tables.json, generated from tools/er_v5_school.dsl together with
 * the migrations and the API schemas), so the CRUD engine maps API models to columns without per-table code.
 */
@Component
public class TableRegistry {

    public record Column(String name, String camel, String type, boolean nn, String fk, List<String> enumValues,
                         boolean hasDefault) {
        /** SQL cast applied to bound parameters of this column. */
        public String cast() {
            return switch (type) {
                case "d" -> "::date";
                case "dt" -> "::timestamptz";
                case "tm" -> "::time";
                case "j" -> "::jsonb";
                case "a" -> "::text[]";
                case "u" -> "::uuid";
                default -> "";
            };
        }
    }

    public record Table(String name, String model, String pk, List<String> pkc, boolean pkSchool, boolean nullableTenant,
                        List<Column> columns, String dateColumn, List<String> searchColumns) {

        public Optional<Column> column(String name) {
            return columns.stream().filter(c -> c.name().equals(name)).findFirst();
        }

        public Optional<Column> byCamel(String camel) {
            return columns.stream().filter(c -> c.camel().equals(camel)).findFirst();
        }

        public boolean has(String column) {
            return column(column).isPresent();
        }

        public String qualified() {
            String[] p = name.split("\\.");
            return "\"" + p[0] + "\".\"" + p[1] + "\"";
        }
    }

    private record RawColumn(String name, String camel, String type, boolean nn, String fk,
                             @com.fasterxml.jackson.annotation.JsonProperty("enum") List<String> enumValues, boolean hasDefault) {}

    private record RawTable(String model, String pk, List<String> pkc, boolean pkSchool, boolean nullableTenant,
                            List<RawColumn> columns, String dateColumn, List<String> searchColumns) {}

    private final Map<String, Table> tables = new LinkedHashMap<>();

    public TableRegistry(JsonMapper jsonMapper) throws IOException {
        try (InputStream in = new ClassPathResource("schema/tables.json").getInputStream()) {
            Map<String, RawTable> raw = jsonMapper.readValue(in, new TypeReference<>() {});
            raw.forEach((name, t) -> tables.put(name, new Table(name, t.model(), t.pk(), t.pkc(), t.pkSchool(),
                    t.nullableTenant(),
                    t.columns().stream().map(c -> new Column(c.name(), c.camel(), c.type(), c.nn(), c.fk(),
                            c.enumValues(), c.hasDefault())).toList(),
                    t.dateColumn(), t.searchColumns())));
        }
    }

    public Table table(String name) {
        Table t = tables.get(name);
        if (t == null) {
            throw new IllegalArgumentException("Unknown table " + name);
        }
        return t;
    }

    public Collection<Table> all() {
        return tables.values();
    }
}
