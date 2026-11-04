package com.daljoalab.seniormind.runtimeconfig;

import com.fasterxml.jackson.databind.JsonNode;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Optional;

/** 설정 문서(config_versions.config) 읽기 전용 래퍼. 키는 db/seed와 같다. */
public record RuntimeConfig(String version, JsonNode root, String signature) {

    public double d(String path, double def) {
        JsonNode n = at(path); return n.isNumber() ? n.asDouble() : def;
    }
    public int i(String path, int def) {
        JsonNode n = at(path); return n.isNumber() ? n.asInt() : def;
    }
    public String s(String path, String def) {
        JsonNode n = at(path); return n.isTextual() ? n.asText() : def;
    }
    public JsonNode at(String path) { return root.at("/" + path.replace('.', '/')); }

    public double r3() { return d("risk.r3_threshold", 0.30); }
    public double r2() { return d("risk.r2_threshold", 0.60); }
    public double r1() { return d("risk.r1_threshold", 0.35); }
    public double watch() { return d("risk.r1_watch_threshold", 0.25); }
    public int cooldownDays(String level) { return i("risk.alert_cooldown_days." + level, switch (level) { case "R1" -> 7; case "R2" -> 3; default -> 0; }); }

    public String actionFor(String level) { return s("safety.actions." + level, switch (level) {
        case "R3" -> "URGENT_SAFETY_CHECK"; case "R2" -> "PROMPT_CONTACT"; default -> "CHECK_IN"; }); }

    public boolean hasPhrase(String id) {
        for (JsonNode p : root.at("/safety/phrases")) if (id.equals(p.path("id").asText())) return true;
        return false;
    }

    public List<String> strings(String path) {
        List<String> out = new ArrayList<>();
        at(path).forEach(n -> out.add(n.asText()));
        return out;
    }

    public Optional<String> minVersion(String platform) {
        JsonNode n = at("client.min_version." + platform);
        return n.isTextual() ? Optional.of(n.asText()) : Optional.empty();
    }

    public static String emotionGroup(String emotion) {
        return switch (emotion == null ? "neutral" : emotion) {
            case "joy" -> "POSITIVE";
            case "surprise" -> "SURPRISE";
            case "sadness", "anger", "fear", "disgust" -> "NEGATIVE";
            default -> "NEUTRAL";
        };
    }

    public static String intensityLevel(double v) { return v < 0.34 ? "LOW" : v < 0.67 ? "MODERATE" : "HIGH"; }

    public static final Map<String, String> P10 = Map.of("message",
            "평소 상태를 알아보기 위한 자료를 모으고 있어요. 아직 평소와의 변화를 판단하기에는 정보가 충분하지 않습니다.");
}
