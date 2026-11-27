package com.school.app.role.transportmanager;

import org.springframework.web.bind.annotation.RestController;

/**
 * Routes, stops, vehicles, drivers, live map, fuel (phase 2).
 *
 * <p>Module for base role(s) TRANSPORT_MANAGER at /api/v1/transportmanager. Contract: openapi/transportmanager.yaml; the generated
 * TransportManagerApi declares every operation with its @Access rule. Operations not overridden here answer 501 until
 * implemented: override the method and call the domain services (com.school.app.domain.*); never call another
 * role module.
 */
@RestController
public class TransportManagerController extends TransportManagerCrud {
}
