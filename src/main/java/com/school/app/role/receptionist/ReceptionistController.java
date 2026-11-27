package com.school.app.role.receptionist;

import org.springframework.web.bind.annotation.RestController;

/**
 * Front office (tablet kiosk): visitors, early leave and pickups, parcels, walk-in enquiries.
 *
 * <p>Module for base role(s) RECEPTIONIST at /api/v1/receptionist. Contract: openapi/receptionist.yaml; the generated
 * ReceptionistApi declares every operation with its @Access rule. Operations not overridden here answer 501 until
 * implemented: override the method and call the domain services (com.school.app.domain.*); never call another
 * role module.
 */
@RestController
public class ReceptionistController extends ReceptionistCrud {
}
