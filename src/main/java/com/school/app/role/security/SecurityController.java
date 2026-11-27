package com.school.app.role.security;

import org.springframework.web.bind.annotation.RestController;

/**
 * Guard (any phone or gate kiosk; everything works offline): gate, patrol, welfare, occurrences, handover.
 *
 * <p>Module for base role(s) SECURITY at /api/v1/security. Contract: openapi/security.yaml; the generated
 * SecurityApi declares every operation with its @Access rule. Operations not overridden here answer 501 until
 * implemented: override the method and call the domain services (com.school.app.domain.*); never call another
 * role module.
 */
@RestController
public class SecurityController extends SecurityCrud {
}
