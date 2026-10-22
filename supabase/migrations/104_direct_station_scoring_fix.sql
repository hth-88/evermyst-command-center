-- =====================================================================
-- 104_direct_station_scoring_fix.sql
-- Chấm điểm trạm trực tiếp bởi Quản trò (station_master) / Admin.
-- ALIGN (AI phải đối chiếu DB thật trước khi chạy, xem Prompt 1):
--   (a) public.require_staff(p_token) là helper xác thực: tên + kiểu trả về
--   (b) transactions.created_by / client_request_id / metadata: kiểu thật
--   (c) mọi cột NOT NULL của station_claims đã được điền ở INSERT bên dưới
--   (d) nếu có cờ game tạm dừng thì thêm kiểm tra GAME_NOT_RUNNING
-- =====================================================================

BEGIN;

-- =====================================================================
-- B1. BỔ SUNG CỘT CẤU HÌNH VÀO STATIONS & STAFF (IDEMPOTENT)
-- =====================================================================

ALTER TABLE public.stations
  ADD COLUMN IF NOT EXISTS allow_multiple_attempts BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS max_score INTEGER NULL,
  ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_stations_max_score'
  ) THEN
    ALTER TABLE public.stations
      ADD CONSTRAINT chk_stations_max_score CHECK (max_score IS NULL OR max_score >= 0);
  END IF;
END $$;

ALTER TABLE public.staff
  ADD COLUMN IF NOT EXISTS assigned_station_id UUID NULL REFERENCES public.stations(id);

-- =====================================================================
-- B2. TẠO BẢNG STATION_PLAYS & CÁC INDEX
-- =====================================================================

CREATE TABLE IF NOT EXISTS public.station_plays (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  team_id           UUID NOT NULL REFERENCES public.teams(id) ON DELETE CASCADE,
  station_id        UUID NOT NULL REFERENCES public.stations(id) ON DELETE CASCADE,
  play_no           INTEGER NOT NULL,
  points            INTEGER NOT NULL CHECK (points >= 0),
  status            TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'reversed')),
  tx_id             UUID NULL REFERENCES public.transactions(id) ON DELETE SET NULL,
  staff_id          UUID NULL,
  staff_name        TEXT NOT NULL,
  note              TEXT NULL,
  client_request_id TEXT NOT NULL UNIQUE,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  reversed_at       TIMESTAMPTZ NULL,
  reversed_by       TEXT NULL,
  CONSTRAINT uq_station_plays_team_station_play_no UNIQUE (team_id, station_id, play_no)
);

CREATE INDEX IF NOT EXISTS idx_station_plays_team_station_status 
  ON public.station_plays (team_id, station_id, status);

CREATE INDEX IF NOT EXISTS idx_station_plays_station_created 
  ON public.station_plays (station_id, created_at DESC);

-- Bật RLS: Không cấp quyền direct CRUD cho anon/authenticated, mọi thao tác qua RPC
ALTER TABLE public.station_plays ENABLE ROW LEVEL SECURITY;

-- =====================================================================
-- B3. HELPER NỘI BỘ TRẢ LỖI CHUẨN JSON (THỎA MÃN CẢ 2 BỘ KHÓA)
-- =====================================================================

CREATE OR REPLACE FUNCTION public._direct_scoring_err(
  p_code TEXT,
  p_message TEXT,
  p_data JSONB DEFAULT '{}'::jsonb
) RETURNS JSONB
LANGUAGE sql IMMUTABLE
AS $$
  SELECT jsonb_build_object(
    'success', false,
    'ok', false,
    'code', p_code,
    'message', p_message,
    'error', p_message,
    'data', p_data,
    'replayed', false,
    'idempotent', false
  );
$$;

