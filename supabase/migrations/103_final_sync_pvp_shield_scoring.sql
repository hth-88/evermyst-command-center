-- ============================================================================
-- MIGRATION 103: FINAL SYNC PVP SHIELD & DIRECT STATION SCORING
-- File: supabase/migrations/103_final_sync_pvp_shield_scoring.sql
-- Mục đích:
-- 1. Bổ sung shield_until cho bảng teams (nếu chưa có).
-- 2. Cập nhật use_item: Khiên +20m dồn, Master Key chặn trừ trùng kho.
-- 3. Cập nhật resolve_pvp: Chặn tự đánh mình, trừ phí mua lượt (p_attack_cost),
--    kiểm tra Khiên Màn Sương phản phệ -10 Lumen, bảo toàn điểm Defender.
-- 4. Cập nhật submit_station_claim & compute_station_points: Hỗ trợ custom_points
--    dương trực tiếp, không bị trần max_score cũ giới hạn.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. SCHEMA & BẢNG TEAM_STATION_KEYS
-- ----------------------------------------------------------------------------
ALTER TABLE public.teams ADD COLUMN IF NOT EXISTS shield_until TIMESTAMPTZ DEFAULT NULL;

CREATE TABLE IF NOT EXISTS public.team_station_keys (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    team_id UUID NOT NULL REFERENCES public.teams(id) ON DELETE CASCADE,
    station_id UUID NOT NULL REFERENCES public.stations(id) ON DELETE CASCADE,
    consumed_claim_id UUID,
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(team_id, station_id)
);

CREATE TABLE IF NOT EXISTS public.pvp_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    attacker_team_id UUID REFERENCES public.teams(id) ON DELETE CASCADE,
    defender_team_id UUID REFERENCES public.teams(id) ON DELETE CASCADE,
    result TEXT,
    stolen_amount INT DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- ----------------------------------------------------------------------------
