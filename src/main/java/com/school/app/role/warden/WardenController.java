package com.school.app.role.warden;

import org.springframework.web.bind.annotation.RestController;

/**
 * Room / block / night / assistant warden: roll call, residents, custody, outings, inspections, handover.
 *
 * <p>Module for base role(s) WARDEN at /api/v1/warden. Contract: openapi/warden.yaml; the generated
 * WardenApi declares every operation with its @Access rule. Operations not overridden here answer 501 until
 * implemented: override the method and call the domain services (com.school.app.domain.*); never call another
 * role module.
 */
@RestController
public class WardenController extends WardenCrud {
}
