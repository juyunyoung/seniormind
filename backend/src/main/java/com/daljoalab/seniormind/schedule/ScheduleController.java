package com.daljoalab.seniormind.schedule;

import com.daljoalab.seniormind.common.ApiException;
import com.daljoalab.seniormind.common.Docs;
import com.daljoalab.seniormind.common.Times;
import com.daljoalab.seniormind.guardian.GuardianAccess;
import com.daljoalab.seniormind.push.PushService;
import com.daljoalab.seniormind.runtimeconfig.RuntimeConfigService;
import com.daljoalab.seniormind.security.CurrentUser;
import com.daljoalab.seniormind.user.ConsentService;
import com.daljoalab.seniormind.user.UserService;
import com.google.cloud.firestore.DocumentReference;
import com.google.cloud.firestore.DocumentSnapshot;
import com.google.cloud.firestore.Firestore;
import com.google.cloud.firestore.QueryDocumentSnapshot;
import jakarta.servlet.http.HttpServletRequest;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/** 백엔드 2.7 일정 + 6.4 반복 규칙 + 6.5 늦은·중복 ack. P2는 투약(medication)만. */
@RestController
public class ScheduleController {
    private final Firestore db;
    private final UserService users;
    private final ConsentService consents;
    private final GuardianAccess access;
    private final PushService push;
    private final RuntimeConfigService configs;

    public ScheduleController(Firestore db, UserService users, ConsentService consents, GuardianAccess access, PushService push,
                              RuntimeConfigService configs) {
        this.db = db; this.users = users; this.consents = consents; this.access = access; this.push = push; this.configs = configs;
    }

    @GetMapping("/schedules")
    public List<Map<String, Object>> list(HttpServletRequest req, @RequestParam("senior_id") String seniorId) throws Exception {
        String uid = CurrentUser.of(req).uid();
        access.selfOrGuardian(uid, seniorId, "schedules");
        List<Map<String, Object>> out = new ArrayList<>();
        for (QueryDocumentSnapshot d : db.collection("schedules").whereEqualTo("senior_id", seniorId).whereEqualTo("active", true).get().get().getDocuments()) {
            out.add(view(d.getId(), d.getData()));
        }
        return out;
    }

    public record Body(String seniorId, String type, String title, String message, String rrule, String timeLocal, String timezone,
                       Boolean needsAck, Integer reminderAfterMin, Integer missedAfterMin) {}

    @PostMapping("/schedules")
    public Map<String, Object> create(HttpServletRequest req, @RequestBody Body b) throws Exception {
        return save(CurrentUser.of(req).uid(), null, b);
    }

    @PutMapping("/schedules/{id}")
    public Map<String, Object> update(HttpServletRequest req, @PathVariable String id, @RequestBody Body b) throws Exception {
        return save(CurrentUser.of(req).uid(), id, b);
    }

    @DeleteMapping("/schedules/{id}")
    public Map<String, Object> delete(HttpServletRequest req, @PathVariable String id) throws Exception {
        String uid = CurrentUser.of(req).uid();
        DocumentReference ref = db.collection("schedules").document(id);
        DocumentSnapshot d = ref.get().get();
        if (!d.exists()) throw ApiException.notFound();
        String seniorId = d.getString("senior_id");
        access.require(uid, seniorId, "schedules");
        ref.update("active", false, "updated_at", Times.now()).get();     // 소프트 삭제
        notifySenior(seniorId);
        return Map.of("ok", true);
    }

