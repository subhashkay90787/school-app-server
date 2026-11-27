-- Screen queries for /api/v1/store (stock, issues, purchase, receipts, audits).

-- name: getHome
SELECT api.feed('STORE_KEEPER',
    (SELECT api.card('low', 'NEEDS_YOU', 'LOW_STOCK', 'Items below reorder level', string_agg(c.item_name, ', '), count(*), 'ACTION', 'stock?lowOnly=true')
       FROM inventory.inventory_stock s JOIN inventory.item_catalog c ON c.item_catalog_id = s.item_catalog_id WHERE s.quantity_on_hand <= coalesce(s.reorder_level, 0)
        AND coalesce(s.reorder_level, 0) > 0),
    (SELECT api.card('requisitions', 'NEEDS_YOU', 'REQUISITIONS', 'Approved requisitions to issue', NULL, count(*), 'ACTION', 'requisitions?status=APPROVED')
       FROM inventory.requisition r WHERE r.status = 'APPROVED'),
    (SELECT api.card('submitted', 'NEEDS_YOU', 'REQUISITIONS_SUBMITTED', 'Requisitions waiting for approval', NULL, count(*), 'INFO', 'requisitions?status=SUBMITTED')
       FROM inventory.requisition r WHERE r.status = 'SUBMITTED'),
    (SELECT api.card('grn', 'NEEDS_YOU', 'GRN_DRAFT', 'Goods receipts to post', NULL, count(*), 'ACTION', 'goods-receipts?status=DRAFT')
       FROM inventory.goods_receipt g WHERE g.status = 'DRAFT'),
    (SELECT api.card('po-due', 'TODAY', 'PO_DUE', 'Deliveries expected', NULL, count(*), 'INFO', 'purchase-orders')
       FROM inventory.purchase_order po WHERE po.status IN ('SENT', 'PARTIALLY_RECEIVED') AND po.expected_date <= current_date + 2),
    (SELECT api.card('warranty', 'FEED', 'WARRANTY', 'Warranties ending this month', NULL, count(*), 'INFO', 'assets')
       FROM inventory.asset_item a WHERE a.warranty_until BETWEEN current_date AND current_date + 30));

-- name: listStock
SELECT api.page(coalesce(jsonb_agg(v ORDER BY (v ->> 'low')::boolean DESC, v ->> 'item'), '[]'::jsonb), :page, :size) FROM (
    SELECT jsonb_strip_nulls(jsonb_build_object('stockId', s.stock_id, 'itemCatalogId', s.item_catalog_id, 'item', c.item_name, 'location', l.room_name,
           'onHand', s.quantity_on_hand, 'reorderLevel', s.reorder_level, 'avgUnitCost', s.avg_unit_cost,
           'low', coalesce(s.reorder_level, 0) > 0 AND s.quantity_on_hand <= s.reorder_level)) AS v
      FROM inventory.inventory_stock s JOIN inventory.item_catalog c ON c.item_catalog_id = s.item_catalog_id JOIN inventory.location l ON l.location_id = s.location_id
     WHERE (:locationId IS NULL OR s.location_id = :locationId::bigint)
       AND (coalesce(:lowOnly::boolean, false) = false OR (coalesce(s.reorder_level, 0) > 0 AND s.quantity_on_hand <= s.reorder_level))
       AND (:q IS NULL OR c.item_name ILIKE '%' || :q || '%')
) x;

