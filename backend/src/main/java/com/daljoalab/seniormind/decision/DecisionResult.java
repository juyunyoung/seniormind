package com.daljoalab.seniormind.decision;

import java.util.List;
import java.util.Map;

/** Decisions 응답을 검증·변환한 값. 등급은 아직 없음(RiskGrader가 정한다). */
public record DecisionResult(
        String reaction,
        String emotion,
        double emotionConfidence,
        double semanticIntensity,
        double pR3,
        Map<String, Double> domainScores,
        List<String> riskDomains,
        List<String> riskSubtypes,
        String memoryControl,
        List<String> nonRiskReasons,
        List<String> cognitiveSignals,
        List<Map<String, Object>> emotionEvidence,
        List<Map<String, Object>> riskEvidence,
        boolean complete,
        Integer inputTokens) {
}
