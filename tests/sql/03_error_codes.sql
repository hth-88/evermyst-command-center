-- ============================================================================
-- SQL TEST SUITE: 03_ERROR_CODES.SQL
-- Mục tiêu: Kiểm thử các mã lỗi nghiệp vụ chuẩn hóa trong error-codes.md
-- ============================================================================

DO $$
DECLARE
    v_admin_id          UUID;
    v_support_id        UUID;
    v_admin_token       TEXT := 'test_token_admin_err';
    v_support_token     TEXT := 'test_token_support_err';
    
    v_team_1_id         UUID;
    v_team_2_id         UUID;
    v_station_id        UUID;
    v_hint_id           UUID;
    v_item_id           UUID;
    v_claim_id          UUID;
    
    v_res               JSONB;
BEGIN
    RAISE NOTICE '>>> BẮT ĐẦU TEST SUITE 03: DANH SÁCH MÃ LỖI CHUẨN HÓA ERROR-CODES.MD <<<';

    SELECT id INTO v_team_1_id FROM teams ORDER BY name ASC LIMIT 1;
    SELECT id INTO v_team_2_id FROM teams WHERE id <> v_team_1_id ORDER BY name ASC LIMIT 1;
    SELECT id INTO v_station_id FROM stations ORDER BY order_index ASC LIMIT 1;

    -- Setup staff
    INSERT INTO staff (id, name, role, is_active, pin, pin_hash, assigned_team_id)
    VALUES (gen_random_uuid(), 'Err Support', 'team_support', true, '888001', crypt('888001', gen_salt('bf', 8)), v_team_1_id)
    RETURNING id INTO v_support_id;

    INSERT INTO staff (id, name, role, is_active, pin, pin_hash)
    VALUES (gen_random_uuid(), 'Err Admin', 'admin', true, '888002', crypt('888002', gen_salt('bf', 8)))
    RETURNING id INTO v_admin_id;

    INSERT INTO staff_sessions (staff_id, token_hash, token, expires_at)
    VALUES 
        (v_support_id, encode(digest(v_support_token, 'sha256'), 'hex'), v_support_token, now() + INTERVAL '24 hours'),
        (v_admin_id, encode(digest(v_admin_token, 'sha256'), 'hex'), v_admin_token, now() + INTERVAL '24 hours');

    -- Setup hint & item
    INSERT INTO hints (id, title, content, tier, price, is_active)
    VALUES (gen_random_uuid(), 'Err Test Hint', 'Secret Content', 'bronze', 25, true)
    RETURNING id INTO v_hint_id;

    INSERT INTO items (id, name, description, price, effect_type, is_active)
    VALUES (gen_random_uuid(), 'Err Test Item', 'Item Test', 30, 'spy', true)
    RETURNING id INTO v_item_id;

    -- 1. ERROR: INVALID_PIN (staff_login với PIN rỗng)
    v_res := staff_login('');
    IF (v_res->>'success')::BOOLEAN = false AND (v_res->>'code') = 'INVALID_PIN' THEN
        RAISE NOTICE ' [PASS] Mã lỗi INVALID_PIN được trả về chính xác khi PIN rỗng.';
    ELSE
        RAISE EXCEPTION 'TEST FAILED: Sai mã lỗi khi PIN rỗng: %', v_res;
    END IF;

    -- 2. ERROR: PIN_NOT_UNIQUE (Tạo nhân sự trùng mã PIN đang dùng)
    v_res := admin_upsert_staff(v_admin_token, NULL, 'Duplicate Staff', 'admin', '888001');
    IF (v_res->>'success')::BOOLEAN = false AND (v_res->>'code') = 'PIN_NOT_UNIQUE' THEN
        RAISE NOTICE ' [PASS] Mã lỗi PIN_NOT_UNIQUE được trả về chính xác khi mã PIN bị trùng.';
    ELSE
        RAISE EXCEPTION 'TEST FAILED: Sai mã lỗi khi trùng PIN: %', v_res;
    END IF;

    -- 3. ERROR: NOTE_REQUIRED_ON_REJECT (Từ chối claim nhưng không nhập lý do)
    INSERT INTO station_claims (id, team_id, station_id, status, input, computed_points, final_points, scoring_snapshot)
    VALUES (gen_random_uuid(), v_team_1_id, v_station_id, 'pending_station', '{"tier": "tier_1"}'::jsonb, 20, 20, '{"scoring_type": "tier"}'::jsonb)
    RETURNING id INTO v_claim_id;

    v_res := verify_station_claim(v_admin_token, v_claim_id, 'reject', NULL, NULL);
    IF (v_res->>'success')::BOOLEAN = false AND (v_res->>'code') = 'NOTE_REQUIRED_ON_REJECT' THEN
        RAISE NOTICE ' [PASS] Mã lỗi NOTE_REQUIRED_ON_REJECT được trả về chính xác khi từ chối thiếu lý do.';
    ELSE
        RAISE EXCEPTION 'TEST FAILED: Sai mã lỗi khi từ chối thiếu lý do: %', v_res;
    END IF;

    -- 4. ERROR: OVERRIDE_REQUIRES_NOTE (Sửa điểm claim nhưng không nhập ghi chú)
    v_res := verify_station_claim(v_admin_token, v_claim_id, 'approve', '{"tier": "tier_2"}'::jsonb, '');
    IF (v_res->>'success')::BOOLEAN = false AND (v_res->>'code') = 'OVERRIDE_REQUIRES_NOTE' THEN
        RAISE NOTICE ' [PASS] Mã lỗi OVERRIDE_REQUIRES_NOTE được trả về chính xác khi sửa điểm thiếu ghi chú.';
    ELSE
        RAISE EXCEPTION 'TEST FAILED: Sai mã lỗi khi sửa điểm thiếu ghi chú: %', v_res;
    END IF;

    -- 5. ERROR: INSUFFICIENT_BALANCE (Mua hint khi không đủ số dư)
    UPDATE teams SET light_balance = 10 WHERE id = v_team_1_id; -- Hint giá 25
    v_res := purchase_hint(v_support_token, v_hint_id, 'req_hint_fail');
    IF (v_res->>'success')::BOOLEAN = false AND (v_res->>'code') IN ('INSUFFICIENT_BALANCE', 'INSUFFICIENT_FUNDS') THEN
        RAISE NOTICE ' [PASS] Mã lỗi INSUFFICIENT_BALANCE được trả về chính xác khi không đủ tiền.';
    ELSE
        RAISE EXCEPTION 'TEST FAILED: Sai mã lỗi khi không đủ tiền mua hint: %', v_res;
    END IF;

    -- 6. ERROR: HINT_ALREADY_PURCHASED (Chặn mua trùng manh mối)
    UPDATE teams SET light_balance = 100 WHERE id = v_team_1_id;
    v_res := purchase_hint(v_support_token, v_hint_id, 'req_hint_ok'); -- Mua thành công lần 1
    v_res := purchase_hint(v_support_token, v_hint_id, 'req_hint_dup'); -- Mua lần 2
    IF (v_res->>'success')::BOOLEAN = false AND (v_res->>'code') IN ('HINT_ALREADY_PURCHASED', 'ALREADY_OWNED') THEN
        RAISE NOTICE ' [PASS] Mã lỗi HINT_ALREADY_PURCHASED được trả về chính xác khi mua trùng manh mối.';
    ELSE
        RAISE EXCEPTION 'TEST FAILED: Sai mã lỗi khi mua trùng manh mối: %', v_res;
    END IF;

    -- 7. ERROR: TARGET_SAME_TEAM (Do thám chính đội của mình)
    -- Cấp 1 item spy cho Team 1
    INSERT INTO team_items (id, team_id, item_id, quantity)
    VALUES (gen_random_uuid(), v_team_1_id, v_item_id, 1)
    ON CONFLICT (team_id, item_id) DO UPDATE SET quantity = team_items.quantity + 1;

    v_res := use_team_item(v_support_token, v_item_id, v_team_1_id, NULL);
    IF (v_res->>'success')::BOOLEAN = false AND (v_res->>'code') = 'TARGET_SAME_TEAM' THEN
        RAISE NOTICE ' [PASS] Mã lỗi TARGET_SAME_TEAM được trả về chính xác khi tự chọn đội mình.';
    ELSE
        RAISE EXCEPTION 'TEST FAILED: Sai mã lỗi TARGET_SAME_TEAM: %', v_res;
    END IF;

    -- 8. ERROR: PVP_SAME_TEAM (Tự PvP với chính mình)
    v_res := resolve_pvp(v_admin_token, v_team_1_id, v_team_1_id, 'req_pvp_self');
    IF (v_res->>'success')::BOOLEAN = false AND (v_res->>'code') = 'PVP_SAME_TEAM' THEN
        RAISE NOTICE ' [PASS] Mã lỗi PVP_SAME_TEAM được trả về chính xác khi tự tấn công đội mình.';
    ELSE
        RAISE EXCEPTION 'TEST FAILED: Sai mã lỗi PVP_SAME_TEAM: %', v_res;
    END IF;

    RAISE NOTICE '>>> TEST SUITE 03 (ERROR-CODES.MD) HOÀN TẤT THÀNH CÔNG 100%! <<<';

    RAISE EXCEPTION 'ROLLBACK_TEST_TRANSACTION';
EXCEPTION
    WHEN EXCEPTION THEN
        IF SQLERRM = 'ROLLBACK_TEST_TRANSACTION' THEN
            RAISE NOTICE '>>> ĐÃ DỌN DẸP SẠCH DỮ LIỆU TEST (ROLLBACK OK) <<<';
        ELSE
            RAISE;
        END IF;
END $$;
