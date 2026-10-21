-- ============================================================================
-- MIGRATION 100: ECONOMY ENGINE, PVP, SHOP, REVERSALS & AUDIT RPCs
-- File: supabase/migrations/100_economy_engine.sql
-- Mục đích: Động cơ kinh tế bất biến (ADR-1, ADR-4), chống âm tuyệt đối & ma trận Reversal
-- ============================================================================

-- Đảm bảo CHECK constraint trên bảng transactions và items đầy đủ kiểu dữ liệu
ALTER TABLE transactions DROP CONSTRAINT IF EXISTS chk_transactions_type;
ALTER TABLE transactions
    ADD CONSTRAINT chk_transactions_type CHECK (
        type IN (
            'station_clear', 
            'buy_hint',
            'hint_purchase',
            'buy_item',
            'shop_item',
            'pvp_steal', 
            'pvp_backlash', 
            'admin_adjust', 
            'reversal',
            'initial_grant',
            'migration_correction'
        )
    );

ALTER TABLE items DROP CONSTRAINT IF EXISTS chk_items_effect_type;
ALTER TABLE items
    ADD CONSTRAINT chk_items_effect_type 
    CHECK (effect_type IN ('shield', 'spy', 'key', 'custom'));

-- ----------------------------------------------------------------------------
-- 1. RPC: PURCHASE_HINT (MUA MANH MỐI BÍ MẬT)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION purchase_hint(
    p_token             TEXT,
    p_hint_id           UUID,
    p_client_request_id TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_staff         staff%ROWTYPE;
    v_team_id       UUID;
    v_team          teams%ROWTYPE;
    v_hint          hints%ROWTYPE;
    v_price         INT;
    v_tx_id         UUID;
    v_new_balance   INT;
    v_existing_tx   transactions%ROWTYPE;
    v_already_owned BOOLEAN;
BEGIN
    -- 1. Xác thực: Chỉ team_support, đội lấy từ token
    v_staff := _require_staff(p_token, ARRAY['team_support']);
    v_team_id := v_staff.assigned_team_id;
    IF v_team_id IS NULL THEN
        RAISE EXCEPTION 'FORBIDDEN_TEAM: Nhân sự chưa được phân công đội chơi.' USING ERRCODE = 'P0005';
    END IF;

    -- 2. Idempotency Check theo client_request_id
    IF p_client_request_id IS NOT NULL AND trim(p_client_request_id) <> '' THEN
        SELECT * INTO v_existing_tx FROM transactions WHERE client_request_id = trim(p_client_request_id);
        IF v_existing_tx.id IS NOT NULL THEN
            SELECT * INTO v_hint FROM hints WHERE id = p_hint_id;
            RETURN jsonb_build_object(
                'success', true,
                'idempotent', true,
                'hint_id', v_hint.id,
                'title', v_hint.title,
                'content', v_hint.content,
                'tier', v_hint.tier,
                'message', 'Manh mối này đã được mở khóa thành công trước đó.'
            );
        END IF;
    END IF;

    -- 3. Kiểm tra Hint tồn tại và active
    SELECT * INTO v_hint FROM hints WHERE id = p_hint_id AND is_active = true AND deleted_at IS NULL;
    IF v_hint.id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'code', 'NOT_FOUND', 'error', 'Manh mối không tồn tại hoặc đã bị ẩn.');
    END IF;

    -- 4. Khóa đội theo thứ tự toàn cục
    SELECT * INTO v_team FROM teams WHERE id = v_team_id AND is_active = true FOR UPDATE;
    IF v_team.id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'code', 'TEAM_NOT_FOUND', 'error', 'Đội chơi không tồn tại.');
    END IF;

    -- 5. Chặn mua trùng (team_id, hint_id)
    SELECT EXISTS (
        SELECT 1 FROM team_hints WHERE team_id = v_team_id AND hint_id = p_hint_id
    ) INTO v_already_owned;

    IF v_already_owned THEN
        RETURN jsonb_build_object(
            'success', false,
            'code', 'HINT_ALREADY_PURCHASED',
            'error', 'Đội đã sở hữu manh mối này từ trước! Vui lòng xem lại trong danh sách manh mối đã mở khóa.'
        );
    END IF;

    -- 6. Lấy giá theo tier từ game_settings
    SELECT COALESCE((value->>'v')::INT, 
        CASE v_hint.tier WHEN 'bronze' THEN 20 WHEN 'silver' THEN 50 WHEN 'gold' THEN 100 ELSE 50 END
    ) INTO v_price
    FROM game_settings WHERE key = 'hint_price_' || v_hint.tier;
    IF v_price IS NULL THEN v_price := 50; END IF;

    -- 7. Kiểm tra đủ số dư (INSUFFICIENT_BALANCE)
    IF v_team.light_balance < v_price THEN
        RETURN jsonb_build_object(
            'success', false,
            'code', 'INSUFFICIENT_BALANCE',
            'error', 'Không đủ Lumen! Cần ' || v_price || ' Lumen, hiện có ' || v_team.light_balance || ' Lumen.'
        );
    END IF;

    -- 8. Trừ tiền & Ghi sổ cái Ledger loại hint_purchase âm
    UPDATE teams 
    SET light_balance = light_balance - v_price 
    WHERE id = v_team_id
    RETURNING light_balance INTO v_new_balance;

    INSERT INTO transactions (
        client_request_id,
        team_id,
        amount,
        type,
        description,
        created_by,
        actor_staff_id,
        actor_role,
        status,
        metadata
    ) VALUES (
        p_client_request_id,
        v_team_id,
        -v_price,
        'hint_purchase',
        'Mua Hint [' || upper(v_hint.tier) || ']: ' || v_hint.title || ' (-' || v_price || ' Lumen)',
        v_staff.name,
        v_staff.id,
        v_staff.role,
        'approved',
        jsonb_build_object('hint_id', v_hint.id, 'tier', v_hint.tier, 'price', v_price)
    ) RETURNING id INTO v_tx_id;

    -- 9. Ghi nhận team_hints kèm purchase_tx_id để phục vụ hoàn tác
    INSERT INTO team_hints (team_id, hint_id, unlocked_by, purchase_tx_id)
    VALUES (v_team_id, p_hint_id, v_staff.name, v_tx_id);

    -- 10. Trả nội dung manh mối
    RETURN jsonb_build_object(
        'success', true,
        'hint_id', v_hint.id,
        'title', v_hint.title,
        'content', v_hint.content,
        'tier', v_hint.tier,
        'price', v_price,
        'new_balance', v_new_balance,
        'tx_id', v_tx_id,
        'message', 'Đã mua thành công manh mối "' || v_hint.title || '" (-' || v_price || ' Lumen)!'
    );
END;
$$;

