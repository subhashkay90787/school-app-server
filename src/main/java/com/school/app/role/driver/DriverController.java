package com.school.app.role.driver;

import org.springframework.web.bind.annotation.RestController;

/**
 * Driving-safe trip screen: next stop, boarding, emergency, masked calls; works offline (phase 2).
 *
 * <p>Module for base role(s) DRIVER at /api/v1/driver. Contract: openapi/driver.yaml; the generated
 * DriverApi declares every operation with its @Access rule. Operations not overridden here answer 501 until
 * implemented: override the method and call the domain services (com.school.app.domain.*); never call another
 * role module.
 */
@RestController
public class DriverController extends DriverCrud {
}
