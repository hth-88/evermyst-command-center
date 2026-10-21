-- ============================================================================
-- MIGRATION 101: SHOP, HINTS, INVENTORY, ATOMIC TRANSACTIONS & PVP BACKLASH
-- File: supabase/migrations/101_shop_inventory_rpc_fix.sql
-- Idempotent script: Chạy an toàn nhiều lần trên Supabase Cloud SQL Editor
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ----------------------------------------------------------------------------
-- 1. BẢNG TEAMS & STAFF: BỔ SUNG CỘT & MAPPING PHÂN CÔNG ĐỘI / TRẠM
-- ----------------------------------------------------------------------------
ALTER TABLE teams
    ADD COLUMN IF NOT EXISTS shield_until TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS unlocked_stations UUID[] DEFAULT '{}'::UUID[];

ALTER TABLE staff
    ADD COLUMN IF NOT EXISTS assigned_team_id UUID REFERENCES teams(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS assigned_station_id UUID REFERENCES stations(id) ON DELETE SET NULL;

-- Cập nhật ràng buộc Staff Role nếu có
ALTER TABLE staff DROP CONSTRAINT IF EXISTS staff_role_check;
ALTER TABLE staff DROP CONSTRAINT IF EXISTS chk_staff_role;
ALTER TABLE staff
    ADD CONSTRAINT chk_staff_role
    CHECK (role IN ('admin', 'support', 'station_master', 'team_support'));

-- Mapping chính xác 6 Support Teams (777001 -> 777006) và 5 Quản Trò (888001 -> 888005)
DO $$
DECLARE
    v_team RECORD;
    v_station RECORD;
BEGIN
    -- Mapping 6 Support Teams (777001 -> 777006)
    FOR v_team IN 
        SELECT id, name, qr_code, ROW_NUMBER() OVER (ORDER BY qr_code, id) as idx 
        FROM (
            SELECT DISTINCT ON (qr_code) id, name, qr_code
            FROM teams 
            WHERE is_active = true 
            ORDER BY qr_code, id
        ) t
        ORDER BY qr_code
        LIMIT 6
    LOOP
        INSERT INTO staff (id, name, role, pin, assigned_team_id, is_active)
        VALUES (
            gen_random_uuid(),
            'Hỗ Trợ ' || v_team.name,
            'team_support',
            ('77700' || v_team.idx)::TEXT,
            v_team.id,
            true
        )
        ON CONFLICT DO NOTHING;

        -- Đồng bộ cập nhật assigned_team_id nếu staff PIN đã tồn tại
        UPDATE staff
        SET assigned_team_id = v_team.id,
            role = 'team_support',
            name = 'Hỗ Trợ ' || v_team.name
        WHERE pin = ('77700' || v_team.idx)::TEXT;
    END LOOP;

    -- Mapping 5 Station Masters (888001 -> 888005)
    FOR v_station IN 
        SELECT DISTINCT ON (order_index) id, name, order_index
        FROM stations 
        WHERE is_active = true 
        ORDER BY order_index, id
    LOOP
        INSERT INTO staff (id, name, role, pin, assigned_station_id, station_assigned, is_active)
        VALUES (
            gen_random_uuid(),
            'Quản Trò ' || v_station.name,
            'station_master',
            ('88800' || v_station.order_index)::TEXT,
            v_station.id,
            v_station.name,
            true
        )
        ON CONFLICT DO NOTHING;

        UPDATE staff
        SET assigned_station_id = v_station.id,
            station_assigned = v_station.name,
            role = 'station_master',
            name = 'Quản Trò ' || v_station.name
        WHERE pin = ('88800' || v_station.order_index)::TEXT;
    END LOOP;
END $$;

-- ----------------------------------------------------------------------------
-- 2. BẢNG TEAM_STATION_KEYS (CHÌA KHÓA VẠN NĂNG CẮM VÀO TRẠM)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS team_station_keys (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    team_id             UUID NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
    station_id          UUID NOT NULL REFERENCES stations(id) ON DELETE CASCADE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_team_station_key UNIQUE (team_id, station_id)
);
CREATE INDEX IF NOT EXISTS idx_team_station_keys_team ON team_station_keys(team_id);
CREATE INDEX IF NOT EXISTS idx_team_station_keys_station ON team_station_keys(station_id);

-- ----------------------------------------------------------------------------
-- 3. ĐỒNG BỘ 3 ĐẠO CỤ CHUẨN XÁC: SHIELD (30✦), SPYGLASS (20✦), MASTER_KEY (60✦)
-- ----------------------------------------------------------------------------
ALTER TABLE items
    ADD COLUMN IF NOT EXISTS item_code TEXT,
    ADD COLUMN IF NOT EXISTS duration_minutes INT DEFAULT 0;

-- Cập nhật ràng buộc effect_type
ALTER TABLE items DROP CONSTRAINT IF EXISTS items_effect_type_check;
ALTER TABLE items DROP CONSTRAINT IF EXISTS chk_items_effect_type;
ALTER TABLE items
    ADD CONSTRAINT chk_items_effect_type 
    CHECK (effect_type IN ('shield', 'spy', 'spyglass', 'key', 'master_key', 'custom'));

-- Dọn dẹp các items trùng lặp hoặc legacy để dữ liệu gọn gàng
DELETE FROM items WHERE name IN ('Khiên Màn Sương', 'Kính Vọng Tầm', 'Mắt Cú Vọ', 'Chìa Khóa Vạn Năng', 'Chìa Khóa Cổ Tích')
   OR item_code IN ('shield', 'spyglass', 'master_key');

INSERT INTO items (id, item_code, name, description, price, effect_type, duration_minutes, is_active)
VALUES
    (
        '30000000-0000-0000-0000-000000000001',
        'shield',
        'Khiên Màn Sương',
        'Kích hoạt bảo vệ đội khỏi tấn công PvP trong 20 phút. Nếu bị đánh lén, kẻ địch bị phạt phản phệ 10 Lumen.',
        30,
        'shield',
        20,
        true
    ),
    (
        '30000000-0000-0000-0000-000000000002',
        'spyglass',
        'Kính Vọng Tầm',
        'Soi ngay số dư Lumen hiện tại và trạng thái Khiên bảo vệ của 1 đội đối thủ bất kỳ.',
        20,
        'spyglass',
        0,
        true
    ),
    (
        '30000000-0000-0000-0000-000000000003',
        'master_key',
        'Chìa Khóa Vạn Năng',
        'Kích hoạt huy hiệu Chìa Khóa tại trạm mục tiêu, giúp đội vượt qua câu đố khó hoặc mở lối tắt.',
        60,
        'master_key',
        0,
        true
    )
ON CONFLICT (id) DO UPDATE SET
    item_code = EXCLUDED.item_code,
    name = EXCLUDED.name,
    description = EXCLUDED.description,
    price = EXCLUDED.price,
    effect_type = EXCLUDED.effect_type,
    duration_minutes = EXCLUDED.duration_minutes,
    is_active = true;

-- ----------------------------------------------------------------------------
-- 4. ĐỒNG BỘ 3 BẬC MANH MỐI BÍ MẬT (HINTS): ĐỒNG (20✦), BẠC (50✦), VÀNG (100✦)
-- KÈM NỘI DUNG MẬT THƯ THỰC TẾ
-- ----------------------------------------------------------------------------
DELETE FROM hints WHERE tier IN ('bronze', 'silver', 'gold');

INSERT INTO hints (id, title, content, tier, order_index, is_active)
VALUES
    (
        '40000000-0000-0000-0000-000000000001',
        'Mật Thư Cổ Tự (Đồng)',
        'Đọc ngược các chữ cái in hoa đầu mỗi khổ thơ trên bảng hiệu trạm: "L-U-M-E-N" chính là chìa khóa khởi động.',
        'bronze',
        1,
        true
    ),
    (
        '40000000-0000-0000-0000-000000000002',
        'Mật Thư Bản Đồ (Bạc)',
        'Dưới chân tảng đá hình lăng kính có khắc tọa độ phụ. Đi về hướng Bắc 15 bước chân sẽ thấy hộp mật mã thứ hai.',
        'silver',
        2,
        true
    ),
    (
        '40000000-0000-0000-0000-000000000003',
        'Bí Mật Đỉnh Tháp (Vàng)',
        'Đáp án câu đố cuối cùng là chuỗi số Fibonacci: 1 - 1 - 2 - 3 - 5 - 8. Tổng số nhân đôi = 40 Lumen quà tặng ẩn.',
        'gold',
        3,
        true
    )
ON CONFLICT (id) DO UPDATE SET
    title = EXCLUDED.title,
    content = EXCLUDED.content,
    tier = EXCLUDED.tier,
    is_active = true;

-- ----------------------------------------------------------------------------
-- 5. BẢNG TEAM_ITEMS & VIEW TEAM_INVENTORY
-- ----------------------------------------------------------------------------
ALTER TABLE team_items
    ADD COLUMN IF NOT EXISTS item_code TEXT;

UPDATE team_items ti
SET item_code = i.item_code
FROM items i
WHERE ti.item_id = i.id AND (ti.item_code IS NULL OR ti.item_code = '');

CREATE OR REPLACE VIEW team_inventory AS
SELECT 
    ti.id,
    ti.team_id,
    ti.item_id,
    COALESCE(ti.item_code, i.item_code) AS item_code,
    i.name AS item_name,
    i.description AS item_description,
    i.effect_type,
    i.duration_minutes,
    ti.quantity,
    ti.used_count,
    ti.updated_at
FROM team_items ti
JOIN items i ON i.id = ti.item_id;

-- ----------------------------------------------------------------------------
-- 6. PHÂN QUYỀN RLS TOÀN DIỆN CHO CÁC BẢNG LIÊN QUAN
-- ----------------------------------------------------------------------------
ALTER TABLE team_station_keys ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow All Team Station Keys" ON team_station_keys;
CREATE POLICY "Allow All Team Station Keys" ON team_station_keys FOR ALL USING (true) WITH CHECK (true);

ALTER TABLE team_hints ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow All Team Hints" ON team_hints;
CREATE POLICY "Allow All Team Hints" ON team_hints FOR ALL USING (true) WITH CHECK (true);

ALTER TABLE team_items ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow All Team Items" ON team_items;
CREATE POLICY "Allow All Team Items" ON team_items FOR ALL USING (true) WITH CHECK (true);

ALTER TABLE transactions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow All Transactions" ON transactions;
CREATE POLICY "Allow All Transactions" ON transactions FOR ALL USING (true) WITH CHECK (true);

ALTER TABLE teams ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow All Teams" ON teams;
CREATE POLICY "Allow All Teams" ON teams FOR ALL USING (true) WITH CHECK (true);

ALTER TABLE staff ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow All Staff" ON staff;
CREATE POLICY "Allow All Staff" ON staff FOR ALL USING (true) WITH CHECK (true);

ALTER TABLE items ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow All Items" ON items;
CREATE POLICY "Allow All Items" ON items FOR ALL USING (true) WITH CHECK (true);

ALTER TABLE hints ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow All Hints" ON hints;
CREATE POLICY "Allow All Hints" ON hints FOR ALL USING (true) WITH CHECK (true);

-- Bật Realtime
DO $$
BEGIN
    BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE teams; EXCEPTION WHEN others THEN NULL; END;
    BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE team_items; EXCEPTION WHEN others THEN NULL; END;
    BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE team_hints; EXCEPTION WHEN others THEN NULL; END;
    BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE team_station_keys; EXCEPTION WHEN others THEN NULL; END;
    BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE transactions; EXCEPTION WHEN others THEN NULL; END;
END $$;

-- ----------------------------------------------------------------------------
-- 7. RPC: BUY_HINT (NGUYÊN TỬ & KHÔNG TRỪ TIỀN TRÙNG)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION buy_hint(
    p_team_id UUID,
    p_hint_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_hint RECORD;
    v_team RECORD;
    v_price INT;
    v_already_owned BOOLEAN;
BEGIN
    -- 1. Kiểm tra hint
    SELECT * INTO v_hint FROM hints WHERE id = p_hint_id AND is_active = true;
    IF v_hint.id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'code', 'NOT_FOUND', 'error', 'Manh mối không tồn tại hoặc đã bị khóa.');
    END IF;

    -- 2. Kiểm tra nếu đội đã mua hint này rồi -> Trả về luôn nội dung, KHÔNG trừ tiền lại!
    SELECT EXISTS(SELECT 1 FROM team_hints WHERE team_id = p_team_id AND hint_id = p_hint_id)
    INTO v_already_owned;

    IF v_already_owned THEN
        RETURN jsonb_build_object(
            'success', true,
            'already_owned', true,
            'hint_title', v_hint.title,
            'hint_content', v_hint.content,
            'secret_content', v_hint.content,
            'tier', v_hint.tier,
            'message', 'Đội đã sở hữu manh mối này từ trước!'
        );
    END IF;

    -- 3. Lấy giá theo tier
    v_price := CASE v_hint.tier
        WHEN 'bronze' THEN 20
        WHEN 'silver' THEN 50
        WHEN 'gold' THEN 100
        ELSE 50
    END;

    -- 4. Khóa dòng kiểm tra số dư
    SELECT * INTO v_team FROM teams WHERE id = p_team_id FOR UPDATE;
    IF v_team.id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'code', 'TEAM_NOT_FOUND', 'error', 'Không tìm thấy đội chơi.');
    END IF;

    IF v_team.light_balance < v_price THEN
        RETURN jsonb_build_object(
            'success', false,
            'code', 'INSUFFICIENT_FUNDS',
            'error', 'Không đủ Lumen! Cần ' || v_price || ' Lumen, hiện chỉ có ' || v_team.light_balance || ' Lumen.'
        );
    END IF;

    -- 5. Trừ tiền nguyên tử
    UPDATE teams SET light_balance = light_balance - v_price WHERE id = p_team_id;

    -- 6. Lưu vào team_hints
    INSERT INTO team_hints (team_id, hint_id, unlocked_by)
    VALUES (p_team_id, p_hint_id, 'Support')
    ON CONFLICT (team_id, hint_id) DO NOTHING;

    -- 7. Ghi sổ cái transactions
    INSERT INTO transactions (team_id, amount, type, description, created_by, status)
    VALUES (
        p_team_id,
        -v_price,
        'buy_hint',
        'Mua Mật Thư [' || upper(v_hint.tier) || ']: ' || v_hint.title,
        'Support',
        'approved'
    );

    RETURN jsonb_build_object(
        'success', true,
        'already_owned', false,
        'hint_title', v_hint.title,
        'hint_content', v_hint.content,
        'secret_content', v_hint.content,
        'tier', v_hint.tier,
        'price', v_price,
        'new_balance', v_team.light_balance - v_price,
        'message', 'Đã mở khóa thành công mật thư "' || v_hint.title || '" (-' || v_price || ' Lumen)!'
    );