-- 2. RPC: USE_ITEM (4 tham số lõi & 6 tham số Overload cho callRpc)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.use_item(
    p_team_id UUID,
    p_item_code TEXT,
    p_target_team_id UUID DEFAULT NULL,
    p_target_station_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_team              teams%ROWTYPE;
    v_team_item         RECORD;
    v_target_team       teams%ROWTYPE;
    v_target_station    stations%ROWTYPE;
    v_code              TEXT;
    v_new_shield_until  TIMESTAMPTZ;
    v_spy_data          JSONB;
BEGIN
    v_code := lower(trim(p_item_code));

    SELECT * INTO v_team FROM teams WHERE id = p_team_id FOR UPDATE;
    IF v_team.id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'code', 'TEAM_NOT_FOUND', 'error', 'Không tìm thấy đội chơi.');
    END IF;

    -- Tìm item trong kho team_items
    SELECT ti.id, ti.quantity, ti.used_count, i.id AS item_id, i.name, i.effect_type, i.item_code
    INTO v_team_item
    FROM team_items ti
    JOIN items i ON ti.item_id = i.id
    WHERE ti.team_id = p_team_id
      AND (
          ti.item_code = v_code
          OR lower(i.item_code) = v_code
          OR (v_code = 'shield' AND (i.effect_type = 'shield' OR i.name ILIKE '%khiên%'))
          OR (v_code IN ('spy', 'spyglass') AND (i.effect_type IN ('spy', 'spyglass') OR i.name ILIKE '%vọng tầm%'))
          OR (v_code IN ('key', 'master_key') AND (i.effect_type IN ('key', 'master_key') OR i.name ILIKE '%chìa khóa%'))
      )
      AND ti.quantity > 0
    LIMIT 1
    FOR UPDATE;

    IF v_team_item.id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'code', 'INSUFFICIENT_ITEMS', 'error', 'Đội không còn đạo cụ này trong kho!');
    END IF;

    -- XỬ LÝ THEO LOẠI ĐẠO CỤ
    IF v_code = 'shield' OR v_team_item.effect_type = 'shield' THEN
        v_new_shield_until := GREATEST(COALESCE(v_team.shield_until, now()), now()) + interval '20 minutes';

        UPDATE teams
        SET shield_until = v_new_shield_until
        WHERE id = p_team_id;

        UPDATE team_items
        SET quantity = quantity - 1,
            used_count = used_count + 1
        WHERE id = v_team_item.id;

        INSERT INTO transactions (team_id, amount, type, description, status)
        VALUES (p_team_id, 0, 'item_use', 'Kích hoạt Khiên Màn Sương (+20 phút bảo vệ)', 'approved');

        RETURN jsonb_build_object(
            'success', true,
            'item_code', 'shield',
            'shield_until', v_new_shield_until,
            'message', '🛡️ Đã kích hoạt Khiên Màn Sương! Đội được bảo vệ trong 20 phút.'
        );

    ELSIF v_code IN ('key', 'master_key') OR v_team_item.effect_type IN ('key', 'master_key') THEN
        IF p_target_station_id IS NULL THEN
            RETURN jsonb_build_object('success', false, 'code', 'MISSING_STATION', 'error', 'Vui lòng chọn trạm mục tiêu để cắm chìa khóa.');
        END IF;

        SELECT * INTO v_target_station FROM stations WHERE id = p_target_station_id;
        IF v_target_station.id IS NULL THEN
            RETURN jsonb_build_object('success', false, 'code', 'STATION_NOT_FOUND', 'error', 'Trạm mục tiêu không tồn tại.');
        END IF;

        -- KIỂM TRA TRÙNG CHÌA KHÓA TRƯỚC KHI TRỪ KHO
        IF EXISTS (
            SELECT 1 FROM team_station_keys
            WHERE team_id = p_team_id AND station_id = p_target_station_id
        ) THEN
            RETURN jsonb_build_object(
                'success', false,
                'code', 'KEY_ALREADY_EXISTS',
                'error', 'Trạm này đã được cắm Chìa Khóa Vạn Năng từ trước!'
            );
        END IF;

        -- Trừ số lượng trong kho
        UPDATE team_items
        SET quantity = quantity - 1,
            used_count = used_count + 1
        WHERE id = v_team_item.id;

        INSERT INTO team_station_keys (team_id, station_id)
        VALUES (p_team_id, p_target_station_id)
        ON CONFLICT (team_id, station_id) DO NOTHING;

        INSERT INTO transactions (team_id, amount, type, description, status)
        VALUES (p_team_id, 0, 'item_use', 'Kích hoạt Chìa Khóa Vạn Năng tại ' || v_target_station.name, 'approved');

        RETURN jsonb_build_object(
            'success', true,
            'item_code', 'master_key',
            'station_id', p_target_station_id,
            'station_name', v_target_station.name,
            'message', '🗝️ Đã cắm Chìa Khóa Vạn Năng tại ' || v_target_station.name || '!'
        );

    ELSIF v_code IN ('spy', 'spyglass') OR v_team_item.effect_type IN ('spy', 'spyglass') THEN
        IF p_target_team_id IS NULL THEN
            RETURN jsonb_build_object('success', false, 'code', 'MISSING_TARGET', 'error', 'Vui lòng chọn đội đối thủ để do thám.');
        END IF;

        SELECT * INTO v_target_team FROM teams WHERE id = p_target_team_id;
        IF v_target_team.id IS NULL THEN
            RETURN jsonb_build_object('success', false, 'code', 'TARGET_NOT_FOUND', 'error', 'Không tìm thấy đội đối thủ.');
        END IF;

        UPDATE team_items
        SET quantity = quantity - 1,
            used_count = used_count + 1
        WHERE id = v_team_item.id;

        v_spy_data := jsonb_build_object(
            'target_team_name', v_target_team.name,
            'balance', v_target_team.light_balance,
            'has_active_shield', (v_target_team.shield_until IS NOT NULL AND v_target_team.shield_until > now()),
            'shield_until', v_target_team.shield_until
        );

        INSERT INTO transactions (team_id, amount, type, description, status)
        VALUES (p_team_id, 0, 'item_use', 'Do thám ' || v_target_team.name, 'approved');

        RETURN jsonb_build_object(
            'success', true,
            'item_code', 'spyglass',
            'data', v_spy_data,
            'message', '🔭 Đã do thám thành công ' || v_target_team.name || '!'
        );
    ELSE
        UPDATE team_items
        SET quantity = quantity - 1,
            used_count = used_count + 1
        WHERE id = v_team_item.id;

        RETURN jsonb_build_object('success', true, 'message', 'Đã sử dụng đạo cụ!');
    END IF;
