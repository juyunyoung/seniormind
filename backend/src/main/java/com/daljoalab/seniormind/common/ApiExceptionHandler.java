package com.daljoalab.seniormind.common;

import java.util.Map;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.servlet.resource.NoResourceFoundException;

@RestControllerAdvice
public class ApiExceptionHandler {
    private static final Logger log = LoggerFactory.getLogger(ApiExceptionHandler.class);

    public static Map<String, Object> body(String code, String message) {
        return Map.of("error", Map.of("code", code, "message", message));
    }

    @ExceptionHandler(ApiException.class)
    public ResponseEntity<Object> api(ApiException e) {
        return ResponseEntity.status(e.status()).body(body(e.code(), e.getMessage()));
    }

    @ExceptionHandler({HttpMessageNotReadableException.class, MethodArgumentNotValidException.class, IllegalArgumentException.class})
    public ResponseEntity<Object> badRequest(Exception e) {
        return ResponseEntity.badRequest().body(body("invalid_request", "요청 형식을 확인해 주세요."));
    }

    @ExceptionHandler(NoResourceFoundException.class)
    public ResponseEntity<Object> noRoute(NoResourceFoundException e) {
        return ResponseEntity.status(404).body(body("not_found", "찾을 수 없어요."));
    }

    @ExceptionHandler(Exception.class)
    public ResponseEntity<Object> other(Exception e) {
        // 원문(자막 등)이 로그에 남지 않도록 예외 종류만 기록
        log.error("unhandled {}", e.getClass().getName());
        return ResponseEntity.status(500).body(body("internal_error", "지금은 연결이 어려워요. 잠시 후 다시 해 주세요."));
    }
}
