package com.school.app.core.access;

import java.lang.annotation.*;

/**
 * Declared on every generated API operation from the spec's x-access:
 * the branch must have {@code feature} switched on for the caller, and the caller must hold at least one of
 * {@code anyOf} in that branch (from the token's school_access). Enforced by {@link AccessInterceptor}.
 */
@Target({ElementType.METHOD, ElementType.TYPE})
@Retention(RetentionPolicy.RUNTIME)
@Documented
public @interface Access {

    /** Feature code that must be enabled (empty = none required). */
    String feature() default "";

    /** Permission codes; holding any one is enough (empty = none required beyond the role module). */
    String[] anyOf() default {};
}
