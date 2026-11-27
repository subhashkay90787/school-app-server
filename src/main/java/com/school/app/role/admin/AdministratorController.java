package com.school.app.role.admin;

import org.springframework.web.bind.annotation.RestController;

/**
 * Management / correspondent: governance, money above the Principal's band, branch comparisons (org-wide when granted at organization level).
 *
 * <p>Module for base role(s) ADMIN at /api/v1/admin. Contract: openapi/admin.yaml; the generated
 * AdministratorApi declares every operation with its @Access rule. Operations not overridden here answer 501 until
 * implemented: override the method and call the domain services (com.school.app.domain.*); never call another
 * role module.
 */
@RestController
public class AdministratorController extends AdministratorCrud {
}
