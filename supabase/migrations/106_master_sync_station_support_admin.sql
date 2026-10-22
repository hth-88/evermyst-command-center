-- =====================================================================
-- 106_master_sync_station_support_admin.sql
-- ĐỒNG BỘ TOÀN DIỆN TRẠM, DỌN SẠCH RÁC V1/V2, MỞ QUYỀN CHẤM ĐIỂM
-- & KÍCH HOẠT CƠ CHẾ TỰ CHỮA LÀNH (SELF-HEALING) CHO TRẠM
-- =====================================================================

BEGIN;

-- ---------------------------------------------------------------------
-- 1. TẠO BẢNG TẠM ĐỐI CHIẾU MAPPING GIỮA TRẠM CŨ (DELETED) VÀ TRẠM MỚI (ACTIVE)
-- ---------------------------------------------------------------------
CREATE TEMP TABLE station_id_mapping AS
SELECT 
  old_s.id AS old_id,
  new_s.id AS new_id,
  old_s.order_index
FROM public.stations old_s
JOIN public.stations new_s ON new_s.order_index = old_s.order_index 
  AND new_s.deleted_at IS NULL 
  AND old_s.deleted_at IS NOT NULL;

-- ---------------------------------------------------------------------
-- 2. ĐỒNG BỘ KHÓA NGOẠI TRỎ TỪ TRẠM CŨ SANG TRẠM MỚI CHUẨN
-- ---------------------------------------------------------------------

-- Cập nhật staff.assigned_station_id
UPDATE public.staff st
SET assigned_station_id = m.new_id
FROM station_id_mapping m
WHERE st.assigned_station_id = m.old_id;

-- Cập nhật hints.station_id
UPDATE public.hints h
SET station_id = m.new_id
FROM station_id_mapping m
WHERE h.station_id = m.old_id;

-- Cập nhật station_plays.station_id
UPDATE public.station_plays sp
SET station_id = m.new_id
FROM station_id_mapping m
WHERE sp.station_id = m.old_id;

-- Cập nhật mảng unlocked_stations trong teams (thay thế old_id bằng new_id)
DO $$
DECLARE
  rec RECORD;
BEGIN
  FOR rec IN SELECT old_id::TEXT, new_id::TEXT FROM station_id_mapping LOOP
    UPDATE public.teams
    SET unlocked_stations = array_replace(unlocked_stations, rec.old_id, rec.new_id)
    WHERE rec.old_id = ANY(unlocked_stations);
  END LOOP;
END $$;

-- ---------------------------------------------------------------------
-- 3. XÓA BỎ VĨNH VIỄN CÁC BẢN GHI TRẠM RÁC CŨ ĐÃ BỊ SOFT-DELETE
-- ---------------------------------------------------------------------
DELETE FROM public.stations WHERE deleted_at IS NOT NULL;

-- Bật allow_multiple_attempts = true và is_active = true cho 5 trạm chuẩn để vận hành linh hoạt
UPDATE public.stations
SET allow_multiple_attempts = true,
    is_active = true
WHERE deleted_at IS NULL;

-- ---------------------------------------------------------------------
-- 4. NÂNG CẤP HÀM award_station_direct_points CÓ SELF-HEALING VÀ KIỂM TRA QUYỀN LINH HOẠT
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
SET search_path = public, pg_temp
AS $$
DECLARE
  v_token_hash            TEXT;
  v_auth                  RECORD;
  v_staff                 RECORD;
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
  v_assigned_order        INTEGER;
