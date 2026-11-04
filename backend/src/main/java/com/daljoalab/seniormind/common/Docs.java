package com.daljoalab.seniormind.common;

import java.util.Collection;
import java.util.List;
import java.util.Map;

/** Firestore 문서 값 꺼내기 도우미. */
public final class Docs {
    private Docs() {}

    public static String str(Map<String, Object> m, String k) { Object v = m == null ? null : m.get(k); return v == null ? null : v.toString(); }
    public static boolean bool(Map<String, Object> m, String k) { return m != null && Boolean.TRUE.equals(m.get(k)); }
    public static double num(Map<String, Object> m, String k, double def) {
        Object v = m == null ? null : m.get(k); return v instanceof Number n ? n.doubleValue() : def;
    }
    public static long lng(Map<String, Object> m, String k, long def) {
        Object v = m == null ? null : m.get(k); return v instanceof Number n ? n.longValue() : def;
    }
    @SuppressWarnings("unchecked")
    public static Map<String, Object> map(Map<String, Object> m, String k) {
        Object v = m == null ? null : m.get(k); return v instanceof Map<?, ?> x ? (Map<String, Object>) x : Map.of();
    }
    @SuppressWarnings("unchecked")
    public static List<String> strings(Map<String, Object> m, String k) {
        Object v = m == null ? null : m.get(k);
        if (v instanceof Collection<?> c) return c.stream().map(String::valueOf).toList();
        return List.of();
    }
}
