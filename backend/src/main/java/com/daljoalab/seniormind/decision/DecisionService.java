package com.daljoalab.seniormind.decision;

import com.daljoalab.seniormind.alert.AlertService;
import com.daljoalab.seniormind.alert.RiskEvent;
import com.daljoalab.seniormind.common.ApiException;
import com.daljoalab.seniormind.common.Docs;
import com.daljoalab.seniormind.common.Times;
import com.daljoalab.seniormind.config.AppProperties;
import com.daljoalab.seniormind.openai.OpenAiClient;
import com.daljoalab.seniormind.runtimeconfig.RuntimeConfig;
import com.daljoalab.seniormind.runtimeconfig.RuntimeConfigService;
import com.daljoalab.seniormind.session.SessionService;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.google.cloud.firestore.DocumentReference;
import com.google.cloud.firestore.DocumentSnapshot;
import com.google.cloud.firestore.FieldValue;
import com.google.cloud.firestore.Firestore;
import com.google.cloud.firestore.Query;
import com.google.cloud.firestore.QueryDocumentSnapshot;
import com.google.cloud.firestore.SetOptions;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import org.springframework.stereotype.Service;

/**
 * POST /api/decision (백엔드 1.2).
 * - 중간 판단(final=false): 반응 질문만, 저장 없음, 세션당 동시 1건·950ms 간격(PoC). 응답 risk_level은 R0, assessment_status=reaction_only.
 * - 최종 판단(final=true): 전체 질문 → 검증 → 등급(p_r3·영역 점수·7일 빈도) → 안전 문구 → assessments 저장 → R2 이상 보호자 알림.
 *   같은 (session_id, utterance_id)는 저장된 결과를 다시 돌려준다(멱등). 판단 실패는 needs_review(R0로 처리하지 않음).
 */
@Service
public class DecisionService {
    private final Firestore db;
    private final SessionService sessions;
    private final RuntimeConfigService configs;
    private final OpenAiClient openai;
    private final AlertService alerts;
    private final AppProperties props;
    private final ObjectMapper json = new ObjectMapper();
    private final Map<String, Long> lastMid = new ConcurrentHashMap<>();
    private final Set<String> midBusy = ConcurrentHashMap.newKeySet();

    public DecisionService(Firestore db, SessionService sessions, RuntimeConfigService configs, OpenAiClient openai,
                           AlertService alerts, AppProperties props) {
        this.db = db; this.sessions = sessions; this.configs = configs; this.openai = openai; this.alerts = alerts; this.props = props;
    }

    public record Utterance(String text, Integer startMs, Integer endMs) {}
    public record Request(String sessionId, String utteranceId, String inputText, String outputText, String previousReaction,
                          Boolean finalTurn, Utterance utterance) {}

    public Map<String, Object> decide(String uid, Request r) {
        long started = System.currentTimeMillis();
        if (r.sessionId() == null || r.utteranceId() == null) throw new IllegalArgumentException("session_id");
        Map<String, Object> session = sessions.owned(uid, r.sessionId());
        String previous = DecisionQuestions.REACTIONS.contains(r.previousReaction()) ? r.previousReaction() : "neutral";
        String input = tail(r.inputText(), 1600), output = tail(r.outputText(), 800);
        boolean finalTurn = Boolean.TRUE.equals(r.finalTurn());
        return finalTurn ? decideFinal(uid, r, session, previous, input, output, started) : decideMid(r, previous, input, output, started);
    }

    private Map<String, Object> decideMid(Request r, String previous, String input, String output, long started) {
        String key = r.sessionId();
        Long last = lastMid.get(key);
        if (last != null && started - last < 950 || !midBusy.add(key)) throw new ApiException(429, "rate_limited", "잠시 후 다시 해 주세요.");
        lastMid.put(key, started);
        try {
            OpenAiClient.Result res = openai.decisions(DecisionQuestions.build(props.openai().judgeModel(), inputJson(previous, input, output, null, r.utteranceId()), false));
            if (!res.ok()) throw ApiException.upstream();
            DecisionResult d = DecisionParser.parse(res.body(), false);
            return response(d.reaction(), "R0", "reaction_only", false, null, "NONE", null, d.inputTokens(), System.currentTimeMillis() - started);
        } finally {
            midBusy.remove(key);
        }
    }

