package com.school.app.core.data;

import java.util.List;

/** An extra WHERE predicate with positional parameters (scope rules, custom filters). */
public record Pred(String sql, List<Object> params) {

    public static Pred of(String sql, Object... params) {
        return new Pred(sql, List.of(params));
    }
}
