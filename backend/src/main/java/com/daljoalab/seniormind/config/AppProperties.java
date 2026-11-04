package com.daljoalab.seniormind.config;

import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties(prefix = "seniormind")
public record AppProperties(
        String projectId,
        String projectNumber,
        boolean firebaseEnabled,
        String appCheckMode,
        int rateLimitPerMinute,
        String pairingScheme,
        boolean devAuthBypass,
        OpenAi openai) {

    public record OpenAi(String apiKey, String baseUrl, String liveModel, String judgeModel, String voice, String delegation) {
        public boolean configured() { return apiKey != null && !apiKey.isBlank(); }
    }

    /** Cloud Run에서 실행 중인지(K_SERVICE 환경변수). 개발용 우회는 여기서 항상 꺼진다. */
    public static boolean onCloudRun() { return System.getenv("K_SERVICE") != null; }

    public boolean devBypassAllowed() { return devAuthBypass && !onCloudRun(); }
}
