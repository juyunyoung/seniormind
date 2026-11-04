package com.daljoalab.seniormind.decision;

import com.fasterxml.jackson.databind.JsonNode;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Decisions 응답 해석(백엔드 1.2 "응답 처리").
 * - 선택지 밖 값은 버린다.
 * - Q01·Q02·p_r3 중 하나라도 없거나 Q02에 확률이 없으면 complete=false → 호출부가 needs_review(R0 금지).
 * 응답 필드 이름이 아직 확정되지 않아 choice/choices/value, probability/confidence/score를 모두 받아들인다.
 */
public final class DecisionParser {
    private DecisionParser() {}

    public static DecisionResult parse(JsonNode body, boolean finalTurn) {
        Map<String, JsonNode> answers = new HashMap<>();
        for (JsonNode a : body.path("answers")) answers.put(a.path("name").asText(), a);
        Integer tokens = body.path("usage").path("input_tokens").isInt() ? body.path("usage").path("input_tokens").asInt() : null;

        String reaction = single(answers.get("Q00_reaction"), DecisionQuestions.REACTIONS);
        if (reaction == null) reaction = "neutral";
        if (!finalTurn) {
            return new DecisionResult(reaction, null, 0, 0, 0, Map.of(), List.of(), List.of(), "NONE",
                    List.of(), List.of(), List.of(), List.of(), true, tokens);
        }

        JsonNode emo = answers.get("Q01_emotion");
        String emotion = single(emo, DecisionQuestions.EMOTIONS);
        double emotionConf = prob(emo, emotion);

        double intensity = intensity(answers.get("Q00_intensity"));

        JsonNode domainNode = answers.get("Q02_risk_domain");
        Map<String, Double> scores = new LinkedHashMap<>();
        List<String> selected = multi(domainNode, DecisionQuestions.DOMAINS);
        boolean domainProbabilities = true;
        for (String d : DecisionQuestions.DOMAINS) {
            Double p = probOrNull(domainNode, d);
            if (p == null && selected.contains(d)) domainProbabilities = false;
            scores.put(d, p == null ? 0.0 : p);
        }

        JsonNode pr3Node = answers.get("p_r3");
        Double pR3 = predicate(pr3Node);

        List<String> subtypes = new ArrayList<>();
        for (String d : selected) {
            for (String s : multi(answers.get(DecisionQuestions.SUBTYPE_QUESTION.get(d)), DecisionQuestions.SUBTYPES.get(d))) {
                subtypes.add(d + "." + s);
            }
        }
        String control = single(answers.get("Q08_memory_control"), DecisionQuestions.MEMORY_CONTROL);
        boolean complete = emotion != null && domainNode != null && domainProbabilities && pR3 != null;

        return new DecisionResult(reaction, emotion, emotionConf, intensity, pR3 == null ? 0 : clamp(pR3), scores, selected, subtypes,
                control == null ? "NONE" : control,
                multi(answers.get("Q09_nonrisk_reason"), DecisionQuestions.NON_RISK),
                multi(answers.get("Q10_cognitive_signal"), DecisionQuestions.COGNITIVE),
                evidence(emo), evidence(domainNode, pr3Node), complete, tokens);
    }

    static String single(JsonNode a, List<String> allowed) {
        if (a == null) return null;
        for (String key : List.of("choice", "value", "answer")) {
            JsonNode n = a.path(key);
            if (n.isTextual() && allowed.contains(n.asText())) return n.asText();
            if (n.isObject() && allowed.contains(n.path("value").asText())) return n.path("value").asText();
        }
        List<String> m = multi(a, allowed);
        return m.isEmpty() ? null : m.get(0);
    }

    static List<String> multi(JsonNode a, List<String> allowed) {
        List<String> out = new ArrayList<>();
        if (a == null) return out;
        for (String key : List.of("choices", "selected", "values")) {
            for (JsonNode n : a.path(key)) {
                String v = n.isTextual() ? n.asText() : n.path("value").asText();
                boolean chosen = n.isTextual() || !n.has("selected") || n.path("selected").asBoolean();
                if (allowed.contains(v) && chosen && !out.contains(v)) out.add(v);
            }
        }
        String one = a.path("choice").asText(null);
        if (one != null && allowed.contains(one) && !out.contains(one)) out.add(one);
        return out;
    }

    /** 선택지별 확률: choices[{value, probability}] 또는 probabilities{value: p} 또는 단일 choice의 probability. */
    static Double probOrNull(JsonNode a, String value) {
        if (a == null || value == null) return null;
        JsonNode map = a.has("probabilities") ? a.path("probabilities") : a.path("scores");
        if (map.isObject() && map.path(value).isNumber()) return clamp(map.path(value).asDouble());
        for (String key : List.of("choices", "selected", "values")) {
            for (JsonNode n : a.path(key)) {
                if (n.isObject() && value.equals(n.path("value").asText())) {
                    for (String pk : List.of("probability", "confidence", "score")) if (n.path(pk).isNumber()) return clamp(n.path(pk).asDouble());
                }
            }
        }
        if (value.equals(a.path("choice").asText(null))) {
            for (String pk : List.of("probability", "confidence", "score")) if (a.path(pk).isNumber()) return clamp(a.path(pk).asDouble());
        }
        return null;
    }

    static double prob(JsonNode a, String value) { Double p = probOrNull(a, value); return p == null ? 0 : p; }

    static Double predicate(JsonNode a) {
        if (a == null) return null;
        for (String pk : List.of("probability", "score", "confidence")) if (a.path(pk).isNumber()) return a.path(pk).asDouble();
        JsonNode v = a.path("value");
        if (v.isNumber()) return v.asDouble();
        return null;   // true/false만 있고 확률이 없으면 판단 불가
    }

    /** 점수 또는 단계(low/mid/high → 0.25/0.55/0.85). */
    static double intensity(JsonNode a) {
        if (a == null) return 0;
        for (String k : List.of("score", "value", "probability")) if (a.path(k).isNumber()) return clamp(a.path(k).asDouble());
        String level = a.path("level").asText(a.path("choice").asText(""));
        return switch (level) { case "low" -> 0.25; case "mid", "medium" -> 0.55; case "high" -> 0.85; default -> 0; };
    }

    /** 근거: {probability, input_range{segment_id, start_ms, end_ms}} 최대 3개. 원문·자유 서술은 버린다. */
    static List<Map<String, Object>> evidence(JsonNode... nodes) {
        List<Map<String, Object>> out = new ArrayList<>();
        for (JsonNode a : nodes) {
            if (a == null) continue;
            for (JsonNode e : a.path("evidence")) {
                if (out.size() >= 3) return out;
                JsonNode r = e.path("input_range");
                Map<String, Object> range = new LinkedHashMap<>();
                if (r.path("segment_id").isTextual()) range.put("segment_id", r.path("segment_id").asText());
                for (String k : List.of("start_ms", "end_ms", "start_char", "end_char")) if (r.path(k).isInt()) range.put(k, r.path(k).asInt());
                if (!range.containsKey("segment_id") || !e.path("probability").isNumber()) continue;
                out.add(Map.of("probability", clamp(e.path("probability").asDouble()), "input_range", range));
            }
        }
        return out;
    }

    static double clamp(double v) { return Math.max(0, Math.min(1, v)); }
}
