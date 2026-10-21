-- ============================================================================
-- MIGRATION 103: HOTFIX TIER CONFIG, KEY BINDING & PVP SYNCHRONIZATION
-- File: supabase/migrations/103_hotfix_tier_key_pvp_sync.sql
-- Idempotent: Chạy an toàn nhiều lần trên Supabase Cloud SQL Editor
-- 1. Đảm bảo schema & backfill tiers chuẩn cho stations và teams.shield_until
-- 2. Sửa use_item: Chặn trừ kho khi trạm đã cắm chìa khóa & hỗ trợ overload 6 tham số
-- 3. Sửa resolve_pvp: Tôn trọng tham số truyền vào, xóa logic ép attacker cũ, hỗ trợ overload 4 tham số
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ----------------------------------------------------------------------------
-- 1. ĐẢM BẢO SCHEMA & BACKFILL TIERS CHO STATIONS VÀ TEAMS
-- ----------------------------------------------------------------------------
ALTER TABLE teams
    ADD COLUMN IF NOT EXISTS shield_until TIMESTAMPTZ DEFAULT NULL;

ALTER TABLE stations
    ADD COLUMN IF NOT EXISTS scoring_type TEXT DEFAULT 'tier',
    ADD COLUMN IF NOT EXISTS scoring_config JSONB DEFAULT '{}'::jsonb;

-- Backfill toàn bộ trạm có scoring_type = 'tier' mà scoring_config rỗng hoặc thiếu tiers
UPDATE stations
SET scoring_config = jsonb_build_object(
    'tiers', jsonb_build_array(
        jsonb_build_object('tier', 'tier_1', 'label', 'Giải mã hoàn hảo', 'points', 50),
        jsonb_build_object('tier', 'tier_2', 'label', 'Hoàn thành tiêu chuẩn', 'points', 30),
        jsonb_build_object('tier', 'tier_3', 'label', 'Hoàn thành trễ hạn', 'points', 15)
    )
)
WHERE scoring_type = 'tier' 
  AND (
      scoring_config IS NULL 
      OR scoring_config = '{}'::jsonb 
      OR NOT (scoring_config ? 'tiers') 
      OR jsonb_array_length(COALESCE(scoring_config->'tiers', '[]'::jsonb)) = 0
  );

-- Đảm bảo bảng team_station_keys có ràng buộc UNIQUE (team_id, station_id)
CREATE TABLE IF NOT EXISTS team_station_keys (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    team_id             UUID NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
    station_id          UUID NOT NULL REFERENCES stations(id) ON DELETE CASCADE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_team_station_key UNIQUE (team_id, station_id)
);
CREATE INDEX IF NOT EXISTS idx_team_station_keys_team ON team_station_keys(team_id);
CREATE INDEX IF NOT EXISTS idx_team_station_keys_station ON team_station_keys(station_id);

ALTER TABLE team_station_keys ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow All Team Station Keys" ON team_station_keys;
CREATE POLICY "Allow All Team Station Keys" ON team_station_keys FOR ALL USING (true) WITH CHECK (true);