    private Map<String, Object> decideFinal(String uid, Request r, Map<String, Object> session, String previous,
                                            String input, String output, long started) {
        DocumentReference ref = db.collection("assessments").document(SessionService.safeId(r.sessionId()) + "_" + SessionService.safeId(r.utteranceId()));
        try {
            DocumentSnapshot existing = ref.get().get();
            if (existing.exists()) return fromStored(existing.getId(), existing.getData());
        } catch (Exception e) { throw ApiException.upstream(); }

        RuntimeConfig cfg = configs.current();
        Utterance u = r.utterance() == null ? new Utterance(lastTurn(input), null, null) : r.utterance();
        Map<String, Object> request = DecisionQuestions.build(props.openai().judgeModel(), inputJson(previous, input, output, u, r.utteranceId()), true);

        DecisionResult d = null;
        int tokens = 0;
        for (int attempt = 0; attempt < 2; attempt++) {     // 구조 오류·누락이면 1회 재시도
            OpenAiClient.Result res = openai.decisions(request);
            if (!res.ok()) continue;
            d = DecisionParser.parse(res.body(), true);
            if (d.inputTokens() != null) tokens += d.inputTokens();
            if (d.complete()) break;
        }
        Instant now = Instant.now();
        if (d == null || !d.complete()) {
            Map<String, Object> doc = baseDoc(uid, r, u, cfg, now, tokens, d);
            doc.put("assessment_status", "needs_review");
            doc.put("risk_level", "unknown");
            doc.put("reaction", "neutral");
            save(ref, doc, r.sessionId(), u, tokens, "R0");
            return response("neutral", "unknown", "needs_review", false, null, "NONE", ref.getId(), tokens, System.currentTimeMillis() - started);
        }

        RiskGrader.Thresholds t = new RiskGrader.Thresholds(cfg.r3(), cfg.r2(), cfg.r1(), cfg.watch());
        String level = RiskGrader.grade(d.pR3(), d.domainScores(), t);

        // 7일 빈도 규칙: 최근 판단을 읽어 영역별로 즉시 적용(배치 아님)
        ZoneId zone = Times.SEOUL;
        List<Map<String, Object>> recent = recent(uid, now);
        boolean escalated = false;
        boolean priorR2 = false;
        Map<String, int[]> frequency = new HashMap<>();
        for (String domain : DecisionQuestions.DOMAINS) {
            double score = d.domainScores().getOrDefault(domain, 0.0);
            List<FrequencyRule.Observation> obs = new ArrayList<>();
            obs.add(new FrequencyRule.Observation(r.sessionId(), Times.day(now, zone), RiskGrader.domainLevel(score, t), RiskGrader.isWatch(score, t)));
            for (Map<String, Object> a : recent) {
                double s = Docs.num(Docs.map(a, "domain_scores"), domain, 0);
                Instant at = Times.instant(a.get("timestamp"));
                if (at == null) continue;
                obs.add(new FrequencyRule.Observation(Docs.str(a, "session_id"), Times.day(at, zone), RiskGrader.domainLevel(s, t), RiskGrader.isWatch(s, t)));
                if ("R2".equals(RiskGrader.domainLevel(s, t)) && "R2".equals(RiskGrader.domainLevel(score, t))) priorR2 = true;
            }
            String current = RiskGrader.domainLevel(score, t);
            String up = FrequencyRule.escalate(current, obs, cfg.i("risk.frequency.r2_sessions", 3), cfg.i("risk.frequency.r2_days", 2),
                    cfg.i("risk.frequency.r1_sessions", 2), cfg.i("risk.frequency.r1_days", 2));
            if (RiskGrader.rank(up) > RiskGrader.rank(current) && RiskGrader.rank(up) > RiskGrader.rank(level)) { level = up; escalated = true; }
            FrequencyRule.Stats st = FrequencyRule.count(obs, o -> !"R0".equals(o.level()));
            frequency.put(domain, new int[]{Math.max(1, st.sessions()), Math.max(1, st.days())});
        }

        boolean elevated = RiskGrader.rank(level) >= 2;
        String phrase = SafetyPhraseSelector.select(level, d.riskDomains(), d.riskSubtypes(), priorR2);
        if (phrase != null && !cfg.hasPhrase(phrase)) phrase = "R3".equals(level) ? "R3_SAFETY_CHECK" : "R2_CHECK_IN";
        String reaction = elevated ? "empathy" : d.reaction();
        List<String> domains = new ArrayList<>(d.riskDomains());
        if (escalated && domains.isEmpty()) domains.addAll(frequencyDomains(d.domainScores(), t));

        Map<String, Object> doc = baseDoc(uid, r, u, cfg, now, tokens, d);
        doc.put("assessment_status", "assessed");
        doc.put("risk_level", level);
        doc.put("risk_domains", domains);
        doc.put("frequency_escalated", escalated);
        doc.put("safety_phrase_id", phrase);
        doc.put("safety_override", elevated);
        doc.put("reaction", reaction);
        doc.put("memory_control_status", "NONE".equals(d.memoryControl()) ? null : "pending");
        save(ref, doc, r.sessionId(), u, tokens, level);

        if (elevated) {
            alerts.handle(new RiskEvent(uid, ref.getId(), level, domains, d.riskSubtypes(), escalated, frequency, now));
        }
        return response(reaction, level, "assessed", elevated, phrase, d.memoryControl(), ref.getId(), tokens, System.currentTimeMillis() - started);
    }

