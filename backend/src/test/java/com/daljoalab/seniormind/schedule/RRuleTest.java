package com.daljoalab.seniormind.schedule;

import static org.junit.jupiter.api.Assertions.*;

import java.time.Instant;
import java.time.ZoneId;
import org.junit.jupiter.api.Test;

class RRuleTest {
    final ZoneId seoul = ZoneId.of("Asia/Seoul");

    @Test
    void supportsOnlyCommonSubset() {
        assertTrue(RRule.valid("FREQ=DAILY"));
        assertTrue(RRule.valid("FREQ=WEEKLY;BYDAY=MO,WE"));
        assertFalse(RRule.valid("FREQ=MONTHLY"));
        assertFalse(RRule.valid("FREQ=WEEKLY"));
        assertFalse(RRule.valid("FREQ=DAILY;INTERVAL=2"));
        assertFalse(RRule.valid("FREQ=WEEKLY;BYDAY=XX"));
    }

    @Test
    void occurrencesUseSeniorTimezoneAndWholeMinutes() {
        // 2026-11-02(월) ~ 11-08(일) 서울 08:00, 월·수
        var list = RRule.occurrences("FREQ=WEEKLY;BYDAY=MO,WE", "08:00", seoul,
                Instant.parse("2026-11-01T15:00:00Z"), Instant.parse("2026-11-08T14:59:59Z"));
        assertEquals(2, list.size());
        assertEquals(Instant.parse("2026-11-01T23:00:00Z"), list.get(0));   // 월 08:00 KST
        assertEquals(0, list.get(1).getEpochSecond() % 60);
        assertEquals(7, RRule.occurrences("FREQ=DAILY", "21:30", seoul,
                Instant.parse("2026-11-01T15:00:00Z"), Instant.parse("2026-11-08T14:59:59Z")).size());
    }
}
