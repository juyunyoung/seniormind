package com.daljoalab.seniormind.runtimeconfig;

import java.util.LinkedHashMap;
import java.util.Map;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

/** GET /config/latest (백엔드 1.6). P1은 서명 없이 제공(앱은 내장 기본값 우선). */
@RestController
public class ConfigController {
    private final RuntimeConfigService configs;

    public ConfigController(RuntimeConfigService configs) { this.configs = configs; }

    @GetMapping("/config/latest")
    public Map<String, Object> latest() {
        RuntimeConfig c = configs.current();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("config_version", c.version());
        out.put("config", c.root());
        out.put("signature", c.signature());
        return out;
    }

    @GetMapping("/healthz")
    public Map<String, String> health() { return Map.of("status", "ok"); }
}
