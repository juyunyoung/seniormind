package com.daljoalab.seniormind.user;

import com.daljoalab.seniormind.common.Docs;
import com.daljoalab.seniormind.common.Times;
import com.daljoalab.seniormind.security.CurrentUser;
import com.google.cloud.firestore.Firestore;
import com.google.cloud.firestore.QueryDocumentSnapshot;
import com.google.cloud.firestore.SetOptions;
import jakarta.servlet.http.HttpServletRequest;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.Map;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

/** 백엔드 1.0 계정·기기·동의 API. */
@RestController
public class UserController {
    private final UserService users;
    private final ConsentService consents;
    private final Firestore db;

    public UserController(UserService users, ConsentService consents, Firestore db) {
        this.users = users; this.consents = consents; this.db = db;
    }

    public record UserUpsert(String role, String displayName, String timezone, Map<String, Object> notificationPrefs) {}

    @PostMapping("/users/me")
    public Map<String, Object> upsertMe(HttpServletRequest req, @RequestBody UserUpsert body) {
        CurrentUser me = CurrentUser.of(req);
        return users.upsert(me.uid(), me.authProvider(), body.role(), body.displayName(), body.timezone(), body.notificationPrefs());
    }

    @GetMapping("/users/me")
    public Map<String, Object> me(HttpServletRequest req) throws Exception {
        CurrentUser me = CurrentUser.of(req);
        Map<String, Object> u = users.require(me.uid());
        Map<String, Object> out = new LinkedHashMap<>(UserService.profile(me.uid(), u));
        out.put("consents", consents.latest(me.uid()));
        String field = "senior".equals(Docs.str(u, "role")) ? "senior_id" : "guardian_id";
        out.put("linked_count", db.collection("guardians").whereEqualTo(field, me.uid()).whereEqualTo("status", "active").get().get().size());
        return out;
    }

    public record DeviceRegister(String deviceId, String platform, String appVersion, String osVersion, String fcmToken,
                                 String notificationPermission, String alarmPermission, String locale, String timezone) {}

    /** 백엔드 6.1 기기 등록. 같은 푸시 토큰이 다른 기기에 있으면 이전 것 비활성(재설치). */
    @PostMapping("/devices")
    public Map<String, Object> device(HttpServletRequest req, @RequestBody DeviceRegister b) throws Exception {
        CurrentUser me = CurrentUser.of(req);
        Map<String, Object> u = users.require(me.uid());
        if (b.deviceId() == null || b.deviceId().isBlank()) throw new IllegalArgumentException("device_id");
        if (b.fcmToken() != null) {
            for (QueryDocumentSnapshot d : db.collection("devices").whereEqualTo("fcm_token", b.fcmToken()).get().get().getDocuments()) {
                if (!d.getId().equals(b.deviceId())) d.getReference().update("active", false, "updated_at", Times.now());
            }
        }
        Map<String, Object> doc = new HashMap<>();
        doc.put("device_id", b.deviceId());
        doc.put("user_id", me.uid());
        doc.put("platform", "android".equals(b.platform()) ? "android" : "ios");
        doc.put("app_version", b.appVersion());
        doc.put("os_version", b.osVersion());
        doc.put("fcm_token", b.fcmToken());
        doc.put("notification_permission", b.notificationPermission() == null ? "unknown" : b.notificationPermission());
        doc.put("alarm_permission", b.alarmPermission() == null ? "unknown" : b.alarmPermission());
        doc.put("locale", b.locale());
        doc.put("timezone", Times.zone(b.timezone()).getId());
        doc.put("last_seen_at", Times.now());
        doc.put("active", true);
        doc.put("updated_at", Times.now());
        db.collection("devices").document(b.deviceId()).set(doc, SetOptions.merge()).get();

        Map<String, Object> userUpdate = new HashMap<>();
        userUpdate.put("platform_hint", doc.get("platform"));
        if ("senior".equals(Docs.str(u, "role")) && b.timezone() != null) userUpdate.put("timezone", doc.get("timezone"));
        db.collection("users").document(me.uid()).set(userUpdate, SetOptions.merge()).get();
        return Map.of("ok", true);
    }

    public record ConsentRequest(String type, String version, Boolean granted, String method, String linkedSeniorId) {}

    @PostMapping("/consents")
    public Map<String, Object> consent(HttpServletRequest req, @RequestBody ConsentRequest b) {
        CurrentUser me = CurrentUser.of(req);
        // 계정 생성(POST /users/me)과 동의 화면이 동시에 진행될 수 있어 역할이 없으면 동의 유형으로 판단
        Map<String, Object> u = users.get(me.uid());
        String role = u != null && Docs.str(u, "role") != null ? Docs.str(u, "role")
                : (ConsentService.GUARDIAN.contains(b.type()) ? "guardian" : "senior");
        consents.add(me.uid(), role, b.type(), b.version(), Boolean.TRUE.equals(b.granted()), b.method(), b.linkedSeniorId());
        return Map.of("ok", true);
    }

    @GetMapping("/consents")
    public Map<String, Boolean> consents(HttpServletRequest req) {
        return consents.latest(CurrentUser.of(req).uid());
    }
}
