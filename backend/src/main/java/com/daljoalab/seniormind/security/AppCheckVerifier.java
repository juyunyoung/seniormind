package com.daljoalab.seniormind.security;

import com.daljoalab.seniormind.config.AppProperties;
import com.nimbusds.jose.JWSAlgorithm;
import com.nimbusds.jose.jwk.source.JWKSource;
import com.nimbusds.jose.jwk.source.JWKSourceBuilder;
import com.nimbusds.jose.proc.JWSVerificationKeySelector;
import com.nimbusds.jose.proc.SecurityContext;
import com.nimbusds.jwt.JWTClaimsSet;
import com.nimbusds.jwt.proc.DefaultJWTProcessor;
import java.net.URI;
import java.util.Date;
import java.util.List;
import org.springframework.stereotype.Component;

/**
 * Firebase App Check 토큰 검증. PC·스크립트는 Apple(App Attest)이 증명한 이 토큰을 만들 수 없다.
 * 규칙: RS256, 공개키 https://firebaseappcheck.googleapis.com/v1/jwks,
 * iss = https://firebaseappcheck.googleapis.com/{프로젝트 번호}, aud에 projects/{번호 또는 ID}.
 */
@Component
public class AppCheckVerifier {
    private static final String JWKS = "https://firebaseappcheck.googleapis.com/v1/jwks";
    private final AppProperties props;
    private final DefaultJWTProcessor<SecurityContext> processor;

    public AppCheckVerifier(AppProperties props) throws Exception {
        this.props = props;
        JWKSource<SecurityContext> keys = JWKSourceBuilder.create(URI.create(JWKS).toURL()).retrying(true).build();
        this.processor = new DefaultJWTProcessor<>();
        this.processor.setJWSKeySelector(new JWSVerificationKeySelector<>(JWSAlgorithm.RS256, keys));
    }

    /** 유효하면 true. 실패 이유는 남기지 않는다(토큰 원문을 로그에 쓰지 않음). */
    public boolean verify(String token) {
        if (token == null || token.isBlank()) return false;
        try {
            JWTClaimsSet c = processor.process(token, null);
            if (c.getExpirationTime() == null || c.getExpirationTime().before(new Date())) return false;
            String number = props.projectNumber();
            String iss = c.getIssuer();
            if (iss == null || !iss.startsWith("https://firebaseappcheck.googleapis.com/")) return false;
            if (number != null && !number.isBlank() && !iss.endsWith("/" + number)) return false;
            List<String> aud = c.getAudience();
            return aud.stream().anyMatch(a -> a.equals("projects/" + props.projectId())
                    || (number != null && !number.isBlank() && a.equals("projects/" + number)));
        } catch (Exception e) {
            return false;
        }
    }
}