END;
$$;

-- Overload hỗ trợ 4 tham số
CREATE OR REPLACE FUNCTION buy_hint(
    p_token TEXT,
    p_client_request_id TEXT,
    p_team_id UUID,
    p_hint_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN buy_hint(p_team_id, p_hint_id);
END;
$$;

-- Overload purchase_hint tương thích
CREATE OR REPLACE FUNCTION purchase_hint(
    p_token TEXT,
    p_client_request_id TEXT,
    p_hint_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_staff staff%ROWTYPE;
BEGIN
    SELECT * INTO v_staff 
    FROM staff_sessions ss 
    JOIN staff s ON s.id = ss.staff_id 
    WHERE ss.token = p_token AND ss.expires_at > now();

    IF v_staff.id IS NULL OR v_staff.assigned_team_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Không xác định được đội của nhân sự.');
    END IF;

    RETURN buy_hint(v_staff.assigned_team_id, p_hint_id);
END;
$$;

CREATE OR REPLACE FUNCTION get_team_unlocked_hints(
    p_team_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_hints JSONB;
BEGIN
    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'id', th.id,
            'team_id', th.team_id,
            'hint_id', th.hint_id,
            'unlocked_at', th.unlocked_at,
            'title', h.title,
            'tier', h.tier,
            'content', h.content,
            'secret_content', h.content
        )
    ), '[]'::jsonb)
    INTO v_hints
    FROM team_hints th
    JOIN hints h ON h.id = th.hint_id
    WHERE th.team_id = p_team_id;

    RETURN jsonb_build_object('success', true, 'hints', v_hints);
