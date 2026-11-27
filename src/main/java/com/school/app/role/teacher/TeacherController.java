package com.school.app.role.teacher;

import org.springframework.web.bind.annotation.RestController;

/**
 * {Teacher} with duty overlays (class teacher, invigilator, escort): register, marks, homework, lesson plans, messages, PTM.
 *
 * <p>Module for base role(s) TEACHER at /api/v1/teacher. Contract: openapi/teacher.yaml; the generated
 * TeacherApi declares every operation with its @Access rule. Operations not overridden here answer 501 until
 * implemented: override the method and call the domain services (com.school.app.domain.*); never call another
 * role module.
 */
@RestController
public class TeacherController extends TeacherCrud {
}
