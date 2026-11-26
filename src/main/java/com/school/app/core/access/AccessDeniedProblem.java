package com.school.app.core.access;

/** 403 with a stable machine code: WRONG_ROLE, FEATURE_OFF, MISSING_PERMISSION, CONSENT_REQUIRED, DUES_HOLD. */
public class AccessDeniedProblem extends RuntimeException {

    private final String code;

    public AccessDeniedProblem(String code, String message) {
        super(message);
        this.code = code;
    }

    public String code() {
        return code;
    }
}
