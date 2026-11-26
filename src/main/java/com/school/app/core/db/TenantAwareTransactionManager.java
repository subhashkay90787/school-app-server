package com.school.app.core.db;

import com.school.app.core.tenant.RequestContext;
import com.school.app.core.tenant.TenantContext;
import jakarta.persistence.EntityManager;
import jakarta.persistence.EntityManagerFactory;
import org.springframework.orm.jpa.EntityManagerHolder;
import org.springframework.orm.jpa.JpaTransactionManager;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.support.TransactionSynchronizationManager;

/**
 * Starts every transaction with the row-level-security settings of the current request:
 * <pre>
 *   app.school_ids  = X-School-Id (already checked against the token's school_access)
 *   app.org_ids     = organization id, for org-wide members (org reports)
 *   app.user_id     = token user_id (audit, history triggers)
 *   app.request_id  = X-Request-Id
 *   app.via         = APP
 * </pre>
 * All are transaction-local (set_config(..., true)). Without a request context nothing is set, so tenant
 * tables return no rows; background jobs run inside {@link SystemContext#run}, which sets app.rls_bypass.
 */
public class TenantAwareTransactionManager extends JpaTransactionManager {

    public TenantAwareTransactionManager(EntityManagerFactory emf) {
        super(emf);
    }

    @Override
    protected void doBegin(Object transaction, TransactionDefinition definition) {
        super.doBegin(transaction, definition);
        EntityManagerHolder holder = (EntityManagerHolder) TransactionSynchronizationManager.getResource(obtainEntityManagerFactory());
        if (holder == null) {
            return;
        }
        EntityManager em = holder.getEntityManager();
        RequestContext ctx = TenantContext.current().orElse(null);
        boolean system = SystemContext.isActive();
        em.createNativeQuery("SELECT set_config('app.school_ids', :schools, true), set_config('app.org_ids', :orgs, true), "
                        + "set_config('app.user_id', :user, true), set_config('app.request_id', :req, true), "
                        + "set_config('app.via', :via, true), set_config('app.rls_bypass', :bypass, true)")
                .setParameter("schools", ctx == null ? "" : ctx.schoolIdsSetting())
                .setParameter("orgs", ctx == null ? "" : ctx.orgIdsSetting())
                .setParameter("user", ctx == null ? "" : Long.toString(ctx.userId()))
                .setParameter("req", ctx == null ? "" : ctx.requestId())
                .setParameter("via", system ? "SYSTEM" : "APP")
                .setParameter("bypass", system ? "on" : "")
                .getResultList();
    }
}
