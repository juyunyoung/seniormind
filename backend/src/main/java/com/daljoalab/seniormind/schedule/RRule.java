package com.daljoalab.seniormind.schedule;

import java.time.DayOfWeek;
import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalTime;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.EnumSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * 두 OS가 같게 해석하는 반복 규칙 부분집합(백엔드 6.4): FREQ=DAILY, FREQ=WEEKLY;BYDAY=MO,TU,...(1개 이상).
 * iOS AlarmScheduler.RRule과 같은 결과를 낸다. 시각은 어르신 시간대 기준, 초 0.
 */
public final class RRule {
    private RRule() {}

    private static final Map<String, DayOfWeek> DAYS = Map.of("MO", DayOfWeek.MONDAY, "TU", DayOfWeek.TUESDAY,
            "WE", DayOfWeek.WEDNESDAY, "TH", DayOfWeek.THURSDAY, "FR", DayOfWeek.FRIDAY, "SA", DayOfWeek.SATURDAY, "SU", DayOfWeek.SUNDAY);

    /** 지원하지 않으면 null. DAILY면 빈 집합이 아니라 7일 전체. */
    public static Set<DayOfWeek> parse(String rrule) {
        if (rrule == null) return null;
        String freq = null, byDay = null;
        for (String part : rrule.trim().split(";")) {
            String[] kv = part.split("=", 2);
            if (kv.length != 2) return null;
            switch (kv[0]) {
                case "FREQ" -> freq = kv[1];
                case "BYDAY" -> byDay = kv[1];
                default -> { return null; }
            }
        }
        if ("DAILY".equals(freq) && byDay == null) return EnumSet.allOf(DayOfWeek.class);
        if (!"WEEKLY".equals(freq) || byDay == null || byDay.isBlank()) return null;
        Set<DayOfWeek> out = EnumSet.noneOf(DayOfWeek.class);
        for (String d : byDay.split(",")) {
            DayOfWeek w = DAYS.get(d.trim());
            if (w == null) return null;
            out.add(w);
        }
        return out;
    }

    public static boolean valid(String rrule) { return parse(rrule) != null; }

    public static LocalTime time(String hhmm) {
        if (hhmm == null || !hhmm.matches("\\d{2}:\\d{2}")) return null;
        try { return LocalTime.parse(hhmm); } catch (Exception e) { return null; }
    }

    /** [from, to] 안의 발생 시각(UTC Instant). */
    public static List<Instant> occurrences(String rrule, String timeLocal, ZoneId zone, Instant from, Instant to) {
        List<Instant> out = new ArrayList<>();
        Set<DayOfWeek> days = parse(rrule);
        LocalTime t = time(timeLocal);
        if (days == null || t == null) return out;
        LocalDate day = from.atZone(zone).toLocalDate().minusDays(1);
        LocalDate last = to.atZone(zone).toLocalDate();
        for (; !day.isAfter(last); day = day.plusDays(1)) {
            if (!days.contains(day.getDayOfWeek())) continue;
            Instant at = day.atTime(t).atZone(zone).toInstant();
            if (!at.isBefore(from) && !at.isAfter(to)) out.add(at);
        }
        return out;
    }
}
