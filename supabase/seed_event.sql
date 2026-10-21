-- ============================================================================
-- EVENT DAY SEED SCRIPT: EVERMYST BIGGAME D26
-- File: supabase/seed_event.sql
-- Mục đích: Khởi tạo dữ liệu chuẩn bị trước Giờ G sự kiện chính thức:
-- 1. Dọn dẹp dữ liệu thử nghiệm cũ (Clean slate)
-- 2. 6 Đội chơi chuẩn (Lửa Thiêng, Sóng Thần, Rừng Xanh, Sấm Sét, Trăng Khuyết, Bình Minh)
--    kèm 100 Lumen số dư ban đầu và 6 bản ghi initial_grant trong transactions.
-- 3. 5 Trạm thử thách cấu hình đa dạng scoring_type (tier, fixed, time_attack, unit_stepper).
-- 4. Đạo cụ cửa hàng (Khiên Màn Sương, Kính Vọng Tầm, Chìa Khóa Vạn Năng) & Manh mối.
-- 5. Danh sách nhân sự với mã PIN 6 số duy nhất (Admin, Station Masters, Team Supports)
--    mã hóa Bcrypt với salt an toàn.
-- 6. Tự động kiểm tra đối soát số dư toàn vẹn (audit_balance_integrity).
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. DỌN DẸP DỮ LIỆU CŨ (CLEAN SLATE TRƯỚC GIỜ G)
-- ----------------------------------------------------------------------------
TRUNCATE TABLE 
    team_items,
    team_hints,
    team_station_keys,
    station_claims,
    transactions,
    pvp_logs,
    staff_sessions,
    auth_attempts,
    admin_audit_log
CASCADE;

DELETE FROM staff WHERE TRUE;
DELETE FROM hints WHERE TRUE;
DELETE FROM items WHERE TRUE;
DELETE FROM stations WHERE TRUE;
DELETE FROM teams WHERE TRUE;

-- ----------------------------------------------------------------------------
-- 2. KHỞI TẠO 6 ĐỘI CHƠI (TEAMS) & SỔ CÁI BAN ĐẦU (100 LUMEN)
-- ----------------------------------------------------------------------------
INSERT INTO teams (id, name, qr_code, light_balance, shield_until, unlocked_stations, is_active, created_at)
VALUES
    ('10000000-0000-0000-0000-000000000001', 'Đội 1: Lửa Thiêng',   'QR_TEAM_FIRE_01',    100, NULL, ARRAY[]::TEXT[], true, now()),
    ('10000000-0000-0000-0000-000000000002', 'Đội 2: Sóng Thần',    'QR_TEAM_WATER_02',   100, NULL, ARRAY[]::TEXT[], true, now()),
    ('10000000-0000-0000-0000-000000000003', 'Đội 3: Rừng Xanh',    'QR_TEAM_EARTH_03',   100, NULL, ARRAY[]::TEXT[], true, now()),
    ('10000000-0000-0000-0000-000000000004', 'Đội 4: Sấm Sét',      'QR_TEAM_THUNDER_04', 100, NULL, ARRAY[]::TEXT[], true, now()),
    ('10000000-0000-0000-0000-000000000005', 'Đội 5: Trăng Khuyết', 'QR_TEAM_MOON_05',    100, NULL, ARRAY[]::TEXT[], true, now()),
    ('10000000-0000-0000-0000-000000000006', 'Đội 6: Bình Minh',    'QR_TEAM_SUN_06',     100, NULL, ARRAY[]::TEXT[], true, now());

-- Ghi sổ cái initial_grant cho 6 đội để bảo toàn bất biến: balance = sum(ledger)
INSERT INTO transactions (id, client_request_id, team_id, amount, type, description, created_by, status, is_reversed, created_at)
VALUES
    (gen_random_uuid(), 'init_grant_team_1', '10000000-0000-0000-0000-000000000001', 100, 'initial_grant', 'Cấp 100 Lumen số dư khởi đầu giải đấu', 'system', 'approved', false, now()),
    (gen_random_uuid(), 'init_grant_team_2', '10000000-0000-0000-0000-000000000002', 100, 'initial_grant', 'Cấp 100 Lumen số dư khởi đầu giải đấu', 'system', 'approved', false, now()),
    (gen_random_uuid(), 'init_grant_team_3', '10000000-0000-0000-0000-000000000003', 100, 'initial_grant', 'Cấp 100 Lumen số dư khởi đầu giải đấu', 'system', 'approved', false, now()),
    (gen_random_uuid(), 'init_grant_team_4', '10000000-0000-0000-0000-000000000004', 100, 'initial_grant', 'Cấp 100 Lumen số dư khởi đầu giải đấu', 'system', 'approved', false, now()),
    (gen_random_uuid(), 'init_grant_team_5', '10000000-0000-0000-0000-000000000005', 100, 'initial_grant', 'Cấp 100 Lumen số dư khởi đầu giải đấu', 'system', 'approved', false, now()),
    (gen_random_uuid(), 'init_grant_team_6', '10000000-0000-0000-0000-000000000006', 100, 'initial_grant', 'Cấp 100 Lumen số dư khởi đầu giải đấu', 'system', 'approved', false, now());

