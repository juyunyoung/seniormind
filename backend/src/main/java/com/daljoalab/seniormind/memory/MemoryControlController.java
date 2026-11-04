package com.daljoalab.seniormind.memory;

import com.daljoalab.seniormind.common.ApiException;
import com.daljoalab.seniormind.common.Docs;
import com.daljoalab.seniormind.common.Times;
import com.daljoalab.seniormind.security.CurrentUser;
import com.daljoalab.seniormind.session.SessionService;
import com.google.cloud.firestore.DocumentReference;
import com.google.cloud.firestore.DocumentSnapshot;
import com.google.cloud.firestore.FieldValue;
import com.google.cloud.firestore.Firestore;
import com.google.cloud.firestore.SetOptions;
import jakarta.servlet.http.HttpServletRequest;
import java.util.List;
import java.util.Map;
import java.util.Set;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

/**
 * POST /memories/control (백엔드 1.4). P1은 scope=last_utterance만 실행한다.
 * 기억 카드 추출은 P2라 아직 카드가 없다: DELETE는 발화 판단·자막을 지우고, DO_NOT_REMEMBER는 추출 제외 목록에 넣는다.
 */
@RestController
public class MemoryControlController {
    private static final Set<String> SCOPES = Set.of("last_utterance", "specific_memory", "specific_topic", "date_range", "all_memories");
    private final Firestore db;

    public MemoryControlController(Firestore db) { this.db = db; }

    public record Body(String assessmentId, Boolean confirmed, String scope, List<String> targetCardIds) {}

    @PostMapping("/memories/control")
    public Map<String, Object> control(HttpServletRequest req, @RequestBody Body b) throws Exception {
        String uid = CurrentUser.of(req).uid();
        if (b.assessmentId() == null) throw new IllegalArgumentException("assessment_id");
        String scope = b.scope() == null ? "last_utterance" : b.scope();
        if (!SCOPES.contains(scope)) throw ApiException.badRequest("invalid_scope", "지울 범위를 확인해 주세요.");
        DocumentReference ref = db.collection("assessments").document(b.assessmentId());
        DocumentSnapshot a = ref.get().get();
        if (!a.exists()) throw ApiException.notFound();
        if (!uid.equals(a.getString("user_id"))) throw ApiException.forbidden("permission_denied");
        String intent = a.getString("memory_control_intent");

        if (!Boolean.TRUE.equals(b.confirmed())) {
            ref.update("memory_control_status", "cancelled", "memory_control_scope", scope, "updated_at", Times.now()).get();
            return Map.of("status", "cancelled");
        }
        if (!"last_utterance".equals(scope)) throw ApiException.badRequest("scope_unsupported", "지금은 방금 하신 말씀만 지울 수 있어요.");

        String sessionId = a.getString("session_id");
        switch (intent == null ? "NONE" : intent) {
            case "DELETE" -> {
                Long start = a.getLong("utterance_start_ms");
                if (start != null) db.collection("transcripts").document(SessionService.safeId(sessionId)).collection("parts").document("input_" + start).delete().get();
                ref.update("deleted", true, "deleted_at", Times.now()).get();
                db.collection("users").document(uid).set(Map.of("baseline_recompute_needed", true), SetOptions.merge()).get();
                db.collection("card_tombstones").document("as_" + b.assessmentId()).set(Map.of("user_id", uid, "deleted_at", Times.now(),
                        "scope", scope, "cascade", Map.of("assessments", 1, "mentions", 0, "baselines_recomputed", false,
                                "topic_stats_recomputed", false))).get();
            }
            case "DO_NOT_REMEMBER" -> db.collection("sessions").document(SessionService.safeId(sessionId))
                    .update("exclude_utterance_ids", FieldValue.arrayUnion(a.getString("utterance_id"))).get();
            default -> { }   // DO_NOT_SHARE·CORRECT: 카드가 생기는 P2부터 실행. 지금은 의도와 확인만 기록
        }
        ref.update("memory_control_status", "executed", "memory_control_scope", scope, "updated_at", Times.now()).get();
        return Map.of("status", "executed", "intent", Docs.str(a.getData(), "memory_control_intent"));
    }
}
