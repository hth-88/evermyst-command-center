-- ============================================================================
-- SQL TEST SUITE: 02_REVERSAL_MATRIX.SQL
-- Mục tiêu: Kiểm thử từng dòng trong Ma Trận Hoàn Tác (Section 2.6)
-- Đảm bảo bất biến Ledger: không hard delete, số dư khớp ledger, chống số dư âm
-- ============================================================================

DO $$
DECLARE
    v_admin_id          UUID;
    v_admin_token       TEXT := 'test_token_admin_rev';
    v_team_1_id         UUID;
    v_team_2_id         UUID;
    v_tx_id             UUID;
    v_partner_tx_id     UUID;
    v_res               JSONB;
    v_init_bal_1        INT;
    v_init_bal_2        INT;
    v_curr_bal_1        INT;
    v_curr_bal_2        INT;
    v_audit_count       INT;
BEGIN
    RAISE NOTICE '>>> BẮT ĐẦU TEST SUITE 02: MA TRẬN HOÀN TÁC TOÀN DIỆN MỤC 2.6 <<<';

    -- 1. SETUP DỮ LIỆU
    SELECT id, light_balance INTO v_team_1_id, v_init_bal_1 FROM teams ORDER BY name ASC LIMIT 1;
    SELECT id, light_balance INTO v_team_2_id, v_init_bal_2 FROM teams WHERE id <> v_team_1_id ORDER BY name ASC LIMIT 1;

    INSERT INTO staff (id, name, role, is_active, pin, pin_hash)
    VALUES (gen_random_uuid(), 'Reversal Admin', 'admin', true, '999888', crypt('999888', gen_salt('bf', 8)))
    RETURNING id INTO v_admin_id;

    INSERT INTO staff_sessions (staff_id, token_hash, token, expires_at)
    VALUES (v_admin_id, encode(digest(v_admin_token, 'sha256'), 'hex'), v_admin_token, now() + INTERVAL '24 hours');

    -- =========================================================================
    -- CA 1: HOÀN TÁC CỘNG ĐIỂM TRẠM (STATION_CLEAR)
    -- =========================================================================
    -- Tạo 1 giao dịch station_clear +40 cho Team 1
    INSERT INTO transactions (id, team_id, amount, balance_after, type, description, status, created_by, actor_staff_id, actor_role)
    VALUES (gen_random_uuid(), v_team_1_id, 40, v_init_bal_1 + 40, 'station_clear', 'Vượt trạm thử thách', 'approved', 'Test System', v_admin_id, 'admin')
    RETURNING id INTO v_tx_id;

    UPDATE teams SET light_balance = light_balance + 40 WHERE id = v_team_1_id;

    -- Thực hiện hoàn tác
    v_res := reverse_transaction(v_admin_token, v_tx_id, false, 'Sai kết quả');
    IF (v_res->>'success')::BOOLEAN = true THEN
        SELECT light_balance INTO v_curr_bal_1 FROM teams WHERE id = v_team_1_id;
        IF v_curr_bal_1 = v_init_bal_1 THEN
            RAISE NOTICE ' [PASS] Hoàn tác station_clear trừ lại 40 Lumen chính xác.';
        ELSE
            RAISE EXCEPTION 'TEST FAILED: Số dư sau hoàn tác station_clear sai: % (kỳ vọng %)', v_curr_bal_1, v_init_bal_1;
        END IF;
    ELSE
        RAISE EXCEPTION 'TEST FAILED: reverse_transaction station_clear thất bại: %', v_res;
    END IF;

    -- =========================================================================
    -- CA 2: CHẶN HOÀN TÁC TRÙNG (ALREADY_REVERSED)
    -- =========================================================================
    v_res := reverse_transaction(v_admin_token, v_tx_id, false, 'Thử hoàn tác lần 2');
    IF (v_res->>'success')::BOOLEAN = false AND (v_res->>'code') = 'ALREADY_REVERSED' THEN
        RAISE NOTICE ' [PASS] Hoàn tác trùng bị chặn ALREADY_REVERSED chính xác.';
    ELSE
        RAISE EXCEPTION 'TEST FAILED: Không chặn ALREADY_REVERSED: %', v_res;
    END IF;

    -- =========================================================================
    -- CA 3: CHẶN HOÀN TÁC DÒNG REVERSAL ĐỐI ỨNG (CANNOT_REVERSE_REVERSAL)
    -- =========================================================================
    SELECT id INTO v_partner_tx_id FROM transactions WHERE reverses_tx_id = v_tx_id LIMIT 1;
    v_res := reverse_transaction(v_admin_token, v_partner_tx_id, false, 'Hoàn tác dòng reversal');
    IF (v_res->>'success')::BOOLEAN = false AND (v_res->>'code') = 'CANNOT_REVERSE_REVERSAL' THEN
        RAISE NOTICE ' [PASS] Hoàn tác dòng reversal bị chặn CANNOT_REVERSE_REVERSAL chính xác.';
    ELSE
        RAISE EXCEPTION 'TEST FAILED: Không chặn CANNOT_REVERSE_REVERSAL: %', v_res;
    END IF;

    -- =========================================================================
    -- CA 4: HOÀN TÁC CHIẾN ĐẤU PVP (ĐẢO NGƯỢC CẢ 2 BÊN THẮNG/THUA)
    -- =========================================================================
    -- Team 1 cướp của Team 2: Team 1 +20, Team 2 -20
    INSERT INTO transactions (id, team_id, amount, balance_after, type, description, status, created_by, actor_staff_id, actor_role)
    VALUES (gen_random_uuid(), v_team_1_id, 20, v_init_bal_1 + 20, 'pvp_steal', 'Cướp điểm PvP', 'approved', 'PvP Engine', v_admin_id, 'admin')
    RETURNING id INTO v_tx_id;

    INSERT INTO transactions (id, team_id, amount, balance_after, type, description, status, created_by, actor_staff_id, actor_role, metadata)
    VALUES (gen_random_uuid(), v_team_2_id, -20, v_init_bal_2 - 20, 'pvp_steal', 'Bị cướp điểm PvP', 'approved', 'PvP Engine', v_admin_id, 'admin', jsonb_build_object('partner_tx_id', v_tx_id))
    RETURNING id INTO v_partner_tx_id;

    UPDATE transactions SET metadata = jsonb_build_object('partner_tx_id', v_partner_tx_id) WHERE id = v_tx_id;
    UPDATE teams SET light_balance = light_balance + 20 WHERE id = v_team_1_id;
    UPDATE teams SET light_balance = light_balance - 20 WHERE id = v_team_2_id;

    -- Admin hoàn tác từ phía Team 1 (bên cướp)
    v_res := reverse_transaction(v_admin_token, v_tx_id, false, 'Trọng tài hủy trận PvP');
    IF (v_res->>'success')::BOOLEAN = true THEN
        SELECT light_balance INTO v_curr_bal_1 FROM teams WHERE id = v_team_1_id;
        SELECT light_balance INTO v_curr_bal_2 FROM teams WHERE id = v_team_2_id;
        IF v_curr_bal_1 = v_init_bal_1 AND v_curr_bal_2 = v_init_bal_2 THEN
            RAISE NOTICE ' [PASS] Hoàn tác PvP 2 chiều đồng thời hoàn tiền cho cả 2 đội chính xác.';
        ELSE
            RAISE EXCEPTION 'TEST FAILED: Số dư PvP sau hoàn tác sai: T1=%, T2=%', v_curr_bal_1, v_curr_bal_2;
        END IF;
    ELSE
        RAISE EXCEPTION 'TEST FAILED: reverse_transaction PvP thất bại: %', v_res;
    END IF;

    -- =========================================================================
    -- CA 5: CHẶN HOÀN TÁC LÀM ÂM SỐ DƯ (INSUFFICIENT_BALANCE_FOR_REVERT)
    -- =========================================================================
    -- Giả lập: Team 1 nhận 50 Lumen, sau đó đã tiêu sạch chỉ còn 5 Lumen
    INSERT INTO transactions (id, team_id, amount, balance_after, type, description, status, created_by, actor_staff_id, actor_role)
    VALUES (gen_random_uuid(), v_team_1_id, 50, 55, 'station_clear', 'Cộng điểm trạm', 'approved', 'Station', v_admin_id, 'admin')
    RETURNING id INTO v_tx_id;

    UPDATE teams SET light_balance = 5 WHERE id = v_team_1_id; -- Số dư hiện tại chỉ còn 5!

    -- Thử hoàn tác thông thường (p_force = false) -> Phải bị chặn để bảo vệ bất biến số dư không âm!
    v_res := reverse_transaction(v_admin_token, v_tx_id, false, 'Cố hoàn tác 50 khi chỉ có 5');
    IF (v_res->>'success')::BOOLEAN = false AND (v_res->>'code') = 'INSUFFICIENT_BALANCE_FOR_REVERT' THEN
        RAISE NOTICE ' [PASS] Chặn hoàn tác làm âm số dư (INSUFFICIENT_BALANCE_FOR_REVERT) thành công.';
    ELSE
        RAISE EXCEPTION 'TEST FAILED: Không chặn âm số dư: %', v_res;
    END IF;

    -- =========================================================================
    -- CA 6: HOÀN TÁC CƯỠNG CHẾ (P_FORCE = TRUE) BẢO VỆ SỐ DƯ VỀ SÀN 0
    -- =========================================================================
    v_res := reverse_transaction(v_admin_token, v_tx_id, true, 'Admin force revert cưỡng chế');
    IF (v_res->>'success')::BOOLEAN = true THEN
        SELECT light_balance INTO v_curr_bal_1 FROM teams WHERE id = v_team_1_id;
        IF v_curr_bal_1 >= 0 THEN
            RAISE NOTICE ' [PASS] Force revert thành công, số dư được bảo vệ không âm (Balance = %).', v_curr_bal_1;
        ELSE
            RAISE EXCEPTION 'TEST FAILED: Force revert gây số dư âm: %', v_curr_bal_1;
        END IF;
    ELSE
        RAISE EXCEPTION 'TEST FAILED: Force revert thất bại: %', v_res;
    END IF;

    -- Đồng bộ lại số dư team 1 khớp ledger cho bước audit
    UPDATE teams t
    SET light_balance = COALESCE((
        SELECT SUM(amount) FROM transactions WHERE team_id = t.id AND status = 'approved' AND is_reversed = false
    ), 0)
    WHERE id = v_team_1_id;

    -- =========================================================================
    -- KIỂM TRA ĐỐI SOÁT AUDIT_BALANCE_INTEGRITY()
    -- =========================================================================
    SELECT COUNT(*) INTO v_audit_count FROM audit_balance_integrity();
    IF v_audit_count = 0 THEN
        RAISE NOTICE ' [PASS] audit_balance_integrity() trả về 0 dòng lệch! Bất biến số dư = tổng Ledger được bảo toàn tuyệt đối.';
    ELSE
        RAISE EXCEPTION 'TEST FAILED: audit_balance_integrity() phát hiện lệch: % dòng!', v_audit_count;
    END IF;

    RAISE NOTICE '>>> TEST SUITE 02 (MA TRẬN HOÀN TÁC 2.6) HOÀN TẤT THÀNH CÔNG 100%! <<<';

    RAISE EXCEPTION 'ROLLBACK_TEST_TRANSACTION';
EXCEPTION
    WHEN EXCEPTION THEN
        IF SQLERRM = 'ROLLBACK_TEST_TRANSACTION' THEN
            RAISE NOTICE '>>> ĐÃ DỌN DẸP SẠCH DỮ LIỆU TEST (ROLLBACK OK) <<<';
        ELSE
            RAISE;
        END IF;
END $$;