-- name: issueStock write
-- ISSUE transactions out of one location; stock goes down (never below zero: the line is refused)
WITH b AS (SELECT :body::jsonb AS j),
     l AS (SELECT (x ->> 'itemCatalogId')::bigint AS item, (x ->> 'quantity')::numeric AS qty, (x ->> 'assetId')::bigint AS asset, x ->> 'batchNo' AS batch
             FROM b, jsonb_array_elements(coalesce(b.j -> 'lines', '[]'::jsonb)) x),
     ok AS (SELECT l.*, s.stock_id, s.avg_unit_cost FROM l JOIN inventory.inventory_stock s ON s.item_catalog_id = l.item, b
             WHERE s.location_id = (b.j ->> 'fromLocationId')::bigint AND l.qty > 0 AND s.quantity_on_hand >= l.qty),
     tx AS (INSERT INTO inventory.inventory_transaction (school_id, item_catalog_id, asset_id, issued_by_user_id, issued_to_user_id, txn_type, quantity, unit_cost,
                                                         from_location_id, issued_to_student_id, issued_to_department_id, cost_centre, reference_kind, reference_id, batch_no, txn_at, note)
            SELECT :school::bigint, ok.item, ok.asset, :me::bigint, (b.j ->> 'issuedToUserId')::bigint, 'ISSUE', ok.qty, ok.avg_unit_cost,
                   (b.j ->> 'fromLocationId')::bigint, (b.j ->> 'issuedToStudentId')::bigint, (b.j ->> 'issuedToDepartmentId')::bigint, b.j ->> 'costCentre',
                   CASE WHEN (b.j ->> 'requisitionId') IS NOT NULL THEN 'REQUISITION' END, (b.j ->> 'requisitionId')::bigint, ok.batch, now(), b.j ->> 'note'
              FROM ok, b WHERE (SELECT count(*) FROM ok) = (SELECT count(*) FROM l) RETURNING *),
     st AS (UPDATE inventory.inventory_stock s SET quantity_on_hand = s.quantity_on_hand - t.quantity FROM tx t
             WHERE s.item_catalog_id = t.item_catalog_id AND s.location_id = t.from_location_id RETURNING 1)
SELECT coalesce(jsonb_agg(api.camel(to_jsonb(tx)) ORDER BY tx.transaction_id), '[]'::jsonb) FROM tx
HAVING count(*) > 0 AND (SELECT count(*) FROM st) >= 0;

-- name: issueRequisition write
-- Issues an APPROVED requisition's lines (quantities as requested unless lines are given) and marks it issued
WITH b AS (SELECT :body::jsonb AS j),
     r AS (SELECT * FROM inventory.requisition WHERE requisition_id = :requisitionId::bigint AND status = 'APPROVED'),
     l AS (SELECT coalesce((x ->> 'itemCatalogId')::bigint, rl.item_catalog_id) AS item, coalesce((x ->> 'quantity')::numeric, rl.quantity) AS qty
             FROM r JOIN inventory.requisition_line rl ON rl.requisition_id = r.requisition_id, b
             LEFT JOIN LATERAL (SELECT x FROM jsonb_array_elements(coalesce(b.j -> 'lines', '[]'::jsonb)) x WHERE (x ->> 'itemCatalogId')::bigint = rl.item_catalog_id) y ON true),
     ok AS (SELECT l.*, s.avg_unit_cost FROM l JOIN inventory.inventory_stock s ON s.item_catalog_id = l.item, b
             WHERE s.location_id = (b.j ->> 'fromLocationId')::bigint AND l.qty > 0 AND s.quantity_on_hand >= l.qty),
     tx AS (INSERT INTO inventory.inventory_transaction (school_id, item_catalog_id, issued_by_user_id, issued_to_user_id, txn_type, quantity, unit_cost,
                                                         from_location_id, issued_to_department_id, cost_centre, reference_kind, reference_id, txn_at, note)
            SELECT r.school_id, ok.item, :me::bigint, coalesce((b.j ->> 'issuedToUserId')::bigint, r.requested_by_user_id), 'ISSUE', ok.qty, ok.avg_unit_cost,
                   (b.j ->> 'fromLocationId')::bigint, r.department_id, coalesce(b.j ->> 'costCentre', r.cost_centre), 'REQUISITION', r.requisition_id, now(), b.j ->> 'note'
              FROM ok, b, r WHERE (SELECT count(*) FROM ok) = (SELECT count(*) FROM l) RETURNING *),
     st AS (UPDATE inventory.inventory_stock s SET quantity_on_hand = s.quantity_on_hand - t.quantity FROM tx t
             WHERE s.item_catalog_id = t.item_catalog_id AND s.location_id = t.from_location_id RETURNING 1),
     rq AS (UPDATE inventory.requisition SET status = 'ISSUED_FROM_STOCK' WHERE requisition_id = (SELECT requisition_id FROM r) AND EXISTS (SELECT 1 FROM tx) RETURNING 1)
SELECT coalesce(jsonb_agg(api.camel(to_jsonb(tx)) ORDER BY tx.transaction_id), '[]'::jsonb) FROM tx
HAVING count(*) > 0 AND (SELECT count(*) FROM st) + (SELECT count(*) FROM rq) >= 0;