-- ----------------------------------------------------------------------------
-- 2. SỬA RPC USE_ITEM: KIỂM TRA TRÙNG CHÌA KHÓA TRƯỚC KHI TRỪ KHO
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.use_item(
    p_team_id           UUID,
    p_item_code         TEXT,
    p_target_team_id    UUID DEFAULT NULL,
    p_target_station_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_item              RECORD;
    v_inventory         RECORD;
    v_target_team       RECORD;
    v_target_station    RECORD;
    v_new_shield_until  TIMESTAMPTZ;
    v_has_active_shield BOOLEAN;
    v_already_keyed     BOOLEAN;
BEGIN
    -- 1. Tìm item theo item_code hoặc id hoặc effect_type
    SELECT * INTO v_item 
    FROM items 
    WHERE (item_code = p_item_code OR id::text = p_item_code OR effect_type = p_item_code)
      AND is_active = true
    LIMIT 1;

    IF v_item.id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'code', 'ITEM_NOT_FOUND', 'error', 'Không tìm thấy đạo cụ trong hệ thống.');
    END IF;

    -- 2. Kiểm tra số lượng trong kho
    SELECT * INTO v_inventory 
    FROM team_items 
    WHERE team_id = p_team_id AND item_id = v_item.id AND quantity > 0
    FOR UPDATE;

    IF v_inventory.id IS NULL OR v_inventory.quantity <= 0 THEN
        RETURN jsonb_build_object(
            'success', false, 
            'code', 'ITEM_NOT_OWNED', 
            'error', 'Đội không còn ' || v_item.name || ' trong kho đồ!'
        );
    END IF;

    -- 3. Xử lý nghiệp vụ theo loại đạo cụ TRƯỚC KHI TRỪ KHO
    IF v_item.effect_type = 'shield' THEN
        -- Tính thời lượng khiên mới
        v_new_shield_until := GREATEST(COALESCE((SELECT shield_until FROM teams WHERE id = p_team_id), now()), now()) + (COALESCE(v_item.duration_minutes, 20) || ' minutes')::INTERVAL;
        
        -- Trừ 1 số lượng trong kho
        UPDATE team_items
        SET quantity = quantity - 1,
            used_count = used_count + 1,
            updated_at = now()
        WHERE id = v_inventory.id;

        -- Bật Khiên Màn Sương
        UPDATE teams
        SET shield_until = v_new_shield_until
        WHERE id = p_team_id;

        INSERT INTO transactions (team_id, amount, type, description, created_by, status)
        VALUES (
            p_team_id, 0, 'buy_item',
            'Sử dụng Khiên Màn Sương (+20 phút bảo vệ)',
            'Support', 'approved'
        );

        RETURN jsonb_build_object(
            'success', true,
            'item_code', 'shield',
            'shield_until', v_new_shield_until,
            'message', '🛡️ Đã kích hoạt Khiên Màn Sương! Đội được bảo vệ an toàn trong 20 phút.'
        );

    ELSIF v_item.effect_type IN ('spy', 'spyglass') THEN
        IF p_target_team_id IS NULL OR p_target_team_id = p_team_id THEN
            RETURN jsonb_build_object('success', false, 'code', 'TARGET_REQUIRED', 'error', 'Vui lòng chọn một đội đối thủ để do thám.');
        END IF;

        SELECT * INTO v_target_team FROM teams WHERE id = p_target_team_id;
        IF v_target_team.id IS NULL THEN
            RETURN jsonb_build_object('success', false, 'code', 'TARGET_NOT_FOUND', 'error', 'Đội đối thủ không tồn tại.');
        END IF;

        -- Trừ 1 số lượng trong kho
        UPDATE team_items
        SET quantity = quantity - 1,
            used_count = used_count + 1,
            updated_at = now()
        WHERE id = v_inventory.id;

        v_has_active_shield := (v_target_team.shield_until IS NOT NULL AND v_target_team.shield_until > now());

        INSERT INTO transactions (team_id, amount, type, description, created_by, status)
        VALUES (
            p_team_id, 0, 'buy_item',
            'Sử dụng Kính Vọng Tầm soi ' || v_target_team.name,
            'Support', 'approved'
        );

        RETURN jsonb_build_object(
            'success', true,
            'item_code', 'spyglass',
            'target_team_name', v_target_team.name,
            'balance', v_target_team.light_balance,
            'has_active_shield', v_has_active_shield,
            'shield_until', v_target_team.shield_until,
            'message', '🔭 Đã do thám thành công ' || v_target_team.name || '!'
        );

    ELSIF v_item.effect_type IN ('key', 'master_key') THEN
        IF p_target_station_id IS NULL THEN
            RETURN jsonb_build_object('success', false, 'code', 'STATION_REQUIRED', 'error', 'Vui lòng chọn trạm mục tiêu để cắm Chìa Khóa Vạn Năng.');
        END IF;

        SELECT * INTO v_target_station FROM stations WHERE id = p_target_station_id AND is_active = true;
        IF v_target_station.id IS NULL THEN
            RETURN jsonb_build_object('success', false, 'code', 'STATION_NOT_FOUND', 'error', 'Trạm mục tiêu không tồn tại hoặc đã đóng.');
        END IF;

        -- KIỂM TRA TRÙNG CHÌA KHÓA TRƯỚC KHI TRỪ VẬT PHẨM TRONG KHO!
        SELECT EXISTS (
            SELECT 1 FROM team_station_keys 
            WHERE team_id = p_team_id AND station_id = p_target_station_id
        ) INTO v_already_keyed;

        IF v_already_keyed THEN
            RETURN jsonb_build_object(
                'success', false, 
                'code', 'KEY_ALREADY_EXISTS', 
                'error', 'Trạm này đã được cắm Chìa Khóa Vạn Năng từ trước!'
            );
        END IF;

        -- Trừ 1 số lượng trong kho
        UPDATE team_items
        SET quantity = quantity - 1,
            used_count = used_count + 1,
            updated_at = now()
        WHERE id = v_inventory.id;

        -- Ghi nhận khóa vào bảng team_station_keys
        INSERT INTO team_station_keys (team_id, station_id)
        VALUES (p_team_id, p_target_station_id)
        ON CONFLICT (team_id, station_id) DO NOTHING;

        INSERT INTO transactions (team_id, amount, type, description, created_by, status)
        VALUES (
            p_team_id, 0, 'buy_item',
            'Kích hoạt Chìa Khóa Vạn Năng tại ' || v_target_station.name,
            'Support', 'approved'
        );

        RETURN jsonb_build_object(
            'success', true,
            'item_code', 'master_key',
            'station_id', p_target_station_id,
            'station_name', v_target_station.name,
            'message', '🗝️ Đã kích hoạt Chìa Khóa Vạn Năng tại ' || v_target_station.name || '!'
        );

    ELSE
        -- Đạo cụ khác
        UPDATE team_items
        SET quantity = quantity - 1,
            used_count = used_count + 1,
            updated_at = now()
        WHERE id = v_inventory.id;

        RETURN jsonb_build_object('success', true, 'message', 'Đã sử dụng ' || v_item.name);
    END IF;
END;
$$;