-- ----------------------------------------------------------------------------
-- 3. KHỞI TẠO 5 TRẠM THỬ THÁCH (STATIONS) VỚI ĐA DẠNG CƠ CHẾ TÍNH ĐIỂM
-- ----------------------------------------------------------------------------
INSERT INTO stations (id, name, description, order_index, scoring_type, scoring_config, min_score, max_score, is_exclusive, allow_multiple_attempts, is_active, created_at)
VALUES
    (
        '20000000-0000-0000-0000-000000000001',
        'Trạm 1: Mê Cung Sương Mù',
        'Vượt mê cung ánh sáng theo bậc thành tích (Tier)',
        1,
        'tier',
        '{"tier_1": 50, "tier_2": 80, "tier_3": 120}'::jsonb,
        50,
        120,
        true,
        false,
        true,
        now()
    ),
    (
        '20000000-0000-0000-0000-000000000002',
        'Trạm 2: Giải Mã Tốc Độ',
        'Giải mật thư trong thời gian nhanh nhất (Time Attack)',
        2,
        'time_attack',
        '{"base": 40, "per_unit": 5, "max_units": 10}'::jsonb,
        40,
        90,
        true,
        false,
        true,
        now()
    ),
    (
        '20000000-0000-0000-0000-000000000003',
        'Trạm 3: Mật Mã Cổ Xưa',
        'Tìm kho báu giải câu đố cố định (Fixed Score)',
        3,
        'fixed',
        '{"fixed_score": 100}'::jsonb,
        100,
        100,
        true,
        false,
        true,
        now()
    ),
    (
        '20000000-0000-0000-0000-000000000004',
        'Trạm 4: Thu Thập Linh Hồn',
        'Trạm sinh tồn thu thập mảnh ngọc (Unit Stepper - Non-exclusive)',
        4,
        'unit_stepper',
        '{"per_unit": 10, "max_units": 15}'::jsonb,
        0,
        150,
        false,
        true,
        true,
        now()
    ),
    (
        '20000000-0000-0000-0000-000000000005',
        'Trạm 5: Đền Thờ Vĩnh Hằng',
        'Đấu trùm cuối cùng các tùy chọn vượt ải (Option Checklist)',
        5,
        'option_checklist',
        '{"base": 50, "options": {"boss": 50, "no_hint": 30, "speed_run": 20}}'::jsonb,
        50,
        150,
        true,
        false,
        true,
        now()
    );

-- ----------------------------------------------------------------------------
-- 4. CỬA HÀNG ĐẠO CỤ (ITEMS) & MANH MỐI BÍ MẬT (HINTS)
-- ----------------------------------------------------------------------------
INSERT INTO items (id, name, description, price, effect_type, duration_minutes, is_active, created_at)
VALUES
    ('30000000-0000-0000-0000-000000000001', 'Khiên Màn Sương',   'Bảo vệ đội khỏi đòn tấn công PvP trong 20 phút. Phản phệ kẻ địch 10 Lumen.', 30, 'shield', 20, true, now()),
    ('30000000-0000-0000-0000-000000000002', 'Kính Vọng Tầm',     'Do thám số dư Lumen và tình trạng khiên phòng thủ của đội đối thủ.',          20, 'spy',     0, true, now()),
    ('30000000-0000-0000-0000-000000000003', 'Chìa Khóa Vạn Năng', 'Bỏ qua một trạm độc quyền, trực tiếp mở khóa trạm và nhận điểm tối thiểu.', 60, 'key',     0, true, now());

