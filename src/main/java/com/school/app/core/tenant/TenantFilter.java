package com.school.app.core.tenant;

import com.school.app.core.directory.DirectoryCache;
import com.school.app.core.security.AuthUser;
import com.school.app.core.security.SchoolAccess;
import com.school.app.core.security.TokenClaims;
import com.school.app.core.web.Problems;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;

/**
 * Resolves the tenant for every /api/v1 request:
 * <ol>
 *   <li>the token must be a user token (client_credentials tokens are refused),</li>
 *   <li>X-School-Id is required and must be one of the token's school_access branches,</li>
 *   <li>the branch and user are written to the thin directory cache from the verified claims,</li>
 *   <li>the context is bound to the thread for the RLS settings of every transaction.</li>
 * </ol>
 */
@Component
public class TenantFilter extends OncePerRequestFilter {

    public static final String SCHOOL_HEADER = "X-School-Id";
    private static final Set<String> NO_SCHOOL_PATHS = Set.of("/api/v1/common/me");

    private final DirectoryCache directoryCache;

    public TenantFilter(DirectoryCache directoryCache) {
        this.directoryCache = directoryCache;
    }

    /**
     * Cross-branch read scope: GET /api/v1/admin/branches/comparison, or GET /api/v1/admin/... with
     * scope=ALL_BRANCHES, by an org-wide role. Adds the caller's other org-wide branches of the same organisation.
     */
    static java.util.List<Long> readBranches(HttpServletRequest request, AuthUser user, SchoolAccess school) {
        if (school == null || !school.orgWide() || !"GET".equals(request.getMethod())
                || !request.getRequestURI().startsWith("/api/v1/admin/")) {
            return java.util.List.of();
        }
        boolean all = request.getRequestURI().equals("/api/v1/admin/branches/comparison")
                || "ALL_BRANCHES".equals(request.getParameter("scope"));
        if (!all) return java.util.List.of();
        return user.schools().stream()
                .filter(s -> s.orgWide() && s.organizationId() == school.organizationId() && s.schoolId() != school.schoolId())
                .map(SchoolAccess::schoolId).toList();
    }

    @Override
    protected boolean shouldNotFilter(HttpServletRequest request) {
        return !request.getRequestURI().startsWith("/api/v1/");
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain)
            throws ServletException, IOException {
        if (!(SecurityContextHolder.getContext().getAuthentication() instanceof JwtAuthenticationToken jwt)) {
            chain.doFilter(request, response); // unauthenticated: the security chain answers 401
            return;
        }
        Optional<AuthUser> parsed = TokenClaims.parse(jwt.getToken());
        if (parsed.isEmpty()) {
            Problems.write(response, HttpStatus.FORBIDDEN, "USER_TOKEN_REQUIRED", "This API needs a user access token.");
            return;
        }
        AuthUser user = parsed.get();
        String requestId = Optional.ofNullable(request.getHeader("X-Request-Id")).orElse(UUID.randomUUID().toString());
        response.setHeader("X-Request-Id", requestId);

        SchoolAccess school = null;
        String header = request.getHeader(SCHOOL_HEADER);
        if (header == null || header.isBlank()) {
            if (!NO_SCHOOL_PATHS.contains(request.getRequestURI())) {
                Problems.write(response, HttpStatus.BAD_REQUEST, "SCHOOL_REQUIRED", "Send the branch in the X-School-Id header.");
                return;
            }
        } else {
            long schoolId;
            try {
                schoolId = Long.parseLong(header.trim());
            } catch (NumberFormatException e) {
                Problems.write(response, HttpStatus.BAD_REQUEST, "SCHOOL_REQUIRED", "X-School-Id must be a number.");
                return;
            }
            school = user.school(schoolId).orElse(null);
            if (school == null) {
                Problems.write(response, HttpStatus.FORBIDDEN, "NOT_IN_SCHOOL",
                        "Your token does not give access to branch " + schoolId + ".");
                return;
            }
            directoryCache.touch(user, school);
        }

        TenantContext.set(new RequestContext(user, school, requestId, readBranches(request, user, school)));
        try {
            chain.doFilter(request, response);
        } finally {
            TenantContext.clear();
        }
    }
}
