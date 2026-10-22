-- =====================================================================
-- MIGRATION 107: FIX AUTH & ENFORCE STATION / SUPPORT PERMISSIONS
-- Dự án: Evermyst Command Center v2.0 (ProPTIT BigGame D26)
-- Khớp 100% Schema thực tế:
--   - staff_sessions(token)
--   - staff(id, name, role, station_assigned, pin, is_active)
--   - station_plays(reversed_by TEXT, reversed_at TIMESTAMPTZ)
-- =====================================================================

BEGIN;

-- ---------------------------------------------------------------------
-- 1. BẢO ĐẢM EXTENSION PGCRYPTO VÀ CẤP QUYỀN TRUY CẬP SCHEMA EXTENSIONS
-- ---------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;
GRANT USAGE ON SCHEMA extensions TO anon, authenticated, service_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA extensions TO anon, authenticated, service_role;

-- ---------------------------------------------------------------------
-- 2. CẬP NHẬT HÀM NỘI BỘ _require_staff: DÙNG TRỰC TIẾP ss.token
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._require_staff(
    p_token     TEXT,
    p_roles     TEXT[] DEFAULT NULL
)
RETURNS staff
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
    v_session       staff_sessions%ROWTYPE;
    v_staff         staff%ROWTYPE;
BEGIN
    IF p_token IS NULL OR trim(p_token) = '' THEN
        RAISE EXCEPTION 'UNAUTHENTICATED: Yêu cầu cung cấp session token.' USING ERRCODE = 'P0001';
    END IF;

    -- Truy vấn session còn hiệu lực qua cột ss.token
    SELECT * INTO v_session
    FROM staff_sessions
    WHERE token = trim(p_token)
      AND expires_at > now();

    IF v_session.id IS NULL THEN
        RAISE EXCEPTION 'UNAUTHENTICATED: Phiên làm việc không tồn tại hoặc đã hết hạn.' USING ERRCODE = 'P0001';
    END IF;

    -- Truy vấn thông tin nhân sự trực tiếp từ bảng staff
    SELECT * INTO v_staff
    FROM staff
    WHERE id = v_session.staff_id;

    IF v_staff.id IS NULL OR v_staff.is_active = false THEN
        RAISE EXCEPTION 'UNAUTHENTICATED: Tài khoản nhân sự đã bị vô hiệu hóa hoặc không tồn tại.' USING ERRCODE = 'P0001';
    END IF;

    -- Kiểm tra phân quyền role nếu có danh sách yêu cầu
    IF p_roles IS NOT NULL AND array_length(p_roles, 1) > 0 THEN
        IF NOT (v_staff.role = ANY(p_roles)) THEN
            RAISE EXCEPTION 'FORBIDDEN_ROLE: Bạn không có quyền thực hiện thao tác này (yêu cầu role: %).',
                array_to_string(p_roles, ', ')
            USING ERRCODE = 'P0003';
        END IF;
    END IF;

    RETURN v_staff;
END;
$$;

