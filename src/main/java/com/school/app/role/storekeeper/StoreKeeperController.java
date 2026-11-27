package com.school.app.role.storekeeper;

import org.springframework.web.bind.annotation.RestController;

/**
 * Stock, GRN, issues, assets, stock audits, hostel kits.
 *
 * <p>Module for base role(s) STORE_KEEPER at /api/v1/storekeeper. Contract: openapi/storekeeper.yaml; the generated
 * StoreKeeperApi declares every operation with its @Access rule. Operations not overridden here answer 501 until
 * implemented: override the method and call the domain services (com.school.app.domain.*); never call another
 * role module.
 */
@RestController
public class StoreKeeperController extends StoreKeeperCrud {
}
