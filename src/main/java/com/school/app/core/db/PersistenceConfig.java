package com.school.app.core.db;

import jakarta.persistence.EntityManagerFactory;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.transaction.PlatformTransactionManager;

@Configuration
public class PersistenceConfig {

    /** Replaces Boot's JpaTransactionManager so every transaction carries the tenant settings. */
    @Bean
    PlatformTransactionManager transactionManager(EntityManagerFactory emf) {
        return new TenantAwareTransactionManager(emf);
    }
}