-- ---------------------------------------------------------------------
-- 3. NÂNG CẤP HÀM award_station_direct_points:
--    - Xác thực bằng ss.token
--    - CHẶN HOÀN TOÀN Support Đội (role = 'support' VÀ station_assigned rỗng)
--    - Tự chữa lành mã trạm (Self-healing Station Lookup)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.award_station_direct_points(
  p_token             TEXT,
  p_team_id           UUID,
  p_station_id        UUID,
  p_points            INTEGER,
  p_client_request_id TEXT,
  p_note              TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_auth                  RECORD;
  v_station               RECORD;
  v_team                  RECORD;
  v_existing_play         RECORD;
  v_active_count          INTEGER;
  v_max_play_no           INTEGER;
  v_play_no               INTEGER;
  v_play_id               UUID;
  v_tx_id                 UUID := NULL;
  v_new_balance           INTEGER;
  v_unlocked              TEXT[];
  v_target_order          INTEGER;
BEGIN
  -- 1. Xác thực session token qua cột token có thật trong staff_sessions
  IF p_token IS NULL OR trim(p_token) = '' THEN
    RETURN public._direct_scoring_err('INVALID_TOKEN', 'Phiên làm việc không tồn tại hoặc đã hết hạn.');
  END IF;

  SELECT ss.staff_id, s.name AS staff_name, s.role AS staff_role, s.station_assigned
  INTO v_auth
  FROM public.staff_sessions ss
  JOIN public.staff s ON s.id = ss.staff_id
  WHERE ss.token = trim(p_token)
    AND ss.expires_at > now()
    AND s.is_active = true
  LIMIT 1;

  IF v_auth.staff_id IS NULL THEN
    RETURN public._direct_scoring_err('INVALID_TOKEN', 'Phiên làm việc không tồn tại hoặc đã hết hạn.');
  END IF;

  -- 2. Tự chữa lành mã trạm (Self-healing Station Lookup theo order_index)
  SELECT * INTO v_station
  FROM public.stations
  WHERE id = p_station_id AND deleted_at IS NULL;

  IF NOT FOUND THEN
    SELECT order_index INTO v_target_order
    FROM public.stations
    WHERE id = p_station_id;

    IF v_target_order IS NOT NULL THEN
      SELECT * INTO v_station
      FROM public.stations
      WHERE order_index = v_target_order AND deleted_at IS NULL
      ORDER BY created_at DESC
      LIMIT 1;

      IF FOUND THEN
        p_station_id := v_station.id;
      END IF;
    END IF;
  END IF;

  IF v_station.id IS NULL THEN
    RETURN public._direct_scoring_err('STATION_NOT_FOUND', 'Không tìm thấy trạm thử thách hoặc trạm đã đóng.');
  END IF;

  IF NOT v_station.is_active THEN
    RETURN public._direct_scoring_err('STATION_INACTIVE', 'Trạm thử thách này đang tạm khóa.');
  END IF;

  -- 3. Phân quyền nghiệp vụ mới:
  --    - Admin: Toàn quyền chấm mọi trạm
  --    - Support Đội (role = 'team_support' hoặc role = 'support' mà station_assigned NULL/rỗng): CHẶN TUYỆT ĐỐI
  --    - Quản Trò Trạm (role = 'station_master' hoặc role = 'support' có station_assigned): Cho phép nếu khớp trạm
  IF v_auth.staff_role = 'admin' THEN
    NULL;
  ELSIF v_auth.staff_role = 'team_support' OR (v_auth.staff_role = 'support' AND (v_auth.station_assigned IS NULL OR btrim(v_auth.station_assigned) = '')) THEN
    RETURN public._direct_scoring_err(
      'FORBIDDEN',
      'Support đội không có quyền cộng điểm trạm. Chỉ Quản trò trạm hoặc Ban tổ chức mới có thể chấm điểm.'
    );
  ELSIF v_auth.staff_role = 'station_master' OR (v_auth.staff_role = 'support' AND btrim(v_auth.station_assigned) <> '') THEN
    -- Quản trò trạm: kiểm tra phân công trạm nếu station_assigned có giá trị
    IF v_auth.station_assigned IS NOT NULL AND btrim(v_auth.station_assigned) <> '' THEN
      IF v_auth.station_assigned = p_station_id::TEXT THEN
        NULL;
      ELSIF v_station.name ILIKE '%' || btrim(v_auth.station_assigned) || '%' 
         OR btrim(v_auth.station_assigned) ILIKE '%' || v_station.name || '%'
         OR btrim(v_auth.station_assigned) ILIKE '%trạm ' || v_station.order_index || '%'
         OR btrim(v_auth.station_assigned) = v_station.order_index::TEXT THEN
        NULL;
      ELSE
        RETURN public._direct_scoring_err('FORBIDDEN_STATION', 'Bạn không được phân công phụ trách trạm này.');
      END IF;
    END IF;
  ELSE
    RETURN public._direct_scoring_err('FORBIDDEN', 'Bạn không có quyền nhập điểm trạm.');
  END IF;

  -- 4. Kiểm tra trạng thái tạm dừng game
  IF EXISTS (
    SELECT 1 FROM public.game_settings 
    WHERE key = 'game_status' AND (value->>'v' = 'paused' OR value->>'status' = 'paused')
  ) THEN
    RETURN public._direct_scoring_err('GAME_NOT_RUNNING', 'Trò chơi hiện đang tạm dừng.');
  END IF;

  -- 5. Validate dữ liệu đầu vào
  IF p_client_request_id IS NULL OR length(btrim(p_client_request_id)) = 0 THEN
    RETURN public._direct_scoring_err('INVALID_REQUEST_ID', 'Thiếu mã yêu cầu (client_request_id).');
  END IF;

  IF p_points IS NULL OR p_points <= 0 THEN
    RETURN public._direct_scoring_err('INVALID_AMOUNT', 'Số điểm cộng phải là số nguyên dương (> 0).');
  END IF;

  -- 6. Khóa dòng đội chơi chống Race Condition
  SELECT * INTO v_team
  FROM public.teams
  WHERE id = p_team_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN public._direct_scoring_err('TEAM_NOT_FOUND', 'Không tìm thấy đội chơi.');
  END IF;
  IF NOT v_team.is_active THEN
    RETURN public._direct_scoring_err('TEAM_INACTIVE', 'Đội chơi này đang bị vô hiệu hóa.');
  END IF;

  -- 7. Idempotency Check
  SELECT * INTO v_existing_play
  FROM public.station_plays
  WHERE client_request_id = p_client_request_id;

  IF FOUND THEN
    RETURN jsonb_build_object(
      'success', true,
      'ok', true,
      'code', 'OK',
      'message', 'Yêu cầu đã được xử lý trước đó.',
      'error', null,
      'replayed', true,
      'idempotent', true,
      'data', jsonb_build_object(
        'play_id', v_existing_play.id,
        'tx_id', v_existing_play.tx_id,
        'points', v_existing_play.points,
        'play_no', v_existing_play.play_no,
        'new_balance', v_team.light_balance
      )
    );
  END IF;

  -- 8. Kiểm tra số lượt chơi
  SELECT count(*) FILTER (WHERE status = 'active'),
         COALESCE(max(play_no), 0)
  INTO v_active_count, v_max_play_no
  FROM public.station_plays
  WHERE team_id = p_team_id AND station_id = p_station_id;

  IF NOT v_station.allow_multiple_attempts AND v_active_count > 0 THEN
    RETURN public._direct_scoring_err(
      'STATION_ALREADY_PLAYED',
      'Đội này đã hoàn thành trạm 1 lượt này rồi.',
      jsonb_build_object('play_count', v_active_count)
    );
  END IF;

  v_play_no := v_max_play_no + 1;

  -- 9. Ghi lượt chơi vào station_plays
  INSERT INTO public.station_plays (
    team_id, station_id, play_no, points, status,
    staff_id, staff_name, note, client_request_id
  ) VALUES (
    p_team_id, p_station_id, v_play_no, p_points, 'active',
    v_auth.staff_id, v_auth.staff_name, p_note, p_client_request_id
  ) RETURNING id INTO v_play_id;

  -- 10. Ghi sổ cái transactions
  INSERT INTO public.transactions (
    team_id,
    amount,
    type,
    description,
    created_by,
    client_request_id,
    is_reversed
  ) VALUES (
    p_team_id,
    p_points,
    'station_clear',
    format('Vượt trạm %s lượt %s (+%s Lumen)', v_station.name, v_play_no, p_points),
    v_auth.staff_name,
    p_client_request_id,
    false
  ) RETURNING id INTO v_tx_id;

  UPDATE public.station_plays
  SET tx_id = v_tx_id
  WHERE id = v_play_id;

  -- 11. Cập nhật số dư và mảng unlocked_stations
  v_new_balance := v_team.light_balance + p_points;
  v_unlocked := COALESCE(v_team.unlocked_stations, ARRAY[]::TEXT[]);

  IF NOT (p_station_id::TEXT = ANY(v_unlocked)) THEN
    v_unlocked := array_append(v_unlocked, p_station_id::TEXT);
  END IF;

  UPDATE public.teams
  SET light_balance = v_new_balance,
      unlocked_stations = v_unlocked
  WHERE id = p_team_id;

  -- 12. Phản hồi thành công
  RETURN jsonb_build_object(
    'success', true,
    'ok', true,
    'code', 'OK',
    'message', format('Đã cộng +%s Lumen cho đội %s thành công!', p_points, v_team.name),
    'error', null,
    'data', jsonb_build_object(
      'play_id', v_play_id,
      'tx_id', v_tx_id,
      'points', p_points,
      'play_no', v_play_no,
      'new_balance', v_new_balance,
      'station_name', v_station.name,
      'team_name', v_team.name
    )
  );
END;
$$;

-- ---------------------------------------------------------------------
-- 4. BỔ SUNG THAM SỐ p_client_request_id CHO reverse_transaction
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.reverse_transaction(
    p_token             TEXT,
    p_tx_id             UUID,
    p_force             BOOLEAN DEFAULT false,
    p_reason            TEXT DEFAULT NULL,
    p_client_request_id TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
    v_admin             RECORD;
    v_orig_tx           transactions%ROWTYPE;
    v_team              teams%ROWTYPE;
    v_reversal_amt      INT;
    v_reversal_tx_id    UUID;
    v_new_balance       INT;
BEGIN
    -- 1. Xác thực quyền Admin qua ss.token
    IF p_token IS NULL OR trim(p_token) = '' THEN
        RETURN jsonb_build_object('success', false, 'code', 'UNAUTHENTICATED', 'error', 'Token rỗng.');
    END IF;

    SELECT s.id, s.name, s.role
    INTO v_admin
    FROM public.staff_sessions ss
    JOIN public.staff s ON s.id = ss.staff_id
    WHERE ss.token = trim(p_token)
      AND ss.expires_at > now()
      AND s.is_active = true
      AND s.role = 'admin'
    LIMIT 1;

    IF v_admin.id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'code', 'FORBIDDEN_ROLE', 'error', 'Chỉ Ban Tổ Chức mới có quyền hoàn tác giao dịch.');
    END IF;

    -- 2. Khóa và lấy thông tin giao dịch gốc
    SELECT * INTO v_orig_tx FROM transactions WHERE id = p_tx_id FOR UPDATE;
    IF v_orig_tx.id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'code', 'TX_NOT_FOUND', 'error', 'Không tìm thấy giao dịch cần hoàn tác.');
    END IF;

    IF v_orig_tx.is_reversed THEN
        RETURN jsonb_build_object('success', false, 'code', 'ALREADY_REVERSED', 'error', 'Giao dịch này đã được hoàn tác trước đó.');
    END IF;

    IF v_orig_tx.type = 'reversal' THEN
        RETURN jsonb_build_object('success', false, 'code', 'CANNOT_REVERSE_REVERSAL', 'error', 'Không thể hoàn tác giao dịch bù trừ.');
    END IF;

    -- 3. Khóa đội chơi
    SELECT * INTO v_team FROM teams WHERE id = v_orig_tx.team_id FOR UPDATE;
    v_reversal_amt := -v_orig_tx.amount;

    -- Kiểm tra số dư nếu giao dịch trừ điểm
    IF v_reversal_amt < 0 AND (v_team.light_balance + v_reversal_amt) < 0 AND NOT p_force THEN
        RETURN jsonb_build_object(
            'success', false,
            'code', 'INSUFFICIENT_BALANCE',
            'error', format('Đội %s không đủ số dư để hoàn tác (Hiện có: %s, cần trừ: %s).', v_team.name, v_team.light_balance, abs(v_reversal_amt))
        );
    END IF;

    -- 4. Đánh dấu giao dịch gốc
    UPDATE transactions SET is_reversed = true WHERE id = v_orig_tx.id;

    -- 5. Tạo giao dịch đảo ngược (Reversal Tx)
    INSERT INTO transactions (
        team_id, amount, type, description, created_by,
        client_request_id, is_reversed, reversal_for_id, status
    ) VALUES (
        v_orig_tx.team_id,
        v_reversal_amt,
        'reversal',
        format('Hoàn tác giao dịch #%s (%s): %s', substring(v_orig_tx.id::text, 1, 8), v_orig_tx.type, COALESCE(p_reason, 'Admin hoàn tác')),
        v_admin.name,
        COALESCE(p_client_request_id, 'rev_' || gen_random_uuid()),
        false,
        v_orig_tx.id,
        'approved'
    ) RETURNING id INTO v_reversal_tx_id;

    -- 6. Cập nhật số dư đội
    v_new_balance := GREATEST(0, v_team.light_balance + v_reversal_amt);
    UPDATE teams SET light_balance = v_new_balance WHERE id = v_team.id;

    -- 7. Đồng bộ nếu giao dịch gắn liền với station_plays (KHÔNG có cột reversal_reason)
    UPDATE station_plays 
    SET status = 'reversed', 
        reversed_at = now(), 
        reversed_by = v_admin.name
    WHERE tx_id = v_orig_tx.id;

    RETURN jsonb_build_object(
        'success', true,
        'code', 'OK',
        'message', format('Đã hoàn tác thành công giao dịch của %s!', v_team.name),
        'data', jsonb_build_object(
            'reversed_tx_id', v_orig_tx.id,
            'reversal_tx_id', v_reversal_tx_id,
            'team_id', v_team.id,
            'new_balance', v_new_balance
        )
    );
