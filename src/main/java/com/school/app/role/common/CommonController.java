package com.school.app.role.common;

import com.school.app.api.model.CalendarEvent;
import com.school.app.api.model.MeContext;
import com.school.app.api.model.Navigation;
import com.school.app.api.model.SchoolContext;
import com.school.app.core.nav.NavigationService;
import com.school.app.domain.calendar.CalendarService;
import com.school.app.core.security.SchoolAccess;
import com.school.app.core.tenant.TenantContext;
import org.springframework.http.ResponseEntity;
import org.springframework.lang.Nullable;
import org.springframework.web.bind.annotation.RestController;

import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;

/**
 * Shared endpoints for every role (/api/v1/common). getMe and getNavigation are served from the token alone;
 * listCalendar reads the branch calendar (through RLS); the rest answer 501 until their domain services exist.
 */
@RestController
public class CommonController extends CommonCrud {

    private final NavigationService navigationService;
    private final CalendarService calendarService;

    public CommonController(NavigationService navigationService, CalendarService calendarService) {
        this.navigationService = navigationService;
        this.calendarService = calendarService;
    }

    @Override
    public ResponseEntity<List<CalendarEvent>> listCalendar(Long xSchoolId, @Nullable LocalDate from, @Nullable LocalDate to) {
        return ResponseEntity.ok(calendarService.events(from, to));
    }

    @Override
    public ResponseEntity<MeContext> getMe() {
        var ctx = TenantContext.require();
        var user = ctx.user();
        return ResponseEntity.ok(new MeContext()
                .userId(user.userId())
                .firstName(user.firstName())
                .lastName(user.lastName())
                .userCategory(user.userCategory())
                .currentSchoolId(ctx.currentSchool().map(SchoolAccess::schoolId).orElse(null))
                .schools(user.schools().stream().map(CommonController::toContext).toList()));
    }

    @Override
    public ResponseEntity<Navigation> getNavigation(Long xSchoolId, @Nullable String role) {
        SchoolAccess school = TenantContext.require().school();
        return ResponseEntity.ok(navigationService.build(school, role));
    }

    private static SchoolContext toContext(SchoolAccess s) {
        return new SchoolContext()
                .schoolId(s.schoolId())
                .schoolName(s.schoolName())
                .branchName(s.branchName())
                .organizationId(s.organizationId())
                .institutionType(s.institutionType())
                .timezone(s.timezone())
                .terminology(s.terminology())
                .roles(new ArrayList<>(s.roles()))
                .baseRoles(new ArrayList<>(s.baseRoles()))
                .permissions(new ArrayList<>(s.permissions()))
                .features(new ArrayList<>(s.features()))
                .orgWide(s.orgWide())
                .permVersion(s.permVersion());
    }
}