-- =====================================================================
-- B3a. RPC GHI: award_station_direct_points
-- Quản trò / Admin chấm điểm trực tiếp cho đội tại trạm
-- =====================================================================

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
BEGIN
  -- 1. Xác thực bằng auth_verify_session V1 (Bắt exception trả INVALID_TOKEN JSON)
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

  -- 2. Kiểm tra phân quyền trạm
  SELECT assigned_station_id INTO v_assigned_station_id
  FROM public.staff WHERE id = v_auth.staff_id;

  IF v_auth.staff_role = 'admin' THEN
    -- Admin có quyền chấm điểm tại tất cả trạm
    NULL;
  ELSIF v_auth.staff_role = 'support' THEN
    IF v_assigned_station_id IS NULL THEN
      RETURN public._direct_scoring_err('FORBIDDEN', 'Tài khoản chưa được gán trạm quản lý.');
    ELSIF v_assigned_station_id IS DISTINCT FROM p_station_id THEN
      RETURN public._direct_scoring_err('FORBIDDEN_STATION', 'Bạn không được phân công quản trạm này.');
    END IF;
  ELSE
    RETURN public._direct_scoring_err('FORBIDDEN', 'Bạn không có quyền nhập điểm trạm.');
  END IF;

  -- 3. Kiểm tra cờ tạm dừng trò chơi (nếu có khóa cấu hình)
  IF EXISTS (
    SELECT 1 FROM public.game_settings 
    WHERE key = 'game_status' AND (value->>'v' = 'paused' OR value->>'status' = 'paused')
  ) THEN
    RETURN public._direct_scoring_err('GAME_NOT_RUNNING', 'Trò chơi hiện đang tạm dừng.');
  END IF;

  -- 4. Validate client_request_id & points
  IF p_client_request_id IS NULL OR length(btrim(p_client_request_id)) = 0 THEN
    RETURN public._direct_scoring_err('INVALID_REQUEST_ID', 'Thiếu mã yêu cầu (client_request_id).');
  END IF;

  IF p_points IS NULL OR p_points < 0 THEN
    RETURN public._direct_scoring_err('INVALID_AMOUNT', 'Số điểm phải là số nguyên không âm.');
  END IF;

  -- 5. Kiểm tra trạm tồn tại, active, chưa bị soft delete
  SELECT * INTO v_station
  FROM public.stations
  WHERE id = p_station_id AND deleted_at IS NULL;

  IF NOT FOUND THEN
    RETURN public._direct_scoring_err('STATION_NOT_FOUND', 'Không tìm thấy trạm.');
  END IF;
  IF NOT v_station.is_active THEN
    RETURN public._direct_scoring_err('STATION_INACTIVE', 'Trạm này đang tạm khóa.');
  END IF;

  IF v_station.max_score IS NOT NULL AND p_points > v_station.max_score THEN
    RETURN public._direct_scoring_err(
      'POINTS_OUT_OF_RANGE',
      format('Điểm tối đa của trạm này là %s.', v_station.max_score),
      jsonb_build_object('max_score', v_station.max_score)
    );
  END IF;

  -- 6. Khóa dòng đội chơi TRƯỚC để tuần tự hóa và chống race condition
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

  -- 7. Kiểm tra Idempotency sau khi đã khóa dòng
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

  -- 8. Đếm số lượt active và tính play_no mới
  SELECT count(*) FILTER (WHERE status = 'active'),
         COALESCE(max(play_no), 0)
  INTO v_active_count, v_max_play_no
  FROM public.station_plays
  WHERE team_id = p_team_id AND station_id = p_station_id;

  -- Nếu là trạm 1 lượt và đã có lượt active -> Chặn
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

  -- 10. Ghi sổ cái transactions nếu points > 0 (chỉ dùng các cột V1 có sẵn)
  IF p_points > 0 THEN
    INSERT INTO public.transactions (
      client_request_id, team_id, amount, type, description,
      created_by, status
    ) VALUES (
      p_client_request_id,
      p_team_id,
      p_points,
      'station_clear',
      format('Trạm %s: +%s Lumen (lượt %s)', v_station.name, p_points, v_play_no),
      v_auth.staff_name,
      'approved'
    ) RETURNING id INTO v_tx_id;

    UPDATE public.station_plays SET tx_id = v_tx_id WHERE id = v_play_id;
  END IF;

  -- 11. Cập nhật số dư và mảng unlocked_stations (luôn update để phát Realtime)
  UPDATE public.teams
  SET light_balance = light_balance + p_points,
      unlocked_stations = CASE
        WHEN p_station_id::text = ANY (COALESCE(unlocked_stations, ARRAY[]::text[]))
          THEN COALESCE(unlocked_stations, ARRAY[]::text[])
        ELSE array_append(COALESCE(unlocked_stations, ARRAY[]::text[]), p_station_id::text)
      END
  WHERE id = p_team_id
  RETURNING light_balance INTO v_new_balance;

  RETURN jsonb_build_object(
    'success', true,
    'ok', true,
    'code', 'OK',
    'message', 'Đã ghi điểm thành công.',
    'error', null,
    'replayed', false,
    'idempotent', false,
    'data', jsonb_build_object(
      'play_id', v_play_id,
      'tx_id', v_tx_id,
      'points', p_points,
      'play_no', v_play_no,
      'play_count', v_active_count + 1,
      'new_balance', v_new_balance,
      'team_name', v_team.name,
      'station_name', v_station.name
    )
  );

