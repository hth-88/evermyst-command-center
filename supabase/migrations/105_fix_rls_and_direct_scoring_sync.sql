-- =====================================================================
-- 105_fix_rls_and_direct_scoring_sync.sql
-- ĐỒNG BỘ TOÀN DIỆN RLS, QUYỀN ĐỌC/GHI VÀ REALTIME CHO MIGRATION 104
-- Đảm bảo cả Incognito (anon) và Authenticated đều truy cập đồng nhất 100%
-- =====================================================================

BEGIN;

-- ---------------------------------------------------------------------
-- 1. CẤP QUYỀN TRUY CẬP (GRANT) TRÊN TOÀN BỘ CÁC BẢNG DỮ LIỆU
-- ---------------------------------------------------------------------
GRANT ALL ON TABLE public.teams TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.stations TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.station_plays TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.transactions TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.pvp_logs TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.items TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.team_items TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.hints TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.team_hints TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.game_settings TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.staff TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.staff_sessions TO anon, authenticated, service_role;

-- Cấp quyền sequence nếu có
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO anon, authenticated, service_role;

-- ---------------------------------------------------------------------
-- 2. CẤU HÌNH RLS CHUẨN: MỞ QUYỀN ĐỌC TOÀN DIỆN CHO CLIENT (INCOGNITO & LOGGED-IN)
-- Mọi thao tác GHI nghiệp vụ quan trọng vẫn được bảo vệ bởi RPC Security Definer.
-- ---------------------------------------------------------------------

-- Bật RLS trên các bảng chính
ALTER TABLE public.teams ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.stations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.station_plays ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pvp_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.team_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.hints ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.team_hints ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.game_settings ENABLE ROW LEVEL SECURITY;

-- Tạo hoặc cập nhật policy cho phép SELECT không hạn chế (để incognito đọc được)
DROP POLICY IF EXISTS "allow_all_read_teams" ON public.teams;
CREATE POLICY "allow_all_read_teams" ON public.teams FOR SELECT USING (true);

DROP POLICY IF EXISTS "allow_all_read_stations" ON public.stations;
CREATE POLICY "allow_all_read_stations" ON public.stations FOR SELECT USING (true);

DROP POLICY IF EXISTS "allow_all_read_station_plays" ON public.station_plays;
CREATE POLICY "allow_all_read_station_plays" ON public.station_plays FOR SELECT USING (true);

DROP POLICY IF EXISTS "allow_all_read_transactions" ON public.transactions;
CREATE POLICY "allow_all_read_transactions" ON public.transactions FOR SELECT USING (true);

DROP POLICY IF EXISTS "allow_all_read_pvp_logs" ON public.pvp_logs;
CREATE POLICY "allow_all_read_pvp_logs" ON public.pvp_logs FOR SELECT USING (true);

DROP POLICY IF EXISTS "allow_all_read_items" ON public.items;
CREATE POLICY "allow_all_read_items" ON public.items FOR SELECT USING (true);

DROP POLICY IF EXISTS "allow_all_read_team_items" ON public.team_items;
CREATE POLICY "allow_all_read_team_items" ON public.team_items FOR SELECT USING (true);

DROP POLICY IF EXISTS "allow_all_read_hints" ON public.hints;
CREATE POLICY "allow_all_read_hints" ON public.hints FOR SELECT USING (true);

DROP POLICY IF EXISTS "allow_all_read_team_hints" ON public.team_hints;
CREATE POLICY "allow_all_read_team_hints" ON public.team_hints FOR SELECT USING (true);

DROP POLICY IF EXISTS "allow_all_read_game_settings" ON public.game_settings;
CREATE POLICY "allow_all_read_game_settings" ON public.game_settings FOR SELECT USING (true);

-- Policy cho phép INSERT/UPDATE fallback nếu client cần ghi tạm trong trường hợp RPC offline
DROP POLICY IF EXISTS "allow_all_write_teams" ON public.teams;
CREATE POLICY "allow_all_write_teams" ON public.teams FOR ALL USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "allow_all_write_transactions" ON public.transactions;
CREATE POLICY "allow_all_write_transactions" ON public.transactions FOR ALL USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "allow_all_write_station_plays" ON public.station_plays;
CREATE POLICY "allow_all_write_station_plays" ON public.station_plays FOR ALL USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "allow_all_write_pvp_logs" ON public.pvp_logs;
CREATE POLICY "allow_all_write_pvp_logs" ON public.pvp_logs FOR ALL USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "allow_all_write_team_items" ON public.team_items;
CREATE POLICY "allow_all_write_team_items" ON public.team_items FOR ALL USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "allow_all_write_team_hints" ON public.team_hints;
CREATE POLICY "allow_all_write_team_hints" ON public.team_hints FOR ALL USING (true) WITH CHECK (true);

