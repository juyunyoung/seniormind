package com.daljoalab.seniormind.guardian;

import com.daljoalab.seniormind.common.ApiException;
import com.daljoalab.seniormind.common.Docs;
import com.google.cloud.firestore.Firestore;
import com.google.cloud.firestore.QueryDocumentSnapshot;
import java.util.List;
import java.util.Map;
import org.springframework.stereotype.Component;

/** 보호자 ↔ 어르신 연결 확인. 연결이 없으면 403 not_linked, 권한이 없으면 403 permission_denied(백엔드 6.7). */
@Component
public class GuardianAccess {
    private final Firestore db;

    public GuardianAccess(Firestore db) { this.db = db; }

    public Map<String, Object> link(String guardianId, String seniorId) {
        try {
            List<QueryDocumentSnapshot> docs = db.collection("guardians").whereEqualTo("guardian_id", guardianId)
                    .whereEqualTo("senior_id", seniorId).whereEqualTo("status", "active").limit(1).get().get().getDocuments();
            if (docs.isEmpty()) throw ApiException.forbidden("not_linked");
            return docs.get(0).getData();
        } catch (ApiException e) { throw e; } catch (Exception e) { throw ApiException.upstream(); }
    }

    public void require(String guardianId, String seniorId, String permission) {
        if (!Docs.bool(Docs.map(link(guardianId, seniorId), "permissions"), permission)) throw ApiException.forbidden("permission_denied");
    }

    /** 어르신 본인이거나, 해당 권한이 있는 연결 보호자. */
    public void selfOrGuardian(String uid, String seniorId, String permission) {
        if (uid.equals(seniorId)) return;
        require(uid, seniorId, permission);
    }
}
