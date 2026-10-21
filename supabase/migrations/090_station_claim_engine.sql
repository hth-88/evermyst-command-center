-- ============================================================================
-- MIGRATION 090: STATION CLAIM & TWO-PHASE VERIFICATION ENGINE
-- File: supabase/migrations/090_station_claim_engine.sql
-- Mục đích: Động cơ Claim trạm (ADR-4), thẩm định 2 bước, khóa deadlock & ghi ledger
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. HÀM TÍNH TOÁN & THẨM ĐỊNH ĐIỂM SỐ TRẠM (SCORING ENGINE)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION compute_station_points(
    p_scoring_type      TEXT,
    p_scoring_config    JSONB,
    p_min_score         INT,
    p_max_score         INT,
    p_input             JSONB
)
RETURNS INT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    v_points        INT := 0;
    v_tier_item     JSONB;
    v_found_tier    BOOLEAN := false;
    v_tier_req      TEXT;
    v_units         INT;
    v_unit_points   INT;
    v_max_units     INT;
BEGIN
    IF p_input IS NULL THEN
        RAISE EXCEPTION 'INVALID_SCORING_INPUT: Input chấm điểm không được để null.' USING ERRCODE = 'P0003';
    END IF;

    -- Model 1: TIER SCORING (Ví dụ: low: 20, mid: 35, high: 50)
    IF p_scoring_type = 'tier' THEN
        v_tier_req := p_input->>'tier';
        IF v_tier_req IS NULL OR trim(v_tier_req) = '' THEN
            RAISE EXCEPTION 'INVALID_SCORING_INPUT: Thiếu thông số "tier" trong input.' USING ERRCODE = 'P0003';
        END IF;

        FOR v_tier_item IN SELECT * FROM jsonb_array_elements(COALESCE(p_scoring_config->'tiers', '[]'::jsonb)) LOOP
            IF v_tier_item->>'tier' = v_tier_req THEN
                v_points := (v_tier_item->>'points')::INT;
                v_found_tier := true;
                EXIT;
            END IF;
        END LOOP;

        IF NOT v_found_tier THEN
            RAISE EXCEPTION 'INVALID_SCORING_INPUT: Tier "%" không hợp lệ trong cấu hình trạm này.', v_tier_req USING ERRCODE = 'P0003';
        END IF;

    -- Model 2: FIXED SCORING (Điểm cố định hoặc checklist hoàn thành)
    ELSIF p_scoring_type = 'fixed' THEN
        IF (p_input->>'completed')::BOOLEAN IS NOT TRUE THEN
            v_points := 0;
        ELSE
            v_points := COALESCE((p_scoring_config->>'points')::INT, p_max_score, 30);
        END IF;

    -- Model 3: TIME ATTACK / UNIT SCORING (Tính theo số lượt / đơn vị đạt được)
    ELSIF p_scoring_type = 'time_attack' THEN
        v_units := (p_input->>'units')::INT;
        IF v_units IS NULL OR v_units < 0 THEN
            RAISE EXCEPTION 'INVALID_SCORING_INPUT: Thông số "units" không hợp lệ hoặc bị âm.' USING ERRCODE = 'P0003';
        END IF;

        v_max_units := COALESCE((p_scoring_config->>'max_units')::INT, 100);
        IF v_units > v_max_units THEN
            RAISE EXCEPTION 'INVALID_SCORING_INPUT: Số units "%" vượt quá giới hạn tối đa cho phép (%).', v_units, v_max_units USING ERRCODE = 'P0003';
        END IF;

        v_unit_points := COALESCE((p_scoring_config->>'unit_points')::INT, 5);
        v_points := COALESCE((p_scoring_config->>'base_points')::INT, 0) + (v_units * v_unit_points);

    ELSE
        RAISE EXCEPTION 'INVALID_SCORING_INPUT: Loại chấm điểm "%" không được hỗ trợ.', p_scoring_type USING ERRCODE = 'P0003';
    END IF;

    -- Ràng buộc trong ngưỡng min / max của trạm
    IF v_points < p_min_score THEN v_points := p_min_score; END IF;
    IF v_points > p_max_score THEN v_points := p_max_score; END IF;

    RETURN v_points;
END;
$$;

