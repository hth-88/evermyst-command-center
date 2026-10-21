-- ============================================================================
-- PREFLIGHT AUDIT SCRIPT - EVERMYST V2 ARCHITECTURE (READ-ONLY / CHỈ SELECT)
-- File: supabase/preflight/001_audit.sql
-- Mục đích: Kiểm tra tính toàn vẹn dữ liệu hiện có trước khi thực hiện migration V2
-- Ràng buộc: TUYỆT ĐỐI CHỈ DÙNG SELECT, KHÔNG GHI/SỬA/XÓA BẤT KỲ DỮ LIỆU NÀO
-- ============================================================================

-- ----------------------------------------------------------------------------
-- (a) KIỂM TRA ĐỘI CÓ LIGHT_BALANCE < 0 (VI PHẠM TÍNH TOÀN VẸN SỐ DƯ)
-- ----------------------------------------------------------------------------
SELECT 
    'CHECK_A_NEGATIVE_BALANCE' AS audit_rule,
    id AS team_id,
    name AS team_name,
    qr_code,
    light_balance,
    created_at
FROM teams
WHERE light_balance < 0;

-- ----------------------------------------------------------------------------
-- (b) KIỂM TRA CẶP (TEAM_ID, STATION) CÓ NHIỀU HƠN 1 PHẦN THƯỞNG CHƯA REVERSED
-- Phát hiện tình trạng spam claim hoặc lặp phần thưởng trạm
-- ----------------------------------------------------------------------------
SELECT 
    'CHECK_B_DUPLICATE_STATION_REWARDS' AS audit_rule,
    team_id,
    description AS station_description,
    COUNT(*) AS active_reward_count,
    SUM(amount) AS total_rewarded_lumen,
    array_agg(id) AS transaction_ids
FROM transactions
WHERE type = 'station_clear'
  AND status = 'approved'
  AND is_reversed = false
GROUP BY team_id, description
HAVING COUNT(*) > 1;

-- ----------------------------------------------------------------------------
-- (c) KIỂM TRA STAFF CÓ ROLE NẰM NGOÀI 3 ROLE MỚI
-- Bộ 3 role mới chuẩn kiến trúc V2: 'admin', 'station_support', 'pvp_referee'
-- (Role cũ hiện tại trong V1 là 'admin' và 'support')
-- ----------------------------------------------------------------------------
SELECT 
    'CHECK_C_LEGACY_OR_INVALID_ROLES' AS audit_rule,
    id AS staff_id,
    name AS staff_name,
    role AS current_role,
    station_assigned,
    is_active,
    created_at
FROM staff
WHERE role NOT IN ('admin', 'station_support', 'pvp_referee');

-- ----------------------------------------------------------------------------
-- (d) KIỂM TRA CHÊNH LỆCH GIỮA LIGHT_BALANCE VÀ TỔNG LEDGER (TRANSACTIONS)
-- Quy tắc: Mọi Lumen thay đổi đều phải được chứng minh bằng dòng Ledger approved & chưa reversed
-- ----------------------------------------------------------------------------
WITH ledger_summary AS (
    SELECT 
        team_id,
        COALESCE(SUM(amount), 0) AS total_ledger_lumen,
        COUNT(id) AS approved_tx_count
    FROM transactions
    WHERE status = 'approved'
      AND is_reversed = false
    GROUP BY team_id
)
SELECT 
    'CHECK_D_BALANCE_LEDGER_DISCREPANCY' AS audit_rule,
    t.id AS team_id,
    t.name AS team_name,
    t.light_balance AS current_team_balance,
    COALESCE(ls.total_ledger_lumen, 0) AS total_ledger_lumen,
    (t.light_balance - COALESCE(ls.total_ledger_lumen, 0)) AS balance_difference,
    COALESCE(ls.approved_tx_count, 0) AS approved_tx_count,
    CASE 
        WHEN (t.light_balance - COALESCE(ls.total_ledger_lumen, 0)) = 100 THEN 'UNLOGGED_INITIAL_GRANT_100'
        WHEN (t.light_balance - COALESCE(ls.total_ledger_lumen, 0)) <> 0 THEN 'LEDGER_INTEGRITY_MISMATCH'
        ELSE 'BALANCED'
    END AS diagnostic_status
FROM teams t
LEFT JOIN ledger_summary ls ON ls.team_id = t.id
WHERE t.light_balance <> COALESCE(ls.total_ledger_lumen, 0);

-- ----------------------------------------------------------------------------
-- (e) KIỂM TRA CÁC GIAO DỊCH ĐANG Ở TRẠNG THÁI PENDING (CHỜ ADMIN DUYỆT)
-- Phải được giải quyết sạch trước khi áp dụng state machine mới
-- ----------------------------------------------------------------------------
SELECT 
    'CHECK_E_PENDING_TRANSACTIONS' AS audit_rule,
    tx.id AS transaction_id,
    tx.client_request_id,
    tx.team_id,
    t.name AS team_name,
    tx.amount,
    tx.type,
    tx.description,
    tx.created_by,
    tx.created_at
FROM transactions tx
JOIN teams t ON t.id = tx.team_id
WHERE tx.status = 'pending';

-- ----------------------------------------------------------------------------
-- (f) KIỂM TRA SỐ LƯỢNG ĐẠO CỤ BỊ ÂM (TEAM_ITEMS.QUANTITY < 0)
-- ----------------------------------------------------------------------------
SELECT 
    'CHECK_F_NEGATIVE_ITEM_QUANTITY' AS audit_rule,
    ti.id AS inventory_id,
    ti.team_id,
    t.name AS team_name,
    ti.item_id,
    i.name AS item_name,
    ti.quantity,
    ti.used_count,
    ti.updated_at
FROM team_items ti
JOIN teams t ON t.id = ti.team_id
JOIN items i ON i.id = ti.item_id
WHERE ti.quantity < 0;

-- ----------------------------------------------------------------------------
-- (g) KIỂM TRA ĐƯỜNG SỬA TRỰC TIẾP TRONG DATABASE (AUDIT TRIGGERS & CONSTRAINTS)
-- Kiểm tra các bảng có trigger bảo vệ không hoặc có check constraint không
-- ----------------------------------------------------------------------------
SELECT 
    'CHECK_G_SCHEMA_CONSTRAINTS' AS audit_rule,
    conname AS constraint_name,
    conrelid::regclass AS table_name,
    pg_get_constraintdef(oid) AS constraint_definition
FROM pg_constraint
WHERE conrelid IN ('teams'::regclass, 'team_items'::regclass, 'transactions'::regclass)
  AND contype = 'c';