END;
$$;

-- ----------------------------------------------------------------------------
-- 8. RPC: BUY_ITEM (MUA ĐẠO CỤ VÀO KHO ĐỒ ĐỘI)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION buy_item(
    p_team_id UUID,
    p_item_code TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_item RECORD;
    v_team RECORD;
    v_new_qty INT;
BEGIN
    -- 1. Tìm item theo item_code hoặc id hoặc effect_type
    SELECT * INTO v_item 
    FROM items 
    WHERE (item_code = p_item_code OR id::text = p_item_code OR effect_type = p_item_code)
      AND is_active = true
    LIMIT 1;

    IF v_item.id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'code', 'ITEM_NOT_FOUND', 'error', 'Đạo cụ không tồn tại trong cửa hàng.');
    END IF;

    -- 2. Kiểm tra số dư đội
    SELECT * INTO v_team FROM teams WHERE id = p_team_id FOR UPDATE;
    IF v_team.id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'code', 'TEAM_NOT_FOUND', 'error', 'Không tìm thấy đội chơi.');
    END IF;

    IF v_team.light_balance < v_item.price THEN
        RETURN jsonb_build_object(
            'success', false,
            'code', 'INSUFFICIENT_FUNDS',
            'error', 'Không đủ Lumen! Cần ' || v_item.price || ' Lumen, hiện chỉ có ' || v_team.light_balance || ' Lumen.'
        );
    END IF;

    -- 3. Trừ tiền nguyên tử
    UPDATE teams SET light_balance = light_balance - v_item.price WHERE id = p_team_id;

    -- 4. Cộng +1 vào kho đồ team_items
    INSERT INTO team_items (team_id, item_id, item_code, quantity, used_count)
    VALUES (p_team_id, v_item.id, v_item.item_code, 1, 0)
    ON CONFLICT (team_id, item_id)
    DO UPDATE SET 
        quantity = team_items.quantity + 1,
        item_code = EXCLUDED.item_code,
        updated_at = now()
    RETURNING quantity INTO v_new_qty;

    -- 5. Ghi log transactions
    INSERT INTO transactions (team_id, amount, type, description, created_by, status)
    VALUES (
        p_team_id,
        -v_item.price,
        'buy_item',
        'Mua đạo cụ: ' || v_item.name || ' (-' || v_item.price || ' Lumen)',
        'Support',
        'approved'
    );

    RETURN jsonb_build_object(
        'success', true,
        'item_name', v_item.name,
        'item_code', v_item.item_code,
        'price', v_item.price,
        'quantity', v_new_qty,
        'new_balance', v_team.light_balance - v_item.price,
        'message', 'Đã mua thành công 1 ' || v_item.name || ' (Kho hiện có: ' || v_new_qty || ')!'
    );
