-- ============================================================================
-- SQL TEST SUITE: 01_AUTH_PERMISSIONS.SQL
-- Mục tiêu: Kiểm thử ma trận phân quyền (Section 2.7) cho từng Role qua RPC
-- Tương thích tiêu chuẩn PostgreSQL (DO $$ test runner với RAISE ASSERT)
-- ============================================================================

DO $$
DECLARE
    v_admin_staff_id        UUID;
    v_support_staff_id      UUID;
    v_station_staff_id      UUID;
    
    v_admin_token           TEXT := 'test_token_admin_001';
    v_support_token         TEXT := 'test_token_support_001';
    v_station_token         TEXT := 'test_token_station_001';
    v_expired_token         TEXT := 'test_token_expired_001';
    v_invalid_token         TEXT := 'test_token_nonexistent_xyz';

    v_team_1_id             UUID;
    v_team_2_id             UUID;
    v_station_1_id          UUID;
    v_station_2_id          UUID;

    v_res                   JSONB;
BEGIN
    RAISE NOTICE '>>> BẮT ĐẦU TEST SUITE 01: PHÂN QUYỀN VAI TRÒ THEO MA TRẬN 2.7 <<<';

    -- 1. SETUP DỮ LIỆU GIẢ LẬP ĐỂ KIỂM THỬ TRONG TRANSACTION NÀY
    SELECT id INTO v_team_1_id FROM teams ORDER BY name ASC LIMIT 1;
    SELECT id INTO v_team_2_id FROM teams WHERE id <> v_team_1_id ORDER BY name ASC LIMIT 1;
    SELECT id INTO v_station_1_id FROM stations ORDER BY order_index ASC LIMIT 1;
    SELECT id INTO v_station_2_id FROM stations WHERE id <> v_station_1_id ORDER BY order_index ASC LIMIT 1;

    -- Tạo 3 staff đại diện 3 roles
    INSERT INTO staff (id, name, role, is_active, pin, pin_hash, assigned_team_id, assigned_station_id)
    VALUES 
        (gen_random_uuid(), 'Test Admin', 'admin', true, '999001', crypt('999001', gen_salt('bf', 8)), NULL, NULL)
    RETURNING id INTO v_admin_staff_id;

    INSERT INTO staff (id, name, role, is_active, pin, pin_hash, assigned_team_id, assigned_station_id)
    VALUES 
        (gen_random_uuid(), 'Test Support', 'team_support', true, '999002', crypt('999002', gen_salt('bf', 8)), v_team_1_id, NULL)
    RETURNING id INTO v_support_staff_id;

    INSERT INTO staff (id, name, role, is_active, pin, pin_hash, assigned_team_id, assigned_station_id)
    VALUES 
        (gen_random_uuid(), 'Test Station Master', 'station_master', true, '999003', crypt('999003', gen_salt('bf', 8)), NULL, v_station_1_id)
    RETURNING id INTO v_station_staff_id;

    -- Tạo session tương ứng
    INSERT INTO staff_sessions (staff_id, token_hash, token, expires_at)
    VALUES
        (v_admin_staff_id, encode(digest(v_admin_token, 'sha256'), 'hex'), v_admin_token, now() + INTERVAL '24 hours'),
        (v_support_staff_id, encode(digest(v_support_token, 'sha256'), 'hex'), v_support_token, now() + INTERVAL '24 hours'),
        (v_station_staff_id, encode(digest(v_station_token, 'sha256'), 'hex'), v_station_token, now() + INTERVAL '24 hours'),
        (v_support_staff_id, encode(digest(v_expired_token, 'sha256'), 'hex'), v_expired_token, now() - INTERVAL '1 hour');

    -- =========================================================================
    -- CA 1: TOKEN HẾT HẠN HOẶC KHÔNG TỒN TẠI PHẢI BỊ CHẶN (UNAUTHENTICATED)
    -- =========================================================================
    BEGIN
        v_res := get_history(v_invalid_token, NULL, 10);
        RAISE EXCEPTION 'TEST FAILED: Token không tồn tại không bị chặn!';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%UNAUTHENTICATED%' THEN
            RAISE NOTICE ' [PASS] Token không tồn tại bị chặn UNAUTHENTICATED thành công.';
        ELSE
            RAISE EXCEPTION 'TEST FAILED: Mong muốn UNAUTHENTICATED nhưng nhận được: %', SQLERRM;
        END IF;
    END;

    BEGIN
        v_res := get_history(v_expired_token, NULL, 10);
        RAISE EXCEPTION 'TEST FAILED: Token hết hạn không bị chặn!';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%UNAUTHENTICATED%' THEN
            RAISE NOTICE ' [PASS] Token hết hạn bị chặn UNAUTHENTICATED thành công.';
        ELSE
            RAISE EXCEPTION 'TEST FAILED: Mong muốn UNAUTHENTICATED nhưng nhận được: %', SQLERRM;
        END IF;
    END;

    -- =========================================================================
    -- CA 2: TEAM SUPPORT KHÔNG ĐƯỢC PHÉP TRUY CẬP VÀO RPC CỦA STATION HOẶC ADMIN
    -- =========================================================================
    BEGIN
        v_res := get_station_queue(v_support_token);
        RAISE EXCEPTION 'TEST FAILED: Support gọi get_station_queue mà không bị chặn!';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%FORBIDDEN_ROLE%' THEN
            RAISE NOTICE ' [PASS] Support gọi get_station_queue bị chặn FORBIDDEN_ROLE.';
        ELSE
            RAISE EXCEPTION 'TEST FAILED: Sai mã lỗi: %', SQLERRM;
        END IF;
    END;

    BEGIN
        v_res := admin_list_staff(v_support_token);
        RAISE EXCEPTION 'TEST FAILED: Support gọi admin_list_staff mà không bị chặn!';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%FORBIDDEN_ROLE%' THEN
            RAISE NOTICE ' [PASS] Support gọi admin_list_staff bị chặn FORBIDDEN_ROLE.';
        ELSE
            RAISE EXCEPTION 'TEST FAILED: Sai mã lỗi: %', SQLERRM;
        END IF;
    END;

    -- =========================================================================
    -- CA 3: STATION MASTER KHÔNG ĐƯỢC XỬ LÝ TRẠM KHÁC (FORBIDDEN_STATION)
    -- =========================================================================
    -- Tạo claim tại Station 2
    INSERT INTO station_claims (id, team_id, station_id, status, input, computed_points, final_points, scoring_snapshot)
    VALUES (
        gen_random_uuid(), v_team_1_id, v_station_2_id, 'pending_station', 
        '{"tier": "low"}'::jsonb, 20, 20,
        '{"scoring_type": "tier", "min_score": 0, "max_score": 100, "scoring_config": {}}'::jsonb
    );

    SELECT id INTO v_station_staff_id FROM station_claims WHERE station_id = v_station_2_id AND status = 'pending_station' LIMIT 1;

    -- Station Master phụ trách Station 1 cố duyệt claim ở Station 2
    v_res := verify_station_claim(v_station_token, v_station_staff_id, 'approve', NULL, NULL);
    IF (v_res->>'success')::BOOLEAN = false AND (v_res->>'code') = 'FORBIDDEN_STATION' THEN
        RAISE NOTICE ' [PASS] Station Master duyệt trạm khác bị trả về FORBIDDEN_STATION chính xác.';
    ELSE
        RAISE EXCEPTION 'TEST FAILED: Station Master duyệt trạm khác không nhận FORBIDDEN_STATION: %', v_res;
    END IF;

    -- =========================================================================
    -- CA 4: ADMIN CÓ TOÀN QUYỀN TRUY CẬP VÀ XỬ LÝ MỌI TRẠM VÀ HÀNG CHỜ
    -- =========================================================================
    v_res := get_station_queue(v_admin_token);
    IF (v_res->>'success')::BOOLEAN = true THEN
        RAISE NOTICE ' [PASS] Admin gọi get_station_queue thành công.';
    ELSE
        RAISE EXCEPTION 'TEST FAILED: Admin không gọi được get_station_queue: %', v_res;
    END IF;

    v_res := admin_list_staff(v_admin_token);
    IF (v_res->>'success')::BOOLEAN = true THEN
        RAISE NOTICE ' [PASS] Admin gọi admin_list_staff thành công.';
    ELSE
        RAISE EXCEPTION 'TEST FAILED: Admin không gọi được admin_list_staff: %', v_res;
    END IF;

    RAISE NOTICE '>>> TEST SUITE 01 (PHÂN QUYỀN MA TRẬN 2.7) HOÀN TẤT THÀNH CÔNG 100%! <<<';
    
    -- Rollback toàn bộ dữ liệu mock kiểm thử
    RAISE EXCEPTION 'ROLLBACK_TEST_TRANSACTION';
EXCEPTION
    WHEN EXCEPTION THEN
        IF SQLERRM = 'ROLLBACK_TEST_TRANSACTION' THEN
            RAISE NOTICE '>>> ĐÃ DỌN DẸP SẠCH DỮ LIỆU TEST (ROLLBACK OK) <<<';
        ELSE
            RAISE;
        END IF;
END $$;