-- name: returnStock write
-- RETURN transactions into the location (stock goes up)
WITH b AS (SELECT :body::jsonb AS j),
     l AS (SELECT (x ->> 'itemCatalogId')::bigint AS item, (x ->> 'quantity')::numeric AS qty, x ->> 'batchNo' AS batch
             FROM b, jsonb_array_elements(coalesce(b.j -> 'lines', '[]'::jsonb)) x WHERE (x ->> 'quantity')::numeric > 0),
     tx AS (INSERT INTO inventory.inventory_transaction (school_id, item_catalog_id, issued_by_user_id, issued_to_user_id, txn_type, quantity, to_location_id,
                                                         issued_to_student_id, cost_centre, batch_no, txn_at, note)
            SELECT :school::bigint, l.item, :me::bigint, (b.j ->> 'issuedToUserId')::bigint, 'RETURN', l.qty, (b.j ->> 'fromLocationId')::bigint,
                   (b.j ->> 'issuedToStudentId')::bigint, b.j ->> 'costCentre', l.batch, now(), b.j ->> 'note' FROM l, b RETURNING *),
     st AS (INSERT INTO inventory.inventory_stock (school_id, item_catalog_id, location_id, quantity_on_hand)
            SELECT :school::bigint, t.item_catalog_id, t.to_location_id, t.quantity FROM tx t
            ON CONFLICT (school_id, item_catalog_id, location_id) DO UPDATE SET quantity_on_hand = inventory.inventory_stock.quantity_on_hand + EXCLUDED.quantity_on_hand
            RETURNING 1)
SELECT coalesce(jsonb_agg(api.camel(to_jsonb(tx)) ORDER BY tx.transaction_id), '[]'::jsonb) FROM tx
HAVING count(*) > 0 AND (SELECT count(*) FROM st) >= 0;

-- name: postGoodsReceipt write
-- DRAFT -> POSTED: accepted quantities into stock (weighted average cost), PO lines' received quantities and status
WITH g AS (SELECT * FROM inventory.goods_receipt WHERE grn_id = :grnId::bigint AND status = 'DRAFT'),
     l AS (SELECT gl.*, coalesce(gl.accepted_qty, gl.received_qty) AS qty FROM inventory.grn_line gl, g WHERE gl.grn_id = g.grn_id),
     st AS (INSERT INTO inventory.inventory_stock (school_id, item_catalog_id, location_id, quantity_on_hand, avg_unit_cost)
            SELECT g.school_id, l.item_catalog_id, g.location_id, l.qty, l.unit_cost FROM l, g
            ON CONFLICT (school_id, item_catalog_id, location_id) DO UPDATE SET
                avg_unit_cost = CASE WHEN inventory.inventory_stock.quantity_on_hand + EXCLUDED.quantity_on_hand > 0
                                     THEN (coalesce(inventory.inventory_stock.avg_unit_cost, 0) * inventory.inventory_stock.quantity_on_hand
                                           + coalesce(EXCLUDED.avg_unit_cost, 0) * EXCLUDED.quantity_on_hand)
                                          / (inventory.inventory_stock.quantity_on_hand + EXCLUDED.quantity_on_hand) END,
                quantity_on_hand = inventory.inventory_stock.quantity_on_hand + EXCLUDED.quantity_on_hand
            RETURNING 1),
     tx AS (INSERT INTO inventory.inventory_transaction (school_id, item_catalog_id, issued_by_user_id, txn_type, quantity, unit_cost, to_location_id,
                                                         reference_kind, reference_id, batch_no, txn_at)
            SELECT g.school_id, l.item_catalog_id, :me::bigint, 'RECEIPT', l.qty, l.unit_cost, g.location_id, 'GRN', g.grn_id, l.batch_no, now() FROM l, g RETURNING 1),
     pol AS (UPDATE inventory.po_line pl SET received_qty = pl.received_qty + l.qty FROM l WHERE pl.po_line_id = l.po_line_id RETURNING pl.po_id),
     po AS (UPDATE inventory.purchase_order po SET status = CASE WHEN NOT EXISTS (SELECT 1 FROM inventory.po_line x WHERE x.po_id = po.po_id
                                                                                   AND x.received_qty + coalesce((SELECT sum(l.qty) FROM l WHERE l.po_line_id = x.po_line_id), 0) < x.quantity)
                                                                 THEN 'RECEIVED' ELSE 'PARTIALLY_RECEIVED' END
             FROM g WHERE po.po_id = g.po_id RETURNING 1),
     up AS (UPDATE inventory.goods_receipt SET status = 'POSTED' WHERE grn_id = (SELECT grn_id FROM g) RETURNING *)
