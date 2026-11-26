package com.school.app.role.admissionofficer;

import com.school.app.role.admissionofficer.api.AdmissionOfficerApi;
import org.springframework.web.bind.annotation.RestController;

/**
 * Enquiry and admission pipeline, tests, seat matrix, conversion.
 *
 * <p>Module for base role(s) ADMISSION_OFFICER at /api/v1/admissionofficer. Contract: openapi/admissionofficer.yaml; the generated
 * AdmissionOfficerApi declares every operation with its @Access rule. Operations not overridden here answer 501 until
 * implemented: override the method and call the domain services (com.school.app.domain.*); never call another
 * role module.
 */
@RestController
public class AdmissionOfficerController implements AdmissionOfficerApi {
}
