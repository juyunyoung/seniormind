package com.daljoalab.seniormind.session;

import com.daljoalab.seniormind.security.CurrentUser;
import jakarta.servlet.http.HttpServletRequest;
import java.util.List;
import java.util.Map;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class SessionController {
    private final SessionService sessions;

    public SessionController(SessionService sessions) { this.sessions = sessions; }

    public record CreateRequest(String sdp, SessionService.Client client) {}

    /** POST /api/session — SDP offer → OpenAI Live → answer. 음성은 WebRTC로 OpenAI에 직접 흐른다. */
    @PostMapping("/api/session")
    @ResponseStatus(HttpStatus.CREATED)
    public Map<String, Object> create(HttpServletRequest req, @RequestBody CreateRequest body) {
        return sessions.create(CurrentUser.of(req).uid(), body.sdp(), body.client());
    }

    public record Usage(Integer seconds) {}
    public record EndRequest(String endReason, Integer durationSec, Usage usage, List<SessionService.Part> transcript) {}

    @PostMapping("/sessions/{id}/end")
    public Map<String, Object> end(HttpServletRequest req, @PathVariable String id, @RequestBody EndRequest body) {
        return sessions.end(CurrentUser.of(req).uid(), id, body.endReason(), body.durationSec(),
                body.usage() == null ? null : body.usage().seconds(), body.transcript());
    }
}