END;
$$;

-- ---------------------------------------------------------------------
-- 5. NÂNG CẤP get_station_recent_plays
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_station_recent_plays(
  p_token      TEXT,
  p_station_id UUID DEFAULT NULL,
  p_limit      INTEGER DEFAULT 20
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_auth                RECORD;
  v_target_station_id   UUID := p_station_id;
  v_rows                JSONB;
BEGIN
  IF p_token IS NULL OR trim(p_token) = '' THEN
    RETURN public._direct_scoring_err('INVALID_TOKEN', 'Token không được để trống.');
  END IF;

  SELECT ss.staff_id, s.name AS staff_name, s.role AS staff_role, s.station_assigned
  INTO v_auth
  FROM public.staff_sessions ss
  JOIN public.staff s ON s.id = ss.staff_id
  WHERE ss.token = trim(p_token)
    AND ss.expires_at > now()
    AND s.is_active = true
  LIMIT 1;

  IF v_auth.staff_id IS NULL THEN
    RETURN public._direct_scoring_err('INVALID_TOKEN', 'Phiên làm việc không tồn tại hoặc đã hết hạn.');
  END IF;

  -- Nếu có p_station_id nhưng không tìm thấy, tự chữa lành theo order_index
  IF v_target_station_id IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM public.stations WHERE id = v_target_station_id AND deleted_at IS NULL) THEN
      SELECT s.id INTO v_target_station_id
      FROM public.stations s
      WHERE s.order_index = (
        SELECT order_index FROM public.stations WHERE id = p_station_id
      ) AND s.deleted_at IS NULL
      ORDER BY s.created_at DESC
      LIMIT 1;
    END IF;
  END IF;

  -- Nếu là quản trò trạm mà không truyền p_station_id -> tự tìm trạm được phân công
  IF (v_auth.staff_role = 'station_master' OR (v_auth.staff_role = 'support' AND v_auth.station_assigned IS NOT NULL AND btrim(v_auth.station_assigned) <> '')) AND v_target_station_id IS NULL THEN
    SELECT s.id INTO v_target_station_id
    FROM public.stations s
    WHERE s.deleted_at IS NULL
      AND (
        s.id::TEXT = v_auth.station_assigned
        OR s.name ILIKE '%' || btrim(v_auth.station_assigned) || '%'
        OR btrim(v_auth.station_assigned) ILIKE '%' || s.name || '%'
        OR btrim(v_auth.station_assigned) ILIKE '%trạm ' || s.order_index || '%'
        OR btrim(v_auth.station_assigned) = s.order_index::TEXT
      )
    ORDER BY s.created_at DESC
    LIMIT 1;
  END IF;

  SELECT COALESCE(jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC), '[]'::jsonb)
  INTO v_rows
  FROM (
    SELECT 
      p.id AS play_id, 
      p.id, 
      p.tx_id, 
      p.team_id, 
      t.name AS team_name,
      p.station_id,
      s.name AS station_name,
      p.points, 
      p.play_no, 
      p.status, 
      p.staff_name, 
      p.note, 
      p.created_at
    FROM public.station_plays p
    JOIN public.teams t ON t.id = p.team_id
    LEFT JOIN public.stations s ON s.id = p.station_id
    WHERE (v_target_station_id IS NULL OR p.station_id = v_target_station_id)
    ORDER BY p.created_at DESC
    LIMIT LEAST(GREATEST(COALESCE(p_limit, 20), 1), 100)
  ) x;

  RETURN jsonb_build_object(
    'success', true,
    'ok', true,
    'code', 'OK',
    'message', '',
    'error', null,
    'data', jsonb_build_object('plays', v_rows)
  );
