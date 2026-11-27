-- Screen queries for /api/v1/mess.

-- name: getHome
WITH m AS (SELECT * FROM hostel.mess ORDER BY mess_id LIMIT 1),
     meal AS (SELECT CASE WHEN localtime < time '10:00' THEN 'BREAKFAST' WHEN localtime < time '15:00' THEN 'LUNCH'
                          WHEN localtime < time '18:30' THEN 'SNACKS' ELSE 'DINNER' END AS meal)
SELECT api.feed('MESS_MANAGER',
    (SELECT api.card('low-stock', 'NEEDS_YOU', 'LOW_STOCK', 'Provisions below reorder level', string_agg(c.item_name, ', '), count(*), 'ACTION', 'stores/low-stock')
       FROM inventory.inventory_stock s JOIN inventory.item_catalog c ON c.item_catalog_id = s.item_catalog_id
      WHERE s.location_id IN (SELECT store_location_id FROM hostel.mess) AND s.quantity_on_hand <= coalesce(s.reorder_level, 0)),
    (SELECT api.card('low-rating', 'NEEDS_YOU', 'FEEDBACK', 'Low ratings yesterday', NULL, count(*), 'ACTION', 'feedback')
       FROM hostel.mess_feedback f WHERE f.meal_date = current_date - 1 AND f.rating <= 2),
    (SELECT api.card('meal-now', 'NOW', 'MEAL_NOW', initcap(meal.meal) || ' now', (SELECT count(*) FROM hostel.meal_attendance a WHERE a.meal_date = current_date
                        AND a.meal = meal.meal AND a.status = 'TAKEN') || ' scanned', NULL, 'INFO', 'messes/' || m.mess_id || '/now')
       FROM m, meal),
    (SELECT api.card('menu', 'TODAY', 'MENU', 'Today''s menu', string_agg(initcap(mm.meal) || ': ' || mm.items, ' · '), NULL, 'INFO', 'menu')
       FROM hostel.mess_menu mm, m WHERE mm.mess_id = m.mess_id AND (mm.menu_date = current_date OR (mm.menu_date IS NULL AND mm.day_of_week = api.dow(current_date)))));

-- name: getMealNow
-- Expected = active subscriptions minus those out (outing / leave) and in sick bay
WITH m AS (SELECT * FROM hostel.mess WHERE mess_id = :messId::bigint),
     meal AS (SELECT CASE WHEN localtime < time '10:00' THEN 'BREAKFAST' WHEN localtime < time '15:00' THEN 'LUNCH'
                          WHEN localtime < time '18:30' THEN 'SNACKS' ELSE 'DINNER' END AS meal),
     subs AS (SELECT s.*, api.hostel_status(s.student_id) AS hs FROM hostel.mess_subscription s JOIN hostel.mess_plan p ON p.plan_id = s.plan_id, m
               WHERE p.mess_id = m.mess_id AND s.status = 'ACTIVE' AND s.from_date <= current_date AND (s.to_date IS NULL OR s.to_date >= current_date))
SELECT jsonb_build_object('messId', m.mess_id, 'meal', meal.meal, 'date', current_date,
    'expected', (SELECT count(*) FROM subs WHERE coalesce(hs, 'IN_HOSTEL') = 'IN_HOSTEL'),
    'scanned', (SELECT count(*) FROM hostel.meal_attendance a WHERE a.mess_id = m.mess_id AND a.meal_date = current_date AND a.meal = meal.meal AND a.status = 'TAKEN'),
    'onOuting', (SELECT count(*) FROM subs WHERE hs IN ('ON_OUTING', 'MISSING')),
    'onLeave', (SELECT count(*) FROM subs WHERE hs = 'ON_LEAVE'),
    'sickBay', (SELECT count(*) FROM subs WHERE hs = 'SICK_BAY'))
FROM m, meal;

