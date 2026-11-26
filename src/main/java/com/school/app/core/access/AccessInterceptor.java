package com.school.app.core.access;

import com.school.app.core.security.SchoolAccess;
import com.school.app.core.tenant.TenantContext;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.stereotype.Component;
import org.springframework.web.method.HandlerMethod;
import org.springframework.web.servlet.HandlerInterceptor;

import java.util.Arrays;
import java.util.Set;

/**
 * Before any controller method:
 * <ol>
 *   <li><b>Role module</b>: /api/v1/&lt;actor&gt;/** only for members whose base roles include that actor
 *       (role -> domain only, never role -> role).</li>
 *   <li><b>Feature</b>: @Access.feature must be in the token's enabled_features for this branch.</li>
 *   <li><b>Permission</b>: the caller must hold one of @Access.anyOf in this branch.</li>
 * </ol>
 * Data scope (own class, own rooms, own children) is checked by the domain services, and again by RLS for
 * the branch.
 */
@Component
public class AccessInterceptor implements HandlerInterceptor {

    private final RoleRoutes roleRoutes;

    public AccessInterceptor(RoleRoutes roleRoutes) {
        this.roleRoutes = roleRoutes;
    }

    @Override
    public boolean preHandle(HttpServletRequest request, HttpServletResponse response, Object handler) {
        if (!(handler instanceof HandlerMethod method)) {
            return true;
        }
        var context = TenantContext.current().orElse(null);
        if (context == null) {
            return true; // not an /api/v1 call (docs, actuator)
        }
        SchoolAccess school = context.school();

        Set<String> allowed = roleRoutes.allowedFor(request.getRequestURI()).orElse(null);
        if (allowed != null && !allowed.contains("*")) {
            if (school == null || school.baseRoles().stream().noneMatch(allowed::contains)) {
                throw new AccessDeniedProblem("WRONG_ROLE", "This module is for " + allowed + "; your roles here are "
                        + (school == null ? "[]" : school.roles()) + ".");
            }
        }

        Access access = method.getMethodAnnotation(Access.class);
        if (access == null || school == null) {
            return true;
        }
        if (!access.feature().isEmpty() && !school.hasFeature(access.feature())) {
            throw new AccessDeniedProblem("FEATURE_OFF", "The " + access.feature() + " feature is not enabled for you in this branch.");
        }
        if (access.anyOf().length > 0 && Arrays.stream(access.anyOf()).noneMatch(school::hasPermission)) {
            throw new AccessDeniedProblem("MISSING_PERMISSION", "You need one of " + Arrays.toString(access.anyOf()) + " in this branch.");
        }
        return true;
    }
}
