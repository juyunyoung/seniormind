package com.daljoalab.seniormind.alert;

import java.time.Instant;
import java.util.List;
import java.util.Map;

/** 판단 1건에서 나온 위험 사건(백엔드 1.2-5). alertEventId = assessmentId(멱등키). */
public record RiskEvent(String seniorId, String assessmentId, String level, List<String> domains, List<String> subtypes,
                        boolean frequencyEscalated, Map<String, int[]> frequency, Instant at) {
    public String alertEventId() { return assessmentId; }
}
