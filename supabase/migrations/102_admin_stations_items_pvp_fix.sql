-- ============================================================================
-- MIGRATION 102: ADMIN CRUD RPCS, STATIONS SCORING SCHEMAS & PVP LOGS
-- File: supabase/migrations/102_admin_stations_items_pvp_fix.sql
-- Idempotent: Chạy an toàn nhiều lần trên Supabase Cloud SQL Editor
-- Sửa triệt để các lỗi:
-- 1. column "scoring_type" of relation "stations" does not exist
-- 2. Could not find function public.admin_upsert_item in schema cache
-- 3. Tạo bảng pvp_logs để ghi nhật ký PvP
-- 4. Đảm bảo admin_upsert_station dùng UUID và nhận đầy đủ tham số
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ----------------------------------------------------------------------------
-- 1. TẠO BẢNG PVP_LOGS (GHI NHẬT KÝ PVP BẤT BIẾN)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS pvp_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    attacker_team_id UUID REFERENCES teams(id) ON DELETE CASCADE,
    defender_team_id UUID REFERENCES teams(id) ON DELETE CASCADE,
    result TEXT,
    stolen_amount INT DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_pvp_logs_attacker ON pvp_logs(attacker_team_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_pvp_logs_defender ON pvp_logs(defender_team_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_pvp_logs_created ON pvp_logs(created_at DESC);

ALTER TABLE pvp_logs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow All PvP Logs" ON pvp_logs;
CREATE POLICY "Allow All PvP Logs" ON pvp_logs FOR ALL USING (true) WITH CHECK (true);

-- ----------------------------------------------------------------------------
-- 2. NÂNG CẤP BẢNG STATIONS: BỔ SUNG CÁC CỘT SCORING
-- ----------------------------------------------------------------------------
ALTER TABLE stations
    ADD COLUMN IF NOT EXISTS scoring_type TEXT DEFAULT 'tier',
    ADD COLUMN IF NOT EXISTS scoring_config JSONB DEFAULT '{}'::jsonb,
    ADD COLUMN IF NOT EXISTS min_score INT DEFAULT 0,
    ADD COLUMN IF NOT EXISTS max_score INT DEFAULT 100,
    ADD COLUMN IF NOT EXISTS allow_multiple_attempts BOOLEAN DEFAULT false,
    ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ DEFAULT NULL;

ALTER TABLE stations DROP CONSTRAINT IF EXISTS chk_stations_scoring_type;
ALTER TABLE stations DROP CONSTRAINT IF EXISTS chk_stations_score_bounds;

ALTER TABLE stations
    ADD CONSTRAINT chk_stations_scoring_type 
    CHECK (scoring_type IN ('tier', 'fixed', 'time_attack'));

ALTER TABLE stations
    ADD CONSTRAINT chk_stations_score_bounds 
    CHECK (min_score >= 0 AND max_score >= min_score);

-- Backfill dữ liệu mẫu cho các trạm chưa có scoring_config
UPDATE stations
SET 
    scoring_type = COALESCE(scoring_type, 'tier'),
    scoring_config = CASE 
        WHEN scoring_config IS NULL OR scoring_config = '{}'::jsonb THEN
            jsonb_build_object(
                'tiers', jsonb_build_array(
                    jsonb_build_object('tier', 'tier_1', 'label', 'Giải mã hoàn hảo', 'points', 50),
                    jsonb_build_object('tier', 'tier_2', 'label', 'Hoàn thành tiêu chuẩn', 'points', 30),
                    jsonb_build_object('tier', 'tier_3', 'label', 'Hoàn thành trễ hạn', 'points', 15)
                )
            )
        ELSE scoring_config
    END,
    min_score = COALESCE(min_score, 0),
    max_score = COALESCE(max_score, 100),
    allow_multiple_attempts = COALESCE(allow_multiple_attempts, false)
WHERE scoring_config IS NULL OR scoring_config = '{}'::jsonb;

-- ----------------------------------------------------------------------------
-- 3. NÂNG CẤP BẢNG ITEMS: BỔ SUNG CÁC CỘT VÀ CHECK EFFECT_TYPE
-- ----------------------------------------------------------------------------
ALTER TABLE items
    ADD COLUMN IF NOT EXISTS item_code TEXT,
    ADD COLUMN IF NOT EXISTS effect_value INT DEFAULT 0,
    ADD COLUMN IF NOT EXISTS duration_minutes INT DEFAULT 0,
    ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ DEFAULT NULL;

ALTER TABLE items DROP CONSTRAINT IF EXISTS items_effect_type_check;
ALTER TABLE items DROP CONSTRAINT IF EXISTS chk_items_effect_type;

ALTER TABLE items
    ADD CONSTRAINT chk_items_effect_type 
    CHECK (effect_type IN ('shield', 'spy', 'spyglass', 'key', 'master_key', 'custom'));

-- Đồng bộ item_code cho các item hiện hữu nếu còn trống
UPDATE items 
SET item_code = CASE 
    WHEN effect_type IN ('shield') THEN 'shield'
    WHEN effect_type IN ('spy', 'spyglass') THEN 'spyglass'
    WHEN effect_type IN ('key', 'master_key') THEN 'master_key'
    ELSE COALESCE(item_code, 'custom')
END
WHERE item_code IS NULL OR item_code = '';

-- ----------------------------------------------------------------------------
-- 4. BẢNG ADMIN_AUDIT_LOG & HÀM _LOG_ADMIN_AUDIT
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS admin_audit_log (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    staff_id    UUID REFERENCES staff(id) ON DELETE SET NULL,
    action      TEXT NOT NULL,
    entity      TEXT NOT NULL,
    entity_id   TEXT,
    before      JSONB,
    after       JSONB,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE admin_audit_log ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow All Admin Audit" ON admin_audit_log;
CREATE POLICY "Allow All Admin Audit" ON admin_audit_log FOR ALL USING (true) WITH CHECK (true);

CREATE OR REPLACE FUNCTION _log_admin_audit(
    p_staff_id  UUID,
    p_action    TEXT,
    p_entity    TEXT,
    p_entity_id TEXT,
    p_before    JSONB,
    p_after     JSONB
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_log_id UUID;
BEGIN
    INSERT INTO admin_audit_log (staff_id, action, entity, entity_id, before, after)
    VALUES (p_staff_id, p_action, p_entity, p_entity_id, p_before, p_after)
    RETURNING id INTO v_log_id;
    RETURN v_log_id;
EXCEPTION WHEN OTHERS THEN
    RETURN NULL;
END;
$$;

-- ----------------------------------------------------------------------------
-- 5. RPC: ADMIN_UPSERT_STATION (HỖ TRỢ ĐẦY ĐỦ THAM SỐ VÀ UUID)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_upsert_station(
    p_allow_multiple_attempts   BOOLEAN DEFAULT false,
    p_description               TEXT DEFAULT '',
    p_id                        UUID DEFAULT NULL,
    p_is_active                 BOOLEAN DEFAULT true,
    p_max_score                 INT DEFAULT 100,
    p_min_score                 INT DEFAULT 0,
    p_name                      TEXT DEFAULT NULL,
    p_order_index               INT DEFAULT 0,
    p_scoring_config            JSONB DEFAULT '{}'::jsonb,
    p_scoring_type              TEXT DEFAULT 'tier',
    p_token                     TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_station_id    UUID;
    v_station       stations%ROWTYPE;
    v_before        JSONB;
    v_after         JSONB;
    v_action        TEXT;
BEGIN
    IF p_name IS NULL OR trim(p_name) = '' THEN
        RETURN jsonb_build_object('success', false, 'code', 'NAME_REQUIRED', 'error', 'Tên trạm không được để trống.');
    END IF;

    IF p_min_score < 0 OR p_max_score < p_min_score THEN
        RETURN jsonb_build_object('success', false, 'code', 'INVALID_SCORE_RANGE', 'error', 'Khoảng điểm không hợp lệ (min >= 0 và min <= max).');
    END IF;

    IF p_scoring_type NOT IN ('tier', 'fixed', 'time_attack') THEN
        RETURN jsonb_build_object('success', false, 'code', 'INVALID_SCORING_TYPE', 'error', 'Mô hình tính điểm không hợp lệ.');
    END IF;

    -- Kiểm tra tồn tại
    IF p_id IS NOT NULL AND EXISTS (SELECT 1 FROM public.stations WHERE id = p_id) THEN
        SELECT * INTO v_station FROM public.stations WHERE id = p_id;
        v_before := to_jsonb(v_station);
        v_action := 'UPDATE';

        UPDATE public.stations
        SET 
            name = trim(p_name),
            description = COALESCE(p_description, ''),
            scoring_type = p_scoring_type,
            scoring_config = COALESCE(p_scoring_config, '{}'::jsonb),
            min_score = p_min_score,
            max_score = p_max_score,
            is_active = COALESCE(p_is_active, true),
            allow_multiple_attempts = COALESCE(p_allow_multiple_attempts, false),
            order_index = COALESCE(p_order_index, 0),
            deleted_at = CASE WHEN p_is_active THEN NULL ELSE deleted_at END
        WHERE id = p_id
        RETURNING * INTO v_station;

        v_station_id := v_station.id;
        v_after := to_jsonb(v_station);
    ELSE
        v_before := NULL;
        v_action := 'CREATE';

        INSERT INTO public.stations (
            id, name, description, scoring_type, scoring_config,
            min_score, max_score, is_active, allow_multiple_attempts, order_index
        )
        VALUES (
            COALESCE(p_id, gen_random_uuid()),
            trim(p_name), COALESCE(p_description, ''), p_scoring_type, COALESCE(p_scoring_config, '{}'::jsonb),
            p_min_score, p_max_score, COALESCE(p_is_active, true), COALESCE(p_allow_multiple_attempts, false), COALESCE(p_order_index, 0)
        )
        RETURNING * INTO v_station;

        v_station_id := v_station.id;
        v_after := to_jsonb(v_station);
    END IF;

    PERFORM _log_admin_audit(NULL, v_action, 'stations', v_station_id::text, v_before, v_after);

    RETURN jsonb_build_object(
        'success', true,
        'message', CASE WHEN v_action = 'CREATE' THEN 'Đã tạo trạm thành công!' ELSE 'Cập nhật cấu hình trạm thành công!' END,
        'station_id', v_station_id,
        'station', v_after
    );
END;
$$;

-- ----------------------------------------------------------------------------
-- 6. RPC: ADMIN_DELETE_STATION
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_delete_station(
    p_id    UUID,
    p_token TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_station       stations%ROWTYPE;
    v_has_claims    BOOLEAN;
BEGIN
    SELECT * INTO v_station FROM public.stations WHERE id = p_id;
    IF v_station.id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'code', 'NOT_FOUND', 'error', 'Trạm không tồn tại.');
    END IF;

    -- Kiểm tra nếu trạm đã có claim -> Xóa mềm
    SELECT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'station_claims') INTO v_has_claims;
    IF v_has_claims THEN
        BEGIN
            EXECUTE 'SELECT EXISTS (SELECT 1 FROM station_claims WHERE station_id = $1)' INTO v_has_claims USING p_id;
        EXCEPTION WHEN OTHERS THEN
            v_has_claims := false;
        END;
    END IF;

    IF v_has_claims THEN
        UPDATE public.stations SET is_active = false, deleted_at = now() WHERE id = p_id;
        RETURN jsonb_build_object('success', true, 'soft_deleted', true, 'message', 'Trạm đã có lượt claim nên được vô hiệu hóa an toàn.');
    ELSE
        DELETE FROM public.stations WHERE id = p_id;
        RETURN jsonb_build_object('success', true, 'soft_deleted', false, 'message', 'Đã xóa trạm thành công.');
    END IF;
END;
$$;

-- ----------------------------------------------------------------------------
-- 7. RPC: ADMIN_UPSERT_ITEM (LƯU & SỬA ĐẠO CỤ TRONG CỬA HÀNG)
-- Khớp 100% với tham số gọi từ ItemEditorModal.tsx
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_upsert_item(
    p_description       TEXT DEFAULT '',
    p_duration_minutes  INT DEFAULT 0,
    p_effect_type       TEXT DEFAULT 'custom',
    p_effect_value      INT DEFAULT 0,
    p_id                UUID DEFAULT NULL,
    p_is_active         BOOLEAN DEFAULT true,
    p_name              TEXT DEFAULT NULL,
    p_price             INT DEFAULT 0,
    p_token             TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_item_id   UUID;
    v_item      items%ROWTYPE;
    v_before    JSONB;
    v_after     JSONB;
    v_action    TEXT;
    v_code      TEXT;
BEGIN
    IF p_name IS NULL OR trim(p_name) = '' THEN
        RETURN jsonb_build_object('success', false, 'code', 'NAME_REQUIRED', 'error', 'Tên đạo cụ không được để trống.');
    END IF;

    IF p_price IS NULL OR p_price < 0 THEN
        RETURN jsonb_build_object('success', false, 'code', 'INVALID_AMOUNT', 'error', 'Giá đạo cụ (price) phải >= 0.');
    END IF;

    IF p_effect_type NOT IN ('shield', 'spy', 'spyglass', 'key', 'master_key', 'custom') THEN
        RETURN jsonb_build_object('success', false, 'code', 'INVALID_EFFECT_TYPE', 'error', 'Loại hiệu ứng không hợp lệ.');
    END IF;

    IF p_effect_type = 'shield' AND (p_duration_minutes IS NULL OR p_duration_minutes <= 0) THEN
        RETURN jsonb_build_object('success', false, 'code', 'INVALID_DURATION', 'error', 'Thời lượng Khiên bảo vệ phải > 0 phút.');
    END IF;

    -- Chuẩn hóa mã đạo cụ
    v_code := CASE 
        WHEN p_effect_type IN ('shield') THEN 'shield'
        WHEN p_effect_type IN ('spy', 'spyglass') THEN 'spyglass'
        WHEN p_effect_type IN ('key', 'master_key') THEN 'master_key'
        ELSE 'custom'
    END;

    IF p_id IS NOT NULL AND EXISTS (SELECT 1 FROM public.items WHERE id = p_id) THEN
        SELECT * INTO v_item FROM public.items WHERE id = p_id;
        v_before := to_jsonb(v_item);
        v_action := 'UPDATE';

        UPDATE public.items
        SET 
            name = trim(p_name),
            description = COALESCE(p_description, ''),
            price = p_price,
            effect_type = p_effect_type,
            effect_value = COALESCE(p_effect_value, 0),
            duration_minutes = COALESCE(p_duration_minutes, 0),
            item_code = v_code,
            is_active = COALESCE(p_is_active, true),
            deleted_at = CASE WHEN p_is_active THEN NULL ELSE deleted_at END
        WHERE id = p_id
        RETURNING * INTO v_item;

        v_item_id := v_item.id;
        v_after := to_jsonb(v_item);
    ELSE
        v_before := NULL;
        v_action := 'CREATE';

        INSERT INTO public.items (
            id, name, description, price, effect_type, effect_value,
            duration_minutes, item_code, is_active
        )
        VALUES (
            COALESCE(p_id, gen_random_uuid()),
            trim(p_name), COALESCE(p_description, ''), p_price, p_effect_type, COALESCE(p_effect_value, 0),
            COALESCE(p_duration_minutes, 0), v_code, COALESCE(p_is_active, true)
        )
        RETURNING * INTO v_item;

        v_item_id := v_item.id;
        v_after := to_jsonb(v_item);
    END IF;

    PERFORM _log_admin_audit(NULL, v_action, 'items', v_item_id::text, v_before, v_after);

    RETURN jsonb_build_object(
        'success', true,
        'message', CASE WHEN v_action = 'CREATE' THEN 'Đã tạo đạo cụ thành công!' ELSE 'Đã cập nhật đạo cụ thành công!' END,
        'item_id', v_item_id,
        'item', v_after
    );
END;
$$;

-- ----------------------------------------------------------------------------
-- 8. RPC: ADMIN_DELETE_ITEM
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_delete_item(
    p_id    UUID,
    p_token TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_item          items%ROWTYPE;
    v_has_usages    BOOLEAN;
BEGIN
    SELECT * INTO v_item FROM public.items WHERE id = p_id;
    IF v_item.id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'code', 'NOT_FOUND', 'error', 'Đạo cụ không tồn tại.');
    END IF;

    -- Kiểm tra nếu đạo cụ đã có trong kho của đội -> Xóa mềm
    SELECT EXISTS (SELECT 1 FROM team_items WHERE item_id = p_id) INTO v_has_usages;

    IF v_has_usages THEN
        UPDATE public.items SET is_active = false, deleted_at = now() WHERE id = p_id;
        RETURN jsonb_build_object('success', true, 'soft_deleted', true, 'message', 'Đạo cụ đã được người chơi sở hữu nên được chuyển sang trạng thái ẩn (is_active = false).');
    ELSE
        DELETE FROM public.items WHERE id = p_id;
        RETURN jsonb_build_object('success', true, 'soft_deleted', false, 'message', 'Đã xóa đạo cụ thành công.');
    END IF;
END;
$$;

-- ----------------------------------------------------------------------------
-- 9. RPC: ADMIN_UPSERT_HINT & ADMIN_DELETE_HINT
-- ----------------------------------------------------------------------------
ALTER TABLE hints ADD COLUMN IF NOT EXISTS price INT DEFAULT 50;
ALTER TABLE hints ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ DEFAULT NULL;

CREATE OR REPLACE FUNCTION public.admin_upsert_hint(
    p_content       TEXT DEFAULT NULL,
    p_id            UUID DEFAULT NULL,
    p_is_active     BOOLEAN DEFAULT true,
    p_order_index   INT DEFAULT 0,
    p_price         INT DEFAULT 50,
    p_station_id    UUID DEFAULT NULL,
    p_tier          TEXT DEFAULT 'bronze',
    p_title         TEXT DEFAULT NULL,
    p_token         TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_hint_id   UUID;
    v_hint      hints%ROWTYPE;
    v_before    JSONB;
    v_after     JSONB;
    v_action    TEXT;
BEGIN
    IF p_title IS NULL OR trim(p_title) = '' THEN
        RETURN jsonb_build_object('success', false, 'code', 'TITLE_REQUIRED', 'error', 'Tiêu đề manh mối không được để trống.');
    END IF;

    IF p_content IS NULL OR trim(p_content) = '' THEN
        RETURN jsonb_build_object('success', false, 'code', 'CONTENT_REQUIRED', 'error', 'Nội dung manh mối không được để trống.');
    END IF;

    IF p_tier NOT IN ('bronze', 'silver', 'gold', 'custom') THEN
        RETURN jsonb_build_object('success', false, 'code', 'INVALID_TIER', 'error', 'Bậc manh mối không hợp lệ.');
    END IF;

    IF p_id IS NOT NULL AND EXISTS (SELECT 1 FROM public.hints WHERE id = p_id) THEN
        SELECT * INTO v_hint FROM public.hints WHERE id = p_id;
        v_before := to_jsonb(v_hint);
        v_action := 'UPDATE';

        UPDATE public.hints
        SET 
            title = trim(p_title),
            content = trim(p_content),
            tier = p_tier,
            price = COALESCE(p_price, 50),
            station_id = p_station_id,
            order_index = COALESCE(p_order_index, 0),
            is_active = COALESCE(p_is_active, true),
            deleted_at = CASE WHEN p_is_active THEN NULL ELSE deleted_at END
        WHERE id = p_id
        RETURNING * INTO v_hint;

        v_hint_id := v_hint.id;
        v_after := to_jsonb(v_hint);
    ELSE
        v_before := NULL;
        v_action := 'CREATE';

        INSERT INTO public.hints (
            id, title, content, tier, price, station_id, order_index, is_active
        )
        VALUES (
            COALESCE(p_id, gen_random_uuid()),
            trim(p_title), trim(p_content), p_tier, COALESCE(p_price, 50),
            p_station_id, COALESCE(p_order_index, 0), COALESCE(p_is_active, true)
        )
        RETURNING * INTO v_hint;

        v_hint_id := v_hint.id;
        v_after := to_jsonb(v_hint);
    END IF;

    PERFORM _log_admin_audit(NULL, v_action, 'hints', v_hint_id::text, v_before, v_after);

    RETURN jsonb_build_object(
        'success', true,
        'message', CASE WHEN v_action = 'CREATE' THEN 'Đã tạo manh mối thành công!' ELSE 'Đã cập nhật manh mối thành công!' END,
        'hint_id', v_hint_id,
        'hint', v_after
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_delete_hint(
    p_id    UUID,
    p_token TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    UPDATE public.hints SET is_active = false, deleted_at = now() WHERE id = p_id;
    RETURN jsonb_build_object('success', true, 'message', 'Đã vô hiệu hóa manh mối thành công.');
END;
$$;

-- ----------------------------------------------------------------------------
-- 10. PHÂN QUYỀN THỰC THI (GRANT) & LÀM MỚI SCHEMA CACHE
-- ----------------------------------------------------------------------------
GRANT EXECUTE ON FUNCTION public.admin_upsert_station TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_delete_station TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_upsert_item TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_delete_item TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_upsert_hint TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_delete_hint TO anon, authenticated, service_role;

-- Cập nhật quyền trên bảng
GRANT SELECT, INSERT, UPDATE, DELETE ON public.stations TO anon, authenticated, service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.items TO anon, authenticated, service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.hints TO anon, authenticated, service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.pvp_logs TO anon, authenticated, service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.admin_audit_log TO anon, authenticated, service_role;

-- Làm mới Schema Cache của Supabase PostgREST ngay lập tức
NOTIFY pgrst, 'reload schema';