    private Map<String, Object> save(String uid, String id, Body b) throws Exception {
        users.requireRole(uid, "guardian");
        if (b.seniorId() == null) throw new IllegalArgumentException("senior_id");
        access.require(uid, b.seniorId(), "schedules");
        if (!consents.all(b.seniorId(), "schedule_share") || !consents.all(uid, "guardian_schedule_manage")) throw ApiException.consentRequired();
        if (!"medication".equals(b.type() == null ? "medication" : b.type())) throw ApiException.badRequest("schedule_type_unsupported", "지금은 약 알림만 등록할 수 있어요.");
        if (!RRule.valid(b.rrule())) throw ApiException.badRequest("rrule_unsupported", "반복은 매일 또는 요일 선택만 할 수 있어요.");
        if (RRule.time(b.timeLocal()) == null) throw ApiException.badRequest("invalid_time", "시간을 확인해 주세요.");
        if (b.title() == null || b.title().isBlank()) throw ApiException.badRequest("invalid_title", "이름을 입력해 주세요.");

        var cfg = configs.current();
        Map<String, Object> senior = users.require(b.seniorId());
        Map<String, Object> doc = new HashMap<>();
        doc.put("senior_id", b.seniorId());
        doc.put("type", "medication");
        doc.put("title", b.title().strip());
        doc.put("message", b.message() == null || b.message().isBlank() ? b.title().strip() + " 드실 시간이에요" : b.message().strip());
        doc.put("rrule", b.rrule().trim());
        doc.put("time_local", b.timeLocal());
        doc.put("timezone", Times.zone(Docs.str(senior, "timezone")).getId());   // 항상 어르신 시간대
        doc.put("needs_ack", b.needsAck() == null || b.needsAck());
        doc.put("reminder_after_min", b.reminderAfterMin() == null ? cfg.i("schedule.reminder_after_min_default", 10) : b.reminderAfterMin());
        doc.put("missed_after_min", b.missedAfterMin() == null ? cfg.i("schedule.missed_after_min_default", 60) : b.missedAfterMin());
        doc.put("active", true);
        doc.put("updated_at", Times.now());
        DocumentReference ref;
        if (id == null) {
            ref = db.collection("schedules").document();
            doc.put("created_by", uid);
            doc.put("created_at", Times.now());
            doc.put("schema_version", "1");
            ref.set(doc).get();
        } else {
            ref = db.collection("schedules").document(id);
            DocumentSnapshot old = ref.get().get();
            if (!old.exists() || !b.seniorId().equals(old.getString("senior_id"))) throw ApiException.notFound();
            ref.update(doc).get();
        }
        notifySenior(b.seniorId());
        return view(ref.getId(), ref.get().get().getData());
    }

    public record Ack(String dueAt, String firedAt, String ackedAt, String ackMethod, Boolean syncedFromOffline) {}

    /** 키 (schedule_id, due_at 분 단위) upsert. 이미 done이면 이른 acked_at 유지, missed 뒤면 done_late, 7일 넘으면 무시. */
    @PostMapping("/schedules/{id}/ack")
    public Map<String, Object> ack(HttpServletRequest req, @PathVariable String id, @RequestBody Ack b) throws Exception {
        String uid = CurrentUser.of(req).uid();
        DocumentSnapshot s = db.collection("schedules").document(id).get().get();
        if (!s.exists()) throw ApiException.notFound();
        if (!uid.equals(s.getString("senior_id"))) throw ApiException.forbidden("permission_denied");
        if (!Boolean.TRUE.equals(s.getBoolean("needs_ack"))) return Map.of("ok", true, "ignored", "needs_ack_false");
        Instant due = Times.minute(Instant.parse(b.dueAt()));
        if (due.isBefore(Instant.now().minus(Duration.ofDays(7)))) return Map.of("ok", true, "ignored", "too_old");
        Instant acked = b.ackedAt() == null ? Instant.now() : Instant.parse(b.ackedAt());
        DocumentReference ref = db.collection("schedule_logs").document(id + "_" + due.getEpochSecond());
        db.runTransaction(tx -> {
            DocumentSnapshot log = tx.get(ref).get();
            Map<String, Object> doc = new HashMap<>();
            String status = log.exists() ? log.getString("status") : "pending";
            Instant prev = log.exists() ? Times.instant(log.get("acked_at")) : null;
            doc.put("schedule_id", id);
            doc.put("senior_id", uid);
            doc.put("due_at", Times.ts(due));
            if (b.firedAt() != null) doc.put("fired_at", Times.ts(Instant.parse(b.firedAt())));
            doc.put("acked_at", Times.ts(prev != null && prev.isBefore(acked) ? prev : acked));
            doc.put("ack_method", b.ackMethod() == null ? "button" : b.ackMethod());
            doc.put("status", "missed".equals(status) || "done_late".equals(status) ? "done_late" : "done");
            doc.put("synced_from_offline", Boolean.TRUE.equals(b.syncedFromOffline()));
            doc.put("updated_at", Times.now());
            tx.set(ref, doc, com.google.cloud.firestore.SetOptions.merge());
            return null;
        }).get();
        return Map.of("ok", true);
    }

    private void notifySenior(String seniorId) {
        push.sendToUser(seniorId, PushService.Kind.SCHEDULES_UPDATED, Map.of("type", "schedules_updated", "senior_id", seniorId), null, null);
    }

    static Map<String, Object> view(String id, Map<String, Object> d) {
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("schedule_id", id);
        for (String k : List.of("senior_id", "type", "title", "message", "rrule", "time_local", "timezone")) out.put(k, Docs.str(d, k));
        out.put("needs_ack", Docs.bool(d, "needs_ack"));
        out.put("reminder_after_min", Docs.lng(d, "reminder_after_min", 10));
        out.put("missed_after_min", Docs.lng(d, "missed_after_min", 60));
        out.put("active", Docs.bool(d, "active"));
        Object up = d.get("updated_at");
        out.put("updated_at", up instanceof com.google.cloud.Timestamp t ? Times.iso(t) : null);
        return out;
    }
}