-- ----------------------------------------------------------------------------
-- 2. HÀM NỘI BỘ: _FINALIZE_CLAIM (CHỐT ĐIỂM, GHI LEDGER & MỞ TRẠM ATOMIC)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION _finalize_claim(
    p_claim_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_claim         station_claims%ROWTYPE;
    v_team          teams%ROWTYPE;
    v_station       stations%ROWTYPE;
    v_tx_id         UUID;
    v_client_req_id TEXT;
    v_new_balance   INT;
BEGIN
    -- 1. KHÓA THEO THỨ TỰ TOÀN CỤC: station_claims -> teams
    SELECT * INTO v_claim FROM station_claims WHERE id = p_claim_id FOR UPDATE;
    IF v_claim.id IS NULL THEN
        RAISE EXCEPTION 'CLAIM_NOT_FOUND: Không tìm thấy claim trạm.' USING ERRCODE = 'P0004';
    END IF;

    IF v_claim.status = 'approved' THEN
        RETURN jsonb_build_object('success', true, 'idempotent', true, 'tx_id', v_claim.tx_id);
    END IF;

    SELECT * INTO v_team FROM teams WHERE id = v_claim.team_id FOR UPDATE;
    SELECT * INTO v_station FROM stations WHERE id = v_claim.station_id;

    -- 2. GHI ĐÚNG 1 DÒNG SỔ CÁI LEDGER (TRANSACTIONS)
    v_client_req_id := 'claim-tx-' || v_claim.id;

    INSERT INTO transactions (
        client_request_id,
        team_id,
        amount,
        type,
        description,
        created_by,
        status,
        claim_id,
        metadata
    ) VALUES (
        v_client_req_id,
        v_claim.team_id,
        v_claim.final_points,
        'station_clear',
        'Vượt trạm ' || COALESCE(v_station.name, 'N/A') || ' (+' || v_claim.final_points || ' Lumen)',
        COALESCE(v_claim.submitted_by_role, 'station_master'),
        'approved',
        v_claim.id,
        jsonb_build_object(
            'station_id', v_claim.station_id,
            'scoring_snapshot', v_claim.scoring_snapshot,
            'input', v_claim.input,
            'key_used', v_claim.key_used
        )
    ) RETURNING id INTO v_tx_id;

    -- 3. CẬP NHẬT SỐ DƯ TEAMS & MỞ KHÓA TRẠM VÀO UNLOCKED_STATIONS
    UPDATE teams
    SET light_balance = light_balance + v_claim.final_points,
        unlocked_stations = array_append(
            array_remove(unlocked_stations, v_claim.station_id::text),
            v_claim.station_id::text
        )
    WHERE id = v_claim.team_id
    RETURNING light_balance INTO v_new_balance;

    -- 4. ĐÁNH DẤU TIÊU THỤ CHÌA KHÓA NẾU CÓ DÙNG KEY
    IF v_claim.key_used = true THEN
        UPDATE team_station_keys
        SET consumed_claim_id = v_claim.id
        WHERE team_id = v_claim.team_id
          AND station_id = v_claim.station_id
          AND consumed_claim_id IS NULL;
    END IF;

    -- 5. CẬP NHẬT TRẠNG THÁI CLAIM SANG APPROVED
    UPDATE station_claims
    SET status = 'approved',
        tx_id = v_tx_id,
        updated_at = now()
    WHERE id = v_claim.id;

    RETURN jsonb_build_object(
        'success', true,
        'claim_id', v_claim.id,
        'status', 'approved',
        'tx_id', v_tx_id,
        'final_points', v_claim.final_points,
        'new_balance', v_new_balance
    );
END;
$$;

REVOKE ALL ON FUNCTION _finalize_claim(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION _finalize_claim(UUID) FROM anon;

-- ----------------------------------------------------------------------------
-- 3. RPC: SUBMIT_STATION_CLAIM (GỬI YÊU CẦU CHẤM ĐIỂM TRẠM)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION submit_station_claim(
    p_token             TEXT,
    p_station_id        UUID,
    p_input             JSONB,
    p_client_request_id TEXT,
    p_team_id           UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_staff                 staff%ROWTYPE;
    v_team_id               UUID;
    v_station               stations%ROWTYPE;
    v_team                  teams%ROWTYPE;
    v_existing_claim        station_claims%ROWTYPE;
    v_computed_points       INT;
    v_scoring_snapshot      JSONB;
    v_is_exclusive          BOOLEAN;
    v_has_key               BOOLEAN := false;
    v_requires_admin_review BOOLEAN := false;
    v_pending_threshold     INT;
    v_new_claim_id          UUID;
    v_final_res             JSONB;
BEGIN
    -- 1. XÁC THỰC DANH TÍNH NHÂN SỰ
    v_staff := _require_staff(p_token, ARRAY['team_support', 'station_master', 'admin']);

    -- 2. XÁC ĐỊNH TEAM_ID VÀ PHÂN QUYỀN TRẠM
    IF v_staff.role = 'team_support' THEN
        -- Team Support BẮT BUỘC chỉ được submit cho đội của mình, bỏ qua p_team_id
        v_team_id := v_staff.assigned_team_id;
        IF v_team_id IS NULL THEN
            RAISE EXCEPTION 'FORBIDDEN_TEAM: Nhân sự chưa được phân công đội chơi.' USING ERRCODE = 'P0005';
        END IF;
    ELSE
        -- Admin hoặc Station Master: Sử dụng p_team_id được truyền vào
        IF p_team_id IS NULL THEN
            RETURN jsonb_build_object('success', false, 'code', 'TEAM_NOT_FOUND', 'error', 'Vui lòng chọn đội chơi.');
        END IF;
        v_team_id := p_team_id;

        -- Station Master: Bắt buộc chỉ được thao tác trạm mình phụ trách
        IF v_staff.role = 'station_master' AND v_staff.assigned_station_id <> p_station_id THEN
            RETURN jsonb_build_object('success', false, 'code', 'FORBIDDEN_STATION', 'error', 'Bạn không được phân công quản lý trạm này.');
        END IF;
    END IF;

    -- 3. IDEMPOTENCY CHECK THEO CLIENT_REQUEST_ID
    IF p_client_request_id IS NOT NULL AND trim(p_client_request_id) <> '' THEN
        SELECT * INTO v_existing_claim FROM station_claims WHERE client_request_id = trim(p_client_request_id);
        IF v_existing_claim.id IS NOT NULL THEN
            RETURN jsonb_build_object(
                'success', true,
                'idempotent', true,
                'claim_id', v_existing_claim.id,
                'status', v_existing_claim.status,
                'points', v_existing_claim.final_points,
                'message', 'Yêu cầu claim trạm đã được tiếp nhận trước đó.'
            );
        END IF;
    END IF;

    -- 4. KHÓA DÒNG ĐỘI CHƠI THEO THỨ TỰ TOÀN CỤC
    SELECT * INTO v_team FROM teams WHERE id = v_team_id AND is_active = true FOR UPDATE;
    IF v_team.id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'code', 'TEAM_NOT_FOUND', 'error', 'Đội chơi không tồn tại hoặc đã bị khóa.');
    END IF;

    -- 5. KIỂM TRA TRẠM ACTIVE
    SELECT * INTO v_station FROM stations WHERE id = p_station_id AND is_active = true AND deleted_at IS NULL;
    IF v_station.id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'code', 'STATION_NOT_FOUND', 'error', 'Trạm thử thách không tồn tại hoặc đã đóng.');
    END IF;

    -- 6. TÍNH ĐỘC QUYỀN (IS_EXCLUSIVE) & KIỂM TRA SLOT
    v_is_exclusive := NOT (v_station.allow_multiple_attempts);

    IF v_is_exclusive THEN
        -- Kiểm tra claim đang active hoặc approved
        SELECT * INTO v_existing_claim
        FROM station_claims
        WHERE team_id = v_team_id
          AND station_id = p_station_id
          AND is_exclusive = true
          AND status IN ('pending_station', 'pending_admin', 'approved')
        LIMIT 1;

        IF v_existing_claim.id IS NOT NULL THEN
            RETURN jsonb_build_object(
                'success', false,
                'code', 'CLAIM_ALREADY_EXISTS',
                'error', 'Đội này đã hoàn thành hoặc đang có yêu cầu chấm điểm trạm này.',
                'claim_id', v_existing_claim.id,
                'claim_status', v_existing_claim.status
            );
        END IF;
    END IF;

    -- 7. KIỂM TRA CHÌA KHÓA TRẠM CHƯA DÙNG
    SELECT EXISTS (
        SELECT 1 FROM team_station_keys
        WHERE team_id = v_team_id
          AND station_id = p_station_id
          AND consumed_claim_id IS NULL
    ) INTO v_has_key;

    -- 8. TÍNH ĐIỂM DỰ KIẾN TỪ CẤU HÌNH VÀ LƯU SNAPSHOT
    v_computed_points := compute_station_points(
        v_station.scoring_type,
        v_station.scoring_config,
        v_station.min_score,
        v_station.max_score,
        p_input
    );

    v_scoring_snapshot := jsonb_build_object(
        'station_id', v_station.id,
        'station_name', v_station.name,
        'scoring_type', v_station.scoring_type,
        'scoring_config', v_station.scoring_config,
        'min_score', v_station.min_score,
        'max_score', v_station.max_score
    );

    -- 9. TÍNH TOÁN REQUIRES_ADMIN_REVIEW
    SELECT COALESCE((value->>'v')::INT, 50) INTO v_pending_threshold
    FROM game_settings WHERE key = 'pending_threshold';
    IF v_pending_threshold IS NULL THEN v_pending_threshold := 50; END IF;

    IF v_computed_points > v_pending_threshold THEN
        v_requires_admin_review := true;
    END IF;

    -- 10. CHÈN BẢN GHI STATION_CLAIMS
    BEGIN
        INSERT INTO station_claims (
            team_id,
            station_id,
            status,
            input,
            original_input,
            scoring_snapshot,
            computed_points,
            final_points,
            is_exclusive,
            requires_admin_review,
            key_used,
            submitted_by,
            submitted_by_role,
            client_request_id,
            station_verified_by,
            station_verified_at
        ) VALUES (
            v_team_id,
            p_station_id,
            CASE 
                WHEN v_staff.role IN ('station_master', 'admin') AND v_requires_admin_review THEN 'pending_admin'
                WHEN v_staff.role IN ('station_master', 'admin') AND NOT v_requires_admin_review THEN 'pending_station'
                ELSE 'pending_station'
            END,
            p_input,
            p_input,
            v_scoring_snapshot,
            v_computed_points,
            v_computed_points,
            v_is_exclusive,
            v_requires_admin_review,
            v_has_key,
            v_staff.id,
            v_staff.role,
            p_client_request_id,
            CASE WHEN v_staff.role IN ('station_master', 'admin') THEN v_staff.id ELSE NULL END,
            CASE WHEN v_staff.role IN ('station_master', 'admin') THEN now() ELSE NULL END
        ) RETURNING id INTO v_new_claim_id;

    EXCEPTION WHEN unique_violation THEN
        RETURN jsonb_build_object(
            'success', false,
            'code', 'CLAIM_ALREADY_EXISTS',
            'error', 'Đội đã có yêu cầu claim trạm này đang được xử lý.'
        );
    END;

    -- 11. XỬ LÝ ĐI TIẾP NẾU DO STATION_MASTER HOẶC ADMIN NHẬP TRỰC TIẾP
    IF v_staff.role IN ('station_master', 'admin') THEN
        IF v_requires_admin_review THEN
            RETURN jsonb_build_object(
                'success', true,
                'claim_id', v_new_claim_id,
                'status', 'pending_admin',
                'points', v_computed_points,
                'message', 'Điểm vượt ngưỡng (' || v_computed_points || ' > ' || v_pending_threshold || '). Chuyển hàng chờ Admin duyệt!'
            );
        ELSE
            -- Không cần admin duyệt -> Finalize ngay lập tức
            v_final_res := _finalize_claim(v_new_claim_id);
            RETURN jsonb_build_object(
                'success', true,
                'claim_id', v_new_claim_id,
                'status', 'approved',
                'points', v_computed_points,
                'tx_id', v_final_res->>'tx_id',
                'message', 'Station Master duyệt thành công! Đã cộng +' || v_computed_points || ' Lumen.'
            );
        END IF;
    END IF;

    -- Nếu do Team Support submit -> dừng ở pending_station chờ Station Master duyệt
    RETURN jsonb_build_object(
        'success', true,
        'claim_id', v_new_claim_id,
        'status', 'pending_station',
        'points', v_computed_points,
        'key_used', v_has_key,
        'message', 'Đã gửi yêu cầu claim trạm. Vui lòng báo Station Master xác nhận!'
    );
END;
$$;

-- ----------------------------------------------------------------------------
-- 4. RPC: VERIFY_STATION_CLAIM (STATION MASTER & ADMIN XÁC MINH / PHÊ DUYỆT)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION verify_station_claim(
    p_token             TEXT,
    p_claim_id          UUID,
    p_action            TEXT, -- 'approve' | 'reject'
    p_override_input    JSONB DEFAULT NULL,
    p_note              TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_staff                 staff%ROWTYPE;
    v_claim                 station_claims%ROWTYPE;
    v_team                  teams%ROWTYPE;
    v_station               stations%ROWTYPE;
    v_recomputed_points     INT;
    v_requires_admin        BOOLEAN;
    v_pending_threshold     INT;
    v_final_res             JSONB;
BEGIN
    -- 1. XÁC THỰC
    v_staff := _require_staff(p_token, ARRAY['station_master', 'admin']);

    -- 2. KHÓA THEO THỨ TỰ TOÀN CỤC: station_claims -> teams
    SELECT * INTO v_claim FROM station_claims WHERE id = p_claim_id FOR UPDATE;
    IF v_claim.id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'code', 'CLAIM_NOT_FOUND', 'error', 'Không tìm thấy claim trạm.');
    END IF;

    SELECT * INTO v_team FROM teams WHERE id = v_claim.team_id FOR UPDATE;
    SELECT * INTO v_station FROM stations WHERE id = v_claim.station_id;

    -- 3. KIỂM TRA PHÂN QUYỀN XỬ LÝ THEO TRẠNG THÁI
    IF v_staff.role = 'station_master' THEN
        -- Station Master chỉ được duyệt trạm mình phụ trách
        IF v_staff.assigned_station_id <> v_claim.station_id THEN
            RETURN jsonb_build_object('success', false, 'code', 'FORBIDDEN_STATION', 'error', 'Bạn không phụ trách trạm này.');
        END IF;

        -- Station Master chỉ được xử lý claim ở pending_station
        IF v_claim.status <> 'pending_station' THEN
            RETURN jsonb_build_object('success', false, 'code', 'CLAIM_STATUS_INVALID', 'error', 'Claim này không ở trạng thái chờ Trạm duyệt (Hiện tại: ' || v_claim.status || ').');
        END IF;
    ELSE
        -- Admin: Được xử lý cả pending_station (force-approve) và pending_admin
        IF v_claim.status NOT IN ('pending_station', 'pending_admin') THEN
            RETURN jsonb_build_object('success', false, 'code', 'CLAIM_STATUS_INVALID', 'error', 'Claim này đã được xử lý xong (Hiện tại: ' || v_claim.status || ').');
        END IF;
    END IF;

    -- 4. XỬ LÝ REJECT (TỪ CHỐI)
    IF p_action = 'reject' THEN
        IF p_note IS NULL OR trim(p_note) = '' THEN
            RETURN jsonb_build_object('success', false, 'code', 'NOTE_REQUIRED_ON_REJECT', 'error', 'Bắt buộc phải nhập lý do khi từ chối claim.');
        END IF;

        UPDATE station_claims
        SET status = 'rejected',
            reject_reason = trim(p_note),
            updated_at = now()
        WHERE id = v_claim.id;

        RETURN jsonb_build_object('success', true, 'status', 'rejected', 'message', 'Đã từ chối claim thành công.');
    END IF;

    -- 5. XỬ LÝ APPROVE (PHÊ DUYỆT)
    IF p_action <> 'approve' THEN
        RETURN jsonb_build_object('success', false, 'code', 'INVALID_ACTION', 'error', 'Hành động không hợp lệ (chỉ approve hoặc reject).');
    END IF;

    v_requires_admin := v_claim.requires_admin_review;

    -- Kiểm tra có override input không
    IF p_override_input IS NOT NULL AND p_override_input <> '{}'::jsonb AND p_override_input <> v_claim.input THEN
        IF p_note IS NULL OR trim(p_note) = '' THEN
            RETURN jsonb_build_object('success', false, 'code', 'OVERRIDE_REQUIRES_NOTE', 'error', 'Bắt buộc phải ghi chú lý do khi chỉnh sửa điểm/input của đội.');
        END IF;

        -- TÍNH LẠI ĐIỂM TRÊN SCORING_SNAPSHOT ĐÃ LƯU (KHÔNG ĐỌC TỪ CONFIG MỚI!)
        v_recomputed_points := compute_station_points(
            v_claim.scoring_snapshot->>'scoring_type',
            v_claim.scoring_snapshot->'scoring_config',
            (v_claim.scoring_snapshot->>'min_score')::INT,
            (v_claim.scoring_snapshot->>'max_score')::INT,
            p_override_input
        );

        -- Khi có override, luôn yêu cầu Admin phê duyệt để đảm bảo minh bạch
        v_requires_admin := true;

        UPDATE station_claims
        SET original_input = v_claim.input,
            input = p_override_input,
            computed_points = v_recomputed_points,
            final_points = v_recomputed_points,
            correction_note = trim(p_note),
            requires_admin_review = true,
            updated_at = now()
        WHERE id = v_claim.id;

        v_claim.final_points := v_recomputed_points;
    END IF;

    -- Ngưỡng pending threshold
    SELECT COALESCE((value->>'v')::INT, 50) INTO v_pending_threshold
    FROM game_settings WHERE key = 'pending_threshold';
    IF v_pending_threshold IS NULL THEN v_pending_threshold := 50; END IF;

    IF v_claim.final_points > v_pending_threshold THEN
        v_requires_admin := true;
    END IF;

    -- ĐIỀU PHỐI LUỒNG TIẾP THEO
    -- Nếu Station Master duyệt nhưng claim cần Admin Review -> chuyển pending_admin
    IF v_staff.role = 'station_master' AND v_requires_admin THEN
        UPDATE station_claims
        SET status = 'pending_admin',
            station_verified_by = v_staff.id,
            station_verified_at = now(),
            requires_admin_review = true,
            updated_at = now()
        WHERE id = v_claim.id;

        RETURN jsonb_build_object(
            'success', true,
            'status', 'pending_admin',
            'message', 'Station Master đã xác nhận trạm. Do điểm cao hoặc có sửa đổi, claim đã chuyển Admin phê duyệt lần cuối!'
        );
    END IF;

    -- Nếu là Admin duyệt hoặc Station Master duyệt claim hợp lệ không cần Admin -> Finalize!
    IF v_staff.role = 'admin' THEN
        UPDATE station_claims
        SET admin_verified_by = v_staff.id,
            admin_verified_at = now(),
            updated_at = now()
        WHERE id = v_claim.id;
    ELSIF v_staff.role = 'station_master' THEN
        UPDATE station_claims
        SET station_verified_by = v_staff.id,
            station_verified_at = now(),
            updated_at = now()
        WHERE id = v_claim.id;
    END IF;

    v_final_res := _finalize_claim(v_claim.id);

    RETURN jsonb_build_object(
        'success', true,
        'status', 'approved',
        'points', v_claim.final_points,
        'tx_id', v_final_res->>'tx_id',
        'message', 'Đã phê duyệt claim thành công! Đội ' || v_team.name || ' nhận +' || v_claim.final_points || ' Lumen.'
    );
END;
$$;

-- ----------------------------------------------------------------------------
-- 5. RPC: CANCEL_STATION_CLAIM (HỦY CLAIM KHI ĐANG PENDING_STATION)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION cancel_station_claim(
    p_token     TEXT,
    p_claim_id  UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_staff staff%ROWTYPE;
    v_claim station_claims%ROWTYPE;
BEGIN
    v_staff := _require_staff(p_token, ARRAY['team_support', 'admin']);

    SELECT * INTO v_claim FROM station_claims WHERE id = p_claim_id FOR UPDATE;
    IF v_claim.id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'code', 'CLAIM_NOT_FOUND', 'error', 'Không tìm thấy claim trạm.');
    END IF;

    IF v_claim.status <> 'pending_station' THEN
        RETURN jsonb_build_object('success', false, 'code', 'CLAIM_STATUS_INVALID', 'error', 'Chỉ có thể hủy claim khi đang chờ Trạm duyệt (pending_station).');
    END IF;

    -- Team Support chỉ được hủy claim của đội mình
    IF v_staff.role = 'team_support' AND v_claim.team_id <> v_staff.assigned_team_id THEN
        RETURN jsonb_build_object('success', false, 'code', 'FORBIDDEN_TEAM', 'error', 'Bạn chỉ có thể hủy claim của đội mình phụ trách.');
    END IF;

    UPDATE station_claims
    SET status = 'cancelled',
        updated_at = now()
    WHERE id = v_claim.id;

    RETURN jsonb_build_object('success', true, 'status', 'cancelled', 'message', 'Đã hủy yêu cầu claim thành công.');
END;
$$;

-- ----------------------------------------------------------------------------
-- 6. CÁC RPC ĐỌC DỮ LIỆU CHUYÊN BIỆT THEO VAI TRÒ
-- ----------------------------------------------------------------------------

-- 6a. RPC GET_STATION_QUEUE: Hàng chờ xử lý dành riêng cho Station Master
CREATE OR REPLACE FUNCTION get_station_queue(
    p_token TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_staff         staff%ROWTYPE;
    v_station_id    UUID;
    v_station       JSONB;
    v_teams         JSONB;
    v_queue         JSONB;
    v_recent        JSONB;
BEGIN
    v_staff := _require_staff(p_token, ARRAY['station_master', 'admin']);

    v_station_id := v_staff.assigned_station_id;
    IF v_staff.role = 'admin' AND v_station_id IS NULL THEN
        -- Admin nếu không gán trạm thì xem trạm đầu tiên hoặc tất cả
        SELECT id INTO v_station_id FROM stations ORDER BY order_index LIMIT 1;
    END IF;

    -- Lấy thông tin cấu hình trạm hiện tại
    SELECT jsonb_build_object(
        'id', id,
        'name', name,
        'scoring_type', scoring_type,
        'scoring_config', scoring_config,
        'min_score', min_score,
        'max_score', max_score,
        'allow_multiple_attempts', allow_multiple_attempts
    ) INTO v_station
    FROM stations WHERE id = v_station_id;

    -- Danh sách đội chơi đang hoạt động
    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object('id', id, 'name', name) ORDER BY name ASC
        ),
        '[]'::jsonb
    ) INTO v_teams
    FROM teams WHERE is_active = true;

    -- 1. Claims đang chờ duyệt (pending_station)
    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'claim_id', c.id,
                'team_id', c.team_id,
                'team_name', t.name,
                'status', c.status,
                'input', c.input,
                'original_input', c.original_input,
                'computed_points', c.computed_points,
                'scoring_snapshot', c.scoring_snapshot,
                'key_used', c.key_used,
                'submitted_by_role', c.submitted_by_role,
                'created_at', c.created_at
            ) ORDER BY c.created_at ASC
        ),
        '[]'::jsonb
    ) INTO v_queue
    FROM station_claims c
    JOIN teams t ON t.id = c.team_id
    WHERE c.station_id = v_station_id
      AND c.status = 'pending_station';

    -- 2. 5 claims vừa xử lý gần nhất (approved/rejected/pending_admin)
    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'claim_id', c.id,
                'team_name', t.name,
                'status', c.status,
                'final_points', c.final_points,
                'reject_reason', c.reject_reason,
                'correction_note', c.correction_note,
                'updated_at', c.updated_at
            ) ORDER BY c.updated_at DESC
        ),
        '[]'::jsonb
    ) INTO v_recent
    FROM (
        SELECT * FROM station_claims
        WHERE station_id = v_station_id
          AND status IN ('approved', 'rejected', 'pending_admin')
        ORDER BY updated_at DESC
        LIMIT 5
    ) c
    JOIN teams t ON t.id = c.team_id;

    RETURN jsonb_build_object(
        'success', true,
        'station_id', v_station_id,
        'station', v_station,
        'teams', v_teams,
        'queue', v_queue,
        'recent_processed', v_recent
    );
