package com.daljoalab.seniormind.common;

/** 공통 오류. 응답은 {"error":{"code","message"}}, message는 사용자에게 바로 보여 줄 한국어(백엔드 6.7). */
public class ApiException extends RuntimeException {
    private final int status;
    private final String code;

    public ApiException(int status, String code, String message) {
        super(message);
        this.status = status;
        this.code = code;
    }

    public int status() { return status; }
    public String code() { return code; }

    public static ApiException badRequest(String code, String message) { return new ApiException(400, code, message); }
    public static ApiException unauthorized() { return new ApiException(401, "auth_required", "다시 로그인해 주세요."); }
    public static ApiException consentRequired() { return new ApiException(403, "consent_required", "먼저 동의가 필요해요."); }
    public static ApiException forbidden(String code) { return new ApiException(403, code, "이 정보를 볼 수 있는 권한이 없어요."); }
    public static ApiException notFound() { return new ApiException(404, "not_found", "찾을 수 없어요. 목록을 새로고침해 주세요."); }
    public static ApiException upstream() { return new ApiException(503, "upstream_unavailable", "지금은 연결이 어려워요. 잠시 후 다시 해 주세요."); }
}
