package com.daljoalab.seniormind.openai;

import com.daljoalab.seniormind.common.ApiException;
import com.daljoalab.seniormind.config.AppProperties;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.Map;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

/**
 * OpenAI 호출(키는 서버만). 형식은 PoC server.mjs 기준이며 실제 명세 확인 필요(백엔드 5장).
 * 타임아웃: Live 세션 25초, Decisions 8초. 재시도는 네트워크 오류만 1회.
 */
@Component
public class OpenAiClient {
    private static final Logger log = LoggerFactory.getLogger(OpenAiClient.class);
    private final AppProperties props;
    private final ObjectMapper json = new ObjectMapper();
    private final HttpClient http = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(10)).build();

    public OpenAiClient(AppProperties props) { this.props = props; }

    public record Result(int status, JsonNode body) {
        public boolean ok() { return status >= 200 && status < 300; }
    }

    public Result liveSession(Map<String, Object> payload) { return post("/v1/live/sessions", payload, 25); }

    public Result decisions(Map<String, Object> payload) { return post("/v1/decisions", payload, 8); }

    private Result post(String path, Map<String, Object> payload, int timeoutSec) {
        if (!props.openai().configured()) {
            throw new ApiException(503, "upstream_unavailable", "서버 설정을 마치는 중이에요. 잠시 후 다시 해 주세요.");
        }
        for (int attempt = 0; ; attempt++) {
            try {
                HttpRequest req = HttpRequest.newBuilder(URI.create(props.openai().baseUrl() + path))
                        .timeout(Duration.ofSeconds(timeoutSec))
                        .header("Authorization", "Bearer " + props.openai().apiKey())
                        .header("Content-Type", "application/json")
                        .POST(HttpRequest.BodyPublishers.ofString(json.writeValueAsString(payload)))
                        .build();
                HttpResponse<String> res = http.send(req, HttpResponse.BodyHandlers.ofString());
                JsonNode body = res.body() == null || res.body().isBlank() ? json.createObjectNode() : json.readTree(res.body());
                if (res.statusCode() >= 300) log.warn("openai {} status={}", path, res.statusCode());
                return new Result(res.statusCode(), body);
            } catch (java.io.IOException e) {
                if (attempt >= 1) { log.warn("openai {} network error", path); throw ApiException.upstream(); }
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                throw ApiException.upstream();
            }
        }
    }
}
