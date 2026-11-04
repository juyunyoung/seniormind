package com.daljoalab.seniormind.alert;

import static org.junit.jupiter.api.Assertions.*;

import java.time.Duration;
import java.time.Instant;
import java.time.LocalTime;
import org.junit.jupiter.api.Test;

class CooldownPolicyTest {
    final Instant now = Instant.parse("2026-11-04T10:00:00Z");

    @Test
    void r2SuppressedWithinThreeDaysR3NeverSuppressed() {
        Instant twoDaysAgo = now.minus(Duration.ofDays(2));
        assertEquals(CooldownPolicy.Action.UPDATE_SUPPRESSED, CooldownPolicy.decide("R2", twoDaysAgo, false, 3, now));
        assertEquals(CooldownPolicy.Action.NEW_PUSH, CooldownPolicy.decide("R2", now.minus(Duration.ofDays(3)), false, 3, now));
        assertEquals(CooldownPolicy.Action.NEW_PUSH, CooldownPolicy.decide("R3", twoDaysAgo, false, 0, now));
    }

    @Test
    void escalationFromR1IsImmediate() {
        assertEquals(CooldownPolicy.Action.NEW_PUSH, CooldownPolicy.decide("R2", now.minus(Duration.ofHours(1)), true, 3, now));
    }

    @Test
    void quietHoursAcrossMidnight() {
        assertTrue(CooldownPolicy.inQuietHours("22:00", "07:00", LocalTime.of(23, 30)));
        assertTrue(CooldownPolicy.inQuietHours("22:00", "07:00", LocalTime.of(6, 59)));
        assertFalse(CooldownPolicy.inQuietHours("22:00", "07:00", LocalTime.of(7, 0)));
        assertFalse(CooldownPolicy.inQuietHours(null, null, LocalTime.NOON));
    }
}
