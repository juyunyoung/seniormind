package com.daljoalab.seniormind.session;

import static org.junit.jupiter.api.Assertions.*;

import org.junit.jupiter.api.Test;

class VersionTest {
    @Test
    void compares() {
        assertTrue(SessionService.compareVersion("0.1.0", "0.1") == 0);
        assertTrue(SessionService.compareVersion("0.0.9", "0.1.0") < 0);
        assertTrue(SessionService.compareVersion("0.10", "0.9") > 0);
    }
}
