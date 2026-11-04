package com.daljoalab.seniormind.config;

import com.google.auth.oauth2.GoogleCredentials;
import com.google.cloud.firestore.Firestore;
import com.google.firebase.FirebaseApp;
import com.google.firebase.FirebaseOptions;
import com.google.firebase.auth.FirebaseAuth;
import com.google.firebase.cloud.FirestoreClient;
import com.google.firebase.messaging.FirebaseMessaging;
import java.io.IOException;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/** Firebase Admin SDK. Cloud Run에서는 서비스 계정 기본 자격 증명을 쓴다(키 파일 없음). */
@Configuration
@ConditionalOnProperty(prefix = "seniormind", name = "firebase-enabled", havingValue = "true", matchIfMissing = true)
public class FirebaseConfig {

    @Bean
    public FirebaseApp firebaseApp(AppProperties props) throws IOException {
        if (!FirebaseApp.getApps().isEmpty()) return FirebaseApp.getInstance();
        FirebaseOptions options = FirebaseOptions.builder()
                .setCredentials(GoogleCredentials.getApplicationDefault())
                .setProjectId(props.projectId())
                .build();
        return FirebaseApp.initializeApp(options);
    }

    @Bean
    public Firestore firestore(FirebaseApp app) { return FirestoreClient.getFirestore(app); }

    @Bean
    public FirebaseAuth firebaseAuth(FirebaseApp app) { return FirebaseAuth.getInstance(app); }

    @Bean
    public FirebaseMessaging firebaseMessaging(FirebaseApp app) { return FirebaseMessaging.getInstance(app); }
}
