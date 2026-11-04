package com.daljoalab.seniormind.push;

import static org.junit.jupiter.api.Assertions.*;

import java.util.Map;
import org.junit.jupiter.api.Test;

class PushMessageTest {
    @Test
    void buildsAllKinds() {
        for (PushService.Kind k : PushService.Kind.values()) {
            assertNotNull(PushService.build("token", k, Map.of("type", "x"), k == PushService.Kind.SCHEDULES_UPDATED ? null : "t", "b"));
        }
    }
}
