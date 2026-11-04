package com.daljoalab.seniormind.decision;

import com.daljoalab.seniormind.security.CurrentUser;
import com.fasterxml.jackson.annotation.JsonProperty;
import jakarta.servlet.http.HttpServletRequest;
import java.util.Map;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class DecisionController {
    private final DecisionService decisions;

    public DecisionController(DecisionService decisions) { this.decisions = decisions; }

    /** 요청 필드 "final"은 자바 예약어라 이름을 따로 매핑한다. */
    public record Body(String sessionId, String utteranceId, String inputText, String outputText, String previousReaction,
                       @JsonProperty("final") Boolean finalTurn, DecisionService.Utterance utterance) {}

    @PostMapping("/api/decision")
    public Map<String, Object> decide(HttpServletRequest req, @RequestBody Body b) {
        return decisions.decide(CurrentUser.of(req).uid(), new DecisionService.Request(b.sessionId(), b.utteranceId(),
                b.inputText(), b.outputText(), b.previousReaction(), b.finalTurn(), b.utterance()));
    }
}