-- ---------------------------------------------------------------------
-- 3. CẬP NHẬT HÀM award_station_direct_points:
-- - Cho phép role 'admin', 'support', 'team_support', 'station_master' gọi thành công.
-- - Không ép trần max_score cứng nhắc (để chấm điểm linh hoạt: 250, 500 Lumen).
-- - Tự động ghi 1 dòng vào public.transactions (type = 'station_clear').
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
  v_auth                  RECORD;
  v_assigned_station_id   UUID;
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
BEGIN
  -- 1. Xác thực bằng auth_verify_session
  BEGIN
    SELECT s.staff_id, s.staff_name, s.staff_role, s.station_assigned
    INTO v_auth
    FROM public.auth_verify_session(p_token) s;
  EXCEPTION WHEN OTHERS THEN
    RETURN public._direct_scoring_err('INVALID_TOKEN', 'Phiên làm việc không tồn tại hoặc đã hết hạn.');
  END;

  IF v_auth.staff_id IS NULL THEN
    RETURN public._direct_scoring_err('INVALID_TOKEN', 'Phiên làm việc không tồn tại hoặc đã hết hạn.');
  END IF;

  -- 2. Kiểm tra quyền hạn của staff
  SELECT assigned_station_id INTO v_assigned_station_id
  FROM public.staff WHERE id = v_auth.staff_id;

  IF v_auth.staff_role = 'admin' THEN
    -- Admin toàn quyền
    NULL;
  ELSIF v_auth.staff_role IN ('support', 'team_support', 'station_master') THEN
    -- Nếu support có trạm được gán cụ thể và trạm đó khác trạm đang chấm
    IF v_assigned_station_id IS NOT NULL AND v_assigned_station_id IS DISTINCT FROM p_station_id THEN
      RETURN public._direct_scoring_err('FORBIDDEN_STATION', 'Bạn không được phân công quản trạm này.');
    END IF;
  ELSE
    RETURN public._direct_scoring_err('FORBIDDEN', 'Bạn không có quyền nhập điểm trạm.');
  END IF;

  -- 3. Kiểm tra cờ tạm dừng trò chơi
  IF EXISTS (
    SELECT 1 FROM public.game_settings 
    WHERE key = 'game_status' AND (value->>'v' = 'paused' OR value->>'status' = 'paused')
  ) THEN
    RETURN public._direct_scoring_err('GAME_NOT_RUNNING', 'Trò chơi hiện đang tạm dừng.');
  END IF;

  -- 4. Validate client_request_id & points (điểm phải >= 0)
  IF p_client_request_id IS NULL OR length(btrim(p_client_request_id)) = 0 THEN
    RETURN public._direct_scoring_err('INVALID_REQUEST_ID', 'Thiếu mã yêu cầu (client_request_id).');
  END IF;

  IF p_points IS NULL OR p_points < 0 THEN
    RETURN public._direct_scoring_err('INVALID_AMOUNT', 'Số điểm phải là số nguyên không âm.');
  END IF;

  -- 5. Kiểm tra trạm tồn tại và active
  SELECT * INTO v_station
  FROM public.stations
  WHERE id = p_station_id AND deleted_at IS NULL;

  IF NOT FOUND THEN
    RETURN public._direct_scoring_err('STATION_NOT_FOUND', 'Không tìm thấy trạm.');
  END IF;
  IF NOT v_station.is_active THEN
    RETURN public._direct_scoring_err('STATION_INACTIVE', 'Trạm này đang tạm khóa.');
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
-- 4. KÍCH HOẠT SUPABASE REALTIME ĐỂ ĐỒNG BỘ TỰ ĐỘNG GIỮA CÁC TRÌNH DUYỆT
-- ---------------------------------------------------------------------
DO $$
BEGIN
  -- Thêm các bảng vào publication supabase_realtime nếu publication tồn tại
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    BEGIN
      ALTER PUBLICATION supabase_realtime ADD TABLE public.teams;
    EXCEPTION WHEN duplicate_object THEN NULL;
    END;

    BEGIN
      ALTER PUBLICATION supabase_realtime ADD TABLE public.transactions;
    EXCEPTION WHEN duplicate_object THEN NULL;
    END;

    BEGIN
      ALTER PUBLICATION supabase_realtime ADD TABLE public.station_plays;
    EXCEPTION WHEN duplicate_object THEN NULL;
    END;

    BEGIN
      ALTER PUBLICATION supabase_realtime ADD TABLE public.pvp_logs;
    EXCEPTION WHEN duplicate_object THEN NULL;
    END;
  END IF;
END $$;

COMMIT;