EXCEPTION
  WHEN unique_violation THEN
    RETURN public._direct_scoring_err(
      'CONFLICT',
      'Yêu cầu trùng lặp hoặc xung đột lượt chơi. Hãy tải lại và kiểm tra.'
    );
END;
$$;

-- =====================================================================
-- B3b. RPC HOÀN TÁC: reverse_station_play
-- Hoàn tác một lượt chơi cụ thể, trừ điểm và cập nhật trạng thái
-- =====================================================================

CREATE OR REPLACE FUNCTION public.reverse_station_play(
  p_token             TEXT,
  p_client_request_id TEXT,
  p_play_id           UUID,
  p_reason            TEXT DEFAULT ''
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_auth                  RECORD;
  v_assigned_station_id   UUID;
  v_team_id               UUID;
  v_play                  RECORD;
  v_team                  RECORD;
  v_existing_rev          RECORD;
  v_undo_window           INTEGER;
  v_reversal_tx_id        UUID := NULL;
  v_new_balance           INTEGER;
  v_remaining_active      INTEGER;
BEGIN
  -- 1. Xác thực session
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

  IF p_client_request_id IS NULL OR length(btrim(p_client_request_id)) = 0 THEN
    RETURN public._direct_scoring_err('INVALID_REQUEST_ID', 'Thiếu mã yêu cầu (client_request_id).');
  END IF;

  -- 2. Kiểm tra Idempotency theo p_client_request_id trong transactions
  SELECT id INTO v_existing_rev
  FROM public.transactions
  WHERE client_request_id = p_client_request_id;

  IF FOUND THEN
    SELECT team_id INTO v_team_id FROM public.station_plays WHERE id = p_play_id;
    SELECT light_balance INTO v_new_balance FROM public.teams WHERE id = v_team_id;
    RETURN jsonb_build_object(
      'success', true,
      'ok', true,
      'code', 'OK',
      'message', 'Yêu cầu hoàn tác đã được xử lý trước đó.',
      'error', null,
      'replayed', true,
      'idempotent', true,
      'data', jsonb_build_object('play_id', p_play_id, 'new_balance', v_new_balance)
    );
  END IF;

  -- 3. Tìm team_id để khóa đội trước (tránh deadlock)
  SELECT team_id INTO v_team_id FROM public.station_plays WHERE id = p_play_id;
  IF NOT FOUND THEN
    RETURN public._direct_scoring_err('NOT_FOUND', 'Không tìm thấy lượt chơi.');
  END IF;

  -- Khóa dòng đội
  SELECT * INTO v_team FROM public.teams WHERE id = v_team_id FOR UPDATE;

  -- Khóa dòng play
  SELECT * INTO v_play FROM public.station_plays WHERE id = p_play_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN public._direct_scoring_err('NOT_FOUND', 'Không tìm thấy lượt chơi.');
  END IF;

  -- 4. Kiểm tra trạng thái
  IF v_play.status != 'active' THEN
    RETURN public._direct_scoring_err('ALREADY_REVERSED', 'Lượt chơi này đã được hoàn tác trước đó.');
  END IF;

  -- 5. Kiểm tra quyền hạn & Cửa sổ hoàn tác
  SELECT assigned_station_id INTO v_assigned_station_id
  FROM public.staff WHERE id = v_auth.staff_id;

  IF v_auth.staff_role = 'admin' THEN
    -- Admin có toàn quyền hoàn tác mọi thời điểm
    NULL;
  ELSIF v_auth.staff_role = 'support' THEN
    IF v_assigned_station_id IS DISTINCT FROM v_play.station_id THEN
      RETURN public._direct_scoring_err('FORBIDDEN_STATION', 'Bạn không được phân công quản trạm của lượt chơi này.');
    END IF;

    SELECT COALESCE((value->>'v')::INT, 5) INTO v_undo_window
    FROM public.game_settings WHERE key = 'undo_window_minutes';
    IF v_undo_window IS NULL THEN v_undo_window := 5; END IF;

    IF (now() - v_play.created_at) > (v_undo_window || ' minutes')::INTERVAL THEN
      RETURN public._direct_scoring_err(
        'UNDO_WINDOW_EXPIRED',
        format('Đã hết thời hạn hoàn tác (%s phút). Hãy liên hệ Admin!', v_undo_window)
      );
    END IF;
  ELSE
    RETURN public._direct_scoring_err('FORBIDDEN', 'Bạn không có quyền hoàn tác.');
  END IF;

  -- 6. Nếu play có giao dịch điểm (> 0)
  IF v_play.tx_id IS NOT NULL AND v_play.points > 0 THEN
    IF v_team.light_balance < v_play.points THEN
      RETURN public._direct_scoring_err(
        'INSUFFICIENT_FUNDS',
        format('Số dư đội (%s Lumen) không đủ để thu hồi %s Lumen.', v_team.light_balance, v_play.points),
        jsonb_build_object('current_balance', v_team.light_balance, 'required_points', v_play.points)
      );
    END IF;

    -- Đánh dấu giao dịch gốc đã bị hoàn tác
    UPDATE public.transactions
    SET is_reversed = true
    WHERE id = v_play.tx_id;

    -- Tạo giao dịch Reversal
    INSERT INTO public.transactions (
      client_request_id, team_id, amount, type, description,
      created_by, status, reversal_for_id
    ) VALUES (
      p_client_request_id,
      v_team_id,
      -v_play.points,
      'reversal',
      format('Hoàn tác lượt chơi trạm #%s (%s)', v_play.play_no, COALESCE(p_reason, 'Sai sót')),
      v_auth.staff_name,
      'approved',
      v_play.tx_id
    ) RETURNING id INTO v_reversal_tx_id;

    -- Trừ số dư đội
    UPDATE public.teams
    SET light_balance = light_balance - v_play.points
    WHERE id = v_team_id
    RETURNING light_balance INTO v_new_balance;
  ELSE
    v_new_balance := v_team.light_balance;
  END IF;

  -- 7. Cập nhật trạng thái play sang reversed
  UPDATE public.station_plays
  SET status = 'reversed',
      reversed_at = now(),
      reversed_by = v_auth.staff_name
  WHERE id = v_play.id;

  -- 8. Kiểm tra xem đội còn lượt chơi active nào tại trạm này không
  SELECT count(*) INTO v_remaining_active
  FROM public.station_plays
  WHERE team_id = v_team_id AND station_id = v_play.station_id AND status = 'active';

  -- Nếu không còn lượt active nào -> gỡ trạm khỏi unlocked_stations
  IF v_remaining_active = 0 THEN
    UPDATE public.teams
    SET unlocked_stations = array_remove(unlocked_stations, v_play.station_id::text)
    WHERE id = v_team_id;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'ok', true,
    'code', 'OK',
    'message', format('Đã hoàn tác thành công lượt chơi #%s.', v_play.play_no),
    'error', null,
    'replayed', false,
    'idempotent', false,
    'data', jsonb_build_object(
      'play_id', v_play.id,
      'reversal_tx_id', v_reversal_tx_id,
      'points_reversed', v_play.points,
      'new_balance', v_new_balance,
      'remaining_active_plays', v_remaining_active
    )
  );
