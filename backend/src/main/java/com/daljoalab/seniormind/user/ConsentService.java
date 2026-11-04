package com.daljoalab.seniormind.user;

import com.daljoalab.seniormind.common.ApiException;
import com.daljoalab.seniormind.common.Times;
import com.google.cloud.firestore.Firestore;
import com.google.cloud.firestore.Query;
import com.google.cloud.firestore.QueryDocumentSnapshot;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Set;
import org.springframework.stereotype.Service;

/** consents/{uid}/items — 이력 보존, 유형별 최신 건이 유효(DB 정의 1장). */
@Service
public class ConsentService {
    public static final Set<String> SENIOR = Set.of("voice_transfer", "transcript_store", "memory_card", "guardian_share",
            "sensitive", "schedule_share", "guardian_topic_share");
    public static final Set<String> GUARDIAN = Set.of("guardian_terms", "guardian_data_view", "guardian_schedule_manage");

    private final Firestore db;

    public ConsentService(Firestore db) { this.db = db; }

    public void add(String uid, String role, String type, String version, boolean granted, String method, String linkedSeniorId) {
        if (!SENIOR.contains(type) && !GUARDIAN.contains(type)) throw ApiException.badRequest("invalid_consent_type", "동의 항목을 확인해 주세요.");
        Map<String, Object> doc = new LinkedHashMap<>();
        doc.put("type", type);
        doc.put("version", version == null ? "draft" : version);
        doc.put("granted", granted);
        doc.put(granted ? "granted_at" : "revoked_at", Times.now());
        doc.put("method", method == null ? "screen_tap" : method);
        doc.put("role", role);
        doc.put("linked_senior_id", linkedSeniorId);
        doc.put("schema_version", "1");
        doc.put("created_at", Times.now());
        try { db.collection("consents").document(uid).collection("items").add(doc).get(); }
        catch (Exception e) { throw ApiException.upstream(); }
    }

    /** 유형별 최신 동의 상태. 보호자 열람 동의는 연결 대상별 키 "guardian_data_view:{seniorId}"도 함께. */
    public Map<String, Boolean> latest(String uid) {
        Map<String, Boolean> out = new HashMap<>();
        try {
            for (QueryDocumentSnapshot d : db.collection("consents").document(uid).collection("items")
                    .orderBy("created_at", Query.Direction.ASCENDING).get().get().getDocuments()) {
                String type = d.getString("type");
                boolean g = Boolean.TRUE.equals(d.getBoolean("granted"));
                out.put(type, g);
                String linked = d.getString("linked_senior_id");
                if (linked != null) out.put(type + ":" + linked, g);
            }
        } catch (Exception e) { throw ApiException.upstream(); }
        return out;
    }

    public boolean all(String uid, String... types) {
        Map<String, Boolean> m = latest(uid);
        for (String t : types) if (!Boolean.TRUE.equals(m.get(t))) return false;
        return true;
    }

    public void require(String uid, String... types) {
        if (!all(uid, types)) throw ApiException.consentRequired();
    }
}