BEGIN
  -- 1. Xác thực session token (chống lỗi version session)
  IF p_token IS NULL OR trim(p_token) = '' THEN
    RETURN public._direct_scoring_err('INVALID_TOKEN', 'Phiên làm việc không tồn tại hoặc đã hết hạn.');
  END IF;

  v_token_hash := encode(digest(trim(p_token), 'sha256'), 'hex');

  SELECT ss.staff_id, s.name AS staff_name, s.role AS staff_role, s.assigned_station_id, s.assigned_team_id
  INTO v_auth
  FROM public.staff_sessions ss
  JOIN public.staff s ON s.id = ss.staff_id
  WHERE (ss.token_hash = v_token_hash OR ss.token = trim(p_token) OR ss.token = v_token_hash)
    AND ss.expires_at > now()
    AND s.is_active = true
  LIMIT 1;

  IF v_auth.staff_id IS NULL THEN
    -- Fallback gọi auth_verify_session
    BEGIN
      SELECT s.staff_id, s.staff_name, s.staff_role, s.station_assigned
      INTO v_auth
      FROM public.auth_verify_session(p_token) s;
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END IF;

  IF v_auth.staff_id IS NULL THEN
    RETURN public._direct_scoring_err('INVALID_TOKEN', 'Phiên làm việc không tồn tại hoặc đã hết hạn.');
  END IF;

  -- 2. Tự chữa lành mã trạm (Self-healing Station Lookup)
  SELECT * INTO v_station
  FROM public.stations
  WHERE id = p_station_id AND deleted_at IS NULL;

  -- Nếu không tìm thấy trạm bằng UUID (ví dụ do client giữ UUID cũ):
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

  -- 3. Kiểm tra quyền hạn của Staff (Hỗ trợ Admin, Support, Team Support, Station Master)
  SELECT assigned_station_id, assigned_team_id, role 
  INTO v_staff
  FROM public.staff WHERE id = v_auth.staff_id;

  IF v_auth.staff_role = 'admin' OR v_staff.role = 'admin' THEN
    -- Admin toàn quyền
    NULL;
  ELSIF v_auth.staff_role = 'team_support' OR v_staff.role = 'team_support' THEN
    -- Support đi theo đội: cho phép chấm điểm mọi trạm cho đội phụ trách
    IF v_staff.assigned_team_id IS NOT NULL AND v_staff.assigned_team_id IS DISTINCT FROM p_team_id THEN
      RETURN public._direct_scoring_err('FORBIDDEN_TEAM', 'Bạn chỉ được chấm điểm cho đội phụ trách của mình.');
    END IF;
  ELSIF v_auth.staff_role IN ('station_master', 'support') OR v_staff.role IN ('station_master', 'support') THEN
    -- Quản trò trạm: nếu có assigned_station_id, kiểm tra khớp UUID HOẶC khớp order_index
    IF v_staff.assigned_station_id IS NOT NULL THEN
      SELECT order_index INTO v_assigned_order
      FROM public.stations WHERE id = v_staff.assigned_station_id;

      IF v_staff.assigned_station_id IS DISTINCT FROM p_station_id AND (v_assigned_order IS NULL OR v_assigned_order <> v_station.order_index) THEN
        RETURN public._direct_scoring_err('FORBIDDEN_STATION', 'Bạn không được phân công phụ trách trạm này.');
      END IF;
    END IF;
  ELSE
    RETURN public._direct_scoring_err('FORBIDDEN', 'Bạn không có quyền nhập điểm trạm.');
  END IF;

  -- 4. Kiểm tra cờ tạm dừng trò chơi
  IF EXISTS (
    SELECT 1 FROM public.game_settings 
    WHERE key = 'game_status' AND (value->>'v' = 'paused' OR value->>'status' = 'paused')
  ) THEN
    RETURN public._direct_scoring_err('GAME_NOT_RUNNING', 'Trò chơi hiện đang tạm dừng.');
  END IF;

  -- 5. Validate client_request_id & points
  IF p_client_request_id IS NULL OR length(btrim(p_client_request_id)) = 0 THEN
    RETURN public._direct_scoring_err('INVALID_REQUEST_ID', 'Thiếu mã yêu cầu (client_request_id).');
  END IF;

  IF p_points IS NULL OR p_points < 0 THEN
    RETURN public._direct_scoring_err('INVALID_AMOUNT', 'Số điểm phải là số nguyên không âm.');
  END IF;

  -- 6. Khóa dòng đội chơi để chống race condition
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

  -- 7. Kiểm tra Idempotency
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

  -- 8. Đếm số lượt active và tính play_no
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

  -- 10. Ghi sổ cái transactions nếu p_points > 0
  IF p_points > 0 THEN
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
  END IF;

  -- 11. Cập nhật số dư và mảng unlocked_stations cho đội
  v_new_balance := v_team.light_balance + p_points;
  v_unlocked := COALESCE(v_team.unlocked_stations, ARRAY[]::TEXT[]);

  IF NOT (p_station_id::TEXT = ANY(v_unlocked)) THEN
    v_unlocked := array_append(v_unlocked, p_station_id::TEXT);
  END IF;

  UPDATE public.teams
  SET light_balance = v_new_balance,
      unlocked_stations = v_unlocked
  WHERE id = p_team_id;

  -- 12. Trả kết quả thành công
  RETURN jsonb_build_object(
    'success', true,
    'ok', true,
    'code', 'OK',
    'message', format('Đã cộng %s Lumen cho đội %s thành công!', p_points, v_team.name),
    'error', null,
    'replayed', false,
    'idempotent', false,
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
-- 5. NÂNG CẤP HÀM get_station_recent_plays
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_station_recent_plays(
  p_token      TEXT,
  p_station_id UUID DEFAULT NULL,
  p_limit      INTEGER DEFAULT 20
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_token_hash          TEXT;
  v_auth                RECORD;
  v_target_station_id   UUID := p_station_id;
  v_rows                JSONB;
BEGIN
  IF p_token IS NULL OR trim(p_token) = '' THEN
    RETURN public._direct_scoring_err('INVALID_TOKEN', 'Token không được để trống.');
  END IF;

  v_token_hash := encode(digest(trim(p_token), 'sha256'), 'hex');

  SELECT ss.staff_id, s.name AS staff_name, s.role AS staff_role, s.assigned_station_id
  INTO v_auth
  FROM public.staff_sessions ss
  JOIN public.staff s ON s.id = ss.staff_id
  WHERE (ss.token_hash = v_token_hash OR ss.token = trim(p_token) OR ss.token = v_token_hash)
    AND ss.expires_at > now()
    AND s.is_active = true
  LIMIT 1;

  IF v_auth.staff_id IS NULL THEN
    RETURN public._direct_scoring_err('INVALID_TOKEN', 'Phiên làm việc không tồn tại hoặc đã hết hạn.');
  END IF;

  -- Nếu có p_station_id nhưng không tìm thấy (lệch UUID cũ), tự chữa lành theo order_index
  IF v_target_station_id IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM public.stations WHERE id = v_target_station_id) THEN
      SELECT s.id INTO v_target_station_id
      FROM public.stations s
      WHERE s.order_index = (
        SELECT order_index FROM public.stations WHERE id = p_station_id
      )
      LIMIT 1;
    END IF;
  END IF;

  -- Nếu là station_master mà p_station_id NULL -> lấy trạm của chính quản trò
  IF v_auth.staff_role IN ('station_master', 'support') AND v_target_station_id IS NULL THEN
    v_target_station_id := v_auth.assigned_station_id;
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
-- 6. NÂNG CẤP HÀM reverse_station_play
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.reverse_station_play(
  p_token             TEXT,
  p_client_request_id TEXT,
  p_play_id           UUID,
  p_reason            TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_token_hash            TEXT;
  v_auth                  RECORD;
  v_play                  RECORD;
  v_team                  RECORD;
  v_undo_window           INTEGER := 10;
  v_reversal_tx_id        UUID := NULL;
  v_new_balance           INTEGER;
  v_assigned_order        INTEGER;
  v_play_station_order    INTEGER;
BEGIN
  IF p_token IS NULL OR trim(p_token) = '' THEN
    RETURN public._direct_scoring_err('INVALID_TOKEN', 'Token không được để trống.');
  END IF;

  v_token_hash := encode(digest(trim(p_token), 'sha256'), 'hex');

  SELECT ss.staff_id, s.name AS staff_name, s.role AS staff_role, s.assigned_station_id
  INTO v_auth
  FROM public.staff_sessions ss
  JOIN public.staff s ON s.id = ss.staff_id
  WHERE (ss.token_hash = v_token_hash OR ss.token = trim(p_token) OR ss.token = v_token_hash)
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

  -- Kiểm tra quyền hoàn tác
  IF v_auth.staff_role = 'admin' THEN
    -- Admin toàn quyền hoàn tác không giới hạn thời gian
    NULL;
  ELSIF v_auth.staff_role IN ('station_master', 'support') THEN
    SELECT order_index INTO v_assigned_order FROM public.stations WHERE id = v_auth.assigned_station_id;
    SELECT order_index INTO v_play_station_order FROM public.stations WHERE id = v_play.station_id;

    IF v_auth.assigned_station_id IS DISTINCT FROM v_play.station_id AND (v_assigned_order IS NULL OR v_assigned_order <> v_play_station_order) THEN
      RETURN public._direct_scoring_err('FORBIDDEN_STATION', 'Bạn không được phân công quản trạm của lượt chơi này.');
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

  UPDATE public.station_plays
  SET status = 'reversed',
      reversed_at = now(),
      reversed_by = v_auth.staff_id,
      reversal_reason = p_reason
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
-- 7. CẤP QUYỀN VÀ RELOAD SCHEMA
-- ---------------------------------------------------------------------

GRANT EXECUTE ON FUNCTION public.award_station_direct_points(TEXT, UUID, UUID, INTEGER, TEXT, TEXT) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_station_recent_plays(TEXT, UUID, INTEGER) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.reverse_station_play(TEXT, TEXT, UUID, TEXT) TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';

COMMIT;
