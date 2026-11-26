package com.school.app.core.security;

import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * One entry of the token's {@code school_access} claim (issued by school-auth, TokenPayloadDto.SchoolAccess):
 * the branch, the caller's roles there, the built-in roles whose modules those roles use, their effective
 * permissions and the features switched on for them.
 */
public record SchoolAccess(
        long schoolId,
        String schoolCode,
        String schoolName,
        String branchCode,
        String branchName,
        long organizationId,
        String orgCode,
        String orgName,
        String institutionType,
        Map<String, Object> terminology,
        String timezone,
        String status,
        List<String> roles,
        Set<String> baseRoles,
        boolean orgWide,
        Set<String> permissions,
        Set<String> features,
        long permVersion) {

    public boolean hasPermission(String code) {
        return permissions.contains(code);
    }

    public boolean hasFeature(String code) {
        return features.contains(code);
    }
}
