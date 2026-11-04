package com.daljoalab.seniormind.alert;

import java.time.Duration;
import java.time.Instant;

/** 알림 억제 창(백엔드 2.9, 명세 Risk_v0.6): R1 7일·R2 3일·R3 없음. R1→R2 상향은 즉시. */
public final class CooldownPolicy {
    private CooldownPolicy() {}

    public enum Action { NEW_PUSH, UPDATE_SUPPRESSED }

    /**
     * @param lastSameLevelFirstAt 같은 (어르신, 보호자, 영역, 등급)의 직전 알림 최초 관찰 시각. 없으면 null.
     * @param escalatedFromR1 직전 같은 영역 알림이 R1이었거나 빈도 규칙으로 올라온 경우
     */
    public static Action decide(String level, Instant lastSameLevelFirstAt, boolean escalatedFromR1, int cooldownDays, Instant now) {
        if ("R3".equals(level)) return Action.NEW_PUSH;
        if (escalatedFromR1) return Action.NEW_PUSH;
        if (lastSameLevelFirstAt != null && Duration.between(lastSameLevelFirstAt, now).toDays() < cooldownDays) {
            return Action.UPDATE_SUPPRESSED;
        }
        return Action.NEW_PUSH;
    }

    /** 방해 금지 시간(보호자 시간대 "HH:mm"~"HH:mm"). R3는 무시. */
    public static boolean inQuietHours(String from, String to, java.time.LocalTime now) {
        if (from == null || to == null) return false;
        java.time.LocalTime f = java.time.LocalTime.parse(from), t = java.time.LocalTime.parse(to);
        return f.isBefore(t) ? !now.isBefore(f) && now.isBefore(t) : !now.isBefore(f) || now.isBefore(t);
    }
}