END;
$$;

-- 6b. RPC GET_TEAM_STATION_STATUS: Bảng trạng thái cả 5 trạm cho Team Support
CREATE OR REPLACE FUNCTION get_team_station_status(
    p_token TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_staff     staff%ROWTYPE;
    v_team_id   UUID;
    v_result    JSONB;
BEGIN
    v_staff := _require_staff(p_token, ARRAY['team_support', 'admin']);

    v_team_id := v_staff.assigned_team_id;
    IF v_staff.role = 'admin' AND v_team_id IS NULL THEN
        SELECT id INTO v_team_id FROM teams ORDER BY created_at LIMIT 1;
    END IF;

    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'station_id', s.id,
                'station_name', s.name,
                'order_index', s.order_index,
                'scoring_type', s.scoring_type,
                'scoring_config', s.scoring_config,
                'allow_multiple_attempts', s.allow_multiple_attempts,
                'has_key', EXISTS (
                    SELECT 1 FROM team_station_keys k
                    WHERE k.team_id = v_team_id 
                      AND k.station_id = s.id 
                      AND k.consumed_claim_id IS NULL
                ),
                'active_claim', (
                    SELECT jsonb_build_object(
                        'id', c.id,
                        'status', c.status,
                        'points', c.final_points,
                        'created_at', c.created_at
                    )
                    FROM station_claims c
                    WHERE c.team_id = v_team_id 
                      AND c.station_id = s.id
                      AND c.status IN ('draft', 'pending_station', 'pending_admin', 'approved')
                    ORDER BY c.created_at DESC
                    LIMIT 1
                )
            ) ORDER BY s.order_index ASC
        ),
        '[]'::jsonb
    ) INTO v_result
    FROM stations s
    WHERE s.deleted_at IS NULL AND s.is_active = true;

    RETURN jsonb_build_object(
        'success', true,
        'team_id', v_team_id,
        'stations', v_result
    );