SELECT api.camel(to_jsonb(up)) FROM up WHERE (SELECT count(*) FROM st) + (SELECT count(*) FROM tx) + (SELECT count(*) FROM pol) + (SELECT count(*) FROM po) >= 0;

-- name: startStockAudit write
-- Lines for every item at the location with the system quantity frozen; counts are blind until submitted
WITH b AS (SELECT :body::jsonb AS j),
     a AS (INSERT INTO inventory.stock_audit (school_id, location_id, audit_date, conducted_by_user_id, status)
           SELECT :school::bigint, (j ->> 'locationId')::bigint, coalesce((j ->> 'auditDate')::date, current_date), :me::bigint, 'IN_PROGRESS' FROM b RETURNING *),
     ln AS (INSERT INTO inventory.stock_audit_line (school_id, audit_id, item_catalog_id, system_qty)
            SELECT a.school_id, a.audit_id, s.item_catalog_id, s.quantity_on_hand FROM a JOIN inventory.inventory_stock s ON s.location_id = a.location_id RETURNING 1)
SELECT audit_id AS result FROM a WHERE (SELECT count(*) FROM ln) >= 0;
-- then
SELECT jsonb_build_object('auditId', a.audit_id, 'location', l.room_name, 'status', a.status, 'blind', true,
    'lines', coalesce((SELECT jsonb_agg(jsonb_strip_nulls(jsonb_build_object('lineId', x.line_id, 'itemCatalogId', x.item_catalog_id, 'item', c.item_name,
                     'assetId', x.asset_id, 'countedQty', x.counted_qty, 'varianceReason', x.variance_reason)) ORDER BY c.item_name)
                 FROM inventory.stock_audit_line x JOIN inventory.item_catalog c ON c.item_catalog_id = x.item_catalog_id WHERE x.audit_id = a.audit_id), '[]'::jsonb))
FROM inventory.stock_audit a JOIN inventory.location l ON l.location_id = a.location_id WHERE a.audit_id = :result::bigint;

-- name: saveCounts write
WITH a AS (SELECT * FROM inventory.stock_audit WHERE audit_id = :auditId::bigint AND status = 'IN_PROGRESS'),
     c AS (SELECT (x ->> 'lineId')::bigint AS line_id, (x ->> 'itemCatalogId')::bigint AS item, (x ->> 'countedQty')::numeric AS qty, x ->> 'varianceReason' AS reason
             FROM jsonb_array_elements(coalesce(:body::jsonb -> 'counts', '[]'::jsonb)) x),
     up AS (UPDATE inventory.stock_audit_line l SET counted_qty = c.qty, variance_reason = coalesce(c.reason, l.variance_reason)
              FROM c, a WHERE l.audit_id = a.audit_id AND (l.line_id = c.line_id OR (c.line_id IS NULL AND l.item_catalog_id = c.item)) RETURNING 1)
SELECT a.audit_id AS result FROM a WHERE (SELECT count(*) FROM up) >= 0;
-- then
SELECT jsonb_build_object('auditId', a.audit_id, 'location', l.room_name, 'status', a.status, 'blind', a.status = 'IN_PROGRESS',
    'lines', coalesce((SELECT jsonb_agg(jsonb_strip_nulls(jsonb_build_object('lineId', x.line_id, 'itemCatalogId', x.item_catalog_id, 'item', c.item_name,
                     'assetId', x.asset_id, 'systemQty', CASE WHEN a.status <> 'IN_PROGRESS' THEN x.system_qty END,
                     'countedQty', x.counted_qty, 'varianceReason', x.variance_reason)) ORDER BY c.item_name)
                 FROM inventory.stock_audit_line x JOIN inventory.item_catalog c ON c.item_catalog_id = x.item_catalog_id WHERE x.audit_id = a.audit_id), '[]'::jsonb))
FROM inventory.stock_audit a JOIN inventory.location l ON l.location_id = a.location_id WHERE a.audit_id = :result::bigint;

