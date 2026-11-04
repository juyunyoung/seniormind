package com.daljoalab.seniormind.security;

import com.daljoalab.seniormind.common.ApiExceptionHandler;
import com.daljoalab.seniormind.config.AppProperties;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.google.firebase.auth.FirebaseAuth;
import com.google.firebase.auth.FirebaseToken;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.util.Map;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

/**
 * 모든 API: Firebase ID 토큰 검증(백엔드 0장) → App Check 확인(log/enforce) → 사용자별 호출 제한.
 * 공개 호출(--allow-unauthenticated)이므로 이 필터가 유일한 관문이다.
 */
@Component
@Order(Ordered.HIGHEST_PRECEDENCE + 10)
public class AuthFilter extends OncePerRequestFilter {
    private static final Logger log = LoggerFactory.getLogger(AuthFilter.class);
    private final ObjectProvider<FirebaseAuth> auth;
    private final AppCheckVerifier appCheck;
    private final AppProperties props;
    private final RateLimiter limiter;
    private final ObjectMapper json = new ObjectMapper();

    public AuthFilter(ObjectProvider<FirebaseAuth> auth, AppCheckVerifier appCheck, AppProperties props) {
        this.auth = auth;
        this.appCheck = appCheck;
        this.props = props;
        this.limiter = new RateLimiter(Math.max(10, props.rateLimitPerMinute()));
    }

    @Override
    protected boolean shouldNotFilter(HttpServletRequest req) {
        return req.getRequestURI().equals("/healthz");
    }

    @Override
    protected void doFilterInternal(HttpServletRequest req, HttpServletResponse res, FilterChain chain)
            throws ServletException, IOException {
        CurrentUser user = authenticate(req);
        if (user == null) { reject(res, 401, "auth_required", "다시 로그인해 주세요."); return; }

        String mode = props.appCheckMode() == null ? "log" : props.appCheckMode();
        if (!"off".equals(mode)) {
            boolean ok = appCheck.verify(req.getHeader("X-Firebase-AppCheck"));
            if (!ok) {
                log.info("app_check_failed path={} platform={} mode={}", req.getRequestURI(), req.getHeader("X-Client-Platform"), mode);
                if ("enforce".equals(mode)) { reject(res, 401, "app_check_failed", "앱을 최신 버전으로 업데이트해 주세요."); return; }
            }
        }
        if (!limiter.allow(user.uid(), System.currentTimeMillis())) {
            reject(res, 429, "rate_limited", "잠시 후 다시 해 주세요."); return;
        }
        req.setAttribute(CurrentUser.ATTR, user);
        chain.doFilter(req, res);
    }

    private CurrentUser authenticate(HttpServletRequest req) {
        String header = req.getHeader("Authorization");
        if (props.devBypassAllowed() && req.getHeader("X-Debug-Uid") != null) {
            return new CurrentUser(req.getHeader("X-Debug-Uid"), "anonymous");   // 로컬 개발 전용
        }
        if (header == null || !header.startsWith("Bearer ")) return null;
        FirebaseAuth fa = auth.getIfAvailable();
        if (fa == null) return null;
        try {
            FirebaseToken t = fa.verifyIdToken(header.substring(7));
            Object fb = t.getClaims().get("firebase");
            String provider = fb instanceof Map<?, ?> m && m.get("sign_in_provider") != null ? m.get("sign_in_provider").toString() : null;
            return new CurrentUser(t.getUid(), provider);
        } catch (Exception e) {
            return null;
        }
    }

    private void reject(HttpServletResponse res, int status, String code, String message) throws IOException {
        res.setStatus(status);
        res.setContentType("application/json;charset=UTF-8");
        res.getWriter().write(json.writeValueAsString(ApiExceptionHandler.body(code, message)));
    }
}
