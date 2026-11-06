package com.daljoalab.seniormind.user;

import com.daljoalab.seniormind.common.ApiException;
import com.daljoalab.seniormind.common.Docs;
import com.daljoalab.seniormind.common.Times;
import com.google.cloud.firestore.DocumentSnapshot;
import com.google.cloud.firestore.Firestore;
import com.google.cloud.firestore.SetOptions;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.Map;
import org.springframework.stereotype.Service;

@Service
public class UserService {
    private final Firestore db;

    public UserService(Firestore db) { this.db = db; }

    public Map<String, Object> get(String uid) {
        try {
            DocumentSnapshot d = db.collection("users").document(uid).get().get();
            return d.exists() ? d.getData() : null;
        } catch (Exception e) { throw ApiException.upstream(); }
    }

    public Map<String, Object> require(String uid) {
        Map<String, Object> u = get(uid);
        if (u == null) throw new ApiException(403, "profile_required", "앱을 다시 시작해 주세요.");
        if (!"active".equals(Docs.str(u, "status"))) throw ApiException.forbidden("account_inactive");
        return u;
    }

    public String role(String uid) { return Docs.str(require(uid), "role"); }

    public void requireRole(String uid, String role) {
        if (!role.equals(role(uid))) throw ApiException.forbidden("permission_denied");
    }

    /** POST /users/me: role은 최초 1회만. notification_prefs는 보낸 키만 병합(백엔드 v0.4.3). */
    public Map<String, Object> upsert(String uid, String authProvider, String role, String displayName, String timezone,
                                      Map<String, Object> notificationPrefs, Integer birthYear, String speechRate) {
        if (!"senior".equals(role) && !"guardian".equals(role)) throw ApiException.badRequest("invalid_role", "역할을 확인해 주세요.");
        Map<String, Object> existing = get(uid);
        if (existing != null && !role.equals(Docs.str(existing, "role"))) {
            throw new ApiException(409, "role_conflict", "이미 다른 역할로 사용 중인 계정이에요.");
        }
        Map<String, Object> doc = new HashMap<>();
        if (existing == null) {
            doc.put("role", role);
            doc.put("status", "active");
            doc.put("locale", "ko-KR");
            doc.put("voice_id", null);
            doc.put("created_at", Times.now());
            doc.put("schema_version", "1");
        }
        doc.put("auth_provider", authProvider);
        if (displayName != null) doc.put("display_name", displayName.strip());
        if (timezone != null) doc.put("timezone", Times.zone(timezone).getId());
        if ("senior".equals(role)) {
            // C04 나이(선택) → 출생 연도. 생애 시기 추정 보조(DB 정의 users.birth_year)
            int year = java.time.Year.now().getValue();
            if (birthYear != null && birthYear >= year - 120 && birthYear <= year - 40) doc.put("birth_year", birthYear);
            // S13 말하는 속도: slow | normal → 다음 대화부터 지시문에 반영
            if ("slow".equals(speechRate) || "normal".equals(speechRate)) doc.put("speech_rate", speechRate);
        }
        if (notificationPrefs != null && "guardian".equals(role)) {
            Map<String, Object> prefs = new HashMap<>(existing == null ? Map.of() : Docs.map(existing, "notification_prefs"));
            prefs.putAll(notificationPrefs);
            doc.put("notification_prefs", prefs);
        }
        doc.put("updated_at", Times.now());
        try { db.collection("users").document(uid).set(doc, SetOptions.merge()).get(); }
        catch (Exception e) { throw ApiException.upstream(); }
        return profile(uid, get(uid));
    }

    public static Map<String, Object> profile(String uid, Map<String, Object> u) {
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("user_id", uid);
        out.put("role", Docs.str(u, "role"));
        out.put("display_name", Docs.str(u, "display_name"));
        out.put("timezone", Docs.str(u, "timezone") == null ? Times.SEOUL.getId() : Docs.str(u, "timezone"));
        if ("guardian".equals(Docs.str(u, "role"))) out.put("notification_prefs", Docs.map(u, "notification_prefs"));
        else out.put("speech_rate", Docs.str(u, "speech_rate") == null ? "normal" : Docs.str(u, "speech_rate"));
        return out;
    }

    public String displayName(String uid) {
        Map<String, Object> u = get(uid);
        return u == null ? null : Docs.str(u, "display_name");
    }
}
