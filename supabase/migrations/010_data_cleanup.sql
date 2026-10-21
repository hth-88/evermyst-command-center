-- ============================================================================
-- MIGRATION 010: DATA CLEANUP & LEDGER RECONCILIATION
-- File: supabase/migrations/010_data_cleanup.sql
-- Mục đích: Dọn dẹp dữ liệu, ngăn chặn duplicate claims và đối soát số dư ban đầu
-- ============================================================================

DO $$
DECLARE
    v_duplicate_count INT;
    v_team RECORD;
    v_sys_actor TEXT := 'migration_010_system';
BEGIN
    -- 1. KIỂM TRA CLAIM TRÙNG TRƯỚC KHI THỰC HIỆN
    -- Nếu phát hiện cùng 1 đội có >= 2 lần nhận thưởng trạm chưa reversed thì DỪNG NGAY LẬP TỨC!
    SELECT COUNT(*) INTO v_duplicate_count
    FROM (
        SELECT team_id, description
        FROM transactions
        WHERE type = 'station_clear'
          AND status = 'approved'
          AND is_reversed = false
        GROUP BY team_id, description
        HAVING COUNT(*) > 1
    ) dup;

    IF v_duplicate_count > 0 THEN
        RAISE EXCEPTION 'MIGRATION_HALTED: Phát hiện % trường hợp nhận thưởng trạm trùng lặp! Yêu cầu Admin xử lý thủ công trước khi migrate.', v_duplicate_count;
    END IF;

    -- 2. XỬ LÝ SỐ DƯ ÂM BẰNG GIAO DỊCH BÙ ĐẮP (MIGRATION_CORRECTION)
    -- Nếu đội có số dư < 0, chèn dòng transaction migration_correction để đưa về 0, không hard-update
    FOR v_team IN SELECT id, name, light_balance FROM teams WHERE light_balance < 0 LOOP
        INSERT INTO transactions (
            client_request_id,
            team_id,
            amount,
            type,
            description,
            created_by,
            status
        ) VALUES (
            'mig-corr-' || v_team.id || '-' || extract(epoch from now())::bigint,
            v_team.id,
            ABS(v_team.light_balance),
            'admin_adjust',
            'Migration V2: Bù đắp số dư âm về 0 (migration_correction)',
            v_sys_actor,
            'approved'
        );

        UPDATE teams
        SET light_balance = 0
        WHERE id = v_team.id;
    END LOOP;

    -- 3. ĐỐI SOÁT LEDGER KHỞI ĐẦU CHO CÁC ĐỘI (INITIAL GRANT RECONCILIATION)
    -- Báo cáo Phase 0 chỉ ra: các đội khởi tạo với DEFAULT 100 Lumen nhưng thiếu dòng Ledger ban đầu.
    -- Chèn 1 dòng initial_grant (+100) cho các đội chưa có dòng giao dịch khởi đầu này để đảm bảo:
    -- light_balance == SUM(transactions.amount WHERE status = 'approved' AND is_reversed = false)
    FOR v_team IN 
        SELECT t.id, t.name, t.light_balance, COALESCE(SUM(tx.amount), 0) AS ledger_sum
        FROM teams t
        LEFT JOIN transactions tx ON tx.team_id = t.id AND tx.status = 'approved' AND tx.is_reversed = false
        GROUP BY t.id, t.name, t.light_balance
        HAVING t.light_balance <> COALESCE(SUM(tx.amount), 0)
    LOOP
        -- Kiểm tra nếu chênh lệch đúng bằng 100 Lumen khởi tạo
        IF (v_team.light_balance - v_team.ledger_sum) = 100 THEN
            INSERT INTO transactions (
                client_request_id,
                team_id,
                amount,
                type,
                description,
                created_by,
                status
            ) VALUES (
                'mig-init-grant-' || v_team.id,
                v_team.id,
                100,
                'admin_adjust',
                'Migration V2: Ghi nhận số dư khởi đầu giải đấu (initial_grant)',
                v_sys_actor,
                'approved'
            );
        END IF;
    END LOOP;

    -- 4. DỌN DẸP STAFF DUPLICATE (NẾU CÓ BẢN GHI TRÙNG LẶP DO SEED 2 LẦN)
    -- Giữ lại bản ghi có id nhỏ nhất cho mỗi (name, pin)
    DELETE FROM staff
    WHERE id NOT IN (
        SELECT MIN(id::text)::uuid
        FROM staff
        GROUP BY name, pin
    );

END $$;
