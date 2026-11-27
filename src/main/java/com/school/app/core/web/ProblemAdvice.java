package com.school.app.core.web;

import com.school.app.core.access.AccessDeniedProblem;
import org.springframework.dao.DataAccessException;
import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

import jakarta.validation.ConstraintViolationException;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.validation.FieldError;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.method.annotation.HandlerMethodValidationException;
import org.springframework.web.method.annotation.MethodArgumentTypeMismatchException;

import java.util.List;
import java.util.Map;
import java.util.NoSuchElementException;

@RestControllerAdvice
public class ProblemAdvice {

    @ExceptionHandler(AccessDeniedProblem.class)
    public ProblemDetail denied(AccessDeniedProblem ex) {
        ProblemDetail p = ProblemDetail.forStatusAndDetail(HttpStatus.FORBIDDEN, ex.getMessage());
        p.setProperty("code", ex.code());
        return p;
    }

    /** Request body / parameter validation: 400 with one entry per field ({field, message}). */
    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ProblemDetail invalidBody(MethodArgumentNotValidException ex) {
        return invalid(ex.getBindingResult().getFieldErrors().stream()
                .map(e -> Map.of("field", e.getField(), "message", String.valueOf(e.getDefaultMessage()))).toList());
    }

    @ExceptionHandler(HandlerMethodValidationException.class)
    public ProblemDetail invalidParameters(HandlerMethodValidationException ex) {
        return invalid(ex.getParameterValidationResults().stream()
                .flatMap(r -> r.getResolvableErrors().stream().map(e -> Map.of(
                        "field", e instanceof FieldError fe ? fe.getField() : String.valueOf(r.getMethodParameter().getParameterName()),
                        "message", String.valueOf(e.getDefaultMessage()))))
                .toList());
    }

    @ExceptionHandler(ConstraintViolationException.class)
    public ProblemDetail invalidConstraints(ConstraintViolationException ex) {
        return invalid(ex.getConstraintViolations().stream()
                .map(v -> Map.of("field", String.valueOf(v.getPropertyPath()), "message", v.getMessage())).toList());
    }

    @ExceptionHandler({HttpMessageNotReadableException.class, MethodArgumentTypeMismatchException.class})
    public ProblemDetail unreadable(Exception ex) {
        ProblemDetail p = ProblemDetail.forStatusAndDetail(HttpStatus.BAD_REQUEST,
                ex instanceof MethodArgumentTypeMismatchException m ? "Invalid value for " + m.getName() : "Request body is not valid JSON for this operation");
        p.setProperty("code", "INVALID");
        return p;
    }

    private static ProblemDetail invalid(List<Map<String, String>> errors) {
        ProblemDetail p = ProblemDetail.forStatusAndDetail(HttpStatus.BAD_REQUEST, "Validation failed");
        p.setProperty("code", "VALIDATION");
        p.setProperty("errors", errors);
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

    /**
     * Database errors by SQLSTATE: bad input (missing required, invalid value, unknown reference) -> 400,
     * duplicates -> 409, row-level security -> 403, rules raised by triggers (ledgers, four-eyes ...) -> 409.
     */
    @ExceptionHandler(DataAccessException.class)
    public ProblemDetail database(DataAccessException ex) {
        Throwable root = ex.getMostSpecificCause();
        String state = root instanceof java.sql.SQLException sql ? sql.getSQLState() : null;
        String msg = root.getMessage() == null ? "Database error" : root.getMessage().lines().findFirst().orElse("")
                .replaceFirst("^ERROR:\\s*", "");
        HttpStatus status;
        String code;
        if (state == null) {
            status = HttpStatus.INTERNAL_SERVER_ERROR;
            code = "DB_ERROR";
        } else if (state.equals("23505")) {
            status = HttpStatus.CONFLICT;
            code = "DUPLICATE";
        } else if (state.equals("42501")) {
            status = HttpStatus.FORBIDDEN;
            code = "OUT_OF_SCOPE";
        } else if (state.equals("23503") && msg.startsWith("update or delete on table")) {
            status = HttpStatus.CONFLICT;
            code = "IN_USE";
            msg = "Still in use by other records; it can't be removed";
        } else if (state.startsWith("23") || state.startsWith("22")) {
            status = HttpStatus.BAD_REQUEST;
            code = state.equals("23503") ? "UNKNOWN_REFERENCE" : state.equals("23502") ? "REQUIRED" : "INVALID";
        } else if (state.equals("P0001")) {
            status = HttpStatus.CONFLICT;
            code = "RULE";
        } else {
            status = HttpStatus.INTERNAL_SERVER_ERROR;
            code = "DB_ERROR";
        }
        ProblemDetail p = ProblemDetail.forStatusAndDetail(status, msg);
        p.setProperty("code", code);
        return p;
    }
}
