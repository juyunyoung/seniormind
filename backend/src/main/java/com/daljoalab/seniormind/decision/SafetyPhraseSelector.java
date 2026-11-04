package com.daljoalab.seniormind.decision;

import java.util.List;
import java.util.Set;

/** 안전 문구 선택(백엔드 1.3 표). R3_CRISIS_HELP·SAFE_RESPIRATORY·SAFE_STROKE는 선택하지 않는다(보류). */
public final class SafetyPhraseSelector {
    private SafetyPhraseSelector() {}

    private static final Set<String> IMMEDIATE = Set.of("self_harm_suicide.intent", "self_harm_suicide.specific_plan",
            "self_harm_suicide.preparatory_behavior", "self_harm_suicide.method");

    /**
     * @param subtypes "domain.subtype" 목록
     * @param priorR2SameDomain7d 같은 영역의 이전 R2 판단이 7일 안에 있는지(이번이 2회째 이상)
     */
    public static String select(String level, List<String> domains, List<String> subtypes, boolean priorR2SameDomain7d) {
        if ("R3".equals(level)) {
            if (subtypes.stream().anyMatch(IMMEDIATE::contains)) return "SAFE_SUICIDE_R3";
            if (domains.contains("self_harm_suicide") || domains.isEmpty()) return "R3_SUICIDE_SUPPORT";
            if (subtypes.contains("other_crisis.acute_confusion")) return "SAFE_CONFUSION";
            if (subtypes.contains("other_crisis.behavioral_crisis")) return "SAFE_BEHAVIOR";
            if (subtypes.contains("addiction.medication_misuse")) return "SAFE_MEDICATION";
            return "R3_SAFETY_CHECK";
        }
        if ("R2".equals(level)) {
            if (domains.contains("self_harm_suicide")) return "SAFE_SUICIDE_R2";
            if (subtypes.contains("anxiety.panic_like")) return "SAFE_ANXIETY";
            if (priorR2SameDomain7d) return "R2_SUPPORT";
            return "R2_CHECK_IN";
        }
        return null;
    }
}
