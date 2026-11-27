package com.school.app.role.parent;

import org.springframework.web.bind.annotation.RestController;

/**
 * Guardian (hosteller and day-scholar variants): child switcher, attendance, fees, outings, pickups, wallet, messages. Sees only linked children.
 *
 * <p>Module for base role(s) PARENT at /api/v1/parent. Contract: openapi/parent.yaml; the generated
 * ParentApi declares every operation with its @Access rule. Operations not overridden here answer 501 until
 * implemented: override the method and call the domain services (com.school.app.domain.*); never call another
 * role module.
 */
@RestController
public class ParentController extends ParentCrud {
}