-- name: recordMeal write
-- One scan per subscription and meal (scanning again returns the same row)
WITH b AS (SELECT :body::jsonb AS j),
     s AS (SELECT s.*, p.mess_id FROM hostel.mess_subscription s JOIN hostel.mess_plan p ON p.plan_id = s.plan_id, b
            WHERE s.status = 'ACTIVE' AND (s.subscription_id = (b.j ->> 'subscriptionId')::bigint
                                           OR ((b.j ->> 'subscriptionId') IS NULL AND s.student_id = (b.j ->> 'studentId')::bigint))
            ORDER BY s.from_date DESC LIMIT 1),
     ins AS (INSERT INTO hostel.meal_attendance (school_id, mess_id, subscription_id, meal_date, meal, status, source)
             SELECT s.school_id, s.mess_id, s.subscription_id, coalesce((b.j ->> 'mealDate')::date, current_date), b.j ->> 'meal', 'TAKEN', 'SCAN'
               FROM s, b
             ON CONFLICT (school_id, subscription_id, meal_date, meal) DO UPDATE SET status = 'TAKEN'
             RETURNING *)
SELECT api.camel(to_jsonb(ins)) FROM ins;

-- name: getFeedback
WITH f AS (SELECT * FROM hostel.mess_feedback WHERE mess_id = :messId::bigint AND meal_date >= coalesce(:from::date, current_date - 7))
SELECT jsonb_build_object('messId', :messId::bigint, 'from', coalesce(:from::date, current_date - 7),
    'average', (SELECT round(avg(rating), 2) FROM f),
    'byMeal', coalesce((SELECT jsonb_object_agg(coalesce(meal, 'ANY'), a) FROM (SELECT meal, round(avg(rating), 2) AS a FROM f GROUP BY meal) x), '{}'::jsonb),
    'comments', coalesce((SELECT jsonb_agg(comment ORDER BY meal_date DESC) FROM (SELECT * FROM f WHERE coalesce(comment, '') <> '' ORDER BY meal_date DESC LIMIT 50) c), '[]'::jsonb))
WHERE EXISTS (SELECT 1 FROM hostel.mess WHERE mess_id = :messId::bigint);

-- name: listLowStock
SELECT coalesce(jsonb_agg(jsonb_build_object('stockId', s.stock_id, 'itemCatalogId', s.item_catalog_id, 'item', c.item_name, 'location', l.room_name,
       'onHand', s.quantity_on_hand, 'reorderLevel', s.reorder_level, 'avgUnitCost', s.avg_unit_cost, 'low', true) ORDER BY c.item_name), '[]'::jsonb)
FROM inventory.inventory_stock s JOIN inventory.item_catalog c ON c.item_catalog_id = s.item_catalog_id JOIN inventory.location l ON l.location_id = s.location_id
WHERE s.quantity_on_hand <= coalesce(s.reorder_level, 0) AND s.location_id IN (SELECT store_location_id FROM hostel.mess);

-- name: getCostPerMeal
WITH m AS (SELECT * FROM hostel.mess WHERE mess_id = :messId::bigint),
     mo AS (SELECT coalesce(to_date(:month || '-01', 'YYYY-MM-DD'), date_trunc('month', current_date)::date) AS s),
     meals AS (SELECT count(*) AS n FROM hostel.meal_attendance a, m, mo WHERE a.mess_id = m.mess_id AND a.status = 'TAKEN'
                 AND a.meal_date >= mo.s AND a.meal_date < mo.s + interval '1 month'),
     cost AS (SELECT coalesce(sum(t.quantity * coalesce(t.unit_cost, 0)), 0) AS c FROM inventory.inventory_transaction t, m, mo
               WHERE t.txn_type IN ('CONSUMPTION', 'ISSUE') AND (t.from_location_id = m.store_location_id OR t.cost_centre = 'MESS')
                 AND t.txn_at >= mo.s AND t.txn_at < mo.s + interval '1 month')
SELECT jsonb_build_object('messId', m.mess_id, 'month', to_char(mo.s, 'YYYY-MM'), 'meals', meals.n, 'provisionsCost', cost.c,
                          'costPerMeal', round(cost.c / nullif(meals.n, 0), 2))
FROM m, mo, meals, cost;