END;
$$;

-- Overload hỗ trợ 4 tham số
CREATE OR REPLACE FUNCTION buy_item(
    p_token TEXT,
    p_client_request_id TEXT,
    p_team_id UUID,
    p_item_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN buy_item(p_team_id, p_item_id::text);
END;
$$;

-- Overload purchase_item tương thích
CREATE OR REPLACE FUNCTION purchase_item(
    p_token TEXT,
    p_client_request_id TEXT,
    p_item_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_staff staff%ROWTYPE;
BEGIN
    SELECT * INTO v_staff 
    FROM staff_sessions ss 
    JOIN staff s ON s.id = ss.staff_id 
    WHERE ss.token = p_token AND ss.expires_at > now();

    IF v_staff.id IS NULL OR v_staff.assigned_team_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Không xác định được đội của nhân sự.');
    END IF;

    RETURN buy_item(v_staff.assigned_team_id, p_item_id::text);
END;
$$;

-- ----------------------------------------------------------------------------
-- 9. RPC: USE_ITEM (KÍCH HOẠT HIỆU ỨNG THỰC TẾ)
-- Hỗ trợ: shield (+20p), spyglass (soi đối thủ), master_key (gắn vào trạm)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION use_item(
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
BEGIN
    -- 1. Tìm item
    SELECT * INTO v_item 
    FROM items 
    WHERE (item_code = p_item_code OR id::text = p_item_code OR effect_type = p_item_code)
    LIMIT 1;

    IF v_item.id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'code', 'ITEM_NOT_FOUND', 'error', 'Không tìm thấy đạo cụ.');
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

    -- 3. Trừ 1 số lượng trong kho
    UPDATE team_items
    SET quantity = quantity - 1,
        used_count = used_count + 1,
        updated_at = now()
    WHERE id = v_inventory.id;

    -- 4. Xử lý Side-effects theo effect_type
    IF v_item.effect_type = 'shield' THEN
        -- Bật Khiên Màn Sương 20 phút
        UPDATE teams
        SET shield_until = GREATEST(COALESCE(shield_until, now()), now()) + INTERVAL '20 minutes'
        WHERE id = p_team_id
        RETURNING shield_until INTO v_new_shield_until;

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
            'message', '🛡️ Đã kích hoạt Khiên Màn Sương! Đội được bảo vệ trong 20 phút.'
        );

    ELSIF v_item.effect_type IN ('spy', 'spyglass') THEN
        -- Soi số dư & trạng thái khiên đội đối thủ
        IF p_target_team_id IS NULL OR p_target_team_id = p_team_id THEN
            -- Hoàn lại số lượng nếu chưa chọn đúng
            UPDATE team_items SET quantity = quantity + 1 WHERE id = v_inventory.id;
            RETURN jsonb_build_object('success', false, 'code', 'TARGET_REQUIRED', 'error', 'Vui lòng chọn một đội đối thủ để do thám.');
        END IF;

        SELECT * INTO v_target_team FROM teams WHERE id = p_target_team_id;
        IF v_target_team.id IS NULL THEN
            UPDATE team_items SET quantity = quantity + 1 WHERE id = v_inventory.id;
            RETURN jsonb_build_object('success', false, 'code', 'TARGET_NOT_FOUND', 'error', 'Đội đối thủ không tồn tại.');
        END IF;

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
        -- Gắn Chìa Khóa Vạn Năng vào trạm mục tiêu
        IF p_target_station_id IS NULL THEN
            UPDATE team_items SET quantity = quantity + 1 WHERE id = v_inventory.id;
            RETURN jsonb_build_object('success', false, 'code', 'STATION_REQUIRED', 'error', 'Vui lòng chọn trạm mục tiêu để cắm Chìa Khóa Vạn Năng.');
        END IF;

        SELECT * INTO v_target_station FROM stations WHERE id = p_target_station_id;
        IF v_target_station.id IS NULL THEN
            UPDATE team_items SET quantity = quantity + 1 WHERE id = v_inventory.id;
            RETURN jsonb_build_object('success', false, 'code', 'STATION_NOT_FOUND', 'error', 'Trạm mục tiêu không tồn tại.');
        END IF;

        -- Ghi vào team_station_keys
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
        RETURN jsonb_build_object('success', true, 'message', 'Đã sử dụng ' || v_item.name);
    END IF;
END;
$$;

-- Overload use_team_item hỗ trợ token phiên
CREATE OR REPLACE FUNCTION use_team_item(
    p_token TEXT,
    p_item_id UUID,
    p_target_team_id UUID DEFAULT NULL,
    p_target_station_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_staff staff%ROWTYPE;
BEGIN
    SELECT * INTO v_staff 
    FROM staff_sessions ss 
    JOIN staff s ON s.id = ss.staff_id 
    WHERE ss.token = p_token AND ss.expires_at > now();

    IF v_staff.id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'code', 'INVALID_TOKEN', 'error', 'Phiên đăng nhập không hợp lệ.');
    END IF;

    IF v_staff.assigned_team_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'code', 'NO_TEAM', 'error', 'Nhân sự chưa được phân công đội.');
    END IF;

    RETURN use_item(v_staff.assigned_team_id, p_item_id::text, p_target_team_id, p_target_station_id);
