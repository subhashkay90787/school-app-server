package com.school.app.core.web;

import com.school.app.core.access.AccessDeniedProblem;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

import java.util.NoSuchElementException;

@RestControllerAdvice
public class ProblemAdvice {

    @ExceptionHandler(AccessDeniedProblem.class)
    public ProblemDetail denied(AccessDeniedProblem ex) {
        ProblemDetail p = ProblemDetail.forStatusAndDetail(HttpStatus.FORBIDDEN, ex.getMessage());
        p.setProperty("code", ex.code());
        return p;
    }

    @ExceptionHandler(NoSuchElementException.class)
    public ProblemDetail notFound(NoSuchElementException ex) {
        return ProblemDetail.forStatusAndDetail(HttpStatus.NOT_FOUND, ex.getMessage());
    }

    @ExceptionHandler(IllegalArgumentException.class)
    public ProblemDetail badRequest(IllegalArgumentException ex) {
        return ProblemDetail.forStatusAndDetail(HttpStatus.BAD_REQUEST, ex.getMessage());
    }

    @ExceptionHandler(IllegalStateException.class)
    public ProblemDetail conflict(IllegalStateException ex) {
        return ProblemDetail.forStatusAndDetail(HttpStatus.CONFLICT, ex.getMessage());
    }

    /** Database rules (ledger edits, four-eyes, cross-branch keys, custody release ...) surface as 409. */
    @ExceptionHandler(DataIntegrityViolationException.class)
    public ProblemDetail integrity(DataIntegrityViolationException ex) {
        String msg = ex.getMostSpecificCause().getMessage();
        msg = msg == null ? "Conflicts with existing data" : msg.lines().findFirst().orElse(msg).replaceFirst("^ERROR:\\s*", "");
        return ProblemDetail.forStatusAndDetail(HttpStatus.CONFLICT, msg);
    }
}