-- name: getMessSubscription
SELECT api.camel(to_jsonb(s)) FROM hostel.mess_subscription s JOIN hostel.mess_plan p ON p.plan_id = s.plan_id
WHERE s.subscription_id = :subscriptionId::bigint AND p.mess_id = :messId::bigint;

-- name: saveMenu write
-- Replaces the given entries (by date when given, else by weekday and meal) for the mess
WITH m AS (SELECT * FROM hostel.mess WHERE mess_id = :messId::bigint),
     e AS (SELECT x ->> 'dayOfWeek' AS dow, (x ->> 'menuDate')::date AS d, x ->> 'meal' AS meal, x ->> 'items' AS items,
                  coalesce((x ->> 'isSpecial')::boolean, false) AS special
             FROM jsonb_array_elements(coalesce(:body::jsonb -> 'entries', '[]'::jsonb)) x WHERE coalesce(x ->> 'items', '') <> ''),
     del AS (DELETE FROM hostel.mess_menu mm USING m, e
              WHERE mm.mess_id = m.mess_id AND mm.meal = e.meal
                AND ((e.d IS NOT NULL AND mm.menu_date = e.d) OR (e.d IS NULL AND mm.menu_date IS NULL AND mm.day_of_week = e.dow)) RETURNING 1),
     ins AS (INSERT INTO hostel.mess_menu (school_id, mess_id, day_of_week, menu_date, meal, items, is_special)
             SELECT m.school_id, m.mess_id, coalesce(e.dow, api.dow(e.d)), e.d, e.meal, e.items, e.special FROM m, e RETURNING 1)
SELECT m.mess_id AS result FROM m WHERE (SELECT count(*) FROM del) + (SELECT count(*) FROM ins) >= 0;
-- then
SELECT coalesce(jsonb_agg(api.camel(to_jsonb(mm)) ORDER BY mm.menu_date NULLS LAST,
                array_position(ARRAY['MON','TUE','WED','THU','FRI','SAT','SUN'], mm.day_of_week),
                array_position(ARRAY['BREAKFAST','LUNCH','SNACKS','DINNER'], mm.meal)), '[]'::jsonb)
FROM hostel.mess_menu mm WHERE mm.mess_id = :result::bigint;

-- name: requisitionProvisions write
WITH b AS (SELECT :body::jsonb AS j),
     num AS (SELECT 'REQ-' || lpad((coalesce((SELECT max(nullif(regexp_replace(requisition_number, '\D', '', 'g'), '')::int) FROM inventory.requisition), 0) + 1)::text, 4, '0') AS n),
     r AS (INSERT INTO inventory.requisition (school_id, requisition_number, requested_by_user_id, department_id, cost_centre, hostel_id, needed_by, justification,
                                              estimated_total, status)
           SELECT :school::bigint, (SELECT n FROM num), :me::bigint, (j ->> 'departmentId')::bigint, coalesce(j ->> 'costCentre', 'MESS'), (j ->> 'hostelId')::bigint,
                  (j ->> 'neededBy')::date, j ->> 'justification',
                  coalesce((j ->> 'estimatedTotal')::numeric, (SELECT sum((x ->> 'quantity')::numeric * coalesce((x ->> 'estimatedUnitCost')::numeric, 0))
                                                                FROM jsonb_array_elements(coalesce(j -> 'lines', '[]'::jsonb)) x)),
                  'SUBMITTED' FROM b RETURNING requisition_id, school_id),
     l AS (INSERT INTO inventory.requisition_line (school_id, requisition_id, item_catalog_id, quantity, estimated_unit_cost)
           SELECT r.school_id, r.requisition_id, (x ->> 'itemCatalogId')::bigint, (x ->> 'quantity')::numeric, (x ->> 'estimatedUnitCost')::numeric
             FROM r, b, jsonb_array_elements(coalesce(b.j -> 'lines', '[]'::jsonb)) x RETURNING 1)
SELECT requisition_id AS result FROM r WHERE (SELECT count(*) FROM l) >= 0;
-- then
SELECT api.camel(to_jsonb(r)) FROM inventory.requisition r WHERE r.requisition_id = :result::bigint;
