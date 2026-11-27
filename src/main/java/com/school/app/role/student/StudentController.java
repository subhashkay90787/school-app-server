package com.school.app.role.student;

import org.springframework.web.bind.annotation.RestController;

/**
 * Adult / college students only (no app for minors): classwork, results, attendance shortfall, fees, hostel self-service.
 *
 * <p>Module for base role(s) STUDENT at /api/v1/student. Contract: openapi/student.yaml; the generated
 * StudentApi declares every operation with its @Access rule. Operations not overridden here answer 501 until
 * implemented: override the method and call the domain services (com.school.app.domain.*); never call another
 * role module.
 */
@RestController
public class StudentController extends StudentCrud {
}