END;
$$;

-- 6c. RPC ADMIN_LIST_CLAIMS: Toàn bộ hàng chờ duyệt dành cho Admin
CREATE OR REPLACE FUNCTION admin_list_claims(
    p_token     TEXT,
    p_status    TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_admin staff%ROWTYPE;
    v_list  JSONB;
BEGIN
    v_admin := _require_staff(p_token, ARRAY['admin']);

    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'claim_id', c.id,
                'team_id', c.team_id,
                'team_name', t.name,
                'station_id', c.station_id,
                'station_name', s.name,
                'status', c.status,
                'input', c.input,
                'original_input', c.original_input,
                'computed_points', c.computed_points,
                'final_points', c.final_points,
                'key_used', c.key_used,
                'requires_admin_review', c.requires_admin_review,
                'correction_note', c.correction_note,
                'reject_reason', c.reject_reason,
                'submitted_by_role', c.submitted_by_role,
                'created_at', c.created_at,
                'updated_at', c.updated_at
            ) ORDER BY c.created_at DESC
        ),
        '[]'::jsonb
    ) INTO v_list
    FROM station_claims c
    JOIN teams t ON t.id = c.team_id
    JOIN stations s ON s.id = c.station_id
    WHERE (p_status IS NULL OR c.status = p_status);

    RETURN jsonb_build_object(
        'success', true,
        'claims', v_list
    );
END;
$$;

-- ----------------------------------------------------------------------------
-- 7. PHÂN QUYỀN EXECUTE PUBLIC RPCS
-- ----------------------------------------------------------------------------
REVOKE ALL ON FUNCTION submit_station_claim(TEXT, UUID, JSONB, TEXT, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION submit_station_claim(TEXT, UUID, JSONB, TEXT, UUID) TO anon, authenticated;

REVOKE ALL ON FUNCTION verify_station_claim(TEXT, UUID, TEXT, JSONB, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION verify_station_claim(TEXT, UUID, TEXT, JSONB, TEXT) TO anon, authenticated;

REVOKE ALL ON FUNCTION cancel_station_claim(TEXT, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION cancel_station_claim(TEXT, UUID) TO anon, authenticated;

REVOKE ALL ON FUNCTION get_station_queue(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_station_queue(TEXT) TO anon, authenticated;

REVOKE ALL ON FUNCTION get_team_station_status(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_team_station_status(TEXT) TO anon, authenticated;

REVOKE ALL ON FUNCTION admin_list_claims(TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION admin_list_claims(TEXT, TEXT) TO anon, authenticated;
