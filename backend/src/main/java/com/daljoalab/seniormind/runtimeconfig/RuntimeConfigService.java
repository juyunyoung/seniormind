package com.daljoalab.seniormind.runtimeconfig;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.google.cloud.firestore.Firestore;
import com.google.cloud.firestore.QueryDocumentSnapshot;
import java.io.InputStream;
import java.util.List;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.stereotype.Service;

/** 활성 설정(config_versions active=true)을 60초 캐시. 없거나 실패하면 내장 기본값(db/seed와 같은 파일). */
@Service
public class RuntimeConfigService {
    private static final Logger log = LoggerFactory.getLogger(RuntimeConfigService.class);
    private final ObjectProvider<Firestore> db;
    private final ObjectMapper json = new ObjectMapper();
    private final RuntimeConfig builtIn;
    private volatile RuntimeConfig cached;
    private volatile long loadedAt;

    public RuntimeConfigService(ObjectProvider<Firestore> db) throws Exception {
        this.db = db;
        try (InputStream in = getClass().getResourceAsStream("/config/default-config.json")) {
            JsonNode doc = json.readTree(in);
            JsonNode cfg = doc.path("config");
            this.builtIn = new RuntimeConfig(cfg.path("config_version").asText("builtin"), cfg, null);
        }
    }

    public RuntimeConfig current() {
        long now = System.currentTimeMillis();
        RuntimeConfig c = cached;
        if (c != null && now - loadedAt < 60_000) return c;
        Firestore fs = db.getIfAvailable();
        if (fs != null) {
            try {
                List<QueryDocumentSnapshot> docs = fs.collection("config_versions").whereEqualTo("active", true).limit(1).get().get().getDocuments();
                if (!docs.isEmpty()) {
                    QueryDocumentSnapshot d = docs.get(0);
                    JsonNode cfg = json.valueToTree(d.get("config"));
                    cached = new RuntimeConfig(cfg.path("config_version").asText(d.getId()), cfg, d.getString("signature"));
                    loadedAt = now;
                    return cached;
                }
            } catch (Exception e) {
                log.warn("config load failed: {}", e.getClass().getSimpleName());
            }
        }
        cached = builtIn;
        loadedAt = now;
        return builtIn;
    }

    public RuntimeConfig builtIn() { return builtIn; }
}