END;
$$;

-- ---------------------------------------------------------------------
-- 6. NÂNG CẤP reverse_station_play
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.reverse_station_play(
  p_token             TEXT,
  p_client_request_id TEXT,
  p_play_id           UUID,
  p_reason            TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_auth                  RECORD;
  v_play                  RECORD;
  v_team                  RECORD;
  v_undo_window           INTEGER := 10;
  v_reversal_tx_id        UUID := NULL;
  v_new_balance           INTEGER;
  v_station               RECORD;
BEGIN
  IF p_token IS NULL OR trim(p_token) = '' THEN
    RETURN public._direct_scoring_err('INVALID_TOKEN', 'Token không được để trống.');
  END IF;

  SELECT ss.staff_id, s.name AS staff_name, s.role AS staff_role, s.station_assigned
  INTO v_auth
  FROM public.staff_sessions ss
  JOIN public.staff s ON s.id = ss.staff_id
  WHERE ss.token = trim(p_token)
    AND ss.expires_at > now()
    AND s.is_active = true
  LIMIT 1;

  IF v_auth.staff_id IS NULL THEN
    RETURN public._direct_scoring_err('INVALID_TOKEN', 'Phiên làm việc không tồn tại hoặc đã hết hạn.');
  END IF;

  -- Khóa dòng play và team
  SELECT * INTO v_play FROM public.station_plays WHERE id = p_play_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN public._direct_scoring_err('NOT_FOUND', 'Không tìm thấy lượt chơi.');
  END IF;

  IF v_play.status != 'active' THEN
    RETURN public._direct_scoring_err('ALREADY_REVERSED', 'Lượt chơi này đã được hoàn tác trước đó.');
  END IF;

  SELECT * INTO v_team FROM public.teams WHERE id = v_play.team_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN public._direct_scoring_err('TEAM_NOT_FOUND', 'Không tìm thấy đội chơi tương ứng.');
  END IF;

  SELECT * INTO v_station FROM public.stations WHERE id = v_play.station_id;

  -- Kiểm tra quyền hoàn tác
  IF v_auth.staff_role = 'admin' THEN
    NULL;
  ELSIF v_auth.staff_role = 'station_master' OR (v_auth.staff_role = 'support' AND v_auth.station_assigned IS NOT NULL AND btrim(v_auth.station_assigned) <> '') THEN
    IF v_station.id IS NOT NULL AND v_auth.station_assigned IS NOT NULL THEN
      IF NOT (
        v_station.id::TEXT = v_auth.station_assigned
        OR v_station.name ILIKE '%' || btrim(v_auth.station_assigned) || '%'
        OR btrim(v_auth.station_assigned) ILIKE '%' || v_station.name || '%'
        OR btrim(v_auth.station_assigned) ILIKE '%trạm ' || v_station.order_index || '%'
        OR btrim(v_auth.station_assigned) = v_station.order_index::TEXT
      ) THEN
        RETURN public._direct_scoring_err('FORBIDDEN_STATION', 'Bạn không được phân công quản trạm của lượt chơi này.');
      END IF;
    END IF;

    SELECT COALESCE((value->>'v')::INT, 10) INTO v_undo_window
    FROM public.game_settings WHERE key = 'undo_window_minutes';
    IF v_undo_window IS NULL THEN v_undo_window := 10; END IF;

    IF (now() - v_play.created_at) > (v_undo_window || ' minutes')::INTERVAL THEN
      RETURN public._direct_scoring_err(
        'UNDO_WINDOW_EXPIRED',
        format('Đã hết thời hạn hoàn tác (%s phút). Hãy liên hệ Admin!', v_undo_window)
      );
    END IF;
  ELSE
    RETURN public._direct_scoring_err('FORBIDDEN', 'Bạn không có quyền hoàn tác lượt chơi.');
  END IF;

  -- Thu hồi điểm nếu điểm > 0
  IF v_play.points > 0 THEN
    IF v_play.tx_id IS NOT NULL THEN
      UPDATE public.transactions
      SET is_reversed = true
      WHERE id = v_play.tx_id;
    END IF;

    INSERT INTO public.transactions (
      client_request_id,
      team_id,
      amount,
      type,
      description,
      created_by,
      status,
      is_reversed,
      reversal_for_id
    ) VALUES (
      COALESCE(p_client_request_id, 'rev_' || gen_random_uuid()),
      v_play.team_id,
      -v_play.points,
      'reversal',
      format('Hoàn tác lượt chơi trạm #%s: %s', v_play.play_no, COALESCE(p_reason, 'Thu hồi điểm')),
      v_auth.staff_name,
      'approved',
      false,
      v_play.tx_id
    ) RETURNING id INTO v_reversal_tx_id;

    v_new_balance := GREATEST(0, v_team.light_balance - v_play.points);
    UPDATE public.teams
    SET light_balance = v_new_balance
    WHERE id = v_play.team_id;
  ELSE
    v_new_balance := v_team.light_balance;
  END IF;

  -- Cập nhật station_plays (dùng reversed_by kiểu TEXT, không có reversal_reason)
  UPDATE public.station_plays
  SET status = 'reversed',
      reversed_at = now(),
      reversed_by = v_auth.staff_name
  WHERE id = p_play_id;

  RETURN jsonb_build_object(
    'success', true,
    'ok', true,
    'code', 'OK',
    'message', format('Đã hoàn tác thành công lượt chấm của đội %s (-%s Lumen).', v_team.name, v_play.points),
    'error', null,
    'data', jsonb_build_object(
      'play_id', p_play_id,
      'points_reversed', v_play.points,
      'new_balance', v_new_balance,
      'reversal_tx_id', v_reversal_tx_id
    )
  );
END;
$$;

-- ---------------------------------------------------------------------
-- 7. CẤP QUYỀN VÀ RELOAD SCHEMA CACHE
-- ---------------------------------------------------------------------
GRANT EXECUTE ON FUNCTION public._require_staff(TEXT, TEXT[]) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.award_station_direct_points(TEXT, UUID, UUID, INTEGER, TEXT, TEXT) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.reverse_transaction(TEXT, UUID, BOOLEAN, TEXT, TEXT) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_station_recent_plays(TEXT, UUID, INTEGER) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.reverse_station_play(TEXT, TEXT, UUID, TEXT) TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';

COMMIT;