-- RPC xem lại manh mối đã mua (miễn phí, không tốn điểm)
CREATE OR REPLACE FUNCTION get_team_unlocked_hints(
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
    v_hints     JSONB;
BEGIN
    v_staff := _require_staff(p_token, ARRAY['team_support', 'admin']);
    v_team_id := v_staff.assigned_team_id;
    IF v_team_id IS NULL AND v_staff.role <> 'admin' THEN
        RAISE EXCEPTION 'FORBIDDEN_TEAM: Chưa được phân công đội.' USING ERRCODE = 'P0005';
    END IF;

    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'hint_id', h.id,
                'title', h.title,
                'content', h.content,
                'tier', h.tier,
                'station_id', h.station_id,
                'unlocked_at', th.unlocked_at,
                'unlocked_by', th.unlocked_by
            ) ORDER BY th.unlocked_at DESC
        ),
        '[]'::jsonb
    ) INTO v_hints
    FROM team_hints th
    JOIN hints h ON h.id = th.hint_id
    WHERE th.team_id = v_team_id;

    RETURN jsonb_build_object('success', true, 'team_id', v_team_id, 'hints', v_hints);
END;
$$;

-- Alias get_team_hints tương thích ngược
CREATE OR REPLACE FUNCTION get_team_hints(p_token TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    RETURN get_team_unlocked_hints(p_token);
END;
$$;

-- ----------------------------------------------------------------------------
-- 2. RPC: PURCHASE_ITEM (MUA ĐẠO CỤ SHOP)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION purchase_item(
    p_token             TEXT,
    p_item_id           UUID,
    p_client_request_id TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_staff         staff%ROWTYPE;
    v_team_id       UUID;
    v_team          teams%ROWTYPE;
    v_item          items%ROWTYPE;
    v_tx_id         UUID;
    v_new_balance   INT;
    v_existing_tx   transactions%ROWTYPE;
    v_shield_dur    INT;
BEGIN
    v_staff := _require_staff(p_token, ARRAY['team_support', 'admin']);
    v_team_id := v_staff.assigned_team_id;
    IF v_team_id IS NULL THEN
        RAISE EXCEPTION 'FORBIDDEN_TEAM: Chưa phân công đội.' USING ERRCODE = 'P0005';
    END IF;

    -- Idempotency Check
    IF p_client_request_id IS NOT NULL AND trim(p_client_request_id) <> '' THEN
        SELECT * INTO v_existing_tx FROM transactions WHERE client_request_id = trim(p_client_request_id);
        IF v_existing_tx.id IS NOT NULL THEN
            RETURN jsonb_build_object('success', true, 'idempotent', true, 'message', 'Đạo cụ đã được mua trước đó.');
        END IF;
    END IF;

    -- Lấy thông tin item
    SELECT * INTO v_item FROM items WHERE id = p_item_id AND is_active = true AND deleted_at IS NULL;
    IF v_item.id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'code', 'ITEM_NOT_FOUND', 'error', 'Đạo cụ không tồn tại hoặc đã ngừng bán.');
    END IF;

    -- Khóa team theo thứ tự toàn cục
    SELECT * INTO v_team FROM teams WHERE id = v_team_id AND is_active = true FOR UPDATE;
    IF v_team.light_balance < v_item.price THEN
        RETURN jsonb_build_object(
            'success', false,
            'code', 'INSUFFICIENT_BALANCE',
            'error', 'Không đủ Lumen! Cần ' || v_item.price || ' Lumen, hiện có ' || v_team.light_balance || ' Lumen.'
        );
    END IF;

    -- Lấy thời lượng khiên nếu là shield
    IF v_item.effect_type = 'shield' THEN
        SELECT COALESCE((value->>'v')::INT, v_item.duration_minutes, 15) INTO v_shield_dur
        FROM game_settings WHERE key = 'shield_duration_minutes';
        IF v_shield_dur IS NULL OR v_shield_dur <= 0 THEN v_shield_dur := 15; END IF;
    END IF;

    -- Trừ tiền
    UPDATE teams 
    SET light_balance = light_balance - v_item.price 
    WHERE id = v_team_id
    RETURNING light_balance INTO v_new_balance;

    -- Ghi Ledger shop_item (metadata chứa item_id, price, duration_minutes)
    INSERT INTO transactions (
        client_request_id,
        team_id,
        amount,
        type,
        description,
        created_by,
        actor_staff_id,
        actor_role,
        status,
        metadata
    ) VALUES (
        p_client_request_id,
        v_team_id,
        -v_item.price,
        'shop_item',
        'Mua đạo cụ ' || v_item.name || ' (-' || v_item.price || ' Lumen)',
        v_staff.name,
        v_staff.id,
        v_staff.role,
        'approved',
        jsonb_build_object(
            'item_id', v_item.id,
            'item_name', v_item.name,
            'effect_type', v_item.effect_type,
            'price', v_item.price,
            'duration_minutes', v_shield_dur
        )
    ) RETURNING id INTO v_tx_id;

    -- Hiệu ứng: Shield tự cộng dồn giờ ngay
    IF v_item.effect_type = 'shield' THEN
        UPDATE teams
        SET shield_until = GREATEST(now(), COALESCE(shield_until, now())) + (v_shield_dur || ' minutes')::INTERVAL
        WHERE id = v_team_id;
    ELSE
        -- Item khác tăng team_items.quantity
        INSERT INTO team_items (team_id, item_id, quantity, used_count)
        VALUES (v_team_id, p_item_id, 1, 0)
        ON CONFLICT (team_id, item_id)
        DO UPDATE SET quantity = team_items.quantity + 1, updated_at = now();
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'item_id', v_item.id,
        'item_name', v_item.name,
        'effect_type', v_item.effect_type,
        'price', v_item.price,
        'new_balance', v_new_balance,
        'tx_id', v_tx_id,
        'message', 'Đã mua thành công "' || v_item.name || '"'
    );
END;
$$;

