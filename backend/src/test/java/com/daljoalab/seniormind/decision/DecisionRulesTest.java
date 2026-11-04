package com.daljoalab.seniormind.decision;

import static org.junit.jupiter.api.Assertions.*;

import com.fasterxml.jackson.databind.ObjectMapper;
import java.time.LocalDate;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.Test;

class DecisionRulesTest {
    final ObjectMapper json = new ObjectMapper();
    final RiskGrader.Thresholds t = new RiskGrader.Thresholds(0.30, 0.60, 0.35, 0.25);

    @Test
    void r3ByPredicateAtBoundary() {
        assertEquals("R3", RiskGrader.grade(0.30, Map.of("depression", 0.1), t));
        assertEquals("R0", RiskGrader.grade(0.29, Map.of("depression", 0.1), t));
    }

    @Test
    void domainThresholdsAndMaxAcrossDomains() {
        assertEquals("R2", RiskGrader.grade(0.0, Map.of("depression", 0.60, "anxiety", 0.4), t));
        assertEquals("R1", RiskGrader.grade(0.0, Map.of("depression", 0.35), t));
        assertEquals("R0", RiskGrader.grade(0.0, Map.of("depression", 0.30), t));
        assertTrue(RiskGrader.isWatch(0.30, t));
    }

    @Test
    void frequencyR1ThreeSessionsTwoDaysBecomesR2() {
        LocalDate d1 = LocalDate.of(2026, 11, 1), d2 = d1.plusDays(1);
        var obs = List.of(new FrequencyRule.Observation("s1", d1, "R1", false),
                new FrequencyRule.Observation("s1", d1, "R1", false),       // 같은 세션 반복은 1회
                new FrequencyRule.Observation("s2", d1, "R1", false),
                new FrequencyRule.Observation("s3", d2, "R1", false));
        assertEquals("R2", FrequencyRule.escalate("R1", obs, 3, 2, 2, 2));
        assertEquals("R1", FrequencyRule.escalate("R1", obs.subList(0, 3), 3, 2, 2, 2));
    }

    @Test
    void frequencyWatchTwoSessionsTwoDaysBecomesR1() {
        LocalDate d1 = LocalDate.of(2026, 11, 1);
        var obs = List.of(new FrequencyRule.Observation("s1", d1, "R0", true),
                new FrequencyRule.Observation("s2", d1.plusDays(1), "R0", true));
        assertEquals("R1", FrequencyRule.escalate("R0", obs, 3, 2, 2, 2));
    }

    @Test
    void safetyPhraseSelection() {
        assertEquals("SAFE_SUICIDE_R3", SafetyPhraseSelector.select("R3", List.of("self_harm_suicide"), List.of("self_harm_suicide.intent"), false));
        assertEquals("R3_SUICIDE_SUPPORT", SafetyPhraseSelector.select("R3", List.of("self_harm_suicide"), List.of("self_harm_suicide.passive_death_wish"), false));
        assertEquals("R3_SUICIDE_SUPPORT", SafetyPhraseSelector.select("R3", List.of(), List.of(), false));
        assertEquals("SAFE_ANXIETY", SafetyPhraseSelector.select("R2", List.of("anxiety"), List.of("anxiety.panic_like"), false));
        assertEquals("SAFE_SUICIDE_R2", SafetyPhraseSelector.select("R2", List.of("self_harm_suicide"), List.of(), false));
        assertEquals("R2_SUPPORT", SafetyPhraseSelector.select("R2", List.of("depression"), List.of(), true));
        assertEquals("R2_CHECK_IN", SafetyPhraseSelector.select("R2", List.of("depression"), List.of(), false));
        assertNull(SafetyPhraseSelector.select("R1", List.of("depression"), List.of(), false));
        for (String level : List.of("R2", "R3")) {
            for (String id : new String[]{"R3_CRISIS_HELP", "SAFE_RESPIRATORY", "SAFE_STROKE"}) {
                assertNotEquals(id, SafetyPhraseSelector.select(level, List.of("other_crisis"), List.of("other_crisis.acute_confusion"), false));
            }
        }
    }

    @Test
    void parsesCompleteAnswer() throws Exception {
        var body = json.readTree("""
            {"answers":[
              {"name":"Q00_reaction","type":"choice","choice":"empathy"},
              {"name":"Q00_intensity","type":"score","level":"high"},
              {"name":"Q01_emotion","type":"choice","choice":"sadness","probability":0.88},
              {"name":"Q02_risk_domain","type":"choice","choices":[{"value":"depression","probability":0.63},{"value":"anxiety","probability":0.18}],
               "evidence":[{"probability":0.63,"input_range":{"segment_id":"u_0001","start_ms":1200,"end_ms":4800},"quote":"원문은 버린다"}]},
              {"name":"Q03_depression_subtype","type":"choice","choices":["loneliness","not_an_option"]},
              {"name":"p_r3","type":"predicate","probability":0.09},
              {"name":"Q08_memory_control","type":"choice","choice":"DELETE"}
            ],"usage":{"input_tokens":412}}""");
        DecisionResult d = DecisionParser.parse(body, true);
        assertTrue(d.complete());
        assertEquals("empathy", d.reaction());
        assertEquals("sadness", d.emotion());
        assertEquals(0.85, d.semanticIntensity());
        assertEquals(0.63, d.domainScores().get("depression"));
        assertEquals(0.0, d.domainScores().get("addiction"));
        assertEquals(List.of("depression.loneliness"), d.riskSubtypes());
        assertEquals("DELETE", d.memoryControl());
        assertEquals(412, d.inputTokens());
        assertEquals(1, d.riskEvidence().size());
        assertFalse(d.riskEvidence().get(0).containsKey("quote"));
    }

    @Test
    void missingPredicateIsIncompleteNotR0() throws Exception {
        var body = json.readTree("""
            {"answers":[{"name":"Q00_reaction","choice":"neutral"},{"name":"Q01_emotion","choice":"neutral","probability":0.9},
              {"name":"Q02_risk_domain","choices":[]}]}""");
        assertFalse(DecisionParser.parse(body, true).complete());
    }

    @Test
    void selectedDomainWithoutProbabilityIsIncomplete() throws Exception {
        var body = json.readTree("""
            {"answers":[{"name":"Q01_emotion","choice":"sadness","probability":0.9},
              {"name":"Q02_risk_domain","choices":["depression"]},{"name":"p_r3","probability":0.1}]}""");
        assertFalse(DecisionParser.parse(body, true).complete());
    }

    @Test
    void outOfRangeReactionFallsBackToNeutral() throws Exception {
        var body = json.readTree("{\"answers\":[{\"name\":\"Q00_reaction\",\"choice\":\"laugh\"}]}");
        assertEquals("neutral", DecisionParser.parse(body, false).reaction());
    }

    @Test
    void finalRequestHasAllQuestionsMidHasOnlyReaction() {
        var fin = DecisionQuestions.build("gpt-6-luna", "{}", true);
        var mid = DecisionQuestions.build("gpt-6-luna", "{}", false);
        assertEquals(13, ((List<?>) fin.get("questions")).size());
        assertEquals(1, ((List<?>) mid.get("questions")).size());
    }
}
