package com.daljoalab.seniormind.common;

import com.google.cloud.Timestamp;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.time.temporal.ChronoUnit;

/** 시각 규칙(백엔드 6.8): 모두 UTC ISO-8601, 소수 초 없음(iOS 디코더 호환). "오늘"은 어르신 시간대. */
public final class Times {
    public static final ZoneId SEOUL = ZoneId.of("Asia/Seoul");
    private Times() {}

    public static String iso(Instant i) { return i == null ? null : i.truncatedTo(ChronoUnit.SECONDS).toString(); }
    public static String iso(Timestamp t) { return t == null ? null : iso(t.toDate().toInstant()); }
    public static Timestamp ts(Instant i) { return Timestamp.ofTimeSecondsAndNanos(i.getEpochSecond(), i.getNano()); }
    public static Instant instant(Object v) {
        if (v instanceof Timestamp t) return t.toDate().toInstant();
        if (v instanceof String s) return Instant.parse(s);
        return null;
    }
    public static Timestamp now() { return Timestamp.now(); }
    public static ZoneId zone(String id) {
        try { return id == null ? SEOUL : ZoneId.of(id); } catch (Exception e) { return SEOUL; }
    }
    public static LocalDate day(Instant i, ZoneId z) { return i.atZone(z).toLocalDate(); }
    /** due_at 분 단위 정규화(초·밀리초 0). */
    public static Instant minute(Instant i) { return i.truncatedTo(ChronoUnit.MINUTES); }
}