INSERT INTO hints (id, station_id, title, content, tier, order_index, is_active, created_at)
VALUES
    ('40000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'Manh mối Mê Cung (Đồng)', 'Lần theo hướng rêu mọc ở ngã ba thứ hai.', 'bronze', 1, true, now()),
    ('40000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000001', 'Manh mối Mê Cung (Bạc)',  'Tại tượng đá thứ ba, rẽ trái để tránh bẫy.', 'silver', 2, true, now()),
    ('40000000-0000-0000-0000-000000000003', '20000000-0000-0000-0000-000000000002', 'Bí mật Giải Mã (Vàng)',   'Mật mã liên quan đến chuỗi Fibonacci 1-1-2-3-5.', 'gold', 1, true, now());

-- ----------------------------------------------------------------------------
-- 5. DANH SÁCH NHÂN SỰ BTC VỚI MÃ PIN 6 SỐ DUY NHẤT (BCRYPT HASH)
-- Mã PIN quy ước rõ ràng:
-- • Admin: 999001 (Tổng Quản Trò), 999002 (Phó BTC)
-- • Station Masters: 888001 -> 888005 (Trạm 1 -> Trạm 5)
-- • Team Supports:   777001 -> 777006 (Đội 1 -> Đội 6)
-- ----------------------------------------------------------------------------
INSERT INTO staff (id, name, role, pin, pin_hash, assigned_team_id, assigned_station_id, is_active, created_at)
VALUES
    -- 2 Admin
    (
        '50000000-0000-0000-0000-000000000001',
        'Admin Tổng Quản Trò',
        'admin',
        '999001',
        crypt('999001', gen_salt('bf', 8)),
        NULL,
        NULL,
        true,
        now()
    ),
    (
        '50000000-0000-0000-0000-000000000002',
        'Admin Phó Ban Tổ Chức',
        'admin',
        '999002',
        crypt('999002', gen_salt('bf', 8)),
        NULL,
        NULL,
        true,
        now()
    ),

    -- 5 Station Masters (Phân công độc quyền theo trạm)
    (
        '50000000-0000-0000-0000-000000000011',
        'Quản Trò Trạm 1 (Mê Cung)',
        'station_master',
        '888001',
        crypt('888001', gen_salt('bf', 8)),
        NULL,
        '20000000-0000-0000-0000-000000000001',
        true,
        now()
    ),
    (
        '50000000-0000-0000-0000-000000000012',
        'Quản Trò Trạm 2 (Tốc Độ)',
        'station_master',
        '888002',
        crypt('888002', gen_salt('bf', 8)),
        NULL,
        '20000000-0000-0000-0000-000000000002',
        true,
        now()
    ),
    (
        '50000000-0000-0000-0000-000000000013',
        'Quản Trò Trạm 3 (Mật Mã)',
        'station_master',
        '888003',
        crypt('888003', gen_salt('bf', 8)),
        NULL,
        '20000000-0000-0000-0000-000000000003',
        true,
        now()
    ),
    (
        '50000000-0000-0000-0000-000000000014',
        'Quản Trò Trạm 4 (Thu Thập)',
        'station_master',
        '888004',
        crypt('888004', gen_salt('bf', 8)),
        NULL,
        '20000000-0000-0000-0000-000000000004',
        true,
        now()
    ),
    (
        '50000000-0000-0000-0000-000000000015',
        'Quản Trò Trạm 5 (Đền Thờ)',
        'station_master',
        '888005',
        crypt('888005', gen_salt('bf', 8)),
        NULL,
        '20000000-0000-0000-0000-000000000005',
        true,
        now()
    ),

    -- 6 Team Supports (Phân công độc quyền theo đội)
    (
        '50000000-0000-0000-0000-000000000021',
        'Hỗ Trợ Đội 1 (Lửa Thiêng)',
        'team_support',
        '777001',
        crypt('777001', gen_salt('bf', 8)),
        '10000000-0000-0000-0000-000000000001',
        NULL,
        true,
        now()
    ),
    (
        '50000000-0000-0000-0000-000000000022',
        'Hỗ Trợ Đội 2 (Sóng Thần)',
        'team_support',
        '777002',
        crypt('777002', gen_salt('bf', 8)),
        '10000000-0000-0000-0000-000000000002',
        NULL,
        true,
        now()
    ),
    (
        '50000000-0000-0000-0000-000000000023',
        'Hỗ Trợ Đội 3 (Rừng Xanh)',
        'team_support',
        '777003',
        crypt('777003', gen_salt('bf', 8)),
        '10000000-0000-0000-0000-000000000003',
        NULL,
        true,
        now()
    ),
    (
        '50000000-0000-0000-0000-000000000024',
        'Hỗ Trợ Đội 4 (Sấm Sét)',
        'team_support',
        '777004',
        crypt('777004', gen_salt('bf', 8)),
        '10000000-0000-0000-0000-000000000004',
        NULL,
        true,
        now()
    ),
    (
        '50000000-0000-0000-0000-000000000025',
        'Hỗ Trợ Đội 5 (Trăng Khuyết)',
        'team_support',
        '777005',
        crypt('777005', gen_salt('bf', 8)),
        '10000000-0000-0000-0000-000000000005',
        NULL,
        true,
        now()
    ),
    (
        '50000000-0000-0000-0000-000000000026',
        'Hỗ Trợ Đội 6 (Bình Minh)',
        'team_support',
        '777006',
        crypt('777006', gen_salt('bf', 8)),
        '10000000-0000-0000-0000-000000000006',
        NULL,
        true,
        now()
    );

COMMIT;

-- ----------------------------------------------------------------------------
-- 6. KIỂM TRA ĐỐI SOÁT TÍNH TOÀN VẸN SỐ DƯ (AUDIT BALANCE INTEGRITY)
-- Phải trả về: total_discrepancy_count = 0, status = 'BALANCED'
-- ----------------------------------------------------------------------------
SELECT * FROM audit_balance_integrity();
