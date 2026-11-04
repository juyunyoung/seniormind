package com.daljoalab.seniormind.guardian;

import com.daljoalab.seniormind.common.ApiException;
import com.daljoalab.seniormind.common.Docs;
import com.daljoalab.seniormind.common.Times;
import com.daljoalab.seniormind.runtimeconfig.RuntimeConfig;
import com.daljoalab.seniormind.schedule.RRule;
import com.daljoalab.seniormind.security.CurrentUser;
import com.daljoalab.seniormind.user.ConsentService;
import com.daljoalab.seniormind.user.UserService;
import com.google.cloud.firestore.DocumentSnapshot;
import com.google.cloud.firestore.Firestore;
import com.google.cloud.firestore.Query;
import com.google.cloud.firestore.QueryDocumentSnapshot;
import jakarta.servlet.http.HttpServletRequest;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * 보호자 보드(백엔드 2.8, 명세 Guardian_View_v0.6)와 알림 API(1.0).
 * 원문·점수·감정 7종 이름·근거 구간은 어떤 응답에도 넣지 않는다.
 */
@RestController
public class BoardController {
    private final Firestore db;
    private final UserService users;
    private final ConsentService consents;
    private final GuardianAccess access;

    public BoardController(Firestore db, UserService users, ConsentService consents, GuardianAccess access) {
        this.db = db; this.users = users; this.consents = consents; this.access = access;
    }

    @GetMapping("/guardian/board/{seniorId}")
    public Map<String, Object> board(HttpServletRequest req, @PathVariable String seniorId) throws Exception {
        String gid = CurrentUser.of(req).uid();
        access.require(gid, seniorId, "board");
        Map<String, Boolean> sc = consents.latest(seniorId);
        if (!Boolean.TRUE.equals(sc.get("guardian_share"))) throw ApiException.consentRequired();
        Map<String, Object> senior = users.require(seniorId);
        ZoneId zone = Times.zone(Docs.str(senior, "timezone"));
        DocumentSnapshot baseline = db.collection("baselines").document(seniorId).get().get();
        Map<String, Object> b = baseline.exists() ? baseline.getData() : Map.of();

        Map<String, Object> out = new LinkedHashMap<>();
        Map<String, Object> device = latestDevice(seniorId);
        out.put("senior", Map.of("display_name", nvl(Docs.str(senior, "display_name"), "어르신"),
                "platform", nvl(Docs.str(senior, "platform_hint"), "unknown")));
        out.put("today_schedules", today(seniorId, zone));

        Map<String, Object> emotion = Docs.map(b, "guardian_emotion_4");
        String intensity = Docs.str(b, "intensity_level_7d");
        if (emotion.isEmpty()) {   // 기준선 배치(P2) 전: 최근 7일 판단으로 즉시 계산(추세 없음)
            double[] acc = new double[5];
            for (QueryDocumentSnapshot a : db.collection("assessments").whereEqualTo("user_id", seniorId)
                    .whereGreaterThanOrEqualTo("timestamp", Times.ts(Instant.now().minus(Duration.ofDays(7))))
                    .orderBy("timestamp", Query.Direction.DESCENDING).limit(500).get().get().getDocuments()) {
                Map<String, Object> m = a.getData();
                if (!"assessed".equals(Docs.str(m, "assessment_status")) || Docs.bool(m, "deleted")) continue;
                switch (RuntimeConfig.emotionGroup(Docs.str(m, "emotion_label"))) {
                    case "POSITIVE" -> acc[0]++; case "NEGATIVE" -> acc[2]++; case "SURPRISE" -> acc[3]++; default -> acc[1]++;
                }
                acc[4] += Docs.num(m, "combined_intensity", 0);
            }
            double n = acc[0] + acc[1] + acc[2] + acc[3];
            emotion = new LinkedHashMap<>();
            emotion.put("POSITIVE", n == 0 ? 0 : round(acc[0] / n));
            emotion.put("NEUTRAL", n == 0 ? 0 : round(acc[1] / n));
            emotion.put("NEGATIVE", n == 0 ? 0 : round(acc[2] / n));
            emotion.put("SURPRISE", n == 0 ? 0 : round(acc[3] / n));
            intensity = n == 0 ? null : RuntimeConfig.intensityLevel(acc[4] / n);
        }
        out.put("emotion_7d", emotion);
        out.put("intensity_7d", intensity);
        String status = nvl(Docs.str(b, "baseline_status"), "building");
        out.put("baseline_status", status);
        out.put("baseline_message", "ready".equals(status) ? null : RuntimeConfig.P10.get("message"));
        out.put("trends", "ready".equals(status) ? trends(b) : List.of());
        out.put("alerts_recent", alerts(seniorId, gid, 10));
        out.put("conversation_topics", Boolean.TRUE.equals(sc.get("guardian_topic_share")) ? Docs.strings(b, "topics_cache") : List.of());
        Map<String, Object> ds = new LinkedHashMap<>();
        ds.put("platform", Docs.str(device, "platform"));
        ds.put("notification_permission", nvl(Docs.str(device, "notification_permission"), "unknown"));
        ds.put("alarm_permission", nvl(Docs.str(device, "alarm_permission"), "unknown"));
        Object seen = device.get("last_seen_at");
        ds.put("last_seen_at", seen instanceof com.google.cloud.Timestamp t ? Times.iso(t) : null);
        out.put("device_status", ds);
        return out;
    }

