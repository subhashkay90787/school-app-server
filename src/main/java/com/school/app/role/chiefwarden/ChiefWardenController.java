package com.school.app.role.chiefwarden;

import org.springframework.web.bind.annotation.RestController;

/**
 * Hostel head: allocation board, travel groups, policies, duty roster, monthly report.
 *
 * <p>Module for base role(s) CHIEF_WARDEN at /api/v1/chiefwarden. Contract: openapi/chiefwarden.yaml; the generated
 * ChiefWardenApi declares every operation with its @Access rule. Operations not overridden here answer 501 until
 * implemented: override the method and call the domain services (com.school.app.domain.*); never call another
 * role module.
 */
@RestController
public class ChiefWardenController extends ChiefWardenCrud {
}
