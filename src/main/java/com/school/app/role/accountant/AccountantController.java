package com.school.app.role.accountant;

import org.springframework.web.bind.annotation.RestController;

/**
 * Fee counter and books: collections, demands, concessions, refunds, expenses, petty cash, budgets, payroll processing, vendor invoices, Tally export.
 *
 * <p>Module for base role(s) ACCOUNTANT at /api/v1/accountant. Contract: openapi/accountant.yaml; the generated
 * AccountantApi declares every operation with its @Access rule. Operations not overridden here answer 501 until
 * implemented: override the method and call the domain services (com.school.app.domain.*); never call another
 * role module.
 */
@RestController
public class AccountantController extends AccountantCrud {
}