-- ----------------------------------------------------------------------------
-- 3. RPC: USE_TEAM_ITEM (SỬ DỤNG ĐẠO CỤ VỚI ĐẦY ĐỦ 4 HIỆU ỨNG THỰC TẾ)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION use_team_item(
    p_token             TEXT,
    p_item_id           UUID,
    p_target_team_id    UUID DEFAULT NULL,
    p_target_station_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_staff             staff%ROWTYPE;
    v_team_id           UUID;
    v_inventory         team_items%ROWTYPE;
    v_item              items%ROWTYPE;
    v_target_team       teams%ROWTYPE;
    v_target_station    stations%ROWTYPE;
    v_spy_snapshot      JSONB;
    v_hints_count       INT;
    v_usage_id          UUID;
    v_has_active_key    BOOLEAN;
BEGIN
    v_staff := _require_staff(p_token, ARRAY['team_support', 'admin']);
    v_team_id := v_staff.assigned_team_id;
    IF v_team_id IS NULL THEN
        RAISE EXCEPTION 'FORBIDDEN_TEAM: Chưa phân công đội.' USING ERRCODE = 'P0005';
    END IF;

    -- 1. Khóa dòng team_items có quantity > 0
    SELECT * INTO v_inventory
    FROM team_items
    WHERE team_id = v_team_id AND item_id = p_item_id
    FOR UPDATE;

    IF v_inventory.id IS NULL OR v_inventory.quantity <= 0 THEN
        RETURN jsonb_build_object('success', false, 'code', 'ITEM_NOT_OWNED', 'error', 'Đội không còn vật phẩm này trong kho đồ.');
    END IF;

    SELECT * INTO v_item FROM items WHERE id = p_item_id;

    -- 2. Xử lý nghiệp vụ theo effect_type
    IF v_item.effect_type = 'shield' THEN
        -- Shield: gia hạn khiên
        UPDATE teams
        SET shield_until = GREATEST(now(), COALESCE(shield_until, now())) + (COALESCE(v_item.duration_minutes, 15) || ' minutes')::INTERVAL
        WHERE id = v_team_id;

    ELSIF v_item.effect_type = 'spy' THEN
        -- Spy: bắt buộc p_target_team_id và khác đội mình
        IF p_target_team_id IS NULL OR p_target_team_id = v_team_id THEN
            RETURN jsonb_build_object('success', false, 'code', 'TARGET_SAME_TEAM', 'error', 'Vui lòng chọn một đội đối thủ để do thám.');
        END IF;

        SELECT * INTO v_target_team FROM teams WHERE id = p_target_team_id AND is_active = true;
        IF v_target_team.id IS NULL THEN
            RETURN jsonb_build_object('success', false, 'code', 'TEAM_NOT_FOUND', 'error', 'Đội đối thủ không tồn tại.');
        END IF;

        SELECT COUNT(*) INTO v_hints_count FROM team_hints WHERE team_id = p_target_team_id;

        -- Đúng 5 trường thông số: team_name, light_balance, shield_until, unlocked_stations_count, hints_unlocked_count
        v_spy_snapshot := jsonb_build_object(
            'team_name', v_target_team.name,
            'light_balance', v_target_team.light_balance,
            'shield_until', v_target_team.shield_until,
            'unlocked_stations_count', COALESCE(cardinality(v_target_team.unlocked_stations), 0),
            'hints_unlocked_count', v_hints_count,
            'spied_at', now()
        );

    ELSIF v_item.effect_type = 'key' THEN
        -- Key: bắt buộc p_target_station_id, trạm phải active, đội chưa clear trạm đó (nếu trạm exclusive), chưa có key chưa dùng cho trạm đó
        IF p_target_station_id IS NULL THEN
            RETURN jsonb_build_object('success', false, 'code', 'STATION_REQUIRED', 'error', 'Vui lòng chọn trạm cần tạo chìa khóa mở lối tắt.');
        END IF;

        SELECT * INTO v_target_station FROM stations WHERE id = p_target_station_id AND is_active = true AND deleted_at IS NULL;
        IF v_target_station.id IS NULL THEN
            RETURN jsonb_build_object('success', false, 'code', 'STATION_NOT_FOUND', 'error', 'Trạm thử thách không tồn tại hoặc đã đóng.');
        END IF;

        -- Kiểm tra đội đã clear trạm đó chưa (nếu trạm exclusive)
        IF v_target_station.is_exclusive AND (SELECT v_target_station.id::text = ANY(unlocked_stations) FROM teams WHERE id = v_team_id) THEN
            RETURN jsonb_build_object('success', false, 'code', 'STATION_ALREADY_CLEARED', 'error', 'Đội đã hoàn thành trạm độc quyền này trước đó, không cần dùng chìa khóa.');
        END IF;

        -- Kiểm tra chưa có key chưa dùng cho trạm đó
        SELECT EXISTS (
            SELECT 1 FROM team_station_keys 
            WHERE team_id = v_team_id AND station_id = p_target_station_id AND consumed_claim_id IS NULL
        ) INTO v_has_active_key;

        IF v_has_active_key THEN
            RETURN jsonb_build_object('success', false, 'code', 'KEY_ALREADY_EXISTS', 'error', 'Đội đã có chìa khóa sẵn sàng cho trạm này.');
        END IF;

    ELSIF v_item.effect_type = 'custom' THEN
        -- Custom: chỉ ghi log, UI ghi rõ "hiệu ứng thủ công do BTC xử lý"
        NULL;
    END IF;

    -- 3. Trừ 1 số lượng trong kho đồ
    UPDATE team_items
    SET quantity = quantity - 1,
        used_count = used_count + 1,
        updated_at = now()
    WHERE id = v_inventory.id;

    -- 4. Ghi item_usage_logs
    INSERT INTO item_usage_logs (
        team_id,
        item_id,
        item_name,
        target_team_id,
        target_station_id,
        actor_staff_id,
        actor_role,
        effect_snapshot
    ) VALUES (
        v_team_id,
        v_item.id,
        v_item.name,
        p_target_team_id,
        p_target_station_id,
        v_staff.id,
        v_staff.role,
        COALESCE(v_spy_snapshot, jsonb_build_object('effect_type', v_item.effect_type, 'duration_minutes', v_item.duration_minutes))
    ) RETURNING id INTO v_usage_id;

    -- Tạo team_station_keys nếu là key (Key không tự tặng điểm)
    IF v_item.effect_type = 'key' THEN
        INSERT INTO team_station_keys (team_id, station_id, item_usage_id)
        VALUES (v_team_id, p_target_station_id, v_usage_id);
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'item_id', v_item.id,
        'item_name', v_item.name,
        'effect_type', v_item.effect_type,
        'spy_data', v_spy_snapshot,
        'message', CASE 
            WHEN v_item.effect_type = 'spy' THEN 'Do thám thành công đội ' || v_target_team.name || '!'
            WHEN v_item.effect_type = 'key' THEN 'Đã trang bị Chìa khóa lối tắt cho ' || v_target_station.name || '!'
            WHEN v_item.effect_type = 'shield' THEN 'Đã kích hoạt Khiên Màn Sương!'
            ELSE 'Đã kích hoạt đạo cụ (Hiệu ứng thủ công do BTC xử lý).'
        END
    );
END;
$$;