END;
$$;

-- =====================================================================
-- B3-TRIGGER: ĐỒNG BỘ KHI ADMIN DÙNG REVERSE_TRANSACTION CŨ
-- Khi transactions.is_reversed chuyển thành true -> đồng bộ station_plays
-- =====================================================================

CREATE OR REPLACE FUNCTION public._trg_sync_station_play_on_tx_reversal()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_play              RECORD;
  v_remaining_active  INTEGER;
BEGIN
  IF (OLD.is_reversed IS DISTINCT FROM true) AND NEW.is_reversed = true THEN
    FOR v_play IN
      SELECT id, team_id, station_id
      FROM public.station_plays
      WHERE tx_id = NEW.id AND status = 'active'
    LOOP
      UPDATE public.station_plays
      SET status = 'reversed',
          reversed_at = now(),
          reversed_by = COALESCE(NEW.reviewed_by, 'tx_reversal_trigger')
      WHERE id = v_play.id;

      SELECT count(*) INTO v_remaining_active
      FROM public.station_plays
      WHERE team_id = v_play.team_id AND station_id = v_play.station_id AND status = 'active';

      IF v_remaining_active = 0 THEN
        UPDATE public.teams
        SET unlocked_stations = array_remove(unlocked_stations, v_play.station_id::text)
        WHERE id = v_play.team_id;
      END IF;
    END LOOP;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_station_play_on_tx_reversal ON public.transactions;
