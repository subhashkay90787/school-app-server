package com.school.app.core.web;

import org.springframework.context.annotation.Configuration;
import org.springframework.web.servlet.config.annotation.ResourceHandlerRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

/**
 * Raw contract files at /openapi/<actor>.yaml (the source the interfaces are generated from).
 * Swagger UI groups per actor are configured in application.properties (springdoc.group-configs).
 */
@Configuration
public class OpenApiDocsConfig implements WebMvcConfigurer {

    @Override
    public void addResourceHandlers(ResourceHandlerRegistry registry) {
        registry.addResourceHandler("/openapi/**").addResourceLocations("classpath:/openapi/");
    }
}
