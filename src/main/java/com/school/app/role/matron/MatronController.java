package com.school.app.role.matron;

import com.school.app.role.matron.api.MatronApi;
import org.springframework.web.bind.annotation.RestController;

/**
 * Sick bay, medication rounds, laundry, welfare notes.
 *
 * <p>Module for base role(s) MATRON at /api/v1/matron. Contract: openapi/matron.yaml; the generated
 * MatronApi declares every operation with its @Access rule. Operations not overridden here answer 501 until
 * implemented: override the method and call the domain services (com.school.app.domain.*); never call another
 * role module.
 */
@RestController
public class MatronController implements MatronApi {
}
