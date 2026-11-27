package com.school.app.core.data;

import java.time.LocalDate;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * List query: equality filters by API (camelCase) field name, free-text search, a date / date range on the
 * table's main date column, extra predicates, paging.
 */
public final class Query {

    final Map<String, Object> filters = new LinkedHashMap<>();
    final List<Pred> preds = new ArrayList<>();
    String search;
    LocalDate date;
    LocalDate from;
    LocalDate to;
    int page = 0;
    int size = 50;

    public static Query create() {
        return new Query();
    }

    /** Equality on the column whose API name is {@code field}; ignored when the value is null or no such column. */
    public Query eq(String field, Object value) {
        if (value != null) {
            filters.put(field, value);
        }
        return this;
    }

    public Query where(Pred pred) {
        if (pred != null) {
            preds.add(pred);
        }
        return this;
    }

    public Query where(List<Pred> list) {
        list.forEach(this::where);
        return this;
    }

    public Query search(String q) {
        this.search = q == null || q.isBlank() ? null : q.trim();
        return this;
    }

    public Query on(LocalDate date) {
        this.date = date;
        return this;
    }

    public Query between(LocalDate from, LocalDate to) {
        this.from = from;
        this.to = to;
        return this;
    }

    public Query page(Integer page, Integer size) {
        this.page = page == null || page < 0 ? 0 : page;
        this.size = size == null ? 50 : Math.max(1, Math.min(size, 200));
        return this;
    }

    public Query unpaged() {
        this.page = 0;
        this.size = 1000;
        return this;
    }
}
