package com.daljoalab.seniormind.security;

import java.util.ArrayDeque;
import java.util.Deque;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/** 사용자별 분당 요청 수 제한(인스턴스 단위, 남용 비용 방지용). */
public class RateLimiter {
    private final int perMinute;
    private final Map<String, Deque<Long>> hits = new ConcurrentHashMap<>();

    public RateLimiter(int perMinute) { this.perMinute = perMinute; }

    public boolean allow(String key, long nowMs) {
        Deque<Long> q = hits.computeIfAbsent(key, k -> new ArrayDeque<>());
        synchronized (q) {
            while (!q.isEmpty() && nowMs - q.peekFirst() > 60_000) q.pollFirst();
            if (q.size() >= perMinute) return false;
            q.addLast(nowMs);
            return true;
        }
    }
}