    private static List<String> frequencyDomains(Map<String, Double> scores, RiskGrader.Thresholds t) {
        List<String> out = new ArrayList<>();
        scores.forEach((k, v) -> { if (v >= t.watch()) out.add(k); });
        return out;
    }

    private Map<String, Object> baseDoc(String uid, Request r, Utterance u, RuntimeConfig cfg, Instant now, int tokens, DecisionResult d) {
        Map<String, Object> doc = new HashMap<>();
        doc.put("user_id", uid);
        doc.put("session_id", r.sessionId());
        doc.put("utterance_id", r.utteranceId());
        doc.put("utterance_start_ms", u.startMs());
        doc.put("timestamp", Times.ts(now));
        doc.put("final", true);
        doc.put("emotion_label", d == null ? null : d.emotion());
        doc.put("emotion_confidence", d == null ? null : d.emotionConfidence());
        doc.put("semantic_intensity", d == null ? null : d.semanticIntensity());
        doc.put("combined_intensity", d == null ? null : d.semanticIntensity());   // 음향 강도 보류
        doc.put("p_r3", d == null ? null : d.pR3());
        doc.put("domain_scores", d == null ? Map.of() : d.domainScores());
        doc.put("risk_domains", d == null ? List.of() : d.riskDomains());
        doc.put("risk_subtypes", d == null ? List.of() : d.riskSubtypes());
        doc.put("frequency_escalated", false);
        doc.put("non_risk_reasons", d == null ? List.of() : d.nonRiskReasons());
        doc.put("emotion_evidence", d == null ? List.of() : d.emotionEvidence());
        doc.put("risk_evidence", d == null ? List.of() : d.riskEvidence());
        doc.put("safety_phrase_id", null);
        doc.put("safety_override", false);
        doc.put("memory_control_intent", d == null ? "NONE" : d.memoryControl());
        doc.put("memory_control_scope", null);
        doc.put("memory_control_status", null);
        doc.put("cognitive_signals", d == null ? List.of() : d.cognitiveSignals());
        doc.put("review", null);
        doc.put("judge_latency_ms", null);
        doc.put("input_tokens", tokens);
        doc.put("config_version", cfg.version());
        doc.put("judge_model", props.openai().judgeModel());
        doc.put("model_version", props.openai().judgeModel());
        doc.put("policy_version", cfg.version());
        doc.put("deleted", false);
        doc.put("schema_version", "1");
        doc.put("created_at", Times.now());
        return doc;
    }

