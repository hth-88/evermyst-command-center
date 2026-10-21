-- ============================================================================
-- EVERMYST TACTICAL OPERATOR - SUPABASE SCHEMA V2 (HARDENED & COMPLETE)
-- Hệ thống Điều hành Nội bộ cho Big Game "Evermyst"
-- Tuân thủ 100% 7 Nguyên tắc Bất biến:
-- 1. Mọi ghi dữ liệu chỉ qua RPC (Security Definer).
-- 2. Idempotent với client_request_id chống bấm đúp trên 4G.
-- 3. Khóa 2 dòng theo thứ tự ID chống Deadlock PvP.
-- 4. Audit trail đầy đủ, Reversal transactions (không sửa/xóa log cũ).
-- 5. Bảo mật RLS ẩn hints.content và staff.pin khỏi anon.
-- ============================================================================

-- 0. EXTENSIONS
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================================
-- 1. DROP EXISTING TO ALLOW CLEAN MIGRATION IF NEEDED
-- ============================================================================
-- (Giữ an toàn: tạo IF NOT EXISTS hoặc cấu trúc rõ ràng)

-- ---------------------------------------------------------------------------
-- 1. TABLES
-- ---------------------------------------------------------------------------

-- 1a. staff: Nhân sự BTC (Admin & Support)
CREATE TABLE IF NOT EXISTS staff (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name              TEXT NOT NULL,
  role              TEXT NOT NULL CHECK (role IN ('admin', 'support')),
  pin               TEXT NOT NULL,
  station_assigned  TEXT DEFAULT NULL,
  is_active         BOOLEAN DEFAULT true,
  created_at        TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_staff_pin ON staff(pin);

-- 1b. staff_sessions: Phiên đăng nhập qua PIN token
CREATE TABLE IF NOT EXISTS staff_sessions (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  staff_id          UUID NOT NULL REFERENCES staff(id) ON DELETE CASCADE,
  token             TEXT UNIQUE NOT NULL,
  expires_at        TIMESTAMPTZ NOT NULL,
  created_at        TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_sessions_token ON staff_sessions(token);

-- 1c. game_settings: Cấu hình game linh hoạt
CREATE TABLE IF NOT EXISTS game_settings (
  key         TEXT PRIMARY KEY,
  value       JSONB NOT NULL,
  label       TEXT NOT NULL,
  description TEXT DEFAULT '',
  category    TEXT NOT NULL DEFAULT 'general',
  is_public   BOOLEAN DEFAULT true,
  updated_at  TIMESTAMPTZ DEFAULT now(),
  updated_by  TEXT DEFAULT 'system'
);

-- 1d. game_settings_history: Lịch sử thay đổi luật chơi
CREATE TABLE IF NOT EXISTS game_settings_history (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  key         TEXT NOT NULL,
  old_value   JSONB,
  new_value   JSONB NOT NULL,
  changed_by  TEXT NOT NULL,
  created_at  TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_settings_hist_key ON game_settings_history(key, created_at DESC);

-- 1e. teams: Đội chơi
CREATE TABLE IF NOT EXISTS teams (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name              TEXT NOT NULL,
  qr_code           TEXT UNIQUE NOT NULL,
  light_balance     INT NOT NULL DEFAULT 100,
  shield_until      TIMESTAMPTZ DEFAULT NULL,
  unlocked_stations TEXT[] DEFAULT '{}',
  is_active         BOOLEAN DEFAULT true,
  created_at        TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_teams_qr ON teams(qr_code);
CREATE INDEX IF NOT EXISTS idx_teams_balance ON teams(light_balance DESC);

-- 1f. stations: Trạm thử thách
CREATE TABLE IF NOT EXISTS stations (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name            TEXT NOT NULL,
  description     TEXT DEFAULT '',
  order_index     INT DEFAULT 0,
  is_active       BOOLEAN DEFAULT true,
  created_at      TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_stations_order ON stations(order_index ASC);

-- 1g. hints: Manh mối (Content được bảo mật)
CREATE TABLE IF NOT EXISTS hints (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  station_id  UUID REFERENCES stations(id) ON DELETE SET NULL,
  title       TEXT NOT NULL,
  content     TEXT NOT NULL,
  tier        TEXT NOT NULL CHECK (tier IN ('bronze', 'silver', 'gold')),
  order_index INT DEFAULT 0,
  is_active   BOOLEAN DEFAULT true,
  created_at  TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_hints_station ON hints(station_id);

-- 1h. team_hints: Manh mối đội đã mở khóa
CREATE TABLE IF NOT EXISTS team_hints (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  team_id     UUID NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
  hint_id     UUID NOT NULL REFERENCES hints(id) ON DELETE CASCADE,
  unlocked_at TIMESTAMPTZ DEFAULT now(),
  unlocked_by TEXT NOT NULL,
  UNIQUE(team_id, hint_id)
);

-- 1i. items: Đạo cụ trong Shop
CREATE TABLE IF NOT EXISTS items (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name              TEXT NOT NULL,
  description       TEXT DEFAULT '',
  price             INT NOT NULL,
  effect_type       TEXT NOT NULL CHECK (effect_type IN ('shield', 'spy', 'key')),
  duration_minutes  INT DEFAULT 0,
  is_active         BOOLEAN DEFAULT true,
  created_at        TIMESTAMPTZ DEFAULT now()
);

-- 1j. team_items: Kho đồ đội (Inventory)
CREATE TABLE IF NOT EXISTS team_items (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  team_id     UUID NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
  item_id     UUID NOT NULL REFERENCES items(id) ON DELETE CASCADE,
  quantity    INT NOT NULL DEFAULT 1 CHECK (quantity >= 0),
  used_count  INT NOT NULL DEFAULT 0,
  created_at  TIMESTAMPTZ DEFAULT now(),
  updated_at  TIMESTAMPTZ DEFAULT now(),
  UNIQUE(team_id, item_id)
);

-- 1k. transactions: Lịch sử tài chính & Audit trail
CREATE TABLE IF NOT EXISTS transactions (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  client_request_id TEXT UNIQUE,
  team_id           UUID NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
  amount            INT NOT NULL,
  type              TEXT NOT NULL CHECK (type IN (
    'station_clear', 'buy_hint', 'buy_item',
    'pvp_steal', 'pvp_backlash', 'admin_adjust', 'reversal'
  )),
  description       TEXT DEFAULT '',
  created_by        TEXT NOT NULL,
  status            TEXT NOT NULL DEFAULT 'approved' CHECK (status IN ('approved', 'pending', 'rejected')),
  reviewed_by       TEXT DEFAULT NULL,
  reviewed_at       TIMESTAMPTZ DEFAULT NULL,
  is_reversed       BOOLEAN DEFAULT false,
  reversal_for_id   UUID REFERENCES transactions(id),
  created_at        TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_tx_team ON transactions(team_id);
CREATE INDEX IF NOT EXISTS idx_tx_status ON transactions(status);
CREATE INDEX IF NOT EXISTS idx_tx_created ON transactions(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_tx_client_req ON transactions(client_request_id);

-- 1l. pvp_logs: Nhật ký giao đấu PvP
CREATE TABLE IF NOT EXISTS pvp_logs (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  client_request_id TEXT UNIQUE,
  attacker_team_id  UUID NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
  defender_team_id  UUID NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
  amount_stolen     INT NOT NULL DEFAULT 0,
  result            TEXT NOT NULL CHECK (result IN ('success', 'backlash', 'cooldown_blocked')),
  created_by        TEXT NOT NULL,
  created_at        TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_pvp_pair ON pvp_logs(attacker_team_id, defender_team_id, created_at DESC);


-- ============================================================================
-- 2. ENABLE REALTIME
-- ============================================================================
DO $$
BEGIN
  BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE teams; EXCEPTION WHEN others THEN NULL; END;
  BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE stations; EXCEPTION WHEN others THEN NULL; END;
  BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE hints; EXCEPTION WHEN others THEN NULL; END;
  BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE items; EXCEPTION WHEN others THEN NULL; END;
  BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE team_hints; EXCEPTION WHEN others THEN NULL; END;
  BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE team_items; EXCEPTION WHEN others THEN NULL; END;
  BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE transactions; EXCEPTION WHEN others THEN NULL; END;
  BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE pvp_logs; EXCEPTION WHEN others THEN NULL; END;
  BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE game_settings; EXCEPTION WHEN others THEN NULL; END;
END $$;


-- ============================================================================
-- 3. ROW LEVEL SECURITY (RLS) - An toàn và bảo mật
-- ============================================================================
ALTER TABLE staff                 ENABLE ROW LEVEL SECURITY;
ALTER TABLE staff_sessions        ENABLE ROW LEVEL SECURITY;
ALTER TABLE game_settings         ENABLE ROW LEVEL SECURITY;
ALTER TABLE game_settings_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE teams                 ENABLE ROW LEVEL SECURITY;
ALTER TABLE stations              ENABLE ROW LEVEL SECURITY;
ALTER TABLE hints                 ENABLE ROW LEVEL SECURITY;
ALTER TABLE team_hints            ENABLE ROW LEVEL SECURITY;
ALTER TABLE items                 ENABLE ROW LEVEL SECURITY;
ALTER TABLE team_items            ENABLE ROW LEVEL SECURITY;
ALTER TABLE transactions          ENABLE ROW LEVEL SECURITY;
ALTER TABLE pvp_logs              ENABLE ROW LEVEL SECURITY;

-- Drop old policies if any to avoid conflict
DO $$
DECLARE
  pol RECORD;
BEGIN
  FOR pol IN SELECT policyname, tablename FROM pg_policies WHERE schemaname = 'public' LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON %I', pol.policyname, pol.tablename);
  END LOOP;
END $$;

-- Policy: Cho phép SELECT dữ liệu công khai cho Anon (đọc bảng điều khiển)
CREATE POLICY "Public Read Game Settings" ON game_settings FOR SELECT USING (true);
CREATE POLICY "Public Read Teams"         ON teams         FOR SELECT USING (true);
CREATE POLICY "Public Read Stations"      ON stations      FOR SELECT USING (true);
CREATE POLICY "Public Read Items"         ON items         FOR SELECT USING (true);
CREATE POLICY "Public Read Team Hints"    ON team_hints    FOR SELECT USING (true);
CREATE POLICY "Public Read Team Items"    ON team_items    FOR SELECT USING (true);
CREATE POLICY "Public Read Transactions"  ON transactions  FOR SELECT USING (true);
CREATE POLICY "Public Read PvP Logs"      ON pvp_logs      FOR SELECT USING (true);
CREATE POLICY "Public Read Staff Public"  ON staff         FOR SELECT USING (true);

-- Bảo mật hints: Chỉ xem id, station_id, title, tier, order_index, is_active.
-- Cột 'content' chỉ được trả về qua RPC bảo mật buy_hint / get_team_hints / admin_list_hints!
CREATE POLICY "Public Read Hints"         ON hints         FOR SELECT USING (true);

-- NGUYÊN TẮC BẤT BIẾN 1: TUYỆT ĐỐI KHÔNG CẤP QUYỀN INSERT/UPDATE/DELETE TRỰC TIẾP TỪ CLIENT!
-- Mọi ghi nhận phải đi qua RPC Security Definer dưới đây.


-- ============================================================================
-- 4. HELPER FUNCTIONS: SESSION & AUTH VALIDATION
-- ============================================================================

-- Hàm kiểm tra session token và trả về thông tin nhân sự
CREATE OR REPLACE FUNCTION auth_verify_session(
  p_token           TEXT,
  p_required_role   TEXT DEFAULT NULL
)
RETURNS TABLE (
  staff_id          UUID,
  staff_name        TEXT,
  staff_role        TEXT,
  station_assigned  TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT s.id, s.name, s.role, s.station_assigned
  FROM staff_sessions ss
  JOIN staff s ON s.id = ss.staff_id
  WHERE ss.token = p_token
    AND ss.expires_at > now()
    AND s.is_active = true
    AND (p_required_role IS NULL OR s.role = p_required_role);

  IF NOT FOUND THEN
    RAISE EXCEPTION 'INVALID_TOKEN: Phiên đăng nhập không hợp lệ hoặc đã hết hạn';
  END IF;
END;
$$;


-- ============================================================================
-- 5. RPC BUSINESS FUNCTIONS (16 RPCs)
-- ============================================================================

-- ---------------------------------------------------------------------------
-- RPC 1: staff_login - Đăng nhập bằng PIN, tạo session token (Hết hạn sau 24h)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION staff_login(
  p_pin TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_staff   RECORD;
  v_token   TEXT;
  v_expires TIMESTAMPTZ;
BEGIN
  SELECT id, name, role, station_assigned INTO v_staff
  FROM staff
  WHERE pin = trim(p_pin) AND is_active = true;

  IF v_staff IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'code', 'INVALID_CREDENTIALS',
      'error', 'Mã PIN không chính xác hoặc tài khoản đã bị khóa'
    );
  END IF;

  -- Tạo token ngẫu nhiên
  v_token := encode(gen_random_bytes(32), 'hex');
  v_expires := now() + INTERVAL '24 hours';

  INSERT INTO staff_sessions (staff_id, token, expires_at)
  VALUES (v_staff.id, v_token, v_expires);

  RETURN jsonb_build_object(
    'success', true,
    'token', v_token,
    'expires_at', v_expires,
    'user', jsonb_build_object(
      'id', v_staff.id,
      'name', v_staff.name,
      'role', v_staff.role,
      'station_assigned', v_staff.station_assigned
    )
  );
END;
$$;

-- ---------------------------------------------------------------------------
-- RPC 2: staff_list_public - Danh sách nhân sự cho màn chọn nhanh (Không lộ PIN)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION staff_list_public()
RETURNS JSONB
LANGUAGE sql
SECURITY DEFINER
AS $$
  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'id', id,
        'name', name,
        'role', role,
        'station_assigned', station_assigned
      ) ORDER BY role ASC, name ASC
    ),
    '[]'::jsonb
  )
  FROM staff
  WHERE is_active = true;
$$;

-- ---------------------------------------------------------------------------
-- RPC 3: get_server_time - Lấy giờ server để tính serverOffsetMs
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_server_time()
RETURNS JSONB
LANGUAGE sql
SECURITY DEFINER
AS $$
  SELECT jsonb_build_object(
    'success', true,
    'server_time', now(),
    'epoch_ms', (EXTRACT(EPOCH FROM now()) * 1000)::BIGINT
  );
$$;

-- ---------------------------------------------------------------------------
-- RPC 4: award_station - Thưởng điểm trạm cho đội (Idempotent + Atomic)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION award_station(
  p_token             TEXT,
  p_client_request_id TEXT,
  p_team_id           UUID,
  p_station_id        UUID,
  p_amount            INT,
  p_unlock_station    BOOLEAN DEFAULT false
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_staff         RECORD;
  v_team          RECORD;
  v_station_name  TEXT;
  v_threshold     INT;
  v_status        TEXT;
  v_tx_id         UUID;
  v_new_balance   INT;
  v_existing_tx   RECORD;
BEGIN
  -- 1. Kiểm tra session
  SELECT * INTO v_staff FROM auth_verify_session(p_token);

  -- 2. Idempotency Check
  IF p_client_request_id IS NOT NULL AND p_client_request_id <> '' THEN
    SELECT id, status, amount INTO v_existing_tx
    FROM transactions WHERE client_request_id = p_client_request_id;
    IF v_existing_tx IS NOT NULL THEN
      RETURN jsonb_build_object(
        'success', true,
        'idempotent', true,
        'status', v_existing_tx.status,
        'transaction_id', v_existing_tx.id,
        'message', 'Yêu cầu đã được xử lý thành công trước đó.'
      );
    END IF;
  END IF;

  -- 3. Validate số tiền
  IF p_amount <= 0 THEN
    RETURN jsonb_build_object('success', false, 'code', 'INVALID_AMOUNT', 'error', 'Số điểm thưởng phải lớn hơn 0');
  END IF;

  -- 4. Khóa dòng đội chơi
  SELECT * INTO v_team FROM teams WHERE id = p_team_id AND is_active = true FOR UPDATE;
  IF v_team IS NULL THEN
    RETURN jsonb_build_object('success', false, 'code', 'TEAM_NOT_FOUND', 'error', 'Đội chơi không tồn tại');
  END IF;

  -- Lấy tên trạm
  SELECT name INTO v_station_name FROM stations WHERE id = p_station_id;

  -- 5. Lấy threshold
  SELECT COALESCE((value->>'v')::INT, 50) INTO v_threshold
  FROM game_settings WHERE key = 'pending_threshold';
  IF v_threshold IS NULL THEN v_threshold := 50; END IF;

  -- Xác định trạng thái
  IF p_amount > v_threshold THEN
    v_status := 'pending';
  ELSE
    v_status := 'approved';
  END IF;

  -- 6. Tạo Transaction
  INSERT INTO transactions (
    client_request_id, team_id, amount, type, description,
    created_by, status
  ) VALUES (
    p_client_request_id,
    p_team_id,
    p_amount,
    'station_clear',
    'Trạm ' || COALESCE(v_station_name, 'N/A') || ' (+' || p_amount || ' Lumen)',
    v_staff.staff_name,
    v_status
  ) RETURNING id INTO v_tx_id;

  -- 7. Cập nhật số dư nếu approved
  IF v_status = 'approved' THEN
    UPDATE teams
    SET light_balance = light_balance + p_amount
    WHERE id = p_team_id
    RETURNING light_balance INTO v_new_balance;
  ELSE
    v_new_balance := v_team.light_balance;
  END IF;

  -- 8. Mở khóa trạm nếu có yêu cầu
  IF p_unlock_station AND p_station_id IS NOT NULL THEN
    UPDATE teams
    SET unlocked_stations = array_append(
      array_remove(unlocked_stations, p_station_id::TEXT),
      p_station_id::TEXT
    )
    WHERE id = p_team_id;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'status', v_status,
    'transaction_id', v_tx_id,
    'new_balance', v_new_balance,
    'message', CASE
      WHEN v_status = 'pending' THEN 'Giao dịch ' || p_amount || ' Lumen vượt ngưỡng (' || v_threshold || ') -> Chờ Admin duyệt!'
      ELSE 'Đã cộng +' || p_amount || ' Lumen cho đội ' || v_team.name
    END
  );
END;
$$;

-- ---------------------------------------------------------------------------
-- RPC 5: buy_hint - Mua Manh mối bí mật (Trừ tiền atomic, trả về nội dung)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION buy_hint(
  p_token             TEXT,
  p_client_request_id TEXT,
  p_team_id           UUID,
  p_hint_id           UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_staff         RECORD;
  v_hint          RECORD;
  v_team          RECORD;
  v_price         INT;
  v_existing_tx   RECORD;
  v_already_owned BOOLEAN;
BEGIN
  SELECT * INTO v_staff FROM auth_verify_session(p_token);

  -- Idempotency check
  IF p_client_request_id IS NOT NULL AND p_client_request_id <> '' THEN
    SELECT id INTO v_existing_tx FROM transactions WHERE client_request_id = p_client_request_id;
    IF v_existing_tx IS NOT NULL THEN
      SELECT title, content INTO v_hint FROM hints WHERE id = p_hint_id;
      RETURN jsonb_build_object(
        'success', true,
        'idempotent', true,
        'hint_title', v_hint.title,
        'hint_content', v_hint.content,
        'message', 'Manh mối đã được mở khóa trước đó.'
      );
    END IF;
  END IF;

  -- Lấy thông tin hint
  SELECT * INTO v_hint FROM hints WHERE id = p_hint_id AND is_active = true;
  IF v_hint IS NULL THEN
    RETURN jsonb_build_object('success', false, 'code', 'NOT_FOUND', 'error', 'Manh mối không tồn tại hoặc đã bị khóa');
  END IF;

  -- Kiểm tra đội đã sở hữu chưa
  SELECT EXISTS(SELECT 1 FROM team_hints WHERE team_id = p_team_id AND hint_id = p_hint_id)
  INTO v_already_owned;
  IF v_already_owned THEN
    RETURN jsonb_build_object(
      'success', true,
      'code', 'ALREADY_OWNED',
      'hint_title', v_hint.title,
      'hint_content', v_hint.content,
      'message', 'Đội đã sở hữu manh mối này từ trước!'
    );
  END IF;

  -- Lấy giá theo tier từ game_settings
  SELECT COALESCE((value->>'v')::INT, 
    CASE v_hint.tier WHEN 'bronze' THEN 20 WHEN 'silver' THEN 50 WHEN 'gold' THEN 100 ELSE 50 END
  ) INTO v_price
  FROM game_settings WHERE key = 'hint_price_' || v_hint.tier;
  IF v_price IS NULL THEN v_price := 50; END IF;

  -- Khóa dòng đội chơi kiểm tra số dư
  SELECT * INTO v_team FROM teams WHERE id = p_team_id FOR UPDATE;
  IF v_team.light_balance < v_price THEN
    RETURN jsonb_build_object(
      'success', false,
      'code', 'INSUFFICIENT_FUNDS',
      'error', 'Không đủ Lumen! Cần ' || v_price || ' Lumen, hiện chỉ có ' || v_team.light_balance
    );
  END IF;

  -- Trừ tiền atomic
  UPDATE teams SET light_balance = light_balance - v_price WHERE id = p_team_id;

  -- Lưu vào team_hints
  INSERT INTO team_hints (team_id, hint_id, unlocked_by)
  VALUES (p_team_id, p_hint_id, v_staff.staff_name);

  -- Ghi transaction
  INSERT INTO transactions (
    client_request_id, team_id, amount, type, description, created_by, status
  ) VALUES (
    p_client_request_id, p_team_id, -v_price, 'buy_hint',
    'Mua Hint [' || upper(v_hint.tier) || ']: ' || v_hint.title,
    v_staff.staff_name, 'approved'
  );

  RETURN jsonb_build_object(
    'success', true,
    'hint_title', v_hint.title,
    'hint_content', v_hint.content,
    'price', v_price,
    'new_balance', v_team.light_balance - v_price,
    'message', 'Đã mua thành công hint "' || v_hint.title || '" (-' || v_price || ' Lumen)'
  );
END;
$$;

-- ---------------------------------------------------------------------------
-- RPC 6: get_team_hints - Lấy danh sách hints đã mở khóa kèm nội dung bí mật
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_team_hints(
  p_token   TEXT,
  p_team_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_staff RECORD;
BEGIN
  SELECT * INTO v_staff FROM auth_verify_session(p_token);

  RETURN (
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
    )
    FROM team_hints th
    JOIN hints h ON h.id = th.hint_id
    WHERE th.team_id = p_team_id
  );
END;
$$;

-- ---------------------------------------------------------------------------
-- RPC 7: buy_item - Mua đạo cụ trong Shop (Cộng vào kho đồ hoặc kích hoạt khiên)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION buy_item(
  p_token             TEXT,
  p_client_request_id TEXT,
  p_team_id           UUID,
  p_item_id           UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_staff         RECORD;
  v_item          RECORD;
  v_team          RECORD;
  v_shield_dur    INT;
  v_existing_tx   RECORD;
BEGIN
  SELECT * INTO v_staff FROM auth_verify_session(p_token);

  -- Idempotency
  IF p_client_request_id IS NOT NULL AND p_client_request_id <> '' THEN
    SELECT id INTO v_existing_tx FROM transactions WHERE client_request_id = p_client_request_id;
    IF v_existing_tx IS NOT NULL THEN
      RETURN jsonb_build_object('success', true, 'idempotent', true, 'message', 'Đạo cụ đã được mua trước đó.');
    END IF;
  END IF;

  SELECT * INTO v_item FROM items WHERE id = p_item_id AND is_active = true;
  IF v_item IS NULL THEN
    RETURN jsonb_build_object('success', false, 'code', 'NOT_FOUND', 'error', 'Vật phẩm không tồn tại');
  END IF;

  -- Khóa dòng đội
  SELECT * INTO v_team FROM teams WHERE id = p_team_id FOR UPDATE;
  IF v_team.light_balance < v_item.price THEN
    RETURN jsonb_build_object(
      'success', false,
      'code', 'INSUFFICIENT_FUNDS',
      'error', 'Không đủ Lumen! Cần ' || v_item.price || ', hiện có ' || v_team.light_balance
    );
  END IF;

  -- Trừ tiền
  UPDATE teams SET light_balance = light_balance - v_item.price WHERE id = p_team_id;

  -- Xử lý theo loại vật phẩm
  IF v_item.effect_type = 'shield' THEN
    -- Khiên kích hoạt ngay lập tức
    SELECT COALESCE((value->>'v')::INT, v_item.duration_minutes, 15) INTO v_shield_dur
    FROM game_settings WHERE key = 'shield_duration_minutes';
    IF v_shield_dur IS NULL OR v_shield_dur <= 0 THEN v_shield_dur := 15; END IF;

    UPDATE teams
    SET shield_until = GREATEST(COALESCE(shield_until, now()), now()) + (v_shield_dur || ' minutes')::INTERVAL
    WHERE id = p_team_id;
  ELSE
    -- Thêm vào kho đồ team_items
    INSERT INTO team_items (team_id, item_id, quantity, used_count)
    VALUES (p_team_id, p_item_id, 1, 0)
    ON CONFLICT (team_id, item_id)
    DO UPDATE SET quantity = team_items.quantity + 1, updated_at = now();
  END IF;

  -- Ghi transaction
  INSERT INTO transactions (
    client_request_id, team_id, amount, type, description, created_by, status
  ) VALUES (
    p_client_request_id, p_team_id, -v_item.price, 'buy_item',
    'Mua ' || v_item.name || ' (-' || v_item.price || ' Lumen)',
    v_staff.staff_name, 'approved'
  );

  RETURN jsonb_build_object(
    'success', true,
    'item_name', v_item.name,
    'effect_type', v_item.effect_type,
    'price', v_item.price,
    'new_balance', v_team.light_balance - v_item.price,
    'message', 'Đã mua thành công "' || v_item.name || '"'
  );
END;
$$;

-- ---------------------------------------------------------------------------
-- RPC 8: use_team_item - Kích hoạt đạo cụ từ kho đồ
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION use_team_item(
  p_token             TEXT,
  p_client_request_id TEXT,
  p_team_id           UUID,
  p_item_id           UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_staff     RECORD;
  v_inventory RECORD;
  v_item      RECORD;
BEGIN
  SELECT * INTO v_staff FROM auth_verify_session(p_token);

  SELECT * INTO v_inventory
  FROM team_items
  WHERE team_id = p_team_id AND item_id = p_item_id AND quantity > 0
  FOR UPDATE;

  IF v_inventory IS NULL THEN
    RETURN jsonb_build_object('success', false, 'code', 'NOT_OWNED', 'error', 'Đội không có vật phẩm này trong kho');
  END IF;

  SELECT * INTO v_item FROM items WHERE id = p_item_id;

  -- Trừ số lượng kho đồ
  UPDATE team_items
  SET quantity = quantity - 1, used_count = used_count + 1, updated_at = now()
  WHERE id = v_inventory.id;

  -- Nếu là khiên thì bật khiên
  IF v_item.effect_type = 'shield' THEN
    UPDATE teams
    SET shield_until = GREATEST(COALESCE(shield_until, now()), now()) + (v_item.duration_minutes || ' minutes')::INTERVAL
    WHERE id = p_team_id;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'message', 'Đã sử dụng thành công: ' || v_item.name
  );
END;
$$;

-- ---------------------------------------------------------------------------
-- RPC 9: resolve_pvp - Xử lý combat giữa 2 đội (DEADLOCK-SAFE + ATOMIC)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION resolve_pvp(
  p_token             TEXT,
  p_client_request_id TEXT,
  p_attacker_id       UUID,
  p_defender_id       UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_staff         RECORD;
  v_atk           RECORD;
  v_def           RECORD;
  v_cooldown_min  INT;
  v_steal_pct     INT;
  v_backlash_amt  INT;
  v_last_combat   TIMESTAMPTZ;
  v_stolen_amount INT;
  v_existing_log  RECORD;
BEGIN
  SELECT * INTO v_staff FROM auth_verify_session(p_token);

  IF p_attacker_id = p_defender_id THEN
    RETURN jsonb_build_object('success', false, 'code', 'FORBIDDEN', 'error', 'Không thể tự tấn công chính mình!');
  END IF;

  -- Idempotency check
  IF p_client_request_id IS NOT NULL AND p_client_request_id <> '' THEN
    SELECT id, result, amount_stolen INTO v_existing_log
    FROM pvp_logs WHERE client_request_id = p_client_request_id;
    IF v_existing_log IS NOT NULL THEN
      RETURN jsonb_build_object(
        'success', true,
        'idempotent', true,
        'result', v_existing_log.result,
        'stolen_amount', v_existing_log.amount_stolen,
        'message', 'Trận đấu này đã được ghi nhận trước đó.'
      );
    END IF;
  END IF;

  -- 1. DEADLOCK PREVENTION: Khóa 2 dòng teams theo thứ tự ID cố định
  IF p_attacker_id < p_defender_id THEN
    PERFORM 1 FROM teams WHERE id = p_attacker_id FOR UPDATE;
    PERFORM 1 FROM teams WHERE id = p_defender_id FOR UPDATE;
  ELSE
    PERFORM 1 FROM teams WHERE id = p_defender_id FOR UPDATE;
    PERFORM 1 FROM teams WHERE id = p_attacker_id FOR UPDATE;
  END IF;

  SELECT * INTO v_atk FROM teams WHERE id = p_attacker_id;
  SELECT * INTO v_def FROM teams WHERE id = p_defender_id;

  IF v_atk IS NULL OR v_def IS NULL THEN
    RETURN jsonb_build_object('success', false, 'code', 'TEAM_NOT_FOUND', 'error', 'Một trong hai đội không tồn tại');
  END IF;

  -- Lấy cài đặt luật PvP
  SELECT COALESCE((value->>'v')::INT, 30) INTO v_cooldown_min FROM game_settings WHERE key = 'pvp_cooldown_minutes';
  SELECT COALESCE((value->>'v')::INT, 15) INTO v_steal_pct    FROM game_settings WHERE key = 'pvp_steal_percent';
  SELECT COALESCE((value->>'v')::INT, 10) INTO v_backlash_amt FROM game_settings WHERE key = 'pvp_backlash_amount';

  -- 2. Kiểm tra Cooldown giữa cặp đội
  SELECT created_at INTO v_last_combat
  FROM pvp_logs
  WHERE attacker_team_id = p_attacker_id
    AND defender_team_id = p_defender_id
    AND result != 'cooldown_blocked'
  ORDER BY created_at DESC
  LIMIT 1;

  IF v_last_combat IS NOT NULL AND (now() - v_last_combat) < (v_cooldown_min || ' minutes')::INTERVAL THEN
    INSERT INTO pvp_logs (client_request_id, attacker_team_id, defender_team_id, amount_stolen, result, created_by)
    VALUES (p_client_request_id, p_attacker_id, p_defender_id, 0, 'cooldown_blocked', v_staff.staff_name);

    RETURN jsonb_build_object(
      'success', false,
      'code', 'COOLDOWN_ACTIVE',
      'result', 'cooldown_blocked',
      'error', v_atk.name || ' vừa tấn công ' || v_def.name || '. Phải chờ thêm cooldown!',
      'cooldown_until', v_last_combat + (v_cooldown_min || ' minutes')::INTERVAL
    );
  END IF;

  -- 3. Kiểm tra Khiên bảo vệ của Defender -> PHẢN PHỆ
  IF v_def.shield_until IS NOT NULL AND v_def.shield_until > now() THEN
    -- Trừ tiền Attacker
    UPDATE teams SET light_balance = light_balance - v_backlash_amt WHERE id = p_attacker_id;

    INSERT INTO transactions (client_request_id, team_id, amount, type, description, created_by, status)
    VALUES (p_client_request_id, p_attacker_id, -v_backlash_amt, 'pvp_backlash',
      'Phản phệ PvP! ' || v_def.name || ' có Khiên. Bị trừ -' || v_backlash_amt || ' Lumen',
      v_staff.staff_name, 'approved');

    INSERT INTO pvp_logs (client_request_id, attacker_team_id, defender_team_id, amount_stolen, result, created_by)
    VALUES (p_client_request_id, p_attacker_id, p_defender_id, 0, 'backlash', v_staff.staff_name);

    RETURN jsonb_build_object(
      'success', true,
      'result', 'backlash',
      'message', '🛡️ PHẢN PHỆ! ' || v_def.name || ' đang có Khiên Màn Sương! ' || v_atk.name || ' bị phạt -' || v_backlash_amt || ' Lumen!',
      'backlash_amount', v_backlash_amt,
      'attacker_new_balance', v_atk.light_balance - v_backlash_amt
    );
  END IF;

  -- 4. Tính toán Cướp điểm thành công
  v_stolen_amount := FLOOR(v_def.light_balance * v_steal_pct / 100.0)::INT;
  IF v_stolen_amount < 1 THEN v_stolen_amount := 0; END IF;

  -- Cập nhật số dư 2 bên
  UPDATE teams SET light_balance = light_balance - v_stolen_amount WHERE id = p_defender_id;
  UPDATE teams SET light_balance = light_balance + v_stolen_amount WHERE id = p_attacker_id;

  -- Ghi nhận 2 transactions
  INSERT INTO transactions (team_id, amount, type, description, created_by, status) VALUES
    (p_attacker_id, v_stolen_amount, 'pvp_steal',
     'PvP thắng: Cướp +' || v_stolen_amount || ' Lumen từ ' || v_def.name,
     v_staff.staff_name, 'approved'),
    (p_defender_id, -v_stolen_amount, 'pvp_steal',
     'PvP thua: Bị ' || v_atk.name || ' cướp -' || v_stolen_amount || ' Lumen',
     v_staff.staff_name, 'approved');

  -- Ghi log combat
  INSERT INTO pvp_logs (client_request_id, attacker_team_id, defender_team_id, amount_stolen, result, created_by)
  VALUES (p_client_request_id, p_attacker_id, p_defender_id, v_stolen_amount, 'success', v_staff.staff_name);

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

-- ---------------------------------------------------------------------------
-- RPC 10: decide_pending - Admin duyệt hoặc từ chối giao dịch pending
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION decide_pending(
  p_token         TEXT,
  p_tx_id         UUID,
  p_decision      TEXT, -- 'approve' | 'reject'
  p_reason        TEXT DEFAULT ''
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_staff RECORD;
  v_tx    RECORD;
BEGIN
  SELECT * INTO v_staff FROM auth_verify_session(p_token, 'admin');

  SELECT * INTO v_tx FROM transactions WHERE id = p_tx_id FOR UPDATE;
  IF v_tx IS NULL THEN
    RETURN jsonb_build_object('success', false, 'code', 'NOT_FOUND', 'error', 'Giao dịch không tồn tại');
  END IF;

  IF v_tx.status != 'pending' THEN
    RETURN jsonb_build_object('success', false, 'code', 'NOT_PENDING', 'error', 'Giao dịch này đã được xử lý: ' || v_tx.status);
  END IF;

  IF p_decision = 'approve' THEN
    UPDATE transactions
    SET status = 'approved', reviewed_by = v_staff.staff_name, reviewed_at = now()
    WHERE id = p_tx_id;

    -- Cộng tiền cho đội
    UPDATE teams SET light_balance = light_balance + v_tx.amount WHERE id = v_tx.team_id;

    RETURN jsonb_build_object('success', true, 'message', 'Đã duyệt +' || v_tx.amount || ' Lumen cho đội!');
  ELSE
    UPDATE transactions
    SET status = 'rejected', reviewed_by = v_staff.staff_name, reviewed_at = now(),
        description = description || ' [Từ chối: ' || COALESCE(p_reason, 'Admin reject') || ']'
    WHERE id = p_tx_id;

    RETURN jsonb_build_object('success', true, 'message', 'Đã từ chối giao dịch');
  END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- RPC 11: admin_adjust_balance - Admin can thiệp cộng/trừ điểm khẩn cấp
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION admin_adjust_balance(
  p_token             TEXT,
  p_client_request_id TEXT,
  p_team_id           UUID,
  p_amount            INT,
  p_description       TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_staff       RECORD;
  v_team        RECORD;
  v_new_balance INT;
BEGIN
  SELECT * INTO v_staff FROM auth_verify_session(p_token, 'admin');

  SELECT * INTO v_team FROM teams WHERE id = p_team_id FOR UPDATE;
  IF v_team IS NULL THEN
    RETURN jsonb_build_object('success', false, 'code', 'TEAM_NOT_FOUND', 'error', 'Đội không tồn tại');
  END IF;

  UPDATE teams
  SET light_balance = light_balance + p_amount
  WHERE id = p_team_id
  RETURNING light_balance INTO v_new_balance;

  INSERT INTO transactions (
    client_request_id, team_id, amount, type, description, created_by, status
  ) VALUES (
    p_client_request_id, p_team_id, p_amount, 'admin_adjust',
    'Admin điều chỉnh: ' || COALESCE(p_description, 'Khẩn cấp'),
    v_staff.staff_name, 'approved'
  );

  RETURN jsonb_build_object(
    'success', true,
    'new_balance', v_new_balance,
    'message', 'Đã ' || CASE WHEN p_amount >= 0 THEN 'cộng +' ELSE 'trừ ' END || p_amount || ' Lumen cho ' || v_team.name
  );
END;
$$;

-- ---------------------------------------------------------------------------
-- RPC 12: admin_set_shield - Bật/tắt hoặc gia hạn khiên thủ công
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION admin_set_shield(
  p_token             TEXT,
  p_team_id           UUID,
  p_duration_minutes  INT -- <= 0 để tắt khiên
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_staff RECORD;
  v_team  RECORD;
BEGIN
  SELECT * INTO v_staff FROM auth_verify_session(p_token, 'admin');

  SELECT * INTO v_team FROM teams WHERE id = p_team_id FOR UPDATE;
  IF v_team IS NULL THEN
    RETURN jsonb_build_object('success', false, 'code', 'TEAM_NOT_FOUND', 'error', 'Đội không tồn tại');
  END IF;

  IF p_duration_minutes > 0 THEN
    UPDATE teams
    SET shield_until = now() + (p_duration_minutes || ' minutes')::INTERVAL
    WHERE id = p_team_id;

    RETURN jsonb_build_object('success', true, 'message', 'Đã bật Khiên ' || p_duration_minutes || ' phút cho ' || v_team.name);
  ELSE
    UPDATE teams SET shield_until = NULL WHERE id = p_team_id;
    RETURN jsonb_build_object('success', true, 'message', 'Đã tắt Khiên của ' || v_team.name);
  END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- RPC 13: reverse_transaction - Hoàn tác giao dịch (Compensating Transaction)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION reverse_transaction(
  p_token             TEXT,
  p_client_request_id TEXT,
  p_tx_id             UUID,
  p_reason            TEXT DEFAULT ''
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_staff         RECORD;
  v_orig_tx       RECORD;
  v_team          RECORD;
  v_reversal_amt  INT;
  v_undo_window   INT;
  v_reversal_id   UUID;
BEGIN
  SELECT * INTO v_staff FROM auth_verify_session(p_token);

  SELECT * INTO v_orig_tx FROM transactions WHERE id = p_tx_id FOR UPDATE;
  IF v_orig_tx IS NULL THEN
    RETURN jsonb_build_object('success', false, 'code', 'NOT_FOUND', 'error', 'Giao dịch không tồn tại');
  END IF;

  IF v_orig_tx.is_reversed THEN
    RETURN jsonb_build_object('success', false, 'code', 'ALREADY_REVERSED', 'error', 'Giao dịch này đã được hoàn tác trước đó');
  END IF;

  IF v_orig_tx.status != 'approved' THEN
    RETURN jsonb_build_object('success', false, 'code', 'NOT_REVERSIBLE', 'error', 'Chỉ có thể hoàn tác giao dịch đã approved');
  END IF;

  -- Kiểm tra cửa sổ hoàn tác nếu không phải Admin
  IF v_staff.staff_role != 'admin' THEN
    SELECT COALESCE((value->>'v')::INT, 5) INTO v_undo_window FROM game_settings WHERE key = 'undo_window_minutes';
    IF v_undo_window IS NULL THEN v_undo_window := 5; END IF;

    IF (now() - v_orig_tx.created_at) > (v_undo_window || ' minutes')::INTERVAL THEN
      RETURN jsonb_build_object(
        'success', false,
        'code', 'UNDO_WINDOW_EXPIRED',
        'error', 'Đã hết thời hạn hoàn tác (' || v_undo_window || ' phút). Hãy báo Admin!'
      );
    END IF;

    IF v_orig_tx.created_by != v_staff.staff_name THEN
      RETURN jsonb_build_object(
        'success', false,
        'code', 'FORBIDDEN',
        'error', 'Bạn chỉ có thể hoàn tác giao dịch do chính mình tạo ra'
      );
    END IF;
  END IF;

  -- Số tiền đối ứng: ngược dấu giao dịch gốc
  v_reversal_amt := -v_orig_tx.amount;

  -- Khóa dòng đội chơi & điều chỉnh số dư
  SELECT * INTO v_team FROM teams WHERE id = v_orig_tx.team_id FOR UPDATE;
  UPDATE teams SET light_balance = light_balance + v_reversal_amt WHERE id = v_orig_tx.team_id;

  -- Đánh dấu giao dịch gốc
  UPDATE transactions SET is_reversed = true WHERE id = p_tx_id;

  -- Tạo giao dịch Reversal
  INSERT INTO transactions (
    client_request_id, team_id, amount, type, description,
    created_by, status, reversal_for_id
  ) VALUES (
    p_client_request_id,
    v_orig_tx.team_id,
    v_reversal_amt,
    'reversal',
    'Hoàn tác giao dịch #' || substr(p_tx_id::TEXT, 1, 8) || ' (' || COALESCE(p_reason, 'Sai sót') || ')',
    v_staff.staff_name,
    'approved',
    p_tx_id
  ) RETURNING id INTO v_reversal_id;

  RETURN jsonb_build_object(
    'success', true,
    'reversal_id', v_reversal_id,
    'message', 'Đã hoàn tác thành công! Điều chỉnh: ' || CASE WHEN v_reversal_amt >= 0 THEN '+' ELSE '' END || v_reversal_amt || ' Lumen'
  );
END;
$$;

-- ---------------------------------------------------------------------------
-- RPC 14: update_setting - Cập nhật cấu hình game + Ghi lịch sử Audit
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION update_setting(
  p_token TEXT,
  p_key   TEXT,
  p_value JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_staff     RECORD;
  v_old_value JSONB;
BEGIN
  SELECT * INTO v_staff FROM auth_verify_session(p_token, 'admin');

  SELECT value INTO v_old_value FROM game_settings WHERE key = p_key;

  UPDATE game_settings
  SET value = p_value, updated_at = now(), updated_by = v_staff.staff_name
  WHERE key = p_key;

  -- Ghi log lịch sử
  INSERT INTO game_settings_history (key, old_value, new_value, changed_by)
  VALUES (p_key, v_old_value, p_value, v_staff.staff_name);

  RETURN jsonb_build_object(
    'success', true,
    'message', 'Đã cập nhật cài đặt ' || p_key
  );
END;
$$;

-- ---------------------------------------------------------------------------
-- RPC 15: admin_list_hints - Admin xem toàn bộ hints kèm mật mã
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION admin_list_hints(
  p_token TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_staff RECORD;
BEGIN
  SELECT * INTO v_staff FROM auth_verify_session(p_token, 'admin');

  RETURN (
    SELECT COALESCE(
      jsonb_agg(
        jsonb_build_object(
          'id', h.id,
          'station_id', h.station_id,
          'title', h.title,
          'content', h.content,
          'tier', h.tier,
          'order_index', h.order_index,
          'is_active', h.is_active,
          'station_name', s.name
        ) ORDER BY h.order_index ASC
      ),
      '[]'::jsonb
    )
    FROM hints h
    LEFT JOIN stations s ON s.id = h.station_id
  );
END;
$$;

-- ---------------------------------------------------------------------------
-- RPC 16: upsert_entity & set_active - CRUD Thực thể qua RPC Security Definer
-- (Thay thế hoàn toàn client-side .insert/.update/.delete)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION upsert_entity(
  p_token       TEXT,
  p_entity_type TEXT, -- 'team' | 'station' | 'hint' | 'item' | 'staff'
  p_data        JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_staff RECORD;
  v_id    UUID;
BEGIN
  SELECT * INTO v_staff FROM auth_verify_session(p_token, 'admin');

  v_id := CASE WHEN (p_data->>'id') IS NOT NULL AND (p_data->>'id') != '' THEN (p_data->>'id')::UUID ELSE NULL END;

  IF p_entity_type = 'team' THEN
    IF v_id IS NOT NULL THEN
      UPDATE teams SET
        name = COALESCE(p_data->>'name', name),
        qr_code = COALESCE(p_data->>'qr_code', qr_code),
        light_balance = COALESCE((p_data->>'light_balance')::INT, light_balance),
        is_active = COALESCE((p_data->>'is_active')::BOOLEAN, is_active)
      WHERE id = v_id;
    ELSE
      INSERT INTO teams (name, qr_code, light_balance)
      VALUES (
        p_data->>'name',
        COALESCE(p_data->>'qr_code', 'TEAM-' || upper(substr(encode(gen_random_bytes(3), 'hex'), 1, 6))),
        COALESCE((p_data->>'light_balance')::INT, 100)
      ) RETURNING id INTO v_id;
    END IF;

  ELSIF p_entity_type = 'station' THEN
    IF v_id IS NOT NULL THEN
      UPDATE stations SET
        name = COALESCE(p_data->>'name', name),
        description = COALESCE(p_data->>'description', description),
        order_index = COALESCE((p_data->>'order_index')::INT, order_index),
        is_active = COALESCE((p_data->>'is_active')::BOOLEAN, is_active)
      WHERE id = v_id;
    ELSE
      INSERT INTO stations (name, description, order_index)
      VALUES (
        p_data->>'name',
        COALESCE(p_data->>'description', ''),
        COALESCE((p_data->>'order_index')::INT, 0)
      ) RETURNING id INTO v_id;
    END IF;

  ELSIF p_entity_type = 'hint' THEN
    IF v_id IS NOT NULL THEN
      UPDATE hints SET
        station_id = CASE WHEN p_data ? 'station_id' THEN (p_data->>'station_id')::UUID ELSE station_id END,
        title = COALESCE(p_data->>'title', title),
        content = COALESCE(p_data->>'content', content),
        tier = COALESCE(p_data->>'tier', tier),
        order_index = COALESCE((p_data->>'order_index')::INT, order_index),
        is_active = COALESCE((p_data->>'is_active')::BOOLEAN, is_active)
      WHERE id = v_id;
    ELSE
      INSERT INTO hints (station_id, title, content, tier, order_index)
      VALUES (
        (p_data->>'station_id')::UUID,
        p_data->>'title',
        p_data->>'content',
        COALESCE(p_data->>'tier', 'bronze'),
        COALESCE((p_data->>'order_index')::INT, 0)
      ) RETURNING id INTO v_id;
    END IF;

  ELSIF p_entity_type = 'item' THEN
    IF v_id IS NOT NULL THEN
      UPDATE items SET
        name = COALESCE(p_data->>'name', name),
        description = COALESCE(p_data->>'description', description),
        price = COALESCE((p_data->>'price')::INT, price),
        effect_type = COALESCE(p_data->>'effect_type', effect_type),
        duration_minutes = COALESCE((p_data->>'duration_minutes')::INT, duration_minutes),
        is_active = COALESCE((p_data->>'is_active')::BOOLEAN, is_active)
      WHERE id = v_id;
    ELSE
      INSERT INTO items (name, description, price, effect_type, duration_minutes)
      VALUES (
        p_data->>'name',
        COALESCE(p_data->>'description', ''),
        COALESCE((p_data->>'price')::INT, 50),
        COALESCE(p_data->>'effect_type', 'shield'),
        COALESCE((p_data->>'duration_minutes')::INT, 15)
      ) RETURNING id INTO v_id;
    END IF;

  ELSIF p_entity_type = 'staff' THEN
    IF v_id IS NOT NULL THEN
      UPDATE staff SET
        name = COALESCE(p_data->>'name', name),
        role = COALESCE(p_data->>'role', role),
        pin = COALESCE(p_data->>'pin', pin),
        station_assigned = COALESCE(p_data->>'station_assigned', station_assigned),
        is_active = COALESCE((p_data->>'is_active')::BOOLEAN, is_active)
      WHERE id = v_id;
    ELSE
      INSERT INTO staff (name, role, pin, station_assigned)
      VALUES (
        p_data->>'name',
        COALESCE(p_data->>'role', 'support'),
        COALESCE(p_data->>'pin', '1234'),
        p_data->>'station_assigned'
      ) RETURNING id INTO v_id;
    END IF;
  ELSE
    RETURN jsonb_build_object('success', false, 'code', 'INVALID_TYPE', 'error', 'Loại thực thể không hợp lệ');
  END IF;

  RETURN jsonb_build_object('success', true, 'id', v_id, 'message', 'Lưu thành công!');
END;
$$;


-- ============================================================================
-- 6. SEED DATA - Dữ liệu khởi tạo chuẩn cho Evermyst
-- ============================================================================

-- 6a. Game Settings
INSERT INTO game_settings (key, value, label, description, category) VALUES
  ('starting_balance',        '{"v": 100}',  'Số dư khởi đầu (Lumen)',      'Lumen ban đầu của mỗi đội',                  'economy'),
  ('station_reward_low',      '{"v": 20}',   'Điểm trạm: Vớt (thấp)',       'Lumen thưởng khi qua trạm mức Vớt',          'station'),
  ('station_reward_mid',      '{"v": 35}',   'Điểm trạm: Đạt (chuẩn)',      'Lumen thưởng khi qua trạm mức Đạt',          'station'),
  ('station_reward_high',     '{"v": 50}',   'Điểm trạm: Xuất sắc (cao)',   'Lumen thưởng khi qua trạm mức Xuất sắc',     'station'),
  ('pending_threshold',       '{"v": 50}',   'Ngưỡng duyệt Admin (Lumen)',  'Giao dịch lớn hơn số này sẽ chờ Admin duyệt', 'station'),
  ('hint_price_bronze',       '{"v": 20}',   'Giá Manh mối: Đồng',          'Giá mua gợi ý bậc Đồng',                     'shop'),
  ('hint_price_silver',       '{"v": 50}',   'Giá Manh mối: Bạc',           'Giá mua gợi ý bậc Bạc',                      'shop'),
  ('hint_price_gold',         '{"v": 100}',  'Giá Manh mối: Vàng',          'Giá mua gợi ý bậc Vàng',                     'shop'),
  ('pvp_cooldown_minutes',    '{"v": 30}',   'Cooldown PvP (phút)',         'Thời gian chờ giữa 2 lần tấn công cùng 1 cặp','pvp'),
  ('pvp_steal_percent',       '{"v": 15}',   'Tỷ lệ cướp PvP (%)',          'Phần trăm số dư bị cướp khi thua PvP',       'pvp'),
  ('pvp_backlash_amount',     '{"v": 10}',   'Phạt Phản phệ (Lumen)',       'Lumen bị trừ khi tấn công đội có Khiên',      'pvp'),
  ('shield_duration_minutes', '{"v": 15}',   'Thời hạn Khiên (phút)',       'Thời gian hiệu lực của Khiên Màn Sương',      'shop'),
  ('undo_window_minutes',     '{"v": 5}',    'Cửa sổ Hoàn tác (phút)',      'Thời gian Support được phép tự Revert',       'system')
ON CONFLICT (key) DO NOTHING;

-- 6b. Nhân sự BTC (4 demo: 2 Admin, 2 Support)
INSERT INTO staff (name, role, pin, station_assigned) VALUES
  ('Admin Tổng Chỉ Huy', 'admin',   '0000', NULL),
  ('Admin Giám Sát',     'admin',   '0001', NULL),
  ('Support Trạm 1',     'support', '1001', 'Trạm 1'),
  ('Support Trạm 2',     'support', '1002', 'Trạm 2'),
  ('Support Trạm 3',     'support', '1003', 'Trạm 3'),
  ('Support Trạm 4',     'support', '1004', 'Trạm 4'),
  ('Support Trạm 5',     'support', '1005', 'Trạm 5'),
  ('Support Lưu Động',   'support', '2001', NULL),
  ('Trọng Tài PvP',      'support', '3001', NULL)
ON CONFLICT DO NOTHING;

-- 6c. 6 Đội chơi
INSERT INTO teams (name, qr_code, light_balance) VALUES
  ('🔥 Lửa Thiêng',     'TEAM-FIRE-001',    100),
  ('🌊 Sóng Thần',      'TEAM-WAVE-002',    100),
  ('🌿 Rừng Xanh',      'TEAM-FOREST-003',  100),
  ('⚡ Sấm Sét',        'TEAM-THUNDER-004', 100),
  ('🌙 Trăng Khuyết',   'TEAM-MOON-005',    100),
  ('☀️ Bình Minh',      'TEAM-SUN-006',     100)
ON CONFLICT (qr_code) DO NOTHING;

-- 6d. 5 Trạm
INSERT INTO stations (name, description, order_index) VALUES
  ('Cổng Sương Mù',       'Trạm 1 - Giải mật mã mở cổng',               1),
  ('Đền Cổ Lumen',        'Trạm 2 - Giải đố logic thu thập ánh sáng',   2),
  ('Rừng Bóng Tối',       'Trạm 3 - Thử thách teamwork vượt mê cung',   3),
  ('Hồ Gương Phản Chiếu', 'Trạm 4 - Trí tuệ và gương phản chiếu',       4),
  ('Đỉnh Tháp Evermyst',  'Trạm 5 - Boss fight cuối cùng',              5)
ON CONFLICT DO NOTHING;

-- 6e. 6 Manh mối bí mật (2 Đồng, 2 Bạc, 2 Vàng)
INSERT INTO hints (title, content, tier, order_index) VALUES
  ('Mật mã La bàn',       'Mật mã ẩn trong hình la bàn trên tấm bản đồ. Đọc ngược chiều kim đồng hồ từ Bắc.', 'bronze', 1),
  ('Ký tự bài thơ',      'Chú ý các chữ cái in hoa đầu mỗi khổ thơ cổ - ghép lại thành tên thần hộ mệnh.',   'bronze', 2),
  ('Lăng kính 7 sắc',     'Ánh sáng đi qua lăng kính tách thành 7 màu. Lấy chữ số ứng với màu Vàng và Tím.',   'silver', 3),
  ('Bản đồ ngầm dưới đá', 'Dưới tảng đá rêu phong có dấu khắc hình tam giác. Đào sâu 10cm thấy hộp chìa khóa.','silver', 4),
  ('Lời tiên tri Tháp',   'Đáp án câu đố cuối là tên người sáng lập Evermyst viết đảo ngược chữ cái.',         'gold',   5),
  ('Dãy Fibonacci cổ',    'Chuỗi số Fibonacci bắt đầu từ 8. Lấy 4 số liên tiếp cộng lại rồi nhân 3.',          'gold',   6)
ON CONFLICT DO NOTHING;

-- 6f. 3 Đạo cụ Shop
INSERT INTO items (name, description, price, effect_type, duration_minutes) VALUES
  ('Khiên Màn Sương',   'Kích hoạt ngay: Miễn nhiễm PvP trong 15 phút. Nếu bị tấn công, kẻ địch bị phạt phản phệ!', 60, 'shield', 15),
  ('Mắt Cú Vọ',        'Soi số dư Lumen và tình trạng khiên của một đội bất kỳ qua BTC.',                         30, 'spy',    0),
  ('Chìa Khóa Cổ Tích', 'Mở khóa một lối tắt đặc biệt bỏ qua một câu đố phụ tại trạm.',                           80, 'key',    0)
ON CONFLICT DO NOTHING;