-- ----------------------------------------------------------------------------
-- 4. RPC: RESOLVE_PVP (GIAO ĐẤU 2 ĐỘI, COOLDOWN 2 CHIỀU & CHỐNG ÂM TUYỆT ĐỐI)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION resolve_pvp(
    p_token             TEXT,
    p_defender_id       UUID,
    p_client_request_id TEXT,
    p_attacker_id       UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_staff             staff%ROWTYPE;
    v_attacker_id       UUID;
    v_atk               teams%ROWTYPE;
    v_def               teams%ROWTYPE;
    v_existing_log      pvp_logs%ROWTYPE;
    v_cooldown_min      INT;
    v_steal_pct         INT;
    v_backlash_amt      INT;
    v_last_combat       TIMESTAMPTZ;
    v_stolen_amount     INT;
    v_actual_penalty    INT;
    v_pvp_group         TEXT;
BEGIN
    -- 1. Xác thực & Attacker lấy từ token (riêng admin có thể chỉ định)
    v_staff := _require_staff(p_token, ARRAY['team_support', 'admin']);
    IF v_staff.role = 'admin' AND p_attacker_id IS NOT NULL THEN
        v_attacker_id := p_attacker_id;
    ELSE
        v_attacker_id := v_staff.assigned_team_id;
    END IF;

    IF v_attacker_id IS NULL THEN
        RAISE EXCEPTION 'FORBIDDEN_TEAM: Chưa phân công đội.' USING ERRCODE = 'P0005';
    END IF;

    -- Chặn tự tấn công
    IF v_attacker_id = p_defender_id THEN
        RETURN jsonb_build_object('success', false, 'code', 'PVP_SAME_TEAM', 'error', 'Không thể tự tấn công chính đội của mình!');
    END IF;

    -- Idempotency check theo client_request_id
    IF p_client_request_id IS NOT NULL AND trim(p_client_request_id) <> '' THEN
        SELECT * INTO v_existing_log FROM pvp_logs WHERE client_request_id = trim(p_client_request_id);
        IF v_existing_log.id IS NOT NULL THEN
            RETURN jsonb_build_object(
                'success', true,
                'idempotent', true,
                'result', v_existing_log.result,
                'stolen_amount', v_existing_log.amount_stolen,
                'message', 'Trận đấu này đã được xử lý trước đó.'
            );
        END IF;
    END IF;

    -- 2. DEADLOCK PREVENTION: Khóa 2 đội theo ID tăng dần
    IF v_attacker_id < p_defender_id THEN
        SELECT * INTO v_atk FROM teams WHERE id = v_attacker_id FOR UPDATE;
        SELECT * INTO v_def FROM teams WHERE id = p_defender_id FOR UPDATE;
    ELSE
        SELECT * INTO v_def FROM teams WHERE id = p_defender_id FOR UPDATE;
        SELECT * INTO v_atk FROM teams WHERE id = v_attacker_id FOR UPDATE;
    END IF;

    IF v_atk.id IS NULL OR v_def.id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'code', 'TEAM_NOT_FOUND', 'error', 'Một trong hai đội không tồn tại.');
    END IF;

    -- 3. CẤU HÌNH LUẬT PVP
    SELECT COALESCE((value->>'v')::INT, 30) INTO v_cooldown_min FROM game_settings WHERE key = 'pvp_cooldown_minutes';
    SELECT COALESCE((value->>'v')::INT, 15) INTO v_steal_pct    FROM game_settings WHERE key = 'pvp_steal_percent';
    SELECT COALESCE((value->>'v')::INT, 10) INTO v_backlash_amt FROM game_settings WHERE key = 'pvp_backlash_amount';

    -- 4. KIỂM TRA COOLDOWN HAI CHIỀU (Sau khi đã khóa 2 đội)
    -- Điều kiện SQL Fix #6: A đánh B hoặc B đánh A trong 30 phút qua
    SELECT created_at INTO v_last_combat
    FROM pvp_logs
    WHERE ((attacker_team_id = v_attacker_id AND defender_team_id = p_defender_id)
       OR  (attacker_team_id = p_defender_id AND defender_team_id = v_attacker_id))
      AND result <> 'cooldown_blocked'
    ORDER BY created_at DESC
    LIMIT 1;

    IF v_last_combat IS NOT NULL AND (now() - v_last_combat) < (v_cooldown_min || ' minutes')::INTERVAL THEN
        INSERT INTO pvp_logs (client_request_id, attacker_team_id, defender_team_id, amount_stolen, result, created_by)
        VALUES (p_client_request_id, v_attacker_id, p_defender_id, 0, 'cooldown_blocked', v_staff.name);

        RETURN jsonb_build_object(
            'success', false,
            'code', 'COOLDOWN_ACTIVE',
            'result', 'cooldown_blocked',
            'error', 'Hai đội vừa giao đấu. Cooldown 2 chiều còn hiệu lực (' || v_cooldown_min || ' phút)!',
            'cooldown_until', v_last_combat + (v_cooldown_min || ' minutes')::INTERVAL
        );
    END IF;

    -- 5. KIỂM TRA KHIÊN CỦA DEFENDER -> PHẢN PHỆ
    IF v_def.shield_until IS NOT NULL AND v_def.shield_until > now() THEN
        -- Backlash = LEAST(số dư attacker, backlash_amount) -> Không bao giờ âm
        v_actual_penalty := LEAST(v_atk.light_balance, v_backlash_amt);

        IF v_actual_penalty > 0 THEN
            UPDATE teams SET light_balance = light_balance - v_actual_penalty WHERE id = v_attacker_id;

            INSERT INTO transactions (
                client_request_id,
                team_id,
                amount,
                type,
                description,
                created_by,
                actor_staff_id,
                actor_role,
                status,
                metadata
            ) VALUES (
                p_client_request_id,
                v_attacker_id,
                -v_actual_penalty,
                'pvp_backlash',
                'Phản phệ PvP: ' || v_def.name || ' có Khiên! Phạt -' || v_actual_penalty || ' Lumen',
                v_staff.name,
                v_staff.id,
                v_staff.role,
                'approved',
                jsonb_build_object('defender_id', p_defender_id, 'nominal_backlash', v_backlash_amt, 'actual_backlash', v_actual_penalty)
            );
        END IF;

        -- Ghi pvp_logs với số tiền thực tế v_actual_penalty
        INSERT INTO pvp_logs (client_request_id, attacker_team_id, defender_team_id, amount_stolen, result, created_by)
        VALUES (p_client_request_id, v_attacker_id, p_defender_id, v_actual_penalty, 'backlash', v_staff.name);

        RETURN jsonb_build_object(
            'success', true,
            'result', 'backlash',
            'backlash_amount', v_actual_penalty,
            'attacker_new_balance', v_atk.light_balance - v_actual_penalty,
            'message', '🛡️ PHẢN PHỆ! ' || v_def.name || ' có Khiên Màn Sương! ' || v_atk.name || ' bị phạt -' || v_actual_penalty || ' Lumen!'
        );
    END IF;

    -- 6. CƯỚP ĐIỂM THÀNH CÔNG: steal FLOOR(số dư defender × 15%)
    v_stolen_amount := FLOOR(v_def.light_balance * (v_steal_pct / 100.0))::INT;

    -- Bằng 0 thì NOTHING_TO_STEAL và không tạo log
    IF v_stolen_amount <= 0 THEN
        RETURN jsonb_build_object(
            'success', false,
            'code', 'NOTHING_TO_STEAL',
            'error', v_def.name || ' không còn Lumen để cướp (Số dư hiện có: ' || v_def.light_balance || '✦).'
        );
    END IF;

    -- Cập nhật số dư 2 bên
    UPDATE teams SET light_balance = light_balance - v_stolen_amount WHERE id = p_defender_id;
    UPDATE teams SET light_balance = light_balance + v_stolen_amount WHERE id = v_attacker_id;

    -- Nhóm 2 dòng transaction bằng pvp_group
    v_pvp_group := 'pvp-' || gen_random_uuid();

    INSERT INTO transactions (team_id, amount, type, description, created_by, actor_staff_id, actor_role, status, metadata) VALUES
        (v_attacker_id, v_stolen_amount, 'pvp_steal',
         'PvP thắng: Cướp +' || v_stolen_amount || ' Lumen từ ' || v_def.name,
         v_staff.name, v_staff.id, v_staff.role, 'approved', jsonb_build_object('pvp_group', v_pvp_group, 'partner_team_id', p_defender_id)),
        (p_defender_id, -v_stolen_amount, 'pvp_steal',
         'PvP thua: Bị ' || v_atk.name || ' cướp -' || v_stolen_amount || ' Lumen',
         v_staff.name, v_staff.id, v_staff.role, 'approved', jsonb_build_object('pvp_group', v_pvp_group, 'partner_team_id', v_attacker_id));

    -- Ghi pvp_logs với số tiền thực tế
    INSERT INTO pvp_logs (client_request_id, attacker_team_id, defender_team_id, amount_stolen, result, created_by)
    VALUES (p_client_request_id, v_attacker_id, p_defender_id, v_stolen_amount, 'success', v_staff.name);

    RETURN jsonb_build_object(
        'success', true,
        'result', 'success',
        'stolen_amount', v_stolen_amount,
        'attacker_new_balance', v_atk.light_balance + v_stolen_amount,
        'defender_new_balance', v_def.light_balance - v_stolen_amount,
        'message', '⚔️ ' || v_atk.name || ' cướp thành công ' || v_stolen_amount || ' Lumen từ ' || v_def.name || '!'
    );