    @GetMapping("/guardian/alerts")
    public List<Map<String, Object>> list(HttpServletRequest req, @RequestParam("senior_id") String seniorId) throws Exception {
        String gid = CurrentUser.of(req).uid();
        access.require(gid, seniorId, "alerts");
        return alerts(seniorId, gid, 50);
    }

    @GetMapping("/guardian/alerts/{id}")
    public Map<String, Object> detail(HttpServletRequest req, @PathVariable String id) throws Exception {
        return alertView(id, owned(CurrentUser.of(req).uid(), id).getData());
    }

    @PatchMapping("/guardian/alerts/{id}/read")
    public Map<String, Object> read(HttpServletRequest req, @PathVariable String id) throws Exception {
        DocumentSnapshot d = owned(CurrentUser.of(req).uid(), id);
        if (d.get("read_at") == null) {
            String status = "safety_checked".equals(d.getString("delivery_status")) ? "safety_checked" : "read";
            d.getReference().update("read_at", Times.now(), "delivery_status", status).get();
        }
        return Map.of("ok", true);
    }

    public record FollowUp(String status) {}

    /** 보호자의 안전 확인 결과. 읽음과 별개. */
    @PatchMapping("/guardian/alerts/{id}/follow-up")
    public Map<String, Object> followUp(HttpServletRequest req, @PathVariable String id, @RequestBody FollowUp b) throws Exception {
        if (!"verified".equals(b.status()) && !"unable_to_contact".equals(b.status())) throw ApiException.badRequest("invalid_status", "선택을 확인해 주세요.");
        DocumentSnapshot d = owned(CurrentUser.of(req).uid(), id);
        d.getReference().update("safety_follow_up_status", b.status(), "delivery_status", "safety_checked",
                "follow_up_at", Times.now()).get();
        return Map.of("ok", true);
    }

    private DocumentSnapshot owned(String gid, String id) throws Exception {
        DocumentSnapshot d = db.collection("alerts").document(id).get().get();
        if (!d.exists()) throw ApiException.notFound();
        if (!gid.equals(d.getString("guardian_id"))) throw ApiException.forbidden("permission_denied");
        return d;
    }

    private List<Map<String, Object>> alerts(String seniorId, String gid, int limit) throws Exception {
        List<Map<String, Object>> out = new ArrayList<>();
        for (QueryDocumentSnapshot a : db.collection("alerts").whereEqualTo("senior_id", seniorId).whereEqualTo("guardian_id", gid)
                .orderBy("created_at", Query.Direction.DESCENDING).limit(limit).get().get().getDocuments()) {
            out.add(alertView(a.getId(), a.getData()));
        }
        return out;
    }

