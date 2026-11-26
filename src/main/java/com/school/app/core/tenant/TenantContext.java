package com.school.app.core.tenant;

import java.util.Optional;

/** Thread-bound request context, set by {@link TenantFilter} and read by the RLS transaction manager. */
public final class TenantContext {

    private static final ThreadLocal<RequestContext> CURRENT = new ThreadLocal<>();

    private TenantContext() {}

    public static Optional<RequestContext> current() {
        return Optional.ofNullable(CURRENT.get());
    }

    public static RequestContext require() {
        return current().orElseThrow(() -> new IllegalStateException("No request context"));
    }

    static void set(RequestContext context) {
        CURRENT.set(context);
    }

    static void clear() {
        CURRENT.remove();
    }

    /** For background jobs: run with a context (or none) and restore the previous one. */
    public static <T> T callAs(RequestContext context, java.util.function.Supplier<T> work) {
        RequestContext previous = CURRENT.get();
        CURRENT.set(context);
        try {
            return work.get();
        } finally {
            if (previous == null) CURRENT.remove();
            else CURRENT.set(previous);
        }
    }
}