END;
$$;

-- ----------------------------------------------------------------------------
-- 5. RPC: REVERSE_TRANSACTION (MA TRẬN HOÀN TÁC TOÀN DIỆN MỤC 2.6)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION reverse_transaction(
    p_token     TEXT,
    p_tx_id     UUID,
    p_force     BOOLEAN DEFAULT false,
    p_reason    TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_staff             staff%ROWTYPE;
    v_orig_tx           transactions%ROWTYPE;
    v_partner_tx        transactions%ROWTYPE;
    v_team              teams%ROWTYPE;
    v_partner_team      teams%ROWTYPE;
    v_undo_window       INT;
    v_reversal_amt      INT;
    v_partner_rev_amt   INT;
    v_shortfall         INT := 0;
    v_claim             station_claims%ROWTYPE;
    v_reversal_tx_id    UUID;
    v_partner_rev_id    UUID;
    v_shield_dur        INT;
BEGIN
    v_staff := _require_staff(p_token, ARRAY['team_support', 'admin']);

    -- 1. Khóa giao dịch gốc
    SELECT * INTO v_orig_tx FROM transactions WHERE id = p_tx_id FOR UPDATE;
    IF v_orig_tx.id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'code', 'NOT_FOUND', 'error', 'Giao dịch không tồn tại.');
    END IF;

    -- 2. Chặn nếu đã reversed hoặc là dòng bù
    IF v_orig_tx.is_reversed THEN
        RETURN jsonb_build_object('success', false, 'code', 'ALREADY_REVERSED', 'error', 'Giao dịch này đã được hoàn tác trước đó.');
    END IF;

    IF v_orig_tx.reverses_tx_id IS NOT NULL OR v_orig_tx.type = 'reversal' THEN
        RETURN jsonb_build_object('success', false, 'code', 'CANNOT_REVERSE_REVERSAL', 'error', 'Không thể hoàn tác một giao dịch đối ứng bù đắp!');
    END IF;

    IF v_orig_tx.status <> 'approved' THEN
        RETURN jsonb_build_object('success', false, 'code', 'NOT_REVERSIBLE', 'error', 'Chỉ có thể hoàn tác giao dịch đã được phê duyệt.');
    END IF;

    -- 3. Kiểm tra quyền và cửa sổ 5 phút (dùng game_settings) & sở hữu đội
    IF v_staff.role <> 'admin' THEN
        SELECT COALESCE((value->>'v')::INT, 5) INTO v_undo_window FROM game_settings WHERE key = 'undo_window_minutes';
        IF v_undo_window IS NULL THEN v_undo_window := 5; END IF;

        IF (now() - v_orig_tx.created_at) > (v_undo_window || ' minutes')::INTERVAL THEN
            RETURN jsonb_build_object('success', false, 'code', 'UNDO_WINDOW_EXPIRED', 'error', 'Đã hết thời hạn tự hoàn tác (' || v_undo_window || ' phút). Vui lòng báo Admin!');
        END IF;

        IF v_staff.role = 'team_support' AND v_staff.assigned_team_id <> v_orig_tx.team_id THEN
            RETURN jsonb_build_object('success', false, 'code', 'FORBIDDEN', 'error', 'Bạn chỉ có quyền hoàn tác giao dịch của đội mình.');
        END IF;

        IF v_orig_tx.created_by <> v_staff.name AND (v_orig_tx.actor_staff_id IS NULL OR v_orig_tx.actor_staff_id <> v_staff.id) THEN
            RETURN jsonb_build_object('success', false, 'code', 'FORBIDDEN', 'error', 'Bạn chỉ được hoàn tác giao dịch do chính mình tạo ra.');
        END IF;
    END IF;

    -- 4. Khóa team theo thứ tự toàn cục (id ASC)
    IF v_orig_tx.type = 'pvp_steal' AND (v_orig_tx.metadata->>'pvp_group') IS NOT NULL THEN
        -- Tìm giao dịch chân đối tác PvP
        SELECT * INTO v_partner_tx
        FROM transactions
        WHERE metadata->>'pvp_group' = v_orig_tx.metadata->>'pvp_group'
          AND id <> v_orig_tx.id
          AND is_reversed = false
        FOR UPDATE;

        IF v_partner_tx.id IS NOT NULL THEN
            IF v_orig_tx.team_id < v_partner_tx.team_id THEN
                SELECT * INTO v_team FROM teams WHERE id = v_orig_tx.team_id FOR UPDATE;
                SELECT * INTO v_partner_team FROM teams WHERE id = v_partner_tx.team_id FOR UPDATE;
            ELSE
                SELECT * INTO v_partner_team FROM teams WHERE id = v_partner_tx.team_id FOR UPDATE;
                SELECT * INTO v_team FROM teams WHERE id = v_orig_tx.team_id FOR UPDATE;
            END IF;
        ELSE
            SELECT * INTO v_team FROM teams WHERE id = v_orig_tx.team_id FOR UPDATE;
        END IF;
    ELSE
        SELECT * INTO v_team FROM teams WHERE id = v_orig_tx.team_id FOR UPDATE;
    END IF;

    -- 5. KIỂM TRA SỐ DƯ (INSUFFICIENT_BALANCE_FOR_REVERT, riêng admin có p_force và ghi shortfall)
    IF v_orig_tx.amount > 0 THEN
        IF v_team.light_balance < v_orig_tx.amount THEN
            IF v_staff.role = 'admin' AND p_force = true THEN
                v_shortfall := v_orig_tx.amount - v_team.light_balance;
                v_reversal_amt := -v_team.light_balance;
            ELSE
                RETURN jsonb_build_object(
                    'success', false,
                    'code', 'INSUFFICIENT_BALANCE_FOR_REVERT',
                    'error', 'Không thể hoàn tác! Đội đã sử dụng số Lumen này (Cần thu hồi ' || v_orig_tx.amount || '✦, hiện chỉ còn ' || v_team.light_balance || '✦). Báo Admin dùng force-revert!'
                );
            END IF;
        ELSE
            v_reversal_amt := -v_orig_tx.amount;
        END IF;
    ELSE
        -- Giao dịch gốc trừ tiền (amount < 0) -> Hoàn tác là cộng trả lại tiền
        v_reversal_amt := -v_orig_tx.amount;
    END IF;

    -- 6. CHẠY SIDE-EFFECT THEO MA TRẬN MỤC 2.6
    -- a. Claim & unlocked_stations & keys
    IF v_orig_tx.type = 'station_clear' AND v_orig_tx.claim_id IS NOT NULL THEN
        SELECT * INTO v_claim FROM station_claims WHERE id = v_orig_tx.claim_id FOR UPDATE;
        IF v_claim.id IS NOT NULL THEN
            UPDATE station_claims SET status = 'cancelled', updated_at = now() WHERE id = v_claim.id;
            UPDATE teams 
            SET unlocked_stations = array_remove(unlocked_stations, v_claim.station_id::text)
            WHERE id = v_orig_tx.team_id;
            IF v_claim.key_used = true THEN
                UPDATE team_station_keys SET consumed_claim_id = NULL WHERE consumed_claim_id = v_claim.id;
            END IF;
        END IF;

    -- b. team_hints
    ELSIF v_orig_tx.type IN ('hint_purchase', 'buy_hint') THEN
        DELETE FROM team_hints WHERE purchase_tx_id = v_orig_tx.id;

    -- c. team_items & shield_until
    ELSIF v_orig_tx.type IN ('shop_item', 'buy_item') THEN
        IF (v_orig_tx.metadata->>'effect_type') = 'shield' THEN
            v_shield_dur := COALESCE((v_orig_tx.metadata->>'duration_minutes')::INT, 15);
            UPDATE teams 
            SET shield_until = CASE 
                WHEN shield_until <= now() THEN shield_until 
                ELSE GREATEST(now(), shield_until - (v_shield_dur || ' minutes')::INTERVAL)
            END
            WHERE id = v_orig_tx.team_id;
        ELSIF (v_orig_tx.metadata->>'item_id') IS NOT NULL THEN
            UPDATE team_items 
            SET quantity = GREATEST(0, quantity - 1)
            WHERE team_id = v_orig_tx.team_id AND item_id = (v_orig_tx.metadata->>'item_id')::UUID;
        END IF;

    -- d. Hai chân PvP
    ELSIF v_orig_tx.type = 'pvp_steal' AND v_partner_tx.id IS NOT NULL THEN
        IF v_partner_tx.amount > 0 AND v_partner_team.light_balance < v_partner_tx.amount THEN
            IF v_staff.role = 'admin' AND p_force = true THEN
                v_partner_rev_amt := -v_partner_team.light_balance;
            ELSE
                RETURN jsonb_build_object(
                    'success', false,
                    'code', 'INSUFFICIENT_BALANCE_FOR_REVERT',
                    'error', 'Không thể hoàn tác trận PvP! Đội đối tác đã tiêu mất số Lumen cướp được.'
                );
            END IF;
        ELSE
            v_partner_rev_amt := -v_partner_tx.amount;
        END IF;

        UPDATE teams SET light_balance = light_balance + v_partner_rev_amt WHERE id = v_partner_tx.team_id;
        UPDATE transactions SET is_reversed = true WHERE id = v_partner_tx.id;

        INSERT INTO transactions (
            team_id, amount, type, description, created_by, actor_staff_id, actor_role, status, reverses_tx_id, metadata
        ) VALUES (
            v_partner_tx.team_id, v_partner_rev_amt, 'reversal',
            'Hoàn tác chân đối tác PvP #' || substr(v_partner_tx.id::text, 1, 8),
            v_staff.name, v_staff.id, v_staff.role, 'approved', v_partner_tx.id,
            jsonb_build_object('pvp_group', v_orig_tx.metadata->>'pvp_group', 'partner_tx_id', v_partner_tx.id)
        ) RETURNING id INTO v_partner_rev_id;
    END IF;

    -- 7. Cập nhật số dư đội, thêm dòng bù có reverses_tx_id, đặt is_reversed
    UPDATE teams SET light_balance = light_balance + v_reversal_amt WHERE id = v_orig_tx.team_id;
    UPDATE transactions SET is_reversed = true WHERE id = v_orig_tx.id;

    INSERT INTO transactions (
        team_id,
        amount,
        type,
        description,
        created_by,
        actor_staff_id,
        actor_role,
        status,
        reverses_tx_id,
        metadata
    ) VALUES (
        v_orig_tx.team_id,
        v_reversal_amt,
        'reversal',
        'Hoàn tác giao dịch #' || substr(v_orig_tx.id::text, 1, 8) || ' (' || COALESCE(p_reason, 'Sai sót') || ')',
        v_staff.name,
        v_staff.id,
        v_staff.role,
        'approved',
        v_orig_tx.id,
        jsonb_build_object(
            'reversed_tx_id', v_orig_tx.id,
            'orig_type', v_orig_tx.type,
            'shortfall', v_shortfall,
            'force', p_force
        )
    ) RETURNING id INTO v_reversal_tx_id;

    RETURN jsonb_build_object(
        'success', true,
        'reversal_id', v_reversal_tx_id,
        'amount_adjusted', v_reversal_amt,
        'shortfall', v_shortfall,
        'message', 'Đã hoàn tác giao dịch thành công!'
    );
