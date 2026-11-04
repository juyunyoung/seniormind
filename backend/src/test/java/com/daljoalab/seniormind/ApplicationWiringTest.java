package com.daljoalab.seniormind;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.google.cloud.firestore.Firestore;
import com.google.firebase.auth.FirebaseAuth;
import com.google.firebase.messaging.FirebaseMessaging;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

/** Firebase 없이 스프링 구성·인증 필터·공개 경로를 확인한다(Firestore는 가짜). */
@SpringBootTest(properties = {"seniormind.firebase-enabled=false", "seniormind.dev-auth-bypass=true", "seniormind.app-check-mode=off"})
@AutoConfigureMockMvc
class ApplicationWiringTest {
    @Autowired MockMvc mvc;
    @MockitoBean Firestore firestore;
    @MockitoBean FirebaseAuth firebaseAuth;
    @MockitoBean FirebaseMessaging firebaseMessaging;

    @Test
    void healthIsPublic() throws Exception {
        mvc.perform(get("/healthz")).andExpect(status().isOk()).andExpect(jsonPath("$.status").value("ok"));
    }

    @Test
    void apiRequiresAuth() throws Exception {
        mvc.perform(get("/config/latest")).andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.error.code").value("auth_required"));
    }

    @Test
    void configFallsBackToBuiltIn() throws Exception {
        mvc.perform(get("/config/latest").header("X-Debug-Uid", "u1")).andExpect(status().isOk())
                .andExpect(jsonPath("$.config_version").value("2026.11.04-1"))
                .andExpect(jsonPath("$.config.safety.phrases[0].id").value("R2_CHECK_IN"));
    }

    @Test
    void malformedBodyIsInvalidRequest() throws Exception {
        mvc.perform(post("/api/decision").header("X-Debug-Uid", "u1").contentType(MediaType.APPLICATION_JSON).content("{oops"))
                .andExpect(status().isBadRequest()).andExpect(jsonPath("$.error.code").value("invalid_request"));
    }
}