END;
$$;

-- Overload 6 tham số cho callRpc từ frontend
CREATE OR REPLACE FUNCTION public.use_item(
    p_token TEXT,
    p_client_request_id TEXT,
    p_team_id UUID,
    p_item_code TEXT,
    p_target_team_id UUID DEFAULT NULL,
    p_target_station_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN public.use_item(p_team_id, p_item_code, p_target_team_id, p_target_station_id);
END;
$$;

-- ----------------------------------------------------------------------------
-- 3. RPC: RESOLVE_PVP (Chặn tự đánh mình, hỗ trợ phí mua lượt p_attack_cost, phản phệ)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.resolve_pvp(
    p_attacker_id   UUID,
    p_defender_id   UUID,
    p_attack_cost   INT DEFAULT 0
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_attacker          teams%ROWTYPE;
    v_defender          teams%ROWTYPE;
    v_attacker_balance  INT;
    v_defender_balance  INT;
    v_stolen_amount     INT := 0;
    v_backlash_amount   INT := 10;
    v_is_shielded       BOOLEAN;
    v_cooldown_min      INT := 30;
    v_cooldown_until    TIMESTAMPTZ;
BEGIN
    -- 1. Chặn tự tấn công chính mình
    IF p_attacker_id = p_defender_id THEN
        RETURN jsonb_build_object(
            'success', false,
            'code', 'SELF_ATTACK_FORBIDDEN',
            'error', 'Không thể tự tấn công đội của chính mình!'
        );
    END IF;

    -- 2. Khóa dòng 2 đội theo thứ tự UUID để chống Deadlock
    IF p_attacker_id < p_defender_id THEN
        SELECT * INTO v_attacker FROM teams WHERE id = p_attacker_id FOR UPDATE;
        SELECT * INTO v_defender FROM teams WHERE id = p_defender_id FOR UPDATE;
    ELSE
        SELECT * INTO v_defender FROM teams WHERE id = p_defender_id FOR UPDATE;
        SELECT * INTO v_attacker FROM teams WHERE id = p_attacker_id FOR UPDATE;
    END IF;

    IF v_attacker.id IS NULL OR v_defender.id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'code', 'TEAM_NOT_FOUND', 'error', 'Không tìm thấy thông tin một trong hai đội.');
    END IF;

    -- 3. Kiểm tra số dư nếu có phí mua lượt tấn công
    IF p_attack_cost > 0 AND v_attacker.light_balance < p_attack_cost THEN
        RETURN jsonb_build_object(
            'success', false,
            'code', 'INSUFFICIENT_LUMEN_FOR_TURN',
            'error', 'Đội tấn công không đủ Lumen để mua lượt PvP!'
        );
    END IF;

    -- Trừ phí mua lượt nếu có
    v_attacker_balance := v_attacker.light_balance;
    IF p_attack_cost > 0 THEN
        v_attacker_balance := v_attacker_balance - p_attack_cost;
        INSERT INTO transactions (team_id, amount, type, description, status)
        VALUES (p_attacker_id, -p_attack_cost, 'pvp_attack_cost', 'Mua lượt tấn công PvP nhắm vào ' || v_defender.name, 'approved');
    END IF;

    -- 4. Kiểm tra Khiên Màn Sương của Defender
    v_is_shielded := (v_defender.shield_until IS NOT NULL AND v_defender.shield_until > now());

    IF v_is_shielded THEN
        -- Phản phệ: Trừ 10 Lumen của Attacker, Defender giữ nguyên 100%
        v_attacker_balance := GREATEST(0, v_attacker_balance - v_backlash_amount);

        UPDATE teams
        SET light_balance = v_attacker_balance
        WHERE id = p_attacker_id;

        INSERT INTO pvp_logs (attacker_team_id, defender_team_id, result, stolen_amount)
        VALUES (p_attacker_id, p_defender_id, 'backlash', 0);

        INSERT INTO transactions (team_id, amount, type, description, status)
        VALUES (p_attacker_id, -v_backlash_amount, 'pvp_backlash', 'Phạt phản phệ Khiên Màn Sương từ ' || v_defender.name || ' (-' || v_backlash_amount || ' Lumen)', 'approved');

        RETURN jsonb_build_object(
            'success', true,
            'result', 'backlash',
            'stolen_amount', 0,
            'amount_stolen', 0,
            'backlash_amount', v_backlash_amount,
            'attack_cost', p_attack_cost,
            'attacker_balance', v_attacker_balance,
            'defender_balance', v_defender.light_balance,
            'message', '🛡️ Tấn công thất bại! ' || v_defender.name || ' đang có Khiên Màn Sương. ' || v_attacker.name || ' bị phạt phản phệ -' || v_backlash_amount || '✦ Lumen!'
        );
    END IF;

    -- 5. Cướp thành công: 15% (tối thiểu 5)
    v_stolen_amount := GREATEST(5, LEAST(v_defender.light_balance, ROUND(v_defender.light_balance * 0.15)));
    v_attacker_balance := v_attacker_balance + v_stolen_amount;
    v_defender_balance := GREATEST(0, v_defender.light_balance - v_stolen_amount);

    UPDATE teams SET light_balance = v_attacker_balance WHERE id = p_attacker_id;
    UPDATE teams SET light_balance = v_defender_balance WHERE id = p_defender_id;

    v_cooldown_until := now() + (v_cooldown_min || ' minutes')::interval;

    INSERT INTO pvp_logs (attacker_team_id, defender_team_id, result, stolen_amount)
    VALUES (p_attacker_id, p_defender_id, 'success', v_stolen_amount);

    INSERT INTO transactions (team_id, amount, type, description, status)
    VALUES
        (p_attacker_id, v_stolen_amount, 'pvp_steal', 'Cướp +' || v_stolen_amount || '✦ từ ' || v_defender.name, 'approved'),
        (p_defender_id, -v_stolen_amount, 'pvp_stolen', 'Bị ' || v_attacker.name || ' cướp -' || v_stolen_amount || '✦', 'approved');

    RETURN jsonb_build_object(
        'success', true,
        'result', 'success',
        'stolen_amount', v_stolen_amount,
        'amount_stolen', v_stolen_amount,
        'attack_cost', p_attack_cost,
        'attacker_balance', v_attacker_balance,
        'defender_balance', v_defender_balance,
        'cooldown_until', v_cooldown_until,
        'message', '⚔️ Tấn công thành công! ' || v_attacker.name || ' đã cướp +' || v_stolen_amount || '✦ Lumen từ ' || v_defender.name || '!'
    );
END;
$$;

-- Overload 2 tham số (tương thích ngược)
CREATE OR REPLACE FUNCTION public.resolve_pvp(
    p_attacker_id UUID,
    p_defender_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN public.resolve_pvp(p_attacker_id, p_defender_id, 0);
END;
$$;

-- Overloads 4 và 5 tham số cho callRpc (hỗ trợ p_token, p_client_request_id, p_attack_cost)
CREATE OR REPLACE FUNCTION public.resolve_pvp(
    p_token             TEXT,
    p_client_request_id TEXT,
    p_attacker_id       UUID,
    p_defender_id       UUID,
    p_attack_cost       INT DEFAULT 0
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN public.resolve_pvp(p_attacker_id, p_defender_id, COALESCE(p_attack_cost, 0));
END;
$$;

CREATE OR REPLACE FUNCTION public.resolve_pvp(
    p_token                 TEXT,
    p_client_request_id     TEXT,
    p_attacker_team_id      UUID,
    p_defender_team_id      UUID,
    p_attack_cost           INT DEFAULT 0
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN public.resolve_pvp(p_attacker_team_id, p_defender_team_id, COALESCE(p_attack_cost, 0));
END;
$$;

-- ----------------------------------------------------------------------------
-- 4. CẬP NHẬT COMPUTE_STATION_POINTS & SUBMIT_STATION_CLAIM CHO CUSTOM_POINTS DƯƠNG
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.compute_station_points(
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

    -- Ưu tiên số 1: Điểm số dương trực tiếp (custom_points hoặc points) không giới hạn trần max_score
    IF (p_input->>'custom_points') IS NOT NULL AND (p_input->>'custom_points')::INT > 0 THEN
        RETURN (p_input->>'custom_points')::INT;
    END IF;

    IF (p_input->>'points') IS NOT NULL AND (p_input->>'points')::INT > 0 THEN
        RETURN (p_input->>'points')::INT;
    END IF;

    -- Model 1: TIER SCORING
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
            v_points := COALESCE(p_max_score, 50);
        END IF;

    -- Model 2: FIXED SCORING
    ELSIF p_scoring_type = 'fixed' THEN
        IF (p_input->>'completed')::BOOLEAN IS NOT TRUE THEN
            v_points := 0;
        ELSE
            v_points := COALESCE((p_scoring_config->>'points')::INT, p_max_score, 30);
        END IF;

    -- Model 3: TIME ATTACK
    ELSIF p_scoring_type = 'time_attack' THEN
        v_units := (p_input->>'units')::INT;
        IF v_units IS NULL OR v_units < 0 THEN
            v_units := 1;
        END IF;
        v_unit_points := COALESCE((p_scoring_config->>'unit_points')::INT, 5);
        v_points := COALESCE((p_scoring_config->>'base_points')::INT, 0) + (v_units * v_unit_points);

    ELSE
        v_points := COALESCE(p_max_score, 50);
    END IF;

    -- Ràng buộc trong ngưỡng min / max chỉ cho các model tự động cũ
    IF v_points < p_min_score THEN v_points := p_min_score; END IF;
    IF p_max_score > 0 AND v_points > p_max_score THEN v_points := p_max_score; END IF;

    RETURN v_points;
END;
$$;

-- Cập nhật submit_station_claim nhận diện custom_points
CREATE OR REPLACE FUNCTION public.submit_station_claim(
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
    -- 1. Xác thực danh tính nhân sự
    v_staff := _require_staff(p_token, ARRAY['team_support', 'station_master', 'admin']);

    -- 2. Xác định team_id
    IF v_staff.role = 'team_support' THEN
        v_team_id := v_staff.assigned_team_id;
        IF v_team_id IS NULL THEN
            RAISE EXCEPTION 'FORBIDDEN_TEAM: Nhân sự chưa được phân công đội chơi.' USING ERRCODE = 'P0005';
        END IF;
    ELSE
        IF p_team_id IS NULL THEN
            RETURN jsonb_build_object('success', false, 'code', 'TEAM_NOT_FOUND', 'error', 'Vui lòng chọn đội chơi.');
        END IF;
        v_team_id := p_team_id;

        IF v_staff.role = 'station_master' AND v_staff.assigned_station_id <> p_station_id THEN
            RETURN jsonb_build_object('success', false, 'code', 'FORBIDDEN_STATION', 'error', 'Bạn không được phân công quản lý trạm này.');
        END IF;
    END IF;

    -- 3. Idempotency theo client_request_id
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

    -- 4. Khóa đội chơi
    SELECT * INTO v_team FROM teams WHERE id = v_team_id AND is_active = true FOR UPDATE;
    IF v_team.id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'code', 'TEAM_NOT_FOUND', 'error', 'Đội chơi không tồn tại hoặc đã bị khóa.');
    END IF;

    -- 5. Kiểm tra trạm
    SELECT * INTO v_station FROM stations WHERE id = p_station_id AND is_active = true AND deleted_at IS NULL;
    IF v_station.id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'code', 'STATION_NOT_FOUND', 'error', 'Trạm thử thách không tồn tại hoặc đã đóng.');
    END IF;

    -- 6. Tính độc quyền slot
    v_is_exclusive := NOT (v_station.allow_multiple_attempts);

    IF v_is_exclusive THEN
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

    -- 7. Kiểm tra chìa khóa trạm
    SELECT EXISTS (
        SELECT 1 FROM team_station_keys
        WHERE team_id = v_team_id
          AND station_id = p_station_id
          AND consumed_claim_id IS NULL
    ) INTO v_has_key;

    -- 8. Ưu tiên custom_points hoặc points dương trực tiếp
    IF (p_input->>'custom_points') IS NOT NULL AND (p_input->>'custom_points')::INT > 0 THEN
        v_computed_points := (p_input->>'custom_points')::INT;
    ELSIF (p_input->>'points') IS NOT NULL AND (p_input->>'points')::INT > 0 THEN
        v_computed_points := (p_input->>'points')::INT;
    ELSE
        v_computed_points := compute_station_points(
            v_station.scoring_type,
            v_station.scoring_config,
            v_station.min_score,
            v_station.max_score,
            p_input
        );
    END IF;

    v_scoring_snapshot := jsonb_build_object(
        'station_id', v_station.id,
        'station_name', v_station.name,
        'scoring_type', v_station.scoring_type,
        'scoring_config', v_station.scoring_config,
        'min_score', v_station.min_score,
        'max_score', v_station.max_score
    );

    -- 9. Thẩm định ngưỡng pending_threshold
    SELECT COALESCE((value->>'v')::INT, 100) INTO v_pending_threshold
    FROM game_settings WHERE key = 'pending_threshold';
    IF v_pending_threshold IS NULL THEN v_pending_threshold := 100; END IF;

    IF v_computed_points > v_pending_threshold THEN
        v_requires_admin_review := true;
    END IF;

    -- 10. Chèn bản ghi station_claims
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

    -- 11. Nếu Quản trò / Admin chấm trực tiếp & điểm dưới ngưỡng threshold -> Tự động finalize duyệt điểm ngay
    IF v_staff.role IN ('station_master', 'admin') AND NOT v_requires_admin_review THEN
        v_final_res := _finalize_claim(v_new_claim_id);
        RETURN jsonb_build_object(
            'success', true,
            'claim_id', v_new_claim_id,
            'status', 'approved',
            'points', v_computed_points,
            'auto_finalized', true,
            'tx_id', v_final_res->>'tx_id',
            'new_balance', v_final_res->>'new_balance',
            'message', 'Đã duyệt và cộng ' || v_computed_points || '✦ Lumen cho đội chơi!'
        );
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'claim_id', v_new_claim_id,
        'status', CASE WHEN v_requires_admin_review THEN 'pending_admin' ELSE 'pending_station' END,
        'computed_points', v_computed_points,
        'is_exclusive', v_is_exclusive,
        'requires_admin_review', v_requires_admin_review,
        'message', 'Yêu cầu claim trạm đã được gửi thành công!'
    );
END;
$$;

-- Cấp quyền thực thi
GRANT EXECUTE ON FUNCTION public.use_item(UUID, TEXT, UUID, UUID) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.use_item(TEXT, TEXT, UUID, TEXT, UUID, UUID) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.resolve_pvp(UUID, UUID, INT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.resolve_pvp(UUID, UUID) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.resolve_pvp(TEXT, TEXT, UUID, UUID, INT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.resolve_pvp(TEXT, TEXT, UUID, UUID) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.resolve_pvp(TEXT, TEXT, UUID, UUID, INT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.compute_station_points(TEXT, JSONB, INT, INT, JSONB) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.submit_station_claim(TEXT, UUID, JSONB, TEXT, UUID) TO anon, authenticated;