END;
$$;

-- ----------------------------------------------------------------------------
-- 6. RPC: ADMIN_ADJUST_BALANCE (ADMIN ĐIỀU CHỈNH SỐ DƯ CÓ LEDGER BẮT BUỘC)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION admin_adjust_balance(
    p_token     TEXT,
    p_team_id   UUID,
    p_delta     INT,
    p_reason    TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_admin         staff%ROWTYPE;
    v_team          teams%ROWTYPE;
    v_tx_id         UUID;
    v_new_balance   INT;
BEGIN
    -- 1. Chỉ admin
    v_admin := _require_staff(p_token, ARRAY['admin']);

    -- 2. p_delta khác 0
    IF p_delta IS NULL OR p_delta = 0 THEN
        RETURN jsonb_build_object('success', false, 'code', 'INVALID_AMOUNT', 'error', 'Số điểm điều chỉnh phải khác 0.');
    END IF;

    -- 3. p_reason bắt buộc
    IF p_reason IS NULL OR trim(p_reason) = '' THEN
        RETURN jsonb_build_object('success', false, 'code', 'REASON_REQUIRED', 'error', 'Bắt buộc phải nhập lý do điều chỉnh số dư.');
    END IF;

    -- 4. Khóa team theo thứ tự toàn cục
    SELECT * INTO v_team FROM teams WHERE id = p_team_id AND is_active = true FOR UPDATE;
    IF v_team.id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'code', 'TEAM_NOT_FOUND', 'error', 'Đội chơi không tồn tại.');
    END IF;

    -- 5. Nếu làm số dư âm thì lỗi INSUFFICIENT_BALANCE
    IF v_team.light_balance + p_delta < 0 THEN
        RETURN jsonb_build_object(
            'success', false,
            'code', 'INSUFFICIENT_BALANCE',
            'error', 'Không thể trừ vượt quá số dư hiện có! (Hiện có: ' || v_team.light_balance || '✦, điều chỉnh: ' || p_delta || '✦).'
        );
    END IF;

    -- 6. Cập nhật số dư & Ghi ledger admin_adjust
    UPDATE teams 
    SET light_balance = light_balance + p_delta 
    WHERE id = p_team_id
    RETURNING light_balance INTO v_new_balance;

    INSERT INTO transactions (
        team_id,
        amount,
        type,
        description,
        created_by,
        status,
        actor_staff_id,
        actor_role,
        metadata
    ) VALUES (
        p_team_id,
        p_delta,
        'admin_adjust',
        'Admin điều chỉnh: ' || trim(p_reason),
        v_admin.name,
        'approved',
        v_admin.id,
        'admin',
        jsonb_build_object('reason', trim(p_reason), 'previous_balance', v_team.light_balance, 'new_balance', v_new_balance)
    ) RETURNING id INTO v_tx_id;

    RETURN jsonb_build_object(
        'success', true,
        'team_id', p_team_id,
        'delta', p_delta,
        'new_balance', v_new_balance,
        'tx_id', v_tx_id,
        'message', 'Đã điều chỉnh ' || CASE WHEN p_delta > 0 THEN '+' ELSE '' END || p_delta || ' Lumen cho đội ' || v_team.name
    );