-- name: createPurchaseOrder write
-- DRAFT PO with lines; totals from the lines (GST from the line or the catalogue)
WITH b AS (SELECT :body::jsonb AS j),
     num AS (SELECT 'PO-' || lpad((coalesce((SELECT max(nullif(regexp_replace(po_number, '\D', '', 'g'), '')::int) FROM inventory.purchase_order), 0) + 1)::text, 4, '0') AS n),
     l AS (SELECT (x ->> 'itemCatalogId')::bigint AS item, (x ->> 'quantity')::numeric AS qty, (x ->> 'unitPrice')::numeric AS price,
                  coalesce((x ->> 'gstRate')::numeric, (SELECT c.gst_rate FROM inventory.item_catalog c WHERE c.item_catalog_id = (x ->> 'itemCatalogId')::bigint), 0) AS gst
             FROM b, jsonb_array_elements(coalesce(b.j -> 'lines', '[]'::jsonb)) x),
     po AS (INSERT INTO inventory.purchase_order (school_id, po_number, vendor_id, requisition_id, order_date, expected_date, subtotal, tax_amount, total_amount, status, created_by_user_id)
            SELECT :school::bigint, (SELECT n FROM num), (j ->> 'vendorId')::bigint, (j ->> 'requisitionId')::bigint, current_date, (j ->> 'expectedDate')::date,
                   (SELECT coalesce(sum(qty * price), 0) FROM l), (SELECT coalesce(sum(qty * price * gst / 100), 0) FROM l),
                   (SELECT coalesce(sum(qty * price * (1 + gst / 100)), 0) FROM l), 'DRAFT', :me::bigint
              FROM b WHERE EXISTS (SELECT 1 FROM l) RETURNING po_id, school_id),
     pl AS (INSERT INTO inventory.po_line (school_id, po_id, item_catalog_id, quantity, unit_price, gst_rate, received_qty)
            SELECT po.school_id, po.po_id, l.item, l.qty, l.price, l.gst, 0 FROM po, l RETURNING 1)
SELECT po_id AS result FROM po WHERE (SELECT count(*) FROM pl) >= 0;
-- then
SELECT api.camel(to_jsonb(p)) FROM inventory.purchase_order p WHERE p.po_id = :result::bigint;

-- name: createGoodsReceipt write
-- DRAFT GRN against an approved / sent PO; posting it (postGoodsReceipt) moves the stock
WITH b AS (SELECT :body::jsonb AS j),
     po AS (SELECT p.* FROM inventory.purchase_order p, b WHERE p.po_id = (b.j ->> 'poId')::bigint AND p.status IN ('APPROVED', 'SENT', 'PARTIALLY_RECEIVED')),
     num AS (SELECT 'GRN-' || lpad((coalesce((SELECT max(nullif(regexp_replace(grn_number, '\D', '', 'g'), '')::int) FROM inventory.goods_receipt), 0) + 1)::text, 4, '0') AS n),
     g AS (INSERT INTO inventory.goods_receipt (school_id, grn_number, po_id, location_id, received_by_user_id, received_at, vendor_challan_no, status)
           SELECT po.school_id, (SELECT n FROM num), po.po_id, (b.j ->> 'locationId')::bigint, :me::bigint, now(), b.j ->> 'vendorChallanNo', 'DRAFT'
             FROM po, b RETURNING grn_id, school_id),
     gl AS (INSERT INTO inventory.grn_line (school_id, grn_id, po_line_id, item_catalog_id, received_qty, accepted_qty, rejected_qty, unit_cost, batch_no, expiry_date)
            SELECT g.school_id, g.grn_id, (x ->> 'poLineId')::bigint,
                   coalesce((x ->> 'itemCatalogId')::bigint, (SELECT pl.item_catalog_id FROM inventory.po_line pl WHERE pl.po_line_id = (x ->> 'poLineId')::bigint)),
                   (x ->> 'receivedQty')::numeric, coalesce((x ->> 'acceptedQty')::numeric, (x ->> 'receivedQty')::numeric), coalesce((x ->> 'rejectedQty')::numeric, 0),
                   coalesce((x ->> 'unitCost')::numeric, (SELECT pl.unit_price FROM inventory.po_line pl WHERE pl.po_line_id = (x ->> 'poLineId')::bigint)),
                   x ->> 'batchNo', (x ->> 'expiryDate')::date
              FROM g, b, jsonb_array_elements(coalesce(b.j -> 'lines', '[]'::jsonb)) x RETURNING 1)
SELECT grn_id AS result FROM g WHERE (SELECT count(*) FROM gl) >= 0;
-- then
SELECT api.camel(to_jsonb(g)) FROM inventory.goods_receipt g WHERE g.grn_id = :result::bigint;
