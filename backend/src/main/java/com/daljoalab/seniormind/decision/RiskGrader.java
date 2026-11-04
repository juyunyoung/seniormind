package com.daljoalab.seniormind.decision;

import java.util.Map;

/** 등급 계산(백엔드 1.2-3, 명세 Risk_v0.6 Pipeline). 영역별로 계산해 최대 등급. 개인별로 낮추는 조정 없음(D34). */
public final class RiskGrader {
    private RiskGrader() {}

    public record Thresholds(double r3, double r2, double r1, double watch) {}

    public static int rank(String level) {
        return switch (level) { case "R3" -> 3; case "R2" -> 2; case "R1" -> 1; default -> 0; };
    }
    public static String max(String a, String b) { return rank(a) >= rank(b) ? a : b; }

    /** 영역 점수 하나의 등급(R3는 p_r3로만). watch는 R0로 두고 빈도 규칙에서만 쓴다. */
    public static String domainLevel(double score, Thresholds t) {
        if (score >= t.r2()) return "R2";
        if (score >= t.r1()) return "R1";
        return "R0";
    }

    public static boolean isWatch(double score, Thresholds t) { return score >= t.watch() && score < t.r1(); }

    public static String grade(double pR3, Map<String, Double> domainScores, Thresholds t) {
        if (pR3 >= t.r3()) return "R3";
        String level = "R0";
        for (double s : domainScores.values()) level = max(level, domainLevel(s, t));
        return level;
    }
}