END;
$$;

-- ----------------------------------------------------------------------------
-- 7. CÁC RPC ĐỌC CÓ PHÂN QUYỀN
-- ----------------------------------------------------------------------------

-- 7a. GET_HISTORY (Tự động tính can_reverse và reverse_blocked_reason)
CREATE OR REPLACE FUNCTION get_history(
    p_token     TEXT,
    p_team_id   UUID DEFAULT NULL,
    p_limit     INT DEFAULT 50
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_staff         staff%ROWTYPE;
    v_undo_window   INT;
    v_result        JSONB;
BEGIN
    v_staff := _require_staff(p_token, ARRAY['team_support', 'station_master', 'admin']);

    SELECT COALESCE((value->>'v')::INT, 5) INTO v_undo_window FROM game_settings WHERE key = 'undo_window_minutes';
    IF v_undo_window IS NULL THEN v_undo_window := 5; END IF;

    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'id', tx.id,
                'team_id', tx.team_id,
                'team_name', t.name,
                'amount', tx.amount,
                'type', tx.type,
                'description', tx.description,
                'created_by', tx.created_by,
                'status', tx.status,
                'is_reversed', tx.is_reversed,
                'reverses_tx_id', tx.reverses_tx_id,
                'created_at', tx.created_at,
                'can_reverse', (
                    NOT tx.is_reversed 
                    AND tx.status = 'approved' 
                    AND tx.type <> 'reversal' 
                    AND tx.reverses_tx_id IS NULL
                    AND (
                        v_staff.role = 'admin' 
                        OR (
                            (tx.created_by = v_staff.name OR tx.actor_staff_id = v_staff.id) 
                            AND (v_staff.role <> 'team_support' OR tx.team_id = v_staff.assigned_team_id)
                            AND (now() - tx.created_at) <= (v_undo_window || ' minutes')::INTERVAL
                        )
                    )
                ),
                'reverse_blocked_reason', CASE
                    WHEN tx.is_reversed THEN 'Giao dịch đã được hoàn tác'
                    WHEN tx.type = 'reversal' OR tx.reverses_tx_id IS NOT NULL THEN 'Không thể hoàn tác giao dịch bù đắp'
                    WHEN tx.status <> 'approved' THEN 'Giao dịch chưa được phê duyệt'
                    WHEN v_staff.role <> 'admin' AND (now() - tx.created_at) > (v_undo_window || ' minutes')::INTERVAL THEN 'Đã quá thời hạn hoàn tác (' || v_undo_window || ' phút)'
                    WHEN v_staff.role = 'team_support' AND tx.team_id <> v_staff.assigned_team_id THEN 'Chỉ có thể hoàn tác giao dịch của đội mình'
                    WHEN v_staff.role <> 'admin' AND tx.created_by <> v_staff.name AND (tx.actor_staff_id IS NULL OR tx.actor_staff_id <> v_staff.id) THEN 'Chỉ người tạo mới được hoàn tác'
                    ELSE NULL
                END
            ) ORDER BY tx.created_at DESC
        ),
        '[]'::jsonb
    ) INTO v_result
    FROM (
        SELECT * FROM transactions
        WHERE (p_team_id IS NULL OR team_id = p_team_id)
        ORDER BY created_at DESC
        LIMIT COALESCE(p_limit, 50)
    ) tx
    JOIN teams t ON t.id = tx.team_id;

    RETURN jsonb_build_object('success', true, 'transactions', v_result);
END;
$$;

