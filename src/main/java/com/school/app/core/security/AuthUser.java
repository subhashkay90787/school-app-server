package com.school.app.core.security;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

/** The caller, as asserted by the signed school-auth access token. Never built from client headers. */
public record AuthUser(
        long userId,
        UUID sessionId,
        String firstName,
        String lastName,
        String email,
        String phoneNumber,
        String userCategory,
        boolean active,
        boolean superUser,
        List<SchoolAccess> schools) {

    public Optional<SchoolAccess> school(long schoolId) {
        return schools.stream().filter(s -> s.schoolId() == schoolId).findFirst();
    }
}
