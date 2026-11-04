package com.daljoalab.seniormind.push;

import com.daljoalab.seniormind.common.Times;
import com.google.cloud.firestore.Firestore;
import com.google.cloud.firestore.QueryDocumentSnapshot;
import com.google.firebase.messaging.AndroidConfig;
import com.google.firebase.messaging.AndroidNotification;
import com.google.firebase.messaging.ApnsConfig;
import com.google.firebase.messaging.Aps;
import com.google.firebase.messaging.FirebaseMessaging;
import com.google.firebase.messaging.FirebaseMessagingException;
import com.google.firebase.messaging.Message;
import com.google.firebase.messaging.MessagingErrorCode;
import com.google.firebase.messaging.Notification;
import java.util.Map;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.stereotype.Service;

/**
 * FCM HTTP v1 발송(백엔드 6.2). 수신자의 활성 기기마다 플랫폼 블록을 붙여 보낸다.
 * 본문은 최소 정보만(잠금 화면 노출 최소화). 원문·점수 금지.
 */
@Service
public class PushService {
    private static final Logger log = LoggerFactory.getLogger(PushService.class);

    public enum Kind { RISK_R3, RISK_R2, SCHEDULE_MISSED, PAIRING_DONE, SCHEDULES_UPDATED }

    private final Firestore db;
    private final ObjectProvider<FirebaseMessaging> fcm;

    public PushService(Firestore db, ObjectProvider<FirebaseMessaging> fcm) { this.db = db; this.fcm = fcm; }

    public int sendToUser(String uid, Kind kind, Map<String, String> data, String title, String body) {
        FirebaseMessaging m = fcm.getIfAvailable();
        if (m == null) return 0;
        int sent = 0;
        try {
            for (QueryDocumentSnapshot d : db.collection("devices").whereEqualTo("user_id", uid).whereEqualTo("active", true).get().get().getDocuments()) {
                String token = d.getString("fcm_token");
                if (token == null || token.isBlank()) continue;
                try {
                    m.send(build(token, kind, data, title, body));
                    sent++;
                } catch (FirebaseMessagingException e) {
                    MessagingErrorCode code = e.getMessagingErrorCode();
                    if (code == MessagingErrorCode.UNREGISTERED || code == MessagingErrorCode.INVALID_ARGUMENT) {
                        d.getReference().update("active", false, "updated_at", Times.now());
                    }
                    log.warn("fcm failed kind={} code={}", kind, code);
                }
            }
        } catch (Exception e) {
            log.warn("fcm lookup failed kind={}", kind);
        }
        return sent;
    }

    static Message build(String token, Kind kind, Map<String, String> data, String title, String body) {
        Message.Builder b = Message.builder().setToken(token).putAllData(data);
        boolean silent = kind == Kind.SCHEDULES_UPDATED;
        if (!silent && title != null) b.setNotification(Notification.builder().setTitle(title).setBody(body).build());

        AndroidConfig.Builder android = AndroidConfig.builder()
                .setPriority(kind == Kind.SCHEDULES_UPDATED ? AndroidConfig.Priority.NORMAL : AndroidConfig.Priority.HIGH);
        String channel = switch (kind) { case RISK_R3 -> "risk_r3"; case RISK_R2 -> "risk"; case SCHEDULE_MISSED -> "schedule"; default -> null; };
        if (channel != null) android.setNotification(AndroidNotification.builder().setChannelId(channel).build());
        b.setAndroidConfig(android.build());

        Aps.Builder aps = Aps.builder();
        ApnsConfig.Builder apns = ApnsConfig.builder();
        switch (kind) {
            case RISK_R3 -> { aps.setSound("default").putCustomData("interruption-level", "time-sensitive"); apns.putHeader("apns-priority", "10"); }
            case RISK_R2, SCHEDULE_MISSED -> { aps.setSound("default").putCustomData("interruption-level", "active"); apns.putHeader("apns-priority", "10"); }
            case PAIRING_DONE -> { aps.setContentAvailable(true); apns.putHeader("apns-priority", "5"); }
            case SCHEDULES_UPDATED -> { aps.setContentAvailable(true); apns.putHeader("apns-push-type", "background").putHeader("apns-priority", "5"); }
        }
        b.setApnsConfig(apns.setAps(aps.build()).build());
        return b.build();
    }
}
