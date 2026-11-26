package com.school.app.core.access;

import org.springframework.core.io.ClassPathResource;
import org.springframework.stereotype.Component;
import tools.jackson.core.type.TypeReference;
import tools.jackson.databind.json.JsonMapper;

import java.io.IOException;
import java.io.InputStream;
import java.util.*;

/**
 * Which built-in (base) roles may use each actor module, from openapi/role-routes.json (generated with the
 * specs). A custom role reaches the module of its base role: the token's base_roles already resolves that.
 * "*" = any signed-in member of the branch (common, assistant).
 */
@Component
public class RoleRoutes {

    private final Map<String, Set<String>> routes = new LinkedHashMap<>();

    public RoleRoutes(JsonMapper jsonMapper) throws IOException {
        try (InputStream in = new ClassPathResource("openapi/role-routes.json").getInputStream()) {
            Map<String, List<String>> raw = jsonMapper.readValue(in, new TypeReference<>() {});
            raw.forEach((prefix, roles) -> routes.put(prefix, Set.copyOf(roles)));
        }
        // School Admin's legacy alias resolves to SCHOOL_ADMIN through base_roles; nothing else to map here
    }

    /** Allowed base roles for the module the path belongs to; empty when the path is no actor module. */
    public Optional<Set<String>> allowedFor(String path) {
        return routes.entrySet().stream()
                .filter(e -> path.equals(e.getKey()) || path.startsWith(e.getKey() + "/"))
                .map(Map.Entry::getValue)
                .findFirst();
    }

    public Map<String, Set<String>> all() {
        return Collections.unmodifiableMap(routes);
    }
}
