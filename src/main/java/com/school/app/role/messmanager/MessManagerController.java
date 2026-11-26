package com.school.app.role.messmanager;

import com.school.app.role.messmanager.api.MessManagerApi;
import org.springframework.web.bind.annotation.RestController;

/**
 * Menus, subscriptions, meal counts, provisions, rebates.
 *
 * <p>Module for base role(s) MESS_MANAGER at /api/v1/messmanager. Contract: openapi/messmanager.yaml; the generated
 * MessManagerApi declares every operation with its @Access rule. Operations not overridden here answer 501 until
 * implemented: override the method and call the domain services (com.school.app.domain.*); never call another
 * role module.
 */
@RestController
public class MessManagerController implements MessManagerApi {
}
