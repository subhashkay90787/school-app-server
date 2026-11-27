package com.school.app.role.schooladmin;

import org.springframework.web.bind.annotation.RestController;

/**
 * Office head: setup checklist, students, staff, sections & subjects, timetable, exams, fee setup, records, imports, devices & posts.
 *
 * <p>Module for base role(s) SCHOOL_ADMIN at /api/v1/schooladmin. Contract: openapi/schooladmin.yaml; the generated
 * SchoolAdminApi declares every operation with its @Access rule. Operations not overridden here answer 501 until
 * implemented: override the method and call the domain services (com.school.app.domain.*); never call another
 * role module.
 */
@RestController
public class SchoolAdminController extends SchoolAdminCrud {
}
