package com.school.app.role.nurse;

import org.springframework.web.bind.annotation.RestController;

/**
 * Infirmary (sick-bay tablet): visits, medical profiles, vaccinations, check-up drives.
 *
 * <p>Module for base role(s) NURSE at /api/v1/nurse. Contract: openapi/nurse.yaml; the generated
 * NurseApi declares every operation with its @Access rule. Operations not overridden here answer 501 until
 * implemented: override the method and call the domain services (com.school.app.domain.*); never call another
 * role module.
 */
@RestController
public class NurseController extends NurseCrud {
}
