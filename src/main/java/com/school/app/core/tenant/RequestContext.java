package com.school.app.core.tenant;

import com.school.app.core.security.AuthUser;
import com.school.app.core.security.SchoolAccess;

import java.util.List;
import java.util.Optional;
import java.util.stream.Collectors;
import java.util.stream.Stream;

/**
 * Who is calling and in which branch, for the current request. {@code school} is empty only on endpoints that
 * don't take X-School-Id (/api/v1/common/me). {@code readBranches}: other branches of the same organisation that an
 * org-wide reader may see in this request (GET on the administrator's cross-branch dashboards only).
 */
public record RequestContext(AuthUser user, SchoolAccess school, String requestId, List<Long> readBranches) {

    public RequestContext(AuthUser user, SchoolAccess school, String requestId) {
        this(user, school, requestId, List.of());
    }

    public Optional<SchoolAccess> currentSchool() {
        return Optional.ofNullable(school);
    }

    public long userId() {
        return user.userId();
    }

    /** RLS scope (app.school_ids): the branch in X-School-Id, plus readBranches on cross-branch dashboards. */
    public String schoolIdsSetting() {
        if (school == null) return "";
        return Stream.concat(Stream.of(school.schoolId()), readBranches.stream()).distinct()
                .map(String::valueOf).collect(Collectors.joining(","));
    }

    public String orgIdsSetting() {
        return school != null && school.orgWide() ? Long.toString(school.organizationId()) : "";
    }
}
