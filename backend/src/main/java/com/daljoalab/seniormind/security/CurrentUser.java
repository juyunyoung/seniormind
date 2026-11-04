package com.daljoalab.seniormind.security;

import com.daljoalab.seniormind.common.ApiException;
import jakarta.servlet.http.HttpServletRequest;

/** 인증 필터가 요청에 붙인 사용자 정보. */
public record CurrentUser(String uid, String signInProvider) {
    public static final String ATTR = "seniormind.user";

    public static CurrentUser of(HttpServletRequest req) {
        Object v = req.getAttribute(ATTR);
        if (v instanceof CurrentUser u) return u;
        throw ApiException.unauthorized();
    }

    /** users.auth_provider 값: anonymous | email | google | apple */
    public String authProvider() {
        if (signInProvider == null) return "anonymous";
        return switch (signInProvider) {
            case "password" -> "email";
            case "google.com" -> "google";
            case "apple.com" -> "apple";
            default -> "anonymous";
        };
    }
}
