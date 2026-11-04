package com.daljoalab.seniormind.alert;

import com.daljoalab.seniormind.common.Docs;
import com.daljoalab.seniormind.common.Times;
import com.daljoalab.seniormind.push.PushService;
import com.daljoalab.seniormind.runtimeconfig.RuntimeConfig;
import com.daljoalab.seniormind.runtimeconfig.RuntimeConfigService;
import com.daljoalab.seniormind.user.ConsentService;
import com.daljoalab.seniormind.user.UserService;
import com.google.cloud.firestore.DocumentReference;
import com.google.cloud.firestore.FieldValue;
import com.google.cloud.firestore.Firestore;
import com.google.cloud.firestore.Query;
import com.google.cloud.firestore.QueryDocumentSnapshot;
import java.time.Instant;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

/**
 * 보호자 위험 알림(백엔드 1.7·2.9). Pub/Sub 대신 판단 요청 안에서 바로 처리한다(1인 개발 단순화, README).
 * R2·R3만 들어온다. R1은 저장만(주간 요약, P3).
 */
@Service
public class AlertService {
    private static final Logger log = LoggerFactory.getLogger(AlertService.class);
    private final Firestore db;
    private final ConsentService consents;
    private final UserService users;
    private final PushService push;
    private final RuntimeConfigService configs;

    public AlertService(Firestore db, ConsentService consents, UserService users, PushService push, RuntimeConfigService configs) {
        this.db = db; this.consents = consents; this.users = users; this.push = push; this.configs = configs;
    }

    public void handle(RiskEvent e) {
        try { dispatch(e); } catch (Exception ex) { log.warn("alert dispatch failed level={}", e.level()); }
    }

    private void dispatch(RiskEvent e) throws Exception {
        // 0) 동의 없으면 알림도 alerts 문서도 만들지 않는다
        if (!consents.all(e.seniorId(), "guardian_share", "sensitive")) return;
        RuntimeConfig cfg = configs.current();
        List<String> domains = e.domains().isEmpty() ? List.of("self_harm_suicide") : e.domains();

        for (QueryDocumentSnapshot link : db.collection("guardians").whereEqualTo("senior_id", e.seniorId())
                .whereEqualTo("status", "active").get().get().getDocuments()) {
            if (!Docs.bool(Docs.map(link.getData(), "permissions"), "alerts")) continue;
            String gid = link.getString("guardian_id");
            Map<String, Object> guardian = users.get(gid);
            Map<String, Object> prefs = Docs.map(guardian, "notification_prefs");
            List<QueryDocumentSnapshot> recent = db.collection("alerts").whereEqualTo("senior_id", e.seniorId())
                    .whereEqualTo("guardian_id", gid).whereEqualTo("type", "risk")
                    .orderBy("last_detected_at", Query.Direction.DESCENDING).limit(30).get().get().getDocuments();

            boolean pushed = false;
            for (String domain : domains) {
                QueryDocumentSnapshot sameLevel = null, sameDomain = null;
                for (QueryDocumentSnapshot a : recent) {
                    if (!Docs.strings(a.getData(), "risk_domains").contains(domain)) continue;
                    if (sameDomain == null) sameDomain = a;
                    if (sameLevel == null && e.level().equals(a.getString("risk_level"))) sameLevel = a;
                }
                boolean escalated = e.frequencyEscalated() || (sameDomain != null && "R1".equals(sameDomain.getString("risk_level")));
                Instant lastFirst = sameLevel == null ? null : Times.instant(sameLevel.get("first_detected_at"));
                CooldownPolicy.Action action = CooldownPolicy.decide(e.level(), lastFirst, escalated, cfg.cooldownDays(e.level()), e.at());

                if (action == CooldownPolicy.Action.UPDATE_SUPPRESSED) {
                    sameLevel.getReference().update("occurrence_count", FieldValue.increment(1), "last_detected_at", Times.ts(e.at()),
                            "suppressed", true, "updated_at", Times.now());
                    continue;
                }
                DocumentReference ref = db.collection("alerts").document(e.alertEventId() + "_" + gid + "_" + domain);
                int[] f = e.frequency().getOrDefault(domain, new int[]{1, 1});
                Map<String, Object> doc = new HashMap<>();
                doc.put("senior_id", e.seniorId());
                doc.put("guardian_id", gid);
                doc.put("alert_event_id", e.alertEventId());
                doc.put("type", "risk");
                doc.put("risk_level", e.level());
                doc.put("risk_domains", List.of(domain));
                doc.put("first_detected_at", Times.ts(e.at()));
                doc.put("last_detected_at", Times.ts(e.at()));
                doc.put("occurrence_count", 1);
                doc.put("distinct_days_7d", f[1]);
                doc.put("independent_sessions_7d", f[0]);
                doc.put("trend", "insufficient_data");          // 확정 추세는 기준선 배치(P2) 이후
                doc.put("recommended_action", cfg.actionFor(e.level()));
                doc.put("suppressed", false);
                doc.put("delivery_status", "sent");
                doc.put("safety_follow_up_status", "pending");
                doc.put("escalated_to", List.of());
                doc.put("created_at", Times.now());
                doc.put("schema_version", "1");
                try { ref.create(doc).get(); }
                catch (Exception dup) { continue; }              // 같은 판단의 재시도 → 이미 있음(멱등)

                if (!pushed && shouldPush(e.level(), prefs, Docs.str(guardian, "timezone"))) {
                    Map<String, String> data = Map.of("type", "risk", "alert_id", ref.getId(), "senior_id", e.seniorId(),
                            "risk_level", e.level(), "risk_domain", domain, "timestamp", Times.iso(e.at()));
                    push.sendToUser(gid, "R3".equals(e.level()) ? PushService.Kind.RISK_R3 : PushService.Kind.RISK_R2, data,
                            "어르신 안부 확인이 필요해요", "앱에서 자세한 내용을 확인해 주세요.");
                    pushed = true;   // 한 판단에 보호자당 푸시 1번
                }
            }
        }
    }

    private static boolean shouldPush(String level, Map<String, Object> prefs, String tz) {
        if ("R3".equals(level)) return true;                    // R3는 설정과 무관하게 항상
        if ("R3".equals(Docs.str(prefs, "risk_min_level"))) return false;
        Map<String, Object> quiet = Docs.map(prefs, "quiet_hours");
        java.time.LocalTime now = java.time.LocalTime.now(Times.zone(tz));
        return !CooldownPolicy.inQuietHours(Docs.str(quiet, "from"), Docs.str(quiet, "to"), now);   // 아침 재발송은 P2 배치
    }
}
