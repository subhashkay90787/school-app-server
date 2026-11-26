/**
 * Domain services, one package per area (com.school.app.domain.academics, .presence, .fees, .comms, .hostel,
 * .custody, .gate, .inventory, .expenses, .people, .library, .admissions, .health, .transport, .reports).
 * Role modules (com.school.app.role.*) call these; domains never call role modules, and role modules never call
 * each other. A custom role reuses its base role's module, so no code is needed per custom role.
 */
package com.school.app.domain;
