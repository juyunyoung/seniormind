package com.daljoalab.seniormind.guardian;

import com.daljoalab.seniormind.common.ApiException;
import com.daljoalab.seniormind.common.Docs;
import com.daljoalab.seniormind.common.Times;
import com.daljoalab.seniormind.config.AppProperties;
import com.daljoalab.seniormind.push.PushService;
import com.daljoalab.seniormind.security.CurrentUser;
import com.daljoalab.seniormind.user.ConsentService;
import com.daljoalab.seniormind.user.UserService;
import com.google.cloud.firestore.DocumentReference;
import com.google.cloud.firestore.DocumentSnapshot;
import com.google.cloud.firestore.Firestore;
import com.google.cloud.firestore.QueryDocumentSnapshot;
import jakarta.servlet.http.HttpServletRequest;
import java.security.SecureRandom;
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
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

/** 백엔드 2.6 QR 연결: 코드 발급(어르신) → 연결(보호자) → 목록·해제(양쪽). */
@RestController
public class PairingController {
    private static final SecureRandom RANDOM = new SecureRandom();
    private final Firestore db;
    private final UserService users;
    private final ConsentService consents;
    private final PushService push;
    private final AppProperties props;

    public PairingController(Firestore db, UserService users, ConsentService consents, PushService push, AppProperties props) {
        this.db = db; this.users = users; this.consents = consents; this.push = push; this.props = props;
    }

    @PostMapping("/pairing/code")
    public Map<String, Object> code(HttpServletRequest req) throws Exception {
        String uid = CurrentUser.of(req).uid();
        users.requireRole(uid, "senior");
        consents.require(uid, "guardian_share", "schedule_share");   // sensitive·guardian_topic_share는 선택
        for (QueryDocumentSnapshot old : db.collection("pairing_codes").whereEqualTo("senior_id", uid).get().get().getDocuments()) {
            old.getReference().delete();
        }
        Instant expires = Instant.now().plus(Duration.ofMinutes(5));
        for (int i = 0; i < 10; i++) {
            String code = String.format("%06d", RANDOM.nextInt(1_000_000));
            DocumentReference ref = db.collection("pairing_codes").document(code);
            try {
                ref.create(Map.of("code", code, "senior_id", uid, "expires_at", Times.ts(expires), "used", false, "created_at", Times.now())).get();
            } catch (Exception taken) { continue; }
            Map<String, Object> out = new LinkedHashMap<>();
            out.put("code", code);
            out.put("expires_at", Times.iso(expires));
            out.put("qr_payload", props.pairingScheme() + "://pair?v=1&code=" + code);
            return out;
        }
        throw ApiException.upstream();
    }

    public record LinkBody(String code, String relation) {}

    @PostMapping("/guardian/link")
    public Map<String, Object> link(HttpServletRequest req, @RequestBody LinkBody b) throws Exception {
        String gid = CurrentUser.of(req).uid();
        users.requireRole(gid, "guardian");
        if (b.code() == null || !b.code().matches("\\d{6}")) throw ApiException.badRequest("pairing_code_invalid", "번호를 다시 확인해 주세요.");
        DocumentReference codeRef = db.collection("pairing_codes").document(b.code());
        DocumentSnapshot code = codeRef.get().get();
        if (!code.exists() || Boolean.TRUE.equals(code.getBoolean("used"))) throw ApiException.badRequest("pairing_code_invalid", "번호를 다시 확인해 주세요.");
        if (Times.instant(code.get("expires_at")).isBefore(Instant.now())) throw ApiException.badRequest("pairing_code_expired", "시간이 지났어요. 어르신 화면에서 다시 만들어 주세요.");
        String seniorId = code.getString("senior_id");
        Map<String, Boolean> mine = consents.latest(gid);
        if (!Boolean.TRUE.equals(mine.get("guardian_terms")) || !Boolean.TRUE.equals(mine.get("guardian_data_view"))) throw ApiException.consentRequired();
        if (!db.collection("guardians").whereEqualTo("guardian_id", gid).whereEqualTo("senior_id", seniorId)
                .whereEqualTo("status", "active").get().get().isEmpty()) {
            throw new ApiException(409, "already_linked", "이미 연결된 어르신이에요.");
        }
        DocumentReference linkRef = db.collection("guardians").document();
        Map<String, Object> doc = new HashMap<>();
        doc.put("senior_id", seniorId);
        doc.put("guardian_id", gid);
        doc.put("relation", b.relation() == null ? "보호자" : b.relation());
        doc.put("permissions", Map.of("board", true, "schedules", true, "alerts", true));
        doc.put("linked_at", Times.now());
        doc.put("linked_by_code", b.code());
        doc.put("status", "active");
        doc.put("schema_version", "1");
        doc.put("created_at", Times.now());
        db.runTransaction(tx -> {
            DocumentSnapshot c = tx.get(codeRef).get();
            if (!c.exists()) throw ApiException.badRequest("pairing_code_invalid", "번호를 다시 확인해 주세요.");
            tx.create(linkRef, doc);
            tx.delete(codeRef);
            return null;
        }).get();
        push.sendToUser(seniorId, PushService.Kind.PAIRING_DONE, Map.of("type", "pairing_done", "link_id", linkRef.getId()),
                "보호자와 연결됐어요", "이제 보호자가 안부를 함께 살펴요.");
        Map<String, Object> out = linkView(linkRef.getId(), doc, users.displayName(seniorId));
        out.put("senior", Map.of("display_name", nvl(users.displayName(seniorId))));
        return out;
    }

    @GetMapping("/guardian/links")
    public List<Map<String, Object>> links(HttpServletRequest req) throws Exception {
        String uid = CurrentUser.of(req).uid();
        boolean senior = "senior".equals(users.role(uid));
        List<Map<String, Object>> out = new ArrayList<>();
        for (QueryDocumentSnapshot d : db.collection("guardians").whereEqualTo(senior ? "senior_id" : "guardian_id", uid)
                .whereEqualTo("status", "active").get().get().getDocuments()) {
            String other = senior ? d.getString("guardian_id") : d.getString("senior_id");
            out.add(linkView(d.getId(), d.getData(), users.displayName(other)));
        }
        return out;
    }

    @DeleteMapping("/guardian/link/{id}")
    public Map<String, Object> unlink(HttpServletRequest req, @PathVariable String id) throws Exception {
        String uid = CurrentUser.of(req).uid();
        DocumentReference ref = db.collection("guardians").document(id);
        DocumentSnapshot d = ref.get().get();
        if (!d.exists()) throw ApiException.notFound();
        boolean isSenior = uid.equals(d.getString("senior_id"));
        if (!isSenior && !uid.equals(d.getString("guardian_id"))) throw ApiException.forbidden("permission_denied");
        ref.update("status", "revoked", "revoked_at", Times.now(), "revoked_by", isSenior ? "senior" : "guardian").get();
        return Map.of("ok", true);
    }

    static Map<String, Object> linkView(String id, Map<String, Object> d, String displayName) {
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("link_id", id);
        out.put("senior_id", Docs.str(d, "senior_id"));
        out.put("guardian_id", Docs.str(d, "guardian_id"));
        out.put("display_name", displayName);
        out.put("relation", Docs.str(d, "relation"));
        Object at = d.get("linked_at");
        out.put("linked_at", at instanceof com.google.cloud.Timestamp t ? Times.iso(t) : Times.iso(Instant.now()));
        out.put("permissions", Docs.map(d, "permissions"));
        return out;
    }

    private static String nvl(String s) { return s == null ? "어르신" : s; }
}
