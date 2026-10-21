-- ============================================================================
-- MIGRATION 080: ADMIN AUDIT LOG & COMPREHENSIVE ADMIN CRUD RPCs
-- File: supabase/migrations/080_admin_audit.sql
-- Mục đích: Bảng audit toàn diện & RPCs cấu hình toàn bộ game không cần deploy (Phase 5)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. BẢNG ADMIN_AUDIT_LOG & CHỈ MỤC
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS admin_audit_log (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    staff_id    UUID REFERENCES staff(id) ON DELETE SET NULL,
    action      TEXT NOT NULL, -- 'CREATE', 'UPDATE', 'DELETE', 'SOFT_DELETE'
    entity      TEXT NOT NULL, -- 'stations', 'hints', 'items', 'staff', 'game_settings'
    entity_id   TEXT,
    before      JSONB,
    after       JSONB,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_admin_audit_staff ON admin_audit_log(staff_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_admin_audit_entity ON admin_audit_log(entity, entity_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_admin_audit_created ON admin_audit_log(created_at DESC);

ALTER TABLE admin_audit_log ENABLE ROW LEVEL SECURITY;

-- Hàm nội bộ ghi log audit admin
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
SET search_path = public, pg_temp
AS $$
DECLARE
    v_log_id UUID;
BEGIN
    INSERT INTO admin_audit_log (staff_id, action, entity, entity_id, before, after)
    VALUES (p_staff_id, p_action, p_entity, p_entity_id, p_before, p_after)
    RETURNING id INTO v_log_id;
    RETURN v_log_id;
END;
$$;

REVOKE ALL ON FUNCTION _log_admin_audit(UUID, TEXT, TEXT, TEXT, JSONB, JSONB) FROM PUBLIC;
REVOKE ALL ON FUNCTION _log_admin_audit(UUID, TEXT, TEXT, TEXT, JSONB, JSONB) FROM anon;

-- Hàm nội bộ: kiểm tra tính duy nhất của mã PIN giữa các staff đang active
CREATE OR REPLACE FUNCTION _check_pin_unique(
    p_pin               TEXT,
    p_exclude_staff_id  UUID DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN 
        SELECT id, pin_hash 
        FROM staff 
        WHERE is_active = true 
          AND (p_exclude_staff_id IS NULL OR id <> p_exclude_staff_id)
          AND pin_hash IS NOT NULL
    LOOP
        IF r.pin_hash = crypt(p_pin, r.pin_hash) THEN
            RETURN false;
        END IF;
    END LOOP;
    RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION _check_pin_unique(TEXT, UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION _check_pin_unique(TEXT, UUID) FROM anon;

-- ----------------------------------------------------------------------------
-- 2. HÀM THẨM ĐỊNH SCORING CONFIG: VALIDATE_SCORING_CONFIG
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION validate_scoring_config(
    p_type      TEXT,
    p_config    JSONB,
    p_min       INT,
    p_max       INT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    v_tier_item     JSONB;
    v_tier_name     TEXT;
    v_tier_pts      INT;
    v_tier_count    INT := 0;
BEGIN
    -- 1. Kiểm tra type
    IF p_type NOT IN ('tier', 'fixed', 'time_attack') THEN
        RAISE EXCEPTION 'INVALID_SCORING_TYPE: Kiểu chấm điểm "%" không hợp lệ (chỉ nhận tier, fixed, time_attack).', p_type 
            USING ERRCODE = 'P0003';
    END IF;

    -- 2. Kiểm tra biên điểm
    IF p_min < 0 OR p_max < p_min THEN
        RAISE EXCEPTION 'INVALID_SCORE_RANGE: Khoảng điểm [%, %] không hợp lệ (min >= 0 và min <= max).', p_min, p_max 
            USING ERRCODE = 'P0003';
    END IF;

    -- 3. Thẩm định chi tiết theo từng type
    IF p_type = 'tier' THEN
        IF p_config IS NULL OR jsonb_typeof(p_config->'tiers') <> 'array' THEN
            RAISE EXCEPTION 'INVALID_SCORING_CONFIG: Cấu hình "tier" bắt buộc phải có mảng "tiers".' 
                USING ERRCODE = 'P0003';
        END IF;

        FOR v_tier_item IN SELECT * FROM jsonb_array_elements(p_config->'tiers') LOOP
            v_tier_count := v_tier_count + 1;
            v_tier_name := v_tier_item->>'tier';
            v_tier_pts := (v_tier_item->>'points')::INT;

            IF v_tier_name IS NULL OR trim(v_tier_name) = '' THEN
                RAISE EXCEPTION 'INVALID_SCORING_CONFIG: Tên tier không được để trống.' USING ERRCODE = 'P0003';
            END IF;

            IF v_tier_pts IS NULL OR v_tier_pts < p_min OR v_tier_pts > p_max THEN
                RAISE EXCEPTION 'INVALID_SCORING_CONFIG: Điểm của tier "%" (%) nằm ngoài khoảng cho phép [%, %].', v_tier_name, v_tier_pts, p_min, p_max 
                    USING ERRCODE = 'P0003';
            END IF;
        END LOOP;

        IF v_tier_count = 0 THEN
            RAISE EXCEPTION 'INVALID_SCORING_CONFIG: Mảng "tiers" phải có ít nhất 1 mức điểm.' USING ERRCODE = 'P0003';
        END IF;

    ELSIF p_type = 'fixed' THEN
        IF p_config IS NOT NULL AND p_config ? 'points' THEN
            IF (p_config->>'points')::INT < p_min OR (p_config->>'points')::INT > p_max THEN
                RAISE EXCEPTION 'INVALID_SCORING_CONFIG: Điểm cố định (%) phải nằm trong khoảng [%, %].', (p_config->>'points')::INT, p_min, p_max 
                    USING ERRCODE = 'P0003';
            END IF;
        END IF;

    ELSIF p_type = 'time_attack' THEN
        IF p_config IS NULL THEN
            RAISE EXCEPTION 'INVALID_SCORING_CONFIG: Cấu hình time_attack không được để null.' USING ERRCODE = 'P0003';
        END IF;

        IF (p_config->>'unit_points')::INT IS NOT NULL AND (p_config->>'unit_points')::INT <= 0 THEN
            RAISE EXCEPTION 'INVALID_SCORING_CONFIG: unit_points phải lớn hơn 0.' USING ERRCODE = 'P0003';
        END IF;

        IF (p_config->>'max_units')::INT IS NOT NULL AND (p_config->>'max_units')::INT <= 0 THEN
            RAISE EXCEPTION 'INVALID_SCORING_CONFIG: max_units phải lớn hơn 0.' USING ERRCODE = 'P0003';
        END IF;
    END IF;

    RETURN true;
END;
$$;

-- ----------------------------------------------------------------------------
-- 3. RPC: ADMIN_UPSERT_STATION & ADMIN_DELETE_STATION
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION admin_upsert_station(
    p_token                     TEXT,
    p_id                        UUID DEFAULT NULL,
    p_name                      TEXT DEFAULT NULL,
    p_description               TEXT DEFAULT '',
    p_order_index               INT DEFAULT 0,
    p_is_active                 BOOLEAN DEFAULT true,
    p_scoring_type              TEXT DEFAULT 'tier',
    p_scoring_config            JSONB DEFAULT '{}'::jsonb,
    p_min_score                 INT DEFAULT 0,
    p_max_score                 INT DEFAULT 50,
    p_allow_multiple_attempts   BOOLEAN DEFAULT false
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_admin     staff%ROWTYPE;
    v_station   stations%ROWTYPE;
    v_before    JSONB;
    v_after     JSONB;
    v_action    TEXT;
BEGIN
    -- 1. Phân quyền: Chỉ admin
    v_admin := _require_staff(p_token, ARRAY['admin']);

    -- 2. Validate input cơ bản
    IF p_name IS NULL OR trim(p_name) = '' THEN
        RETURN jsonb_build_object('success', false, 'code', 'NAME_REQUIRED', 'error', 'Tên trạm không được để trống.');
    END IF;

    -- 3. Validate scoring config bằng validate_scoring_config & min <= max
    BEGIN
        PERFORM validate_scoring_config(p_scoring_type, p_scoring_config, p_min_score, p_max_score);
    EXCEPTION WHEN OTHERS THEN
        RETURN jsonb_build_object('success', false, 'code', 'INVALID_SCORING_CONFIG', 'error', SQLERRM);
    END IF;

    -- 4. Thực thi Update hoặc Insert
    IF p_id IS NOT NULL THEN
        SELECT * INTO v_station FROM stations WHERE id = p_id;
        IF v_station.id IS NULL THEN
            RETURN jsonb_build_object('success', false, 'code', 'NOT_FOUND', 'error', 'Không tìm thấy trạm cần chỉnh sửa.');
        END IF;

        v_before := to_jsonb(v_station);
        v_action := 'UPDATE';

        -- Cập nhật: Sửa rule chỉ ảnh hưởng claim mới (claim cũ đã lưu snapshot)
        -- allow_multiple_attempts chỉ có hiệu lực với claim mới
        UPDATE stations
        SET name = trim(p_name),
            description = COALESCE(p_description, description),
            order_index = COALESCE(p_order_index, order_index),
            is_active = COALESCE(p_is_active, is_active),
            scoring_type = p_scoring_type,
            scoring_config = p_scoring_config,
            min_score = p_min_score,
            max_score = p_max_score,
            allow_multiple_attempts = COALESCE(p_allow_multiple_attempts, false),
            deleted_at = CASE WHEN p_is_active THEN NULL ELSE deleted_at END
        WHERE id = p_id
        RETURNING * INTO v_station;

        v_after := to_jsonb(v_station);
    ELSE
        v_before := NULL;
        v_action := 'CREATE';

        INSERT INTO stations (
            name, description, order_index, is_active,
            scoring_type, scoring_config, min_score, max_score,
            allow_multiple_attempts
        ) VALUES (
            trim(p_name), COALESCE(p_description, ''), COALESCE(p_order_index, 0), COALESCE(p_is_active, true),
            p_scoring_type, p_scoring_config, p_min_score, p_max_score,
            COALESCE(p_allow_multiple_attempts, false)
        ) RETURNING * INTO v_station;

        v_after := to_jsonb(v_station);
    END IF;

    -- 5. Ghi audit log
    PERFORM _log_admin_audit(v_admin.id, v_action, 'stations', v_station.id::text, v_before, v_after);

    RETURN jsonb_build_object(
        'success', true,
        'station', v_after,
        'message', CASE WHEN v_action = 'CREATE' THEN 'Đã tạo trạm thành công!' ELSE 'Đã cập nhật cấu hình trạm thành công!' END
    );
END;
$$;

CREATE OR REPLACE FUNCTION admin_delete_station(
    p_token TEXT,
    p_id    UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_admin         staff%ROWTYPE;
    v_station       stations%ROWTYPE;
    v_has_claims    BOOLEAN;
    v_before        JSONB;
    v_after         JSONB;
BEGIN
    v_admin := _require_staff(p_token, ARRAY['admin']);

    SELECT * INTO v_station FROM stations WHERE id = p_id;
    IF v_station.id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'code', 'NOT_FOUND', 'error', 'Trạm không tồn tại.');
    END IF;

    v_before := to_jsonb(v_station);

    -- Không xóa trạm đã có claim, chỉ is_active=false (xóa mềm)
    SELECT EXISTS (SELECT 1 FROM station_claims WHERE station_id = p_id) INTO v_has_claims;

    UPDATE stations
    SET is_active = false,
        deleted_at = now()
    WHERE id = p_id
    RETURNING * INTO v_station;

    v_after := to_jsonb(v_station);

    PERFORM _log_admin_audit(v_admin.id, 'SOFT_DELETE', 'stations', p_id::text, v_before, v_after);

    RETURN jsonb_build_object(
        'success', true,
        'has_claims', v_has_claims,
        'message', CASE 
            WHEN v_has_claims THEN 'Trạm đã có lượt vượt điểm nên được vô hiệu hóa an toàn (is_active = false).'
            ELSE 'Đã vô hiệu hóa trạm thành công.'
        END
    );
END;
$$;

-- ----------------------------------------------------------------------------
-- 4. BỔ SUNG CỘT PRICE VÀ TIER 'CUSTOM' CHO HINTS
-- ----------------------------------------------------------------------------
ALTER TABLE hints ADD COLUMN IF NOT EXISTS price INT DEFAULT 0;

ALTER TABLE hints DROP CONSTRAINT IF EXISTS chk_hints_price;
ALTER TABLE hints ADD CONSTRAINT chk_hints_price CHECK (price >= 0);

ALTER TABLE hints DROP CONSTRAINT IF EXISTS hints_tier_check;
ALTER TABLE hints DROP CONSTRAINT IF EXISTS chk_hints_tier;
ALTER TABLE hints ADD CONSTRAINT chk_hints_tier CHECK (tier IN ('bronze', 'silver', 'gold', 'custom'));

-- ----------------------------------------------------------------------------
-- 5. RPC: ADMIN_UPSERT_HINT & ADMIN_DELETE_HINT
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION admin_upsert_hint(
    p_token         TEXT,
    p_id            UUID DEFAULT NULL,
    p_title         TEXT DEFAULT NULL,
    p_tier          TEXT DEFAULT 'silver',
    p_price         INT DEFAULT 0,
    p_content       TEXT DEFAULT NULL,
    p_station_id    UUID DEFAULT NULL,
    p_order_index   INT DEFAULT 0,
    p_is_active     BOOLEAN DEFAULT true
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_admin staff%ROWTYPE;
    v_hint  hints%ROWTYPE;
    v_before JSONB;
    v_after JSONB;
    v_action TEXT;
BEGIN
    v_admin := _require_staff(p_token, ARRAY['admin']);

    IF p_title IS NULL OR trim(p_title) = '' THEN
        RETURN jsonb_build_object('success', false, 'code', 'TITLE_REQUIRED', 'error', 'Tiêu đề manh mối không được để trống.');
    END IF;

    IF p_content IS NULL OR trim(p_content) = '' THEN
        RETURN jsonb_build_object('success', false, 'code', 'CONTENT_REQUIRED', 'error', 'Nội dung manh mối không được để trống.');
    END IF;

    IF p_tier NOT IN ('bronze', 'silver', 'gold', 'custom') THEN
        RETURN jsonb_build_object('success', false, 'code', 'INVALID_TIER', 'error', 'Tier không hợp lệ (chỉ nhận bronze, silver, gold, custom).');
    END IF;

    IF p_price IS NULL OR p_price < 0 THEN
        RETURN jsonb_build_object('success', false, 'code', 'INVALID_AMOUNT', 'error', 'Giá manh mối (price) phải >= 0.');
    END IF;

    IF p_station_id IS NOT NULL THEN
        IF NOT EXISTS (SELECT 1 FROM stations WHERE id = p_station_id) THEN
            RETURN jsonb_build_object('success', false, 'code', 'STATION_NOT_FOUND', 'error', 'Trạm liên kết không tồn tại.');
        END IF;
    END IF;

    IF p_id IS NOT NULL THEN
        SELECT * INTO v_hint FROM hints WHERE id = p_id;
        IF v_hint.id IS NULL THEN
            RETURN jsonb_build_object('success', false, 'code', 'NOT_FOUND', 'error', 'Manh mối không tồn tại.');
        END IF;

        v_before := to_jsonb(v_hint);
        v_action := 'UPDATE';

        UPDATE hints
        SET title = trim(p_title),
            tier = p_tier,
            price = p_price,
            content = trim(p_content),
            station_id = p_station_id,
            order_index = COALESCE(p_order_index, order_index),
            is_active = COALESCE(p_is_active, is_active),
            deleted_at = CASE WHEN p_is_active THEN NULL ELSE deleted_at END
        WHERE id = p_id
        RETURNING * INTO v_hint;

        v_after := to_jsonb(v_hint);
    ELSE
        v_before := NULL;
        v_action := 'CREATE';

        INSERT INTO hints (
            title, tier, price, content, station_id, order_index, is_active
        ) VALUES (
            trim(p_title), p_tier, p_price, trim(p_content), p_station_id, COALESCE(p_order_index, 0), COALESCE(p_is_active, true)
        ) RETURNING * INTO v_hint;

        v_after := to_jsonb(v_hint);
    END IF;

    PERFORM _log_admin_audit(v_admin.id, v_action, 'hints', v_hint.id::text, v_before, v_after);

    RETURN jsonb_build_object(
        'success', true,
        'hint', v_after,
        'message', CASE WHEN v_action = 'CREATE' THEN 'Đã tạo manh mối thành công!' ELSE 'Đã cập nhật manh mối thành công!' END
    );
END;
$$;

CREATE OR REPLACE FUNCTION admin_delete_hint(
    p_token TEXT,
    p_id    UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_admin         staff%ROWTYPE;
    v_hint          hints%ROWTYPE;
    v_is_purchased  BOOLEAN;
    v_before        JSONB;
    v_after         JSONB;
BEGIN
    v_admin := _require_staff(p_token, ARRAY['admin']);

    SELECT * INTO v_hint FROM hints WHERE id = p_id;
    IF v_hint.id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'code', 'NOT_FOUND', 'error', 'Manh mối không tồn tại.');
    END IF;

    v_before := to_jsonb(v_hint);

    -- Xóa mềm nếu hint đã được mua
    SELECT EXISTS (SELECT 1 FROM team_hints WHERE hint_id = p_id) INTO v_is_purchased;

    IF v_is_purchased THEN
        UPDATE hints
        SET is_active = false,
            deleted_at = now()
        WHERE id = p_id
        RETURNING * INTO v_hint;

        v_after := to_jsonb(v_hint);
        PERFORM _log_admin_audit(v_admin.id, 'SOFT_DELETE', 'hints', p_id::text, v_before, v_after);

        RETURN jsonb_build_object(
            'success', true,
            'soft_deleted', true,
            'message', 'Manh mối này đã được đội mua trước đó nên đã được xóa mềm (is_active = false) để bảo toàn lịch sử mở khóa.'
        );
    ELSE
        DELETE FROM hints WHERE id = p_id;
        v_after := NULL;
        PERFORM _log_admin_audit(v_admin.id, 'DELETE', 'hints', p_id::text, v_before, NULL);

        RETURN jsonb_build_object('success', true, 'soft_deleted', false, 'message', 'Đã xóa manh mối thành công.');
    END IF;
END;
$$;

-- ----------------------------------------------------------------------------
-- 6. RPC: ADMIN_UPSERT_ITEM & ADMIN_DELETE_ITEM
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION admin_upsert_item(
    p_token             TEXT,
    p_id                UUID DEFAULT NULL,
    p_name              TEXT DEFAULT NULL,
    p_description       TEXT DEFAULT '',
    p_price             INT DEFAULT 0,
    p_effect_type       TEXT DEFAULT 'custom',
    p_effect_value      INT DEFAULT 0,
    p_duration_minutes  INT DEFAULT 0,
    p_is_active         BOOLEAN DEFAULT true
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_admin     staff%ROWTYPE;
    v_item      items%ROWTYPE;
    v_before    JSONB;
    v_after     JSONB;
    v_action    TEXT;
BEGIN
    v_admin := _require_staff(p_token, ARRAY['admin']);

    IF p_name IS NULL OR trim(p_name) = '' THEN
        RETURN jsonb_build_object('success', false, 'code', 'NAME_REQUIRED', 'error', 'Tên đạo cụ không được để trống.');
    END IF;

    IF p_price IS NULL OR p_price < 0 THEN
        RETURN jsonb_build_object('success', false, 'code', 'INVALID_AMOUNT', 'error', 'Giá đạo cụ (price) phải >= 0.');
    END IF;

    IF p_effect_type NOT IN ('shield', 'spy', 'key', 'custom') THEN
        RETURN jsonb_build_object('success', false, 'code', 'INVALID_EFFECT_TYPE', 'error', 'Loại hiệu ứng không hợp lệ (chỉ nhận shield, spy, key, custom).');
    END IF;

    -- Bắt buộc duration_minutes > 0 với shield
    IF p_effect_type = 'shield' AND (p_duration_minutes IS NULL OR p_duration_minutes <= 0) THEN
        RETURN jsonb_build_object(
            'success', false,
            'code', 'INVALID_DURATION',
            'error', 'Đạo cụ Khiên bảo vệ bắt buộc phải có thời lượng lớn hơn 0 phút (duration_minutes > 0).'
        );
    END IF;

    IF p_id IS NOT NULL THEN
        SELECT * INTO v_item FROM items WHERE id = p_id;
        IF v_item.id IS NULL THEN
            RETURN jsonb_build_object('success', false, 'code', 'NOT_FOUND', 'error', 'Đạo cụ không tồn tại.');
        END IF;

        v_before := to_jsonb(v_item);
        v_action := 'UPDATE';

        UPDATE items
        SET name = trim(p_name),
            description = COALESCE(p_description, description),
            price = p_price,
            effect_type = p_effect_type,
            effect_value = COALESCE(p_effect_value, effect_value),
            duration_minutes = COALESCE(p_duration_minutes, duration_minutes),
            is_active = COALESCE(p_is_active, is_active),
            deleted_at = CASE WHEN p_is_active THEN NULL ELSE deleted_at END
        WHERE id = p_id
        RETURNING * INTO v_item;

        v_after := to_jsonb(v_item);
    ELSE
        v_before := NULL;
        v_action := 'CREATE';

        INSERT INTO items (
            name, description, price, effect_type, effect_value, duration_minutes, is_active
        ) VALUES (
            trim(p_name), COALESCE(p_description, ''), p_price, p_effect_type,
            COALESCE(p_effect_value, 0), COALESCE(p_duration_minutes, 0), COALESCE(p_is_active, true)
        ) RETURNING * INTO v_item;

        v_after := to_jsonb(v_item);
    END IF;

    PERFORM _log_admin_audit(v_admin.id, v_action, 'items', v_item.id::text, v_before, v_after);

    RETURN jsonb_build_object(
        'success', true,
        'item', v_after,
        'message', CASE WHEN v_action = 'CREATE' THEN 'Đã tạo đạo cụ thành công!' ELSE 'Đã cập nhật đạo cụ thành công!' END
    );
END;
$$;

CREATE OR REPLACE FUNCTION admin_delete_item(
    p_token TEXT,
    p_id    UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_admin             staff%ROWTYPE;
    v_item              items%ROWTYPE;
    v_has_transactions  BOOLEAN;
    v_before            JSONB;
    v_after             JSONB;
BEGIN
    v_admin := _require_staff(p_token, ARRAY['admin']);

    SELECT * INTO v_item FROM items WHERE id = p_id;
    IF v_item.id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'code', 'NOT_FOUND', 'error', 'Đạo cụ không tồn tại.');
    END IF;

    v_before := to_jsonb(v_item);

    -- Xóa mềm nếu đã có giao dịch hoặc tồn tại trong kho đồ
    SELECT (
        EXISTS (SELECT 1 FROM transactions WHERE (metadata->>'item_id')::text = p_id::text)
        OR EXISTS (SELECT 1 FROM team_items WHERE item_id = p_id)
        OR EXISTS (SELECT 1 FROM item_usage_logs WHERE item_id = p_id)
    ) INTO v_has_transactions;

    IF v_has_transactions THEN
        UPDATE items
        SET is_active = false,
            deleted_at = now()
        WHERE id = p_id
        RETURNING * INTO v_item;

        v_after := to_jsonb(v_item);
        PERFORM _log_admin_audit(v_admin.id, 'SOFT_DELETE', 'items', p_id::text, v_before, v_after);

        RETURN jsonb_build_object(
            'success', true,
            'soft_deleted', true,
            'message', 'Đạo cụ này đã phát sinh giao dịch/sử dụng nên đã được xóa mềm (is_active = false).'
        );
    ELSE
        DELETE FROM items WHERE id = p_id;
        PERFORM _log_admin_audit(v_admin.id, 'DELETE', 'items', p_id::text, v_before, NULL);

        RETURN jsonb_build_object('success', true, 'soft_deleted', false, 'message', 'Đã xóa đạo cụ thành công.');
    END IF;
END;
$$;

-- ----------------------------------------------------------------------------
-- 7. RPC: ADMIN_UPSERT_STAFF & ADMIN_LIST_STAFF
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION admin_list_staff(
    p_token TEXT
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
                'id', s.id,
                'name', s.name,
                'role', s.role,
                'assigned_team_id', s.assigned_team_id,
                'team_name', t.name,
                'assigned_station_id', s.assigned_station_id,
                'station_name', st.name,
                'is_active', s.is_active,
                'created_at', s.created_at
            ) ORDER BY s.role ASC, s.name ASC
        ),
        '[]'::jsonb
    ) INTO v_list
    FROM staff s
    LEFT JOIN teams t ON t.id = s.assigned_team_id
    LEFT JOIN stations st ON st.id = s.assigned_station_id;

    RETURN jsonb_build_object('success', true, 'staff', v_list);
END;
$$;

CREATE OR REPLACE FUNCTION admin_upsert_staff(
    p_token                 TEXT,
    p_id                    UUID DEFAULT NULL,
    p_name                  TEXT DEFAULT NULL,
    p_role                  TEXT DEFAULT 'team_support',
    p_assigned_team_id      UUID DEFAULT NULL,
    p_assigned_station_id   UUID DEFAULT NULL,
    p_pin                   TEXT DEFAULT NULL,
    p_is_active             BOOLEAN DEFAULT true
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_admin         staff%ROWTYPE;
    v_target_staff  staff%ROWTYPE;
    v_pin_hash      TEXT;
    v_other_admins  INT;
    v_before        JSONB;
    v_after         JSONB;
    v_action        TEXT;
BEGIN
    v_admin := _require_staff(p_token, ARRAY['admin']);

    -- 1. Validate tên
    IF p_name IS NULL OR trim(p_name) = '' THEN
        RETURN jsonb_build_object('success', false, 'code', 'NAME_REQUIRED', 'error', 'Tên nhân sự không được để trống.');
    END IF;

    -- 2. Validate role
    IF p_role NOT IN ('admin', 'team_support', 'station_master') THEN
        RETURN jsonb_build_object('success', false, 'code', 'FORBIDDEN_ROLE', 'error', 'Vai trò không hợp lệ (admin, team_support, station_master).');
    END IF;

    -- 3. Validate ràng buộc phân công theo CHECK chk_staff_role_assignment
    IF p_role = 'admin' THEN
        IF p_assigned_team_id IS NOT NULL OR p_assigned_station_id IS NOT NULL THEN
            RETURN jsonb_build_object(
                'success', false,
                'code', 'INVALID_STAFF_ASSIGNMENT',
                'error', 'Vai trò admin không được phép gán vào đội hoặc trạm cụ thể.'
            );
        END IF;
    ELSIF p_role = 'team_support' THEN
        IF p_assigned_team_id IS NULL OR p_assigned_station_id IS NOT NULL THEN
            RETURN jsonb_build_object(
                'success', false,
                'code', 'INVALID_STAFF_ASSIGNMENT',
                'error', 'Vai trò team_support bắt buộc phải được gán vào một đội và không gán vào trạm.'
            );
        END IF;
        IF NOT EXISTS (SELECT 1 FROM teams WHERE id = p_assigned_team_id) THEN
            RETURN jsonb_build_object('success', false, 'code', 'TEAM_NOT_FOUND', 'error', 'Đội được gán không tồn tại.');
        END IF;
    ELSIF p_role = 'station_master' THEN
        IF p_assigned_station_id IS NULL OR p_assigned_team_id IS NOT NULL THEN
            RETURN jsonb_build_object(
                'success', false,
                'code', 'INVALID_STAFF_ASSIGNMENT',
                'error', 'Vai trò station_master bắt buộc phải được gán vào một trạm và không gán vào đội.'
            );
        END IF;
        IF NOT EXISTS (SELECT 1 FROM stations WHERE id = p_assigned_station_id) THEN
            RETURN jsonb_build_object('success', false, 'code', 'STATION_NOT_FOUND', 'error', 'Trạm được gán không tồn tại.');
        END IF;
    END IF;

    -- 4. Không cho admin tự vô hiệu hóa chính mình nếu là admin cuối cùng
    IF p_id IS NOT NULL AND p_id = v_admin.id THEN
        IF p_is_active = false OR p_role <> 'admin' THEN
            SELECT COUNT(*) INTO v_other_admins 
            FROM staff 
            WHERE role = 'admin' AND is_active = true AND id <> p_id;

            IF v_other_admins = 0 THEN
                RETURN jsonb_build_object(
                    'success', false,
                    'code', 'LAST_ADMIN_PROTECTED',
                    'error', 'Không thể tự vô hiệu hóa hoặc hạ quyền của Admin cuối cùng trong hệ thống!'
                );
            END IF;
        END IF;
    END IF;

    -- 5. Validate & Kiểm tra trùng mã PIN (nếu có cập nhật PIN)
    IF p_pin IS NOT NULL AND trim(p_pin) <> '' THEN
        IF NOT _check_pin_unique(trim(p_pin), p_id) THEN
            RETURN jsonb_build_object(
                'success', false,
                'code', 'PIN_NOT_UNIQUE',
                'error', 'Mã PIN này đã được sử dụng bởi một nhân sự khác đang hoạt động!'
            );
        END IF;
        v_pin_hash := crypt(trim(p_pin), gen_salt('bf', 8));
    END IF;

    -- 6. Thực hiện UPDATE hoặc INSERT
    IF p_id IS NOT NULL THEN
        SELECT * INTO v_target_staff FROM staff WHERE id = p_id;
        IF v_target_staff.id IS NULL THEN
            RETURN jsonb_build_object('success', false, 'code', 'NOT_FOUND', 'error', 'Nhân sự không tồn tại.');
        END IF;

        -- Bảo mật: Snapshot không lưu pin_hash
        v_before := jsonb_build_object(
            'id', v_target_staff.id,
            'name', v_target_staff.name,
            'role', v_target_staff.role,
            'assigned_team_id', v_target_staff.assigned_team_id,
            'assigned_station_id', v_target_staff.assigned_station_id,
            'is_active', v_target_staff.is_active
        );
        v_action := 'UPDATE';

        UPDATE staff
        SET name = trim(p_name),
            role = p_role,
            assigned_team_id = p_assigned_team_id,
            assigned_station_id = p_assigned_station_id,
            is_active = COALESCE(p_is_active, is_active),
            pin = CASE WHEN p_pin IS NOT NULL AND trim(p_pin) <> '' THEN trim(p_pin) ELSE pin END,
            pin_hash = CASE WHEN v_pin_hash IS NOT NULL THEN v_pin_hash ELSE pin_hash END
        WHERE id = p_id
        RETURNING * INTO v_target_staff;

        v_after := jsonb_build_object(
            'id', v_target_staff.id,
            'name', v_target_staff.name,
            'role', v_target_staff.role,
            'assigned_team_id', v_target_staff.assigned_team_id,
            'assigned_station_id', v_target_staff.assigned_station_id,
            'is_active', v_target_staff.is_active
        );

        -- Nếu vô hiệu hóa nhân sự, thu hồi toàn bộ session hiện tại
        IF p_is_active = false THEN
            PERFORM admin_revoke_sessions(p_token, v_target_staff.id);
        END IF;
    ELSE
        v_before := NULL;
        v_action := 'CREATE';

        IF p_pin IS NULL OR trim(p_pin) = '' THEN
            RETURN jsonb_build_object('success', false, 'code', 'INVALID_PIN', 'error', 'Bắt buộc phải cấp mã PIN khi tạo nhân sự mới.');
        END IF;

        INSERT INTO staff (
            name, role, assigned_team_id, assigned_station_id, is_active, pin, pin_hash
        ) VALUES (
            trim(p_name), p_role, p_assigned_team_id, p_assigned_station_id,
            COALESCE(p_is_active, true), trim(p_pin), v_pin_hash
        ) RETURNING * INTO v_target_staff;

        v_after := jsonb_build_object(
            'id', v_target_staff.id,
            'name', v_target_staff.name,
            'role', v_target_staff.role,
            'assigned_team_id', v_target_staff.assigned_team_id,
            'assigned_station_id', v_target_staff.assigned_station_id,
            'is_active', v_target_staff.is_active
        );
    END IF;

    -- 7. Ghi audit log
    PERFORM _log_admin_audit(v_admin.id, v_action, 'staff', v_target_staff.id::text, v_before, v_after);

    RETURN jsonb_build_object(
        'success', true,
        'staff', v_after,
        'message', CASE WHEN v_action = 'CREATE' THEN 'Đã thêm nhân sự mới thành công!' ELSE 'Đã cập nhật thông tin nhân sự thành công!' END
    );
END;
$$;

-- ----------------------------------------------------------------------------
-- 8. RPC: ADMIN_UPDATE_GAME_SETTINGS & UPDATE_SETTING
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION admin_update_game_settings(
    p_token TEXT,
    p_key   TEXT,
    p_value JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_admin     staff%ROWTYPE;
    v_old_value JSONB;
BEGIN
    v_admin := _require_staff(p_token, ARRAY['admin']);

    IF p_key IS NULL OR trim(p_key) = '' THEN
        RETURN jsonb_build_object('success', false, 'code', 'KEY_REQUIRED', 'error', 'Mã cài đặt (key) không được để trống.');
    END IF;

    SELECT value INTO v_old_value FROM game_settings WHERE key = trim(p_key);
    IF v_old_value IS NULL THEN
        -- Nếu key chưa tồn tại, chèn mới
        INSERT INTO game_settings (key, value, updated_by, updated_at)
        VALUES (trim(p_key), p_value, v_admin.name, now());
    ELSE
        UPDATE game_settings
        SET value = p_value,
            updated_at = now(),
            updated_by = v_admin.name
        WHERE key = trim(p_key);
    END IF;

    -- Ghi log lịch sử thay đổi game_settings_history
    INSERT INTO game_settings_history (key, old_value, new_value, changed_by)
    VALUES (trim(p_key), v_old_value, p_value, v_admin.name);

    -- Ghi audit log chung
    PERFORM _log_admin_audit(v_admin.id, 'UPDATE', 'game_settings', trim(p_key), v_old_value, p_value);

    RETURN jsonb_build_object(
        'success', true,
        'key', trim(p_key),
        'value', p_value,
        'message', 'Đã cập nhật cài đặt ' || trim(p_key) || ' thành công!'
    );
END;
$$;

-- Alias update_setting tương thích ngược
CREATE OR REPLACE FUNCTION update_setting(
    p_token TEXT,
    p_key   TEXT,
    p_value JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    RETURN admin_update_game_settings(p_token, p_key, p_value);
END;
$$;

-- ----------------------------------------------------------------------------
-- 9. RPC ĐỌC: ADMIN_GET_ADMIN_AUDIT_LOG
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION admin_get_admin_audit_log(
    p_token     TEXT,
    p_entity    TEXT DEFAULT NULL,
    p_limit     INT DEFAULT 100
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_admin staff%ROWTYPE;
    v_logs  JSONB;
BEGIN
    v_admin := _require_staff(p_token, ARRAY['admin']);

    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'id', l.id,
                'staff_id', l.staff_id,
                'staff_name', s.name,
                'action', l.action,
                'entity', l.entity,
                'entity_id', l.entity_id,
                'before', l.before,
                'after', l.after,
                'created_at', l.created_at
            ) ORDER BY l.created_at DESC
        ),
        '[]'::jsonb
    ) INTO v_logs
    FROM (
        SELECT * FROM admin_audit_log
        WHERE (p_entity IS NULL OR entity = p_entity)
        ORDER BY created_at DESC
        LIMIT COALESCE(p_limit, 100)
    ) l
    LEFT JOIN staff s ON s.id = l.staff_id;

    RETURN jsonb_build_object('success', true, 'audit_logs', v_logs);
END;
$$;

-- ----------------------------------------------------------------------------
-- 10. PHÂN QUYỀN EXECUTE PUBLIC RPCS
-- ----------------------------------------------------------------------------
REVOKE ALL ON FUNCTION admin_upsert_station(TEXT, UUID, TEXT, TEXT, INT, BOOLEAN, TEXT, JSONB, INT, INT, BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION admin_upsert_station(TEXT, UUID, TEXT, TEXT, INT, BOOLEAN, TEXT, JSONB, INT, INT, BOOLEAN) TO anon, authenticated;

REVOKE ALL ON FUNCTION admin_delete_station(TEXT, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION admin_delete_station(TEXT, UUID) TO anon, authenticated;

REVOKE ALL ON FUNCTION admin_upsert_hint(TEXT, UUID, TEXT, TEXT, INT, TEXT, UUID, INT, BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION admin_upsert_hint(TEXT, UUID, TEXT, TEXT, INT, TEXT, UUID, INT, BOOLEAN) TO anon, authenticated;

REVOKE ALL ON FUNCTION admin_delete_hint(TEXT, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION admin_delete_hint(TEXT, UUID) TO anon, authenticated;

REVOKE ALL ON FUNCTION admin_upsert_item(TEXT, UUID, TEXT, TEXT, INT, TEXT, INT, INT, BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION admin_upsert_item(TEXT, UUID, TEXT, TEXT, INT, TEXT, INT, INT, BOOLEAN) TO anon, authenticated;

REVOKE ALL ON FUNCTION admin_delete_item(TEXT, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION admin_delete_item(TEXT, UUID) TO anon, authenticated;

REVOKE ALL ON FUNCTION admin_upsert_staff(TEXT, UUID, TEXT, TEXT, UUID, UUID, TEXT, BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION admin_upsert_staff(TEXT, UUID, TEXT, TEXT, UUID, UUID, TEXT, BOOLEAN) TO anon, authenticated;

REVOKE ALL ON FUNCTION admin_list_staff(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION admin_list_staff(TEXT) TO anon, authenticated;

REVOKE ALL ON FUNCTION admin_update_game_settings(TEXT, TEXT, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION admin_update_game_settings(TEXT, TEXT, JSONB) TO anon, authenticated;

REVOKE ALL ON FUNCTION update_setting(TEXT, TEXT, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION update_setting(TEXT, TEXT, JSONB) TO anon, authenticated;

REVOKE ALL ON FUNCTION admin_get_admin_audit_log(TEXT, TEXT, INT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION admin_get_admin_audit_log(TEXT, TEXT, INT) TO anon, authenticated;
