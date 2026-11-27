package com.school.app.role.securitysupervisor;

import org.springframework.web.bind.annotation.RestController;

/**
 * Guard roster, live posts, patrol routes and compliance, occurrences, keys.
 *
 * <p>Module for base role(s) SECURITY_SUPERVISOR at /api/v1/securitysupervisor. Contract: openapi/securitysupervisor.yaml; the generated
 * SecuritySupervisorApi declares every operation with its @Access rule. Operations not overridden here answer 501 until
 * implemented: override the method and call the domain services (com.school.app.domain.*); never call another
 * role module.
 */
@RestController
public class SecuritySupervisorController extends SecuritySupervisorCrud {
}