    /** 명세 alert_detail_fields 7종 + 전달·안전 확인 상태. */
    static Map<String, Object> alertView(String id, Map<String, Object> a) {
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("alert_id", id);
        out.put("type", Docs.str(a, "type"));
        out.put("risk_level", Docs.str(a, "risk_level"));
        out.put("risk_domains", Docs.strings(a, "risk_domains"));
        out.put("first_detected_at", iso(a.get("first_detected_at")));
        out.put("last_detected_at", iso(a.get("last_detected_at") != null ? a.get("last_detected_at") : a.get("created_at")));
        out.put("trend", nvl(Docs.str(a, "trend"), "insufficient_data"));
        out.put("frequency", Map.of("distinct_days_7d", Docs.lng(a, "distinct_days_7d", 0), "independent_sessions_7d", Docs.lng(a, "independent_sessions_7d", 0)));
        out.put("recommended_action", Docs.str(a, "recommended_action"));
        out.put("delivery_status", Docs.str(a, "delivery_status"));
        out.put("safety_follow_up_status", Docs.str(a, "safety_follow_up_status"));
        return out;
    }

    /** 오늘(어르신 시간대) 일정: done/done_late → done, pending/missed → not_done, 기록 없음 → unknown. 확인 불필요 일정은 unknown. */
    private List<Map<String, Object>> today(String seniorId, ZoneId zone) throws Exception {
        Instant start = Instant.now().atZone(zone).toLocalDate().atStartOfDay(zone).toInstant();
        Instant end = start.plus(Duration.ofDays(1)).minusSeconds(1);
        List<Map<String, Object>> out = new ArrayList<>();
        for (QueryDocumentSnapshot s : db.collection("schedules").whereEqualTo("senior_id", seniorId).whereEqualTo("active", true).get().get().getDocuments()) {
            for (Instant due : RRule.occurrences(s.getString("rrule"), s.getString("time_local"), zone, start, end)) {
                String status = "unknown";
                if (Boolean.TRUE.equals(s.getBoolean("needs_ack"))) {
                    DocumentSnapshot log = db.collection("schedule_logs").document(s.getId() + "_" + due.getEpochSecond()).get().get();
                    if (log.exists()) {
                        String st = log.getString("status");
                        status = "done".equals(st) || "done_late".equals(st) ? "done" : "not_done";
                    } else if (due.isBefore(Instant.now())) {
                        status = "not_done";
                    }
                }
                out.add(Map.of("schedule_id", s.getId(), "title", nvl(s.getString("title"), ""), "due_at", Times.iso(due), "status", status));
            }
        }
        out.sort((x, y) -> x.get("due_at").toString().compareTo(y.get("due_at").toString()));
        return out;
    }

    private static List<Map<String, Object>> trends(Map<String, Object> b) {
        List<Map<String, Object>> out = new ArrayList<>();
        Object v = b.get("confirmed_trends");
        if (v instanceof List<?> list) for (Object o : list) {
            if (o instanceof Map<?, ?> m) out.add(Map.of("signal", String.valueOf(m.get("signal")), "trend", String.valueOf(m.get("trend")),
                    "message", m.get("message") == null ? "" : String.valueOf(m.get("message"))));
        }
        return out;
    }

    private Map<String, Object> latestDevice(String seniorId) throws Exception {
        List<QueryDocumentSnapshot> d = db.collection("devices").whereEqualTo("user_id", seniorId).whereEqualTo("active", true)
                .orderBy("last_seen_at", Query.Direction.DESCENDING).limit(1).get().get().getDocuments();
        return d.isEmpty() ? Map.of() : d.get(0).getData();
    }

    private static Object iso(Object v) { return v instanceof com.google.cloud.Timestamp t ? Times.iso(t) : null; }
    private static String nvl(String s, String def) { return s == null ? def : s; }
    private static double round(double v) { return Math.round(v * 100) / 100.0; }
}
