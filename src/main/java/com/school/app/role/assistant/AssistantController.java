package com.school.app.role.assistant;

import com.school.app.role.assistant.api.AssistantApi;
import org.springframework.web.bind.annotation.RestController;

/**
 * Read-only contract for school-mcp (voice and AI assistants act as the signed-in user). GET only; every write happens in the app (parental control).
 *
 * <p>Module for base role(s) * at /api/v1/assistant. Contract: openapi/assistant.yaml; the generated
 * AssistantApi declares every operation with its @Access rule. Operations not overridden here answer 501 until
 * implemented: override the method and call the domain services (com.school.app.domain.*); never call another
 * role module.
 */
@RestController
public class AssistantController implements AssistantApi {
}
