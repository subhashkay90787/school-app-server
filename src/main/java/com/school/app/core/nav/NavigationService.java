package com.school.app.core.nav;

import com.school.app.api.model.NavEntry;
import com.school.app.api.model.Navigation;
import com.school.app.core.security.SchoolAccess;
import org.springframework.core.io.ClassPathResource;
import org.springframework.stereotype.Service;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;

import java.io.IOException;
import java.io.InputStream;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

/**
 * Navigation = token features ∩ role permissions (UX v2 section 3), from navigation.json (tabs and sidebar per
 * base role, UX v2 section 5). A tab whose feature is off is hidden; labels use the branch terminology
 * ({unit}, {learner}, {faculty} ...). Mobile keeps at most 5 tabs, the last being More.
 */
@Service
public class NavigationService {

    private final JsonNode catalog;

    public NavigationService(JsonMapper jsonMapper) throws IOException {
        try (InputStream in = new ClassPathResource("navigation.json").getInputStream()) {
            this.catalog = jsonMapper.readTree(in);
        }
    }

    public Navigation build(SchoolAccess school, String requestedRole) {
        String role = requestedRole != null && school.roles().contains(requestedRole) ? requestedRole : primaryRole(school);
        String base = school.baseRoles().contains(role) ? role : school.baseRoles().stream().findFirst().orElse(role);
        JsonNode def = catalog.path("roles").path(base);
        return new Navigation()
                .roleCode(role)
                .baseRoleCode(base)
                .mobileTabs(entries(def.path("mobile"), school))
                .webSidebar(entries(def.path("web"), school));
    }

    private List<NavEntry> entries(JsonNode keys, SchoolAccess school) {
        List<NavEntry> out = new ArrayList<>();
        for (JsonNode k : keys) {
            JsonNode e = catalog.path("entries").path(k.asString());
            String feature = e.path("feature").isNull() || e.path("feature").isMissingNode() ? null : e.path("feature").asString();
            if (feature != null && !school.hasFeature(feature)) {
                continue;
            }
            boolean permitted = true;
            if (e.path("anyOf").size() > 0) {
                permitted = false;
                for (JsonNode p : e.path("anyOf")) {
                    permitted |= school.hasPermission(p.asString());
                }
            }
            if (!permitted) {
                continue;
            }
            out.add(new NavEntry().key(k.asString()).label(label(e.path("label").asString(), school.terminology()))
                    .icon(e.path("icon").asString()).feature(feature).locked(false));
        }
        return out;
    }

    private static String primaryRole(SchoolAccess school) {
        return school.roles().isEmpty() ? "" : school.roles().get(0);
    }

    /** "{unit}" -> "Class", "{unit:plural}" -> "Classes"; unknown keys fall back to the key itself. */
    static String label(String template, Map<String, Object> terminology) {
        var m = java.util.regex.Pattern.compile("\\{(\\w+)(:plural)?}").matcher(template);
        StringBuilder out = new StringBuilder();
        while (m.find()) {
            Object term = terminology == null ? null : terminology.get(m.group(1));
            String word = term == null ? m.group(1) : term.toString();
            m.appendReplacement(out, java.util.regex.Matcher.quoteReplacement(m.group(2) == null ? word : plural(word)));
        }
        m.appendTail(out);
        return out.toString();
    }

    static String plural(String word) {
        if (word.isEmpty()) return word;
        String lower = word.toLowerCase();
        if (lower.endsWith("s") || lower.endsWith("x") || lower.endsWith("ch") || lower.endsWith("sh")) return word + "es";
        if (lower.endsWith("y") && word.length() > 1 && "aeiou".indexOf(lower.charAt(lower.length() - 2)) < 0) {
            return word.substring(0, word.length() - 1) + "ies";
        }
        return word + "s";
    }
}
