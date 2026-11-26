package com.school.app.core.db;

import java.util.function.Supplier;

/** Marks work done by the server itself (nightly sync, purge jobs): transactions bypass RLS. */
public final class SystemContext {

    private static final ThreadLocal<Boolean> ACTIVE = ThreadLocal.withInitial(() -> false);

    private SystemContext() {}

    public static boolean isActive() {
        return ACTIVE.get();
    }

    public static <T> T run(Supplier<T> work) {
        boolean previous = ACTIVE.get();
        ACTIVE.set(true);
        try {
            return work.get();
        } finally {
            ACTIVE.set(previous);
        }
    }
}