END;
$$;

-- ----------------------------------------------------------------------------
-- 10. BẢNG PVP_LOGS & RPC: RESOLVE_PVP (DEADLOCK-SAFE + PHẢN PHỆ KHI GẶP KHIÊN BẢO VỆ)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS pvp_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    attacker_team_id UUID REFERENCES teams(id) ON DELETE CASCADE,
    defender_team_id UUID REFERENCES teams(id) ON DELETE CASCADE,
    result TEXT,
    stolen_amount INT DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE pvp_logs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow All PvP Logs" ON pvp_logs;
CREATE POLICY "Allow All PvP Logs" ON pvp_logs FOR ALL USING (true) WITH CHECK (true);

CREATE OR REPLACE FUNCTION resolve_pvp(
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
        RETURN jsonb_build_object('success', false, 'error', 'Không thể tấn công chính đội mình.');
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
        RETURN jsonb_build_object('success', false, 'error', 'Không tìm thấy thông tin một trong hai đội.');
    END IF;

    -- Kiểm tra Khiên bảo vệ của bên phòng thủ
    v_is_shielded := (v_defender.shield_until IS NOT NULL AND v_defender.shield_until > now());

    IF v_is_shielded THEN
        -- Bị phản phệ: kẻ tấn công bị trừ 10 Lumen, phòng thủ được an toàn
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
        VALUES (p_attacker_id, p_defender_id, 'backlash', -v_backlash_amount, now());

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

-- Overload resolve_pvp hỗ trợ 4 tham số
CREATE OR REPLACE FUNCTION resolve_pvp(
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
    RETURN resolve_pvp(p_attacker_team_id, p_defender_team_id);
END;
$$;

-- Overload resolve_pvp với 1 target_team_id (lấy attacker từ token phiên)
CREATE OR REPLACE FUNCTION resolve_pvp(
    p_token TEXT,
    p_client_request_id TEXT,
    p_target_team_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_staff staff%ROWTYPE;
BEGIN
    SELECT * INTO v_staff 
    FROM staff_sessions ss 
    JOIN staff s ON s.id = ss.staff_id 
    WHERE ss.token = p_token AND ss.expires_at > now();

    IF v_staff.id IS NULL OR v_staff.assigned_team_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Không xác định được đội của người dùng.');
    END IF;

    RETURN resolve_pvp(v_staff.assigned_team_id, p_target_team_id);
END;
$$;
