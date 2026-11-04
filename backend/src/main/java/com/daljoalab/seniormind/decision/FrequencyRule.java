package com.daljoalab.seniormind.decision;

import java.time.LocalDate;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

/**
 * 7일 빈도 규칙(백엔드 1.2-3, 명세 Risk_v0.6 E13·E14). 같은 세션 반복은 1회.
 * - 같은 영역 R1이 서로 다른 3세션 ∧ 2일 이상 → R2 후보
 * - 0.25~0.35 신호가 2세션 ∧ 2일 이상 → R1 후보
 */
public final class FrequencyRule {
    private FrequencyRule() {}

    /** 최근 7일 같은 영역 관찰 1건(현재 발화 포함). level: 그 발화의 영역 등급(R0/R1/R2), watch: 0.25~0.35 여부. */
    public record Observation(String sessionId, LocalDate day, String level, boolean watch) {}

    public record Stats(int sessions, int days) {}

    public static Stats count(List<Observation> obs, java.util.function.Predicate<Observation> filter) {
        Set<String> sessions = new HashSet<>();
        Set<LocalDate> days = new HashSet<>();
        for (Observation o : obs) if (filter.test(o)) { sessions.add(o.sessionId()); days.add(o.day()); }
        return new Stats(sessions.size(), days.size());
    }

    /** 현재 등급을 빈도로 올린 값. */
    public static String escalate(String current, List<Observation> obs, int r2Sessions, int r2Days, int r1Sessions, int r1Days) {
        if ("R1".equals(current)) {
            Stats s = count(obs, o -> "R1".equals(o.level()));
            if (s.sessions() >= r2Sessions && s.days() >= r2Days) return "R2";
        }
        if ("R0".equals(current)) {
            Stats s = count(obs, Observation::watch);
            if (s.sessions() >= r1Sessions && s.days() >= r1Days) return "R1";
        }
        return current;
    }
}
