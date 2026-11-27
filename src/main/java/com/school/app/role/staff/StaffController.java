package com.school.app.role.staff;

import org.springframework.web.bind.annotation.RestController;

/**
 * Librarian and general staff: scan-first library counter, tasks.
 *
 * <p>Module for base role(s) STAFF at /api/v1/staff. Contract: openapi/staff.yaml; the generated
 * StaffApi declares every operation with its @Access rule. Operations not overridden here answer 501 until
 * implemented: override the method and call the domain services (com.school.app.domain.*); never call another
 * role module.
 */
@RestController
public class StaffController extends StaffCrud {
}