    private void save(DocumentReference ref, Map<String, Object> doc, String sessionId, Utterance u, int tokens, String level) {
        try {
            ref.set(doc).get();
            if (u.text() != null && u.startMs() != null) {
                db.collection("transcripts").document(SessionService.safeId(sessionId)).collection("parts").document("input_" + u.startMs())
                        .set(Map.of("direction", "input", "text", u.text(), "utterance_id", doc.get("utterance_id"),
                                "start_ms", u.startMs(), "end_ms", u.endMs() == null ? u.startMs() : u.endMs(), "created_at", Times.now()), SetOptions.merge()).get();
            }
            DocumentReference sref = db.collection("sessions").document(SessionService.safeId(sessionId));
            db.runTransaction(tx -> {
                DocumentSnapshot s = tx.get(sref).get();
                Map<String, Object> up = new HashMap<>();
                up.put("utterance_count", FieldValue.increment(1));
                up.put("judge_input_tokens", FieldValue.increment(tokens));
                String max = s.getString("max_risk_level");
                if (RiskGrader.rank(level) > RiskGrader.rank(max == null ? "R0" : max)) up.put("max_risk_level", level);
                if (RiskGrader.rank(level) >= 2) up.put("recall_blocked", true);
                tx.update(sref, up);
                return null;
            }).get();
        } catch (Exception e) {
            throw ApiException.upstream();
        }
    }

    private List<Map<String, Object>> recent(String uid, Instant now) {
        List<Map<String, Object>> out = new ArrayList<>();
        try {
            for (QueryDocumentSnapshot a : db.collection("assessments").whereEqualTo("user_id", uid)
                    .whereGreaterThanOrEqualTo("timestamp", Times.ts(now.minus(Duration.ofDays(7))))
                    .orderBy("timestamp", Query.Direction.DESCENDING).limit(300).get().get().getDocuments()) {
                Map<String, Object> m = a.getData();
                if (Docs.bool(m, "final") && "assessed".equals(Docs.str(m, "assessment_status")) && !Docs.bool(m, "deleted")) out.add(m);
            }
        } catch (Exception e) { throw ApiException.upstream(); }
        return out;
    }

    private static Map<String, Object> fromStored(String id, Map<String, Object> a) {
        return response(Docs.str(a, "reaction"), Docs.str(a, "risk_level"), Docs.str(a, "assessment_status"), Docs.bool(a, "safety_override"),
                Docs.str(a, "safety_phrase_id"), Docs.str(a, "memory_control_intent"), id, (int) Docs.lng(a, "input_tokens", 0), 0);
    }

    static Map<String, Object> response(String reaction, String level, String status, boolean override, String phrase,
                                        String control, String assessmentId, Integer tokens, long latency) {
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("reaction", reaction == null ? "neutral" : reaction);
        out.put("risk_level", level);
        out.put("assessment_status", status);
        out.put("safety_override", override);
        out.put("safety_phrase_id", phrase);
        out.put("memory_control", control == null ? "NONE" : control);
        out.put("assessment_id", assessmentId);
        out.put("usage", tokens == null ? Map.of() : Map.of("input_tokens", tokens));
        out.put("latency_ms", latency);
        return out;
    }

    private String inputJson(String previous, String input, String output, Utterance u, String utteranceId) {
        Map<String, Object> in = new LinkedHashMap<>();
        in.put("previous_reaction", previous);
        in.put("assistant_recent", output);
        in.put("user_recent", input);
        in.put("user_newest", u == null ? lastTurn(input) : u.text());
        if (u != null && u.startMs() != null) {
            in.put("segments", List.of(Map.of("segment_id", utteranceId, "start_ms", u.startMs(), "end_ms", u.endMs() == null ? u.startMs() : u.endMs())));
        }
        try { return json.writeValueAsString(in); } catch (Exception e) { throw new IllegalStateException(e); }
    }

    private static String tail(String s, int max) { return s == null ? "" : s.length() <= max ? s : s.substring(s.length() - max); }
    private static String lastTurn(String s) { return tail(s, 300); }
}