-- Overload nhận đủ 6 tham số khớp với callRpc từ Frontend
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
-- 3. SỬA RPC RESOLVE_PVP: TÔN TRỌNG THAM SỐ VÀ PHẢN PHỆ KHI CÓ KHIÊN
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.resolve_pvp(
    p_attacker_id UUID,
    p_defender_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_attacker RECORD;
    v_defender RECORD;
    v_is_shielded BOOLEAN;
    v_steal_amount INT;
    v_backlash_amount INT := 10;
BEGIN
    IF p_attacker_id = p_defender_id THEN
        RETURN jsonb_build_object('success', false, 'code', 'PVP_SAME_TEAM', 'error', 'Không thể tấn công chính đội mình.');
    END IF;

    -- Deadlock-free locking: khóa dòng theo thứ tự UUID
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

    -- Kiểm tra Khiên bảo vệ của bên phòng thủ
    v_is_shielded := (v_defender.shield_until IS NOT NULL AND v_defender.shield_until > now());

    IF v_is_shielded THEN
        -- BỊ PHẢN PHỆ: Kẻ tấn công bị trừ 10 Lumen, bên phòng thủ được bảo vệ toàn vẹn
        UPDATE teams 
        SET light_balance = GREATEST(0, light_balance - v_backlash_amount) 
        WHERE id = p_attacker_id;

        INSERT INTO transactions (team_id, amount, type, description, created_by, status)
        VALUES (
            p_attacker_id, -v_backlash_amount, 'pvp_backlash',
            'Phản phệ PvP khi tấn công ' || v_defender.name || ' đang có Khiên Màn Sương',
            'Support', 'approved'
        );

        INSERT INTO pvp_logs (attacker_team_id, defender_team_id, result, stolen_amount, created_at)
        VALUES (p_attacker_id, p_defender_id, 'backlash', 0, now());

        RETURN jsonb_build_object(
            'success', true,
            'result', 'backlash',
            'message', '🛡️ Tấn công thất bại! ' || v_defender.name || ' đang bật Khiên Màn Sương. ' || v_attacker.name || ' bị phạt phản phệ -' || v_backlash_amount || ' Lumen!',
            'stolen_amount', 0,
            'backlash_amount', v_backlash_amount,
            'attacker_balance', GREATEST(0, v_attacker.light_balance - v_backlash_amount),
            'defender_balance', v_defender.light_balance
        );
    END IF;

    -- Tấn công thành công: Cướp 15% số dư của bên phòng thủ (tối thiểu 5, tối đa số dư của defender)
    v_steal_amount := GREATEST(5, LEAST(v_defender.light_balance, ROUND(v_defender.light_balance * 0.15)::INT));
    IF v_defender.light_balance <= 0 THEN
        v_steal_amount := 0;
    END IF;

    IF v_steal_amount > 0 THEN
        UPDATE teams SET light_balance = light_balance - v_steal_amount WHERE id = p_defender_id;
        UPDATE teams SET light_balance = light_balance + v_steal_amount WHERE id = p_attacker_id;

        INSERT INTO transactions (team_id, amount, type, description, created_by, status)
        VALUES 
            (p_defender_id, -v_steal_amount, 'pvp_loss', 'Bị ' || v_attacker.name || ' cướp ' || v_steal_amount || ' Lumen', 'Support', 'approved'),
            (p_attacker_id, v_steal_amount, 'pvp_win', 'Cướp thành công ' || v_steal_amount || ' Lumen từ ' || v_defender.name, 'Support', 'approved');
    END IF;

    INSERT INTO pvp_logs (attacker_team_id, defender_team_id, result, stolen_amount, created_at)
    VALUES (p_attacker_id, p_defender_id, 'attacker_win', v_steal_amount, now());

    RETURN jsonb_build_object(
        'success', true,
        'result', 'attacker_win',
        'message', '⚔️ Tấn công thành công! ' || v_attacker.name || ' đã cướp ' || v_steal_amount || ' Lumen từ ' || v_defender.name || '!',
        'stolen_amount', v_steal_amount,
        'attacker_balance', v_attacker.light_balance + v_steal_amount,
        'defender_balance', v_defender.light_balance - v_steal_amount
    );
END;
$$;

-- Overload 4 tham số khớp với callRpc dạng (p_attacker_id, p_defender_id)
CREATE OR REPLACE FUNCTION public.resolve_pvp(
    p_token TEXT,
    p_client_request_id TEXT,
    p_attacker_id UUID,
    p_defender_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN public.resolve_pvp(p_attacker_id, p_defender_id);
END;
$$;

-- Overload 4 tham số dạng (p_attacker_team_id, p_defender_team_id)
CREATE OR REPLACE FUNCTION public.resolve_pvp(
    p_token TEXT,
    p_client_request_id TEXT,
    p_attacker_team_id UUID,
    p_defender_team_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN public.resolve_pvp(p_attacker_team_id, p_defender_team_id);
END;
$$;

-- Cấp quyền thực thi
GRANT EXECUTE ON FUNCTION public.use_item TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.resolve_pvp TO anon, authenticated, service_role;

-- Cập nhật Schema Cache
NOTIFY pgrst, 'reload schema';
