package com.school.app.role.hrmanager;

import com.school.app.role.hrmanager.api.HrManagerApi;
import org.springframework.web.bind.annotation.RestController;

/**
 * People, leave, shifts & roster, presence exceptions, payroll, recruitment.
 *
 * <p>Module for base role(s) HR_MANAGER at /api/v1/hrmanager. Contract: openapi/hrmanager.yaml; the generated
 * HrManagerApi declares every operation with its @Access rule. Operations not overridden here answer 501 until
 * implemented: override the method and call the domain services (com.school.app.domain.*); never call another
 * role module.
 */
@RestController
public class HrManagerController implements HrManagerApi {
}
