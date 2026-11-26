package com.school.app.core.web;

import jakarta.servlet.http.HttpServletResponse;
import org.springframework.http.HttpStatus;

import java.io.IOException;

/** Problem responses written from filters (before Spring MVC). Shape matches the spec's Problem schema. */
public final class Problems {

    private Problems() {}

    public static void write(HttpServletResponse response, HttpStatus status, String code, String detail) throws IOException {
        response.setStatus(status.value());
        response.setContentType("application/problem+json");
        response.getWriter().write("{\"type\":\"about:blank\",\"title\":\"" + status.getReasonPhrase()
                + "\",\"status\":" + status.value() + ",\"code\":\"" + code + "\",\"detail\":\"" + escape(detail) + "\"}");
    }

    private static String escape(String s) {
        return s.replace("\\", "\\\\").replace("\"", "\\\"");
    }
}
