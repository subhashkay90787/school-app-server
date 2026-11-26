package com.school.app.domain.calendar;

import com.school.app.api.model.CalendarEvent;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.util.List;

/**
 * Branch calendar. Reads run inside a transaction, so the tenant-aware transaction manager has set
 * app.school_ids: row-level security limits rows to the X-School-Id branch without a WHERE on school_id.
 */
@Service
public class CalendarService {

    private final JdbcClient jdbc;

    public CalendarService(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    @Transactional(readOnly = true)
    public List<CalendarEvent> events(LocalDate from, LocalDate to) {
        LocalDate start = from != null ? from : LocalDate.now().withDayOfMonth(1);
        LocalDate end = to != null ? to : start.plusMonths(3);
        return jdbc.sql("""
                        SELECT school_id, event_id, academic_year_id, event_type, title, start_date, end_date, applies_to,
                               program_id, class_section_id, hostel_id, is_holiday, created_by_user_id
                        FROM calendar.event
                        WHERE start_date <= :end AND coalesce(end_date, start_date) >= :start
                        ORDER BY start_date, event_id
                        """)
                .param("start", start).param("end", end)
                .query((rs, i) -> new CalendarEvent()
                        .schoolId(rs.getLong("school_id"))
                        .eventId(rs.getLong("event_id"))
                        .academicYearId((Long) rs.getObject("academic_year_id"))
                        .eventType(CalendarEvent.EventTypeEnum.fromValue(rs.getString("event_type")))
                        .title(rs.getString("title"))
                        .startDate(rs.getObject("start_date", LocalDate.class))
                        .endDate(rs.getObject("end_date", LocalDate.class))
                        .appliesTo(rs.getString("applies_to") == null ? null : CalendarEvent.AppliesToEnum.fromValue(rs.getString("applies_to")))
                        .programId((Long) rs.getObject("program_id"))
                        .classSectionId((Long) rs.getObject("class_section_id"))
                        .hostelId((Long) rs.getObject("hostel_id"))
                        .isHoliday(rs.getBoolean("is_holiday"))
                        .createdByUserId((Long) rs.getObject("created_by_user_id")))
                .list();
    }
}