CREATE TRIGGER trg_sync_station_play_on_tx_reversal
  AFTER UPDATE OF is_reversed ON public.transactions
  FOR EACH ROW
  EXECUTE FUNCTION public._trg_sync_station_play_on_tx_reversal();

-- =====================================================================
-- B3c. RPC ĐỌC: get_team_station_progress
-- Hỗ trợ bất kỳ nhân sự đăng nhập xem tiến độ trạm của đội
-- =====================================================================

CREATE OR REPLACE FUNCTION public.get_team_station_progress(
  p_token      TEXT,
  p_team_id    UUID,
  p_station_id UUID DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_auth          RECORD;
  v_unlocked      TEXT[];
  v_rows          JSONB;
  v_total_points  INTEGER;
  v_total_plays   INTEGER;
BEGIN
  -- Xác thực
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

  IF p_team_id IS NULL THEN
    RETURN public._direct_scoring_err('TEAM_REQUIRED', 'Vui lòng chọn đội chơi.');
  END IF;

  SELECT COALESCE(unlocked_stations, ARRAY[]::text[]) INTO v_unlocked
  FROM public.teams WHERE id = p_team_id;

  IF NOT FOUND THEN
    RETURN public._direct_scoring_err('TEAM_NOT_FOUND', 'Không tìm thấy đội chơi.');
  END IF;

  -- Tổng hợp tiến độ từng trạm
  SELECT COALESCE(jsonb_agg(
           jsonb_build_object(
             'station_id', s.id,
             'name', s.name,
             'description', s.description,
             'order_index', s.order_index,
             'allow_multiple_attempts', s.allow_multiple_attempts,
             'max_score', s.max_score,
             'has_played', (agg.play_count > 0 OR s.id::text = ANY (v_unlocked)),
             'play_count', agg.play_count,
             'total_points', agg.total_points,
             'last_played_at', agg.last_played_at,
             'legacy', (agg.play_count = 0 AND s.id::text = ANY (v_unlocked))
           ) ORDER BY s.order_index, s.name
         ), '[]'::jsonb)
  INTO v_rows
  FROM public.stations s
  CROSS JOIN LATERAL (
    SELECT count(*)::int                        AS play_count,
           COALESCE(sum(p.points), 0)::int      AS total_points,
           max(p.created_at)                    AS last_played_at
    FROM public.station_plays p
    WHERE p.team_id = p_team_id AND p.station_id = s.id AND p.status = 'active'
  ) agg
  WHERE s.deleted_at IS NULL
    AND s.is_active
    AND (p_station_id IS NULL OR s.id = p_station_id);

  -- Tổng toàn đội trên toàn bộ trạm
  SELECT COALESCE(sum(points), 0)::int, count(*)::int
  INTO v_total_points, v_total_plays
  FROM public.station_plays
  WHERE team_id = p_team_id AND status = 'active';

  RETURN jsonb_build_object(
    'success', true,
    'ok', true,
    'code', 'OK',
    'message', '',
    'error', null,
    'replayed', false,
    'idempotent', false,
    'data', jsonb_build_object(
      'team_id', p_team_id,
      'stations', v_rows,
      'total_points', v_total_points,
      'total_plays', v_total_plays
    )
  );
END;
$$;

-- =====================================================================
-- B3d. RPC ĐỌC: get_station_recent_plays
-- Lượt nhập gần nhất của trạm cho Quản trò soát lỗi
-- =====================================================================

CREATE OR REPLACE FUNCTION public.get_station_recent_plays(
  p_token      TEXT,
  p_station_id UUID,
  p_limit      INTEGER DEFAULT 20
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_auth                RECORD;
  v_assigned_station_id UUID;
  v_rows                JSONB;
BEGIN
  -- Xác thực
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

  SELECT assigned_station_id INTO v_assigned_station_id
  FROM public.staff WHERE id = v_auth.staff_id;

  IF v_auth.staff_role = 'admin' THEN
    NULL;
  ELSIF v_auth.staff_role = 'support' THEN
    IF v_assigned_station_id IS DISTINCT FROM p_station_id THEN
      RETURN public._direct_scoring_err('FORBIDDEN_STATION', 'Bạn không được phân công quản trạm này.');
    END IF;
  ELSE
    RETURN public._direct_scoring_err('FORBIDDEN', 'Không có quyền truy cập.');
  END IF;

  SELECT COALESCE(jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC), '[]'::jsonb)
  INTO v_rows
  FROM (
    SELECT p.id AS play_id, p.tx_id, p.team_id, t.name AS team_name,
           p.points, p.play_no, p.status, p.staff_name, p.note, p.created_at
    FROM public.station_plays p
    JOIN public.teams t ON t.id = p.team_id
    WHERE p.station_id = p_station_id
    ORDER BY p.created_at DESC
    LIMIT LEAST(GREATEST(COALESCE(p_limit, 20), 1), 100)
  ) x;

  RETURN jsonb_build_object(
    'success', true,
    'ok', true,
    'code', 'OK',
    'message', '',
    'error', null,
    'replayed', false,
    'idempotent', false,
    'data', jsonb_build_object('plays', v_rows)
  );
END;
$$;

-- =====================================================================
-- B5. PHÂN QUYỀN THỰC THI (ANON, AUTHENTICATED) & RELOAD SCHEMA
-- =====================================================================

REVOKE ALL ON FUNCTION public.award_station_direct_points(TEXT, UUID, UUID, INTEGER, TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.reverse_station_play(TEXT, TEXT, UUID, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_team_station_progress(TEXT, UUID, UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_station_recent_plays(TEXT, UUID, INTEGER) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.award_station_direct_points(TEXT, UUID, UUID, INTEGER, TEXT, TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.reverse_station_play(TEXT, TEXT, UUID, TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_team_station_progress(TEXT, UUID, UUID) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_station_recent_plays(TEXT, UUID, INTEGER) TO anon, authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;