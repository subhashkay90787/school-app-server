package com.school.app.core.tenant;

import com.school.app.core.security.AuthUser;
import com.school.app.core.security.SchoolAccess;

import java.util.Optional;

/**
 * Who is calling and in which branch, for the current request. {@code school} is empty only on endpoints that
 * don't take X-School-Id (/api/v1/common/me).
 */
public record RequestContext(AuthUser user, SchoolAccess school, String requestId) {

    public Optional<SchoolAccess> currentSchool() {
        return Optional.ofNullable(school);
    }

    public long userId() {
        return user.userId();
    }

    /** RLS scope (app.school_ids): the branch in X-School-Id. */
    public String schoolIdsSetting() {
        return school == null ? "" : Long.toString(school.schoolId());
    }

    public String orgIdsSetting() {
        return school != null && school.orgWide() ? Long.toString(school.organizationId()) : "";
    }
}
