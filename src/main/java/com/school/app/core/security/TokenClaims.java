package com.school.app.core.security;

import org.springframework.security.oauth2.jwt.Jwt;

import java.util.*;

/** Reads the custom claims written by school-auth's CustomJwtTokenCustomizerConfig. */
public final class TokenClaims {

    private TokenClaims() {}

    /** @return empty for tokens without a user (client_credentials). */
    public static Optional<AuthUser> parse(Jwt jwt) {
        Object userId = jwt.getClaims().get("user_id");
        if (userId == null) {
            return Optional.empty();
        }
        Map<String, Object> details = map(jwt.getClaims().get("user_details"));
        List<String> platformRoles = strings(jwt.getClaims().get("roles"));
        List<SchoolAccess> schools = new ArrayList<>();
        for (Object o : list(jwt.getClaims().get("school_access"))) {
            Map<String, Object> m = map(o);
            Set<String> features = new LinkedHashSet<>();
            for (Object f : list(m.get("enabled_features"))) {
                Object code = map(f).get("feature_code");
                if (code != null) {
                    features.add(code.toString());
                }
            }
            schools.add(new SchoolAccess(
                    num(m.get("school_id")), str(m.get("school_code")), str(m.get("school_name")),
                    str(m.get("branch_code")), str(m.get("branch_name")), num(m.get("organization_id")),
                    str(m.get("org_code")), str(m.get("org_name")), str(m.get("institution_type")),
                    map(m.get("terminology")), str(m.get("timezone")), str(m.get("status")),
                    strings(m.get("roles")), new LinkedHashSet<>(strings(m.get("base_roles"))),
                    Boolean.TRUE.equals(m.get("org_wide")),
                    new LinkedHashSet<>(strings(m.get("permissions"))), features, num(m.get("perm_version"))));
        }
        String sid = jwt.getClaimAsString("sid");
        return Optional.of(new AuthUser(
                Long.parseLong(userId.toString()),
                sid == null ? null : UUID.fromString(sid),
                str(details.get("first_name")), str(details.get("last_name")), str(details.get("email")),
                str(details.get("phone_number")), str(details.get("user_category")),
                !Boolean.FALSE.equals(details.get("is_active_flag")),
                platformRoles.contains("SUPER_USER"),
                List.copyOf(schools)));
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> map(Object o) {
        return o instanceof Map<?, ?> m ? (Map<String, Object>) m : Map.of();
    }

    private static List<?> list(Object o) {
        return o instanceof List<?> l ? l : List.of();
    }

    private static List<String> strings(Object o) {
        return list(o).stream().map(Object::toString).toList();
    }

    private static String str(Object o) {
        return o == null ? null : o.toString();
    }

    private static long num(Object o) {
        return o == null ? 0L : o instanceof Number n ? n.longValue() : Long.parseLong(o.toString());
    }
}
