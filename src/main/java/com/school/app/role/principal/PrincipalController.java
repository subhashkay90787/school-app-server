package com.school.app.role.principal;

import org.springframework.web.bind.annotation.RestController;

/**
 * Runs the branch day to day: pulse, cover board, presence, academics, incidents, circulars.
 *
 * <p>Module for base role(s) PRINCIPAL at /api/v1/principal. Contract: openapi/principal.yaml; the generated
 * PrincipalApi declares every operation with its @Access rule. Operations not overridden here answer 501 until
 * implemented: override the method and call the domain services (com.school.app.domain.*); never call another
 * role module.
 */
@RestController
public class PrincipalController extends PrincipalCrud {
}