-- 7b. GET_TEAM_DASHBOARD (Trạng thái tổng thể của đội)
CREATE OR REPLACE FUNCTION get_team_dashboard(
    p_token     TEXT,
    p_team_id   UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_staff         staff%ROWTYPE;
    v_team_id       UUID;
    v_team          teams%ROWTYPE;
    v_items         JSONB;
    v_hints_count   INT;
BEGIN
    v_staff := _require_staff(p_token, ARRAY['team_support', 'admin']);
    IF v_staff.role = 'admin' AND p_team_id IS NOT NULL THEN
        v_team_id := p_team_id;
    ELSE
        v_team_id := v_staff.assigned_team_id;
    END IF;

    IF v_team_id IS NULL THEN
        RAISE EXCEPTION 'FORBIDDEN_TEAM: Chưa phân công đội.' USING ERRCODE = 'P0005';
    END IF;

    SELECT * INTO v_team FROM teams WHERE id = v_team_id;
    SELECT COUNT(*) INTO v_hints_count FROM team_hints WHERE team_id = v_team_id;

    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'item_id', ti.item_id,
                'name', i.name,
                'description', i.description,
                'effect_type', i.effect_type,
                'quantity', ti.quantity,
                'used_count', ti.used_count
            )
        ),
        '[]'::jsonb
    ) INTO v_items
    FROM team_items ti
    JOIN items i ON i.id = ti.item_id
    WHERE ti.team_id = v_team_id AND ti.quantity > 0;

    RETURN jsonb_build_object(
        'success', true,
        'team', jsonb_build_object(
            'id', v_team.id,
            'name', v_team.name,
            'qr_code', v_team.qr_code,
            'light_balance', v_team.light_balance,
            'shield_until', v_team.shield_until,
            'is_shielded', (v_team.shield_until IS NOT NULL AND v_team.shield_until > now()),
            'unlocked_stations_count', COALESCE(cardinality(v_team.unlocked_stations), 0),
            'hints_count', v_hints_count
        ),
        'inventory', v_items
    );
END;
$$;

-- 7c. ADMIN_GET_AUDIT_LOG (Dành riêng cho Admin)
CREATE OR REPLACE FUNCTION admin_get_audit_log(
    p_token     TEXT,
    p_filter    TEXT DEFAULT 'all',
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
                'id', tx.id,
                'team_id', tx.team_id,
                'team_name', t.name,
                'amount', tx.amount,
                'type', tx.type,
                'description', tx.description,
                'created_by', tx.created_by,
                'actor_staff_id', tx.actor_staff_id,
                'actor_role', tx.actor_role,
                'status', tx.status,
                'is_reversed', tx.is_reversed,
                'reverses_tx_id', tx.reverses_tx_id,
                'claim_id', tx.claim_id,
                'metadata', tx.metadata,
                'created_at', tx.created_at,
                'can_reverse', (
                    NOT tx.is_reversed 
                    AND tx.status = 'approved' 
                    AND tx.type <> 'reversal' 
                    AND tx.reverses_tx_id IS NULL
                ),
                'reverse_blocked_reason', CASE
                    WHEN tx.is_reversed THEN 'Giao dịch đã được hoàn tác'
                    WHEN tx.type = 'reversal' OR tx.reverses_tx_id IS NOT NULL THEN 'Không thể hoàn tác giao dịch bù đắp'
                    WHEN tx.status <> 'approved' THEN 'Giao dịch chưa được phê duyệt'
                    ELSE NULL
                END
            ) ORDER BY tx.created_at DESC
        ),
        '[]'::jsonb
    ) INTO v_logs
    FROM (
        SELECT * FROM transactions
        WHERE (
            p_filter = 'all'
            OR (p_filter = 'station' AND type = 'station_clear')
            OR (p_filter = 'shop' AND type IN ('buy_hint', 'hint_purchase', 'buy_item', 'shop_item'))
            OR (p_filter = 'pvp' AND type IN ('pvp_steal', 'pvp_backlash'))
            OR (p_filter = 'reversal' AND type = 'reversal')
        )
        ORDER BY created_at DESC
        LIMIT COALESCE(p_limit, 100)
    ) tx
    JOIN teams t ON t.id = tx.team_id;

    RETURN jsonb_build_object('success', true, 'audit_logs', v_logs);
END;
$$;

-- 7d. ADMIN_GET_LEADERBOARD
CREATE OR REPLACE FUNCTION admin_get_leaderboard(
    p_token TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_staff staff%ROWTYPE;
    v_board JSONB;
BEGIN
    v_staff := _require_staff(p_token, ARRAY['admin', 'station_master', 'team_support']);

    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'id', id,
                'name', name,
                'light_balance', light_balance,
                'shield_until', shield_until,
                'unlocked_stations_count', COALESCE(cardinality(unlocked_stations), 0),
                'is_shielded', (shield_until IS NOT NULL AND shield_until > now())
            ) ORDER BY light_balance DESC, name ASC
        ),
        '[]'::jsonb
    ) INTO v_board
    FROM teams
    WHERE is_active = true;

    RETURN jsonb_build_object('success', true, 'leaderboard', v_board);
END;
$$;

-- ----------------------------------------------------------------------------
-- 8. PHÂN QUYỀN EXECUTE PUBLIC RPCS
-- ----------------------------------------------------------------------------
REVOKE ALL ON FUNCTION purchase_hint(TEXT, UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION purchase_hint(TEXT, UUID, TEXT) TO anon, authenticated;

REVOKE ALL ON FUNCTION get_team_unlocked_hints(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_team_unlocked_hints(TEXT) TO anon, authenticated;

REVOKE ALL ON FUNCTION get_team_hints(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_team_hints(TEXT) TO anon, authenticated;

REVOKE ALL ON FUNCTION purchase_item(TEXT, UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION purchase_item(TEXT, UUID, TEXT) TO anon, authenticated;

REVOKE ALL ON FUNCTION use_team_item(TEXT, UUID, UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION use_team_item(TEXT, UUID, UUID, UUID) TO anon, authenticated;

REVOKE ALL ON FUNCTION resolve_pvp(TEXT, UUID, TEXT, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION resolve_pvp(TEXT, UUID, TEXT, UUID) TO anon, authenticated;

REVOKE ALL ON FUNCTION reverse_transaction(TEXT, UUID, BOOLEAN, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION reverse_transaction(TEXT, UUID, BOOLEAN, TEXT) TO anon, authenticated;

REVOKE ALL ON FUNCTION admin_adjust_balance(TEXT, UUID, INT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION admin_adjust_balance(TEXT, UUID, INT, TEXT) TO anon, authenticated;

REVOKE ALL ON FUNCTION get_history(TEXT, UUID, INT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_history(TEXT, UUID, INT) TO anon, authenticated;

REVOKE ALL ON FUNCTION get_team_dashboard(TEXT, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_team_dashboard(TEXT, UUID) TO anon, authenticated;

REVOKE ALL ON FUNCTION admin_get_audit_log(TEXT, TEXT, INT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION admin_get_audit_log(TEXT, TEXT, INT) TO anon, authenticated;

REVOKE ALL ON FUNCTION admin_get_leaderboard(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION admin_get_leaderboard(TEXT) TO anon, authenticated;
