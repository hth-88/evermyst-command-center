# ĐẶC TẢ KỸ THUẬT: KHẮC PHỤC LỖI PGCRYPTO DIGEST, REVERSE TRANSACTION & TÁI CẤU TRÚC PHÂN QUYỀN TRẠM - SUPPORT

- **Tài liệu:** `FIX_SPEC_STATION_SUPPORT.md`
- **Dự án:** Evermyst Command Center v2.0 (ProPTIT BigGame D26)
- **Tác giả:** Technical Lead & Database Architect
- **Đối tượng thực hiện:** Lập trình viên Front-end & Back-end (Argon)
- **Mức độ nghiêm trọng:** P0 (Chặn toàn bộ luồng vận hành chấm điểm thực tế)
- **Trạng thái:** Sẵn sàng thực thi (Ready for Implementation)

---

## 1. TỔNG QUAN & PHÂN TÍCH NGUYÊN NHÂN GỐC RỄ (EXECUTIVE SUMMARY)

### 1.1. Bối Cảnh Hệ Thống
Hệ thống Evermyst Command Center v2.0 vận hành trên kiến trúc React + Vite + Supabase (PostgreSQL 15+). Luồng vận hành chính gồm 3 vai trò:
1. **Quản Trò Trạm (`/station`):** Chấm điểm trực tiếp cho các đội chơi tại trạm thử thách qua RPC `award_station_direct_points`.
2. **Support Đội (`/support`):** Đồng hành cùng từng đội chơi, theo dõi trạng thái lộ trình thử thách, manh mối, vật phẩm và chiến trường PvP.
3. **Ban Tổ Chức / Admin (`/admin`):** Giám sát thời gian thực bảng xếp hạng, đối soát và thu hồi điểm trạm qua `reverse_station_play` và `reverse_transaction`.

### 1.2. Phân Tích Triệu Chứng & Nguyên Nhân Gốc Lỗi 1: `function digest(text, unknown) does not exist`
* **Triệu chứng (Ảnh 1):** Tại `/station`, khi Quản Trò Trạm 2 (Đền Cổ Lumen) bấm *"XÁC NHẬN CỘNG ĐIỂM TRẠM"*, trình duyệt văng popup `alert()`:
  ```text
  evermyst-command-center.vercel.app says:
  function digest(text, unknown) does not exist
  ```
* **Nguyên nhân gốc rễ (Root Cause):**
  1. Trong Supabase Cloud / Postgres, extension `pgcrypto` được cài đặt mặc định vào schema riêng là `extensions`:
     ```sql
     CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;
     ```
  2. Tại các hàm bảo mật RPC (như `award_station_direct_points`, `get_station_recent_plays`, `reverse_station_play` trong migration 104, 105, 106), thân hàm được cấu hình:
     ```sql
     SET search_path = public, pg_temp;
     ```
  3. Dòng code kiểm tra session token:
     ```sql
     v_token_hash := encode(digest(trim(p_token), 'sha256'), 'hex');
     ```
  4. Do `search_path` chỉ có `public` và `pg_temp`, PostgreSQL không tìm thấy hàm `digest()` trong schema `extensions`. Đồng thời vì tham số `'sha256'` là chuỗi hằng số chưa ép kiểu (kiểu `unknown`), PostgreSQL cố tìm hàm `public.digest(text, unknown)` và ném lỗi `42883 (undefined_function)`.
  5. **Hậu quả:** Mọi RPC có dòng băm token bằng `digest()` đều bị crash 100%, chặn đứng việc cộng điểm và xem lịch sử trạm.

### 1.3. Phân Tích Triệu Chứng & Nguyên Nhân Gốc Lỗi 2: `Could not find the function public.reverse_transaction(...) in the schema cache`
* **Triệu chứng (Ảnh 2):** Tại `/admin`, khi Admin bấm nút *"Hoàn Tác Tiêu Chuẩn"* tại cột 3 Nhật Ký Giao Dịch & Sổ Cái, trình duyệt văng popup:
  ```text
  Could not find the function public.reverse_transaction(p_client_request_id, p_force, p_token, p_tx_id) in the schema cache
  ```
* **Nguyên nhân gốc rễ (Root Cause):**
  1. Tại client `src/lib/rpc.ts`, `'reverse_transaction'` được khai báo nằm trong danh sách `IDEMPOTENT_MUTATIONS`. Do đó, `callRpc` tự động bổ sung tham số `p_client_request_id` vào request payload gửi lên Supabase:
     ```ts
     { p_token, p_tx_id, p_force, p_client_request_id }
     ```
  2. Tuy nhiên, trong database (`100_economy_engine.sql`), hàm SQL `reverse_transaction` chỉ được khai báo 4 tham số:
     ```sql
     CREATE OR REPLACE FUNCTION reverse_transaction(
         p_token     TEXT,
         p_tx_id     UUID,
         p_force     BOOLEAN DEFAULT false,
         p_reason    TEXT DEFAULT NULL
     )
     ```
  3. PostgREST sử dụng cơ chế so khớp chữ ký hàm nghiêm ngặt (Strict Named Arguments Matching). Khi nhận payload có key `p_client_request_id` mà hàm SQL không có tham số tương ứng, PostgREST không tìm thấy hàm phù hợp trong cache schema và trả về lỗi `PGRST202`.

### 1.4. Thay Đổi Nghiệp Vụ Nghiêm Ngặt (Business Requirements Shift)
Ban Tổ Chức quyết định tái cấu trúc triệt để phân quyền chấm điểm:
1. **Support Đội (`/support`):** **TƯỚC BỎ HOÀN TOÀN QUYỀN CỘNG ĐIỂM**. Support là người hỗ trợ đội chơi, không được tự chấm điểm cho đội mình để tránh gian lận. Giao diện tab Trạm tại `/support` chuyển thành dạng **READ-ONLY Dashboard**: hiển thị tiến độ các trạm, trạng thái vượt trạm, số lần chơi và tổng điểm đã tích lũy. Gỡ bỏ toàn bộ form nhập điểm, các nút bấm nhanh (+50, +100...) và nút xác nhận cộng điểm.
2. **Quản Trò (`/station`) & Admin (`/admin`):** Là hai vai trò duy nhất có quyền nhập điểm trạm qua `award_station_direct_points` và thu hồi điểm qua `reverse_station_play`.
3. **UX/UI:** Loại bỏ hoàn toàn các hàm `alert()` mặc định của trình duyệt, thay thế 100% bằng Toast Notification (`addToast`) mượt mà của hệ thống.

---

## 2. ĐẶC TẢ SỬA ĐỔI DATABASE & SQL MIGRATION (DATABASE FIX SPECIFICATION)

### 2.1. Quản Lý Extension `pgcrypto` & Cấu Hình `search_path`
Tất cả các hàm RPC Security Definer phải được cấu hình `search_path` chứa cả schema `extensions`:
```sql
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;
GRANT USAGE ON SCHEMA extensions TO anon, authenticated, service_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA extensions TO anon, authenticated, service_role;
```
Trong thân hàm, định nghĩa rõ ràng:
```sql
SET search_path = public, extensions, pg_temp;
```
Và gọi hàm băm token an toàn:
```sql
v_token_hash := encode(extensions.digest(trim(p_token)::bytea, 'sha256'), 'hex');
```

---

### 2.2. Tái Định Nghĩa Hàm `public.award_station_direct_points`
Hàm mới phải:
1. Bổ sung `extensions` vào `search_path`.
2. Kiểm tra quyền hạn:
   - `admin`: Toàn quyền chấm mọi trạm cho mọi đội.
   - `station_master` (hoặc nhân sự có `assigned_station_id`): Chỉ được chấm điểm cho trạm mà mình phụ trách (khớp UUID hoặc khớp `order_index`).
   - `team_support` / `support`: **BỊ CHẶN TUYỆT ĐỐI**. Trả về lỗi:
     ```json
     {
       "success": false,
       "code": "FORBIDDEN",
       "error": "Support đội không có quyền cộng điểm trạm. Chỉ Quản trò trạm hoặc Ban tổ chức mới có thể chấm điểm."
     }
     ```
3. Giữ nguyên cơ chế tự chữa lành (Self-healing Station Lookup) để tự map ID trạm cũ sang ID trạm mới.

```sql
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
  -- 1. Xác thực session token
  IF p_token IS NULL OR trim(p_token) = '' THEN
    RETURN public._direct_scoring_err('INVALID_TOKEN', 'Phiên làm việc không tồn tại hoặc đã hết hạn.');
  END IF;

  v_token_hash := encode(extensions.digest(trim(p_token)::bytea, 'sha256'), 'hex');

  SELECT ss.staff_id, s.name AS staff_name, s.role AS staff_role, s.assigned_station_id, s.assigned_team_id
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

  -- 2. Tự chữa lành mã trạm (Self-healing Station Lookup)
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

  -- 3. Phân quyền nghiệp vụ mới: CHẶN HOÀN TOÀN SUPPORT ĐỘI
  SELECT assigned_station_id, assigned_team_id, role 
  INTO v_staff
  FROM public.staff WHERE id = v_auth.staff_id;

  IF v_auth.staff_role = 'admin' OR v_staff.role = 'admin' THEN
    -- Admin toàn quyền
    NULL;
  ELSIF v_auth.staff_role = 'team_support' OR v_staff.role = 'team_support' OR v_staff.assigned_team_id IS NOT NULL THEN
    -- CHẶN DỨT KHOÁT SUPPORT ĐỘI
    RETURN public._direct_scoring_err(
      'FORBIDDEN',
      'Support đội không có quyền cộng điểm trạm. Chỉ Quản trò trạm hoặc Ban tổ chức mới có thể chấm điểm.'
    );
  ELSIF v_auth.staff_role IN ('station_master', 'support') OR v_staff.role IN ('station_master', 'support') THEN
    -- Quản trò trạm: Kiểm tra trạm được phân công
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
```

---

### 2.3. Bổ Sung Tham Số `p_client_request_id` Cho Hàm `reverse_transaction`
Để tương thích với `callRpc` ở client:
```sql
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
    v_token_hash        TEXT;
    v_admin             staff%ROWTYPE;
    v_orig_tx           transactions%ROWTYPE;
    v_partner_tx        transactions%ROWTYPE;
    v_team              teams%ROWTYPE;
    v_partner_team      teams%ROWTYPE;
    v_undo_window       INT;
    v_reversal_amt      INT;
    v_reversal_tx_id    UUID;
    v_new_balance       INT;
    v_partner_balance   INT;
BEGIN
    -- 1. Xác thực quyền Admin
    IF p_token IS NULL OR trim(p_token) = '' THEN
        RETURN jsonb_build_object('success', false, 'code', 'UNAUTHENTICATED', 'error', 'Token rỗng.');
    END IF;

    v_token_hash := encode(extensions.digest(trim(p_token)::bytea, 'sha256'), 'hex');

    SELECT s.* INTO v_admin
    FROM staff_sessions ss
    JOIN staff s ON s.id = ss.staff_id
    WHERE (ss.token_hash = v_token_hash OR ss.token = trim(p_token) OR ss.token = v_token_hash)
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

    -- 7. Đồng bộ nếu giao dịch gắn liền với station_plays
    UPDATE station_plays 
    SET status = 'reversed', 
        reversed_at = now(), 
        reversed_by = v_admin.id,
        reversal_reason = COALESCE(p_reason, 'Hoàn tác từ Sổ Cái Admin')
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
```

---

### 2.4. Cập Nhật Hàm Nội Bộ `_require_staff` (Bảo Vệ Toàn Hệ Thống)
Trong hệ thống, các RPC của Sổ Cái / Kinh Tế như `purchase_hint`, `transfer_lumen`, `reverse_transaction` đều gọi hàm nội bộ `_require_staff(p_token, p_roles)`. Do đó, hàm này cũng phải được cấu hình an toàn:
```sql
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
    v_token_hash    TEXT;
    v_session       staff_sessions%ROWTYPE;
    v_staff         staff%ROWTYPE;
BEGIN
    IF p_token IS NULL OR trim(p_token) = '' THEN
        RAISE EXCEPTION 'UNAUTHENTICATED: Yêu cầu cung cấp session token.' USING ERRCODE = 'P0001';
    END IF;

    v_token_hash := encode(extensions.digest(trim(p_token)::bytea, 'sha256'), 'hex');

    SELECT * INTO v_session
    FROM staff_sessions
    WHERE (token_hash = v_token_hash OR token = trim(p_token) OR token = v_token_hash)
      AND expires_at > now()
    LIMIT 1;

    IF v_session.id IS NULL THEN
        RAISE EXCEPTION 'UNAUTHENTICATED: Phiên làm việc không tồn tại hoặc đã hết hạn.' USING ERRCODE = 'P0001';
    END IF;

    SELECT * INTO v_staff
    FROM staff
    WHERE id = v_session.staff_id;

    IF v_staff.id IS NULL OR v_staff.is_active = false THEN
        RAISE EXCEPTION 'UNAUTHENTICATED: Tài khoản nhân sự đã bị vô hiệu hóa hoặc không tồn tại.' USING ERRCODE = 'P0001';
    END IF;

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
```

---

### 2.5. Cập Nhật Hàm `get_station_recent_plays` và `reverse_station_play`

#### (A) Hàm `get_station_recent_plays`:
```sql
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
  v_token_hash          TEXT;
  v_auth                RECORD;
  v_target_station_id   UUID := p_station_id;
  v_rows                JSONB;
BEGIN
  IF p_token IS NULL OR trim(p_token) = '' THEN
    RETURN public._direct_scoring_err('INVALID_TOKEN', 'Token không được để trống.');
  END IF;

  v_token_hash := encode(extensions.digest(trim(p_token)::bytea, 'sha256'), 'hex');

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
```

#### (B) Hàm `reverse_station_play`:
```sql
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

  v_token_hash := encode(extensions.digest(trim(p_token)::bytea, 'sha256'), 'hex');

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

  IF v_auth.staff_role = 'admin' THEN
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
```

---

### 2.6. File Migration Hoàn Chỉnh: `supabase/migrations/107_fix_pgcrypto_and_station_support_permissions.sql`
Toàn bộ mã SQL hoàn chỉnh đã được đóng gói sẵn trong file [107_fix_pgcrypto_and_station_support_permissions.sql](file:///c:/Users/ADMIN/Documents/ProPTIT/Ban%20SK/BIGGAME%20D26/supabase/migrations/107_fix_pgcrypto_and_station_support_permissions.sql). Lập trình viên chỉ cần mở Supabase SQL Editor và chạy một lần duy nhất.

Cú pháp reload schema cache:
```sql
GRANT EXECUTE ON FUNCTION public._require_staff(TEXT, TEXT[]) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.award_station_direct_points(TEXT, UUID, UUID, INTEGER, TEXT, TEXT) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.reverse_transaction(TEXT, UUID, BOOLEAN, TEXT, TEXT) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_station_recent_plays(TEXT, UUID, INTEGER) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.reverse_station_play(TEXT, TEXT, UUID, TEXT) TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';
COMMIT;
```

---

## 3. ĐẶC TẢ TÁI CẤU TRÚC FRONTEND (FRONTEND REFACTORING SPECIFICATION)

### 3.1. Danh Sách Các File Cần Chỉnh Sửa
| File | Loại thay đổi | Mục đích |
| :--- | :--- | :--- |
| `src/components/support/StationTab.tsx` | **Refactor Core** | Chuyển đổi toàn bộ sang Read-only Dashboard, gỡ form & button cộng điểm |
| `src/pages/StationPage.tsx` | **Refactor & UX** | Thay `alert()` bằng `addToast`, xác nhận và xử lý mượt mà |
| `src/pages/AdminPage.tsx` | **Refactor & UX** | Thay `alert()` bằng `addToast`, tương thích `reverse_transaction` |
| `src/components/admin/PendingAdminQueue.tsx` | **Refactor & UX** | Thay `alert()` bằng `addToast` khi thu hồi điểm |
| `src/lib/rpc.ts` | **Check Param** | Đảm bảo truyền tham số chuẩn xác sang RPC |

---

### 3.2. Chi Tiết Tái Cấu Trúc `src/components/support/StationTab.tsx` (Read-Only Mode)

#### (A) Những Phần CẦN LOẠI BỎ:
- `import { StationScoringForm } from '@/components/scoring/StationScoringForm';`
- State `formData`, `activeFormStationId`, `isSubmitting`.
- Hàm `handleSubmitClaim`.
- Nút bấm *"Nhập điểm trạm trực tiếp"*, form mở ra, nút *"XÁC NHẬN CỘNG ĐIỂM TRẠM"*, các nút nhanh `+50✦`, `+100✦`...

#### (B) Những Phần CẦN BỔ SUNG & HOÀN THIỆN:
- **Card Trạm Read-Only Hiện Đại:**
  - Hiển thị thứ tự và Tên trạm (`Trạm 1: Cổng Sương Mù`).
  - Badge Loại điểm: `TIER` / `MANUAL` / `RANGE`.
  - Badge Trạng Thái:
    - **Đã hoàn thành / Đã nhận điểm:** Hiển thị Badge Xanh lá (`CheckCircle2`), số điểm đã nhận (`+150✦`), và số lượt đã thi đấu (`2 lượt`).
    - **Chưa hoàn thành:** Hiển thị Badge Xám (`Clock`), chữ *"Chưa hoàn thành"*.
  - Lịch Sử Lượt Chấm Tại Trạm Của Đội:
    - Hiển thị danh sách các lượt mà đội đã được Quản trò chấm tại trạm này (Thời gian, người chấm, điểm, ghi chú nếu có).
  - Không có bất kỳ nút input hoặc form nộp dữ liệu nào.

#### (C) Mockup Mã Nguồn Chuẩn Cho `StationTab.tsx`:
```tsx
import React, { useState, useEffect, useCallback } from 'react';
import { useGame } from '@/contexts/GameContext';
import type { Team, Station } from '@/lib/types';
import {
  MapPin,
  CheckCircle2,
  Clock,
  RotateCcw,
  Sparkles,
  Award,
  Layers,
} from 'lucide-react';

interface StationTabProps {
  selectedTeam: Team | null;
}

interface StationStatusItem {
  station_id: string;
  station_name: string;
  order_index: number;
  scoring_type: string;
  allow_multiple_attempts: boolean;
  total_points: number;
  play_count: number;
  is_completed: boolean;
  recent_plays: Array<{
    id: string;
    points: number;
    play_no: number;
    staff_name: string;
    created_at: string;
    note?: string;
  }>;
}

export default function StationTab({ selectedTeam }: StationTabProps) {
  const { stations, transactions, refreshAll } = useGame();
  const [stationStatuses, setStationStatuses] = useState<StationStatusItem[]>([]);
  const [isLoading, setIsLoading] = useState(true);

  const fetchStationStatuses = useCallback(async () => {
    if (!selectedTeam) return;
    setIsLoading(true);
    try {
      const activeStations = stations
        .filter((s: any) => !s.deleted_at && s.is_active)
        .sort((a, b) => a.order_index - b.order_index);

      const teamStationTx = transactions.filter(
        (t) => t.team_id === selectedTeam.id && t.type === 'station_clear' && !t.is_reversed
      );

      const mapped: StationStatusItem[] = activeStations.map((st) => {
        // Lấy toàn bộ giao dịch vượt trạm này của đội
        const relatedTxs = teamStationTx.filter((tx) =>
          tx.description?.includes(st.name) || (tx.metadata as any)?.station_id === st.id
        );

        const totalPoints = relatedTxs.reduce((sum, tx) => sum + (tx.amount || 0), 0);
        const playCount = relatedTxs.length;
        const isCompleted = selectedTeam.unlocked_stations?.includes(st.id) || playCount > 0;

        return {
          station_id: st.id,
          station_name: st.name,
          order_index: st.order_index,
          scoring_type: st.scoring_type,
          allow_multiple_attempts: st.allow_multiple_attempts,
          total_points: totalPoints,
          play_count: playCount,
          is_completed: isCompleted,
          recent_plays: relatedTxs.map((tx, idx) => ({
            id: tx.id,
            points: tx.amount,
            play_no: idx + 1,
            staff_name: tx.created_by || 'Quản trò',
            created_at: tx.created_at,
            note: tx.description,
          })),
        };
      });

      setStationStatuses(mapped);
    } catch (err) {
      console.error('Lỗi tính toán lộ trình trạm:', err);
    } finally {
      setIsLoading(false);
    }
  }, [selectedTeam, stations, transactions]);

  useEffect(() => {
    fetchStationStatuses();
  }, [fetchStationStatuses]);

  const formatTime = (isoString?: string) => {
    if (!isoString) return '';
    const d = new Date(isoString);
    return `${d.getHours().toString().padStart(2, '0')}:${d.getMinutes().toString().padStart(2, '0')} - ${d.getDate()}/${d.getMonth() + 1}`;
  };

  if (!selectedTeam) {
    return (
      <div className="flex flex-col items-center justify-center py-24 px-4 text-center">
        <div className="w-16 h-16 rounded-3xl bg-evermyst-card border border-evermyst-border flex items-center justify-center mb-3">
          <MapPin className="w-8 h-8 text-lumen" />
        </div>
        <h3 className="text-base font-bold text-evermyst-text">Chưa phân công đội chơi</h3>
        <p className="text-xs text-evermyst-text-muted mt-1 max-w-xs">
          Tài khoản Support chưa được phân công đội phụ trách. Vui lòng liên hệ Admin.
        </p>
      </div>
    );
  }

  return (
    <div className="p-4 space-y-4 pb-28 animate-fadeIn">
      {/* Header Info */}
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-base font-black text-white flex items-center gap-2">
            <MapPin className="w-4 h-4 text-lumen" />
            Tiến Độ Lộ Trình Thử Thách
          </h2>
          <p className="text-[11px] text-evermyst-text-muted">
            Theo dõi kết quả thi đấu tại các trạm của {selectedTeam.name} (Chế độ xem Support)
          </p>
        </div>

        <button
          onClick={async () => {
            await refreshAll();
            await fetchStationStatuses();
          }}
          className="text-[11px] font-bold text-lumen hover:underline flex items-center gap-1"
        >
          <RotateCcw className="w-3 h-3" /> Làm mới
        </button>
      </div>

      {/* Danh sách các Trạm dạng Read-Only Cards */}
      <div className="space-y-3">
        {stationStatuses.map((item, idx) => {
          return (
            <div
              key={item.station_id}
              className={`rounded-2xl border transition-all overflow-hidden ${
                item.is_completed
                  ? 'bg-success/5 border-success/30'
                  : 'bg-evermyst-card border-evermyst-border opacity-85'
              }`}
            >
              {/* Header Card */}
              <div className="p-4 flex items-start justify-between gap-3">
                <div className="space-y-1.5 flex-1">
                  <div className="flex items-center gap-2 flex-wrap">
                    <span className="w-6 h-6 rounded-lg bg-evermyst-surface text-lumen text-xs font-mono font-black flex items-center justify-center border border-evermyst-border">
                      {idx + 1}
                    </span>
                    <h3 className="text-sm font-black text-white leading-tight">
                      {item.station_name}
                    </h3>
                  </div>

                  <div className="text-[11px] text-evermyst-text-muted flex items-center gap-2 flex-wrap">
                    <span className="uppercase font-semibold tracking-wider px-2 py-0.5 rounded-md bg-evermyst-surface border border-evermyst-border text-[10px]">
                      {item.scoring_type}
                    </span>
                    {item.allow_multiple_attempts && (
                      <span className="text-lumen font-bold text-[10px] flex items-center gap-1">
                        <Layers className="w-3 h-3" /> Đa lượt chơi
                      </span>
                    )}
                  </div>
                </div>

                {/* Status & Points Badge */}
                <div className="shrink-0 text-right space-y-1">
                  {item.is_completed ? (
                    <div className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-xl bg-success/20 text-success border border-success/30 font-black text-xs">
                      <CheckCircle2 className="w-4 h-4" />
                      <span>+{item.total_points}✦ Lumen</span>
                    </div>
                  ) : (
                    <div className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-xl bg-evermyst-surface text-evermyst-text-dim border border-evermyst-border text-xs font-semibold">
                      <Clock className="w-3.5 h-3.5" />
                      <span>Chưa hoàn thành</span>
                    </div>
                  )}

                  {item.play_count > 0 && (
                    <div className="text-[10px] text-evermyst-text-dim font-mono">
                      Đã chơi: <strong>{item.play_count} lượt</strong>
                    </div>
                  )}
                </div>
              </div>

              {/* Lịch sử các lượt chơi của trạm này (nếu có) */}
              {item.recent_plays.length > 0 && (
                <div className="px-4 pb-3 pt-1 border-t border-evermyst-border/50 bg-evermyst-surface/40 space-y-2">
                  <div className="text-[10px] font-bold text-evermyst-text-dim uppercase tracking-wider flex items-center gap-1">
                    <Award className="w-3 h-3 text-lumen" /> Lịch sử chấm điểm:
                  </div>
                  <div className="space-y-1.5">
                    {item.recent_plays.map((play) => (
                      <div
                        key={play.id}
                        className="flex items-center justify-between text-xs p-2 rounded-xl bg-evermyst-card border border-evermyst-border"
                      >
                        <div className="space-y-0.5">
                          <div className="font-semibold text-white flex items-center gap-1.5">
                            <span className="text-lumen font-mono text-[10px]">Lượt #{play.play_no}</span>
                            <span>•</span>
                            <span className="text-[11px] text-evermyst-text-dim">Chấm bởi: {play.staff_name}</span>
                          </div>
                          <div className="text-[10px] text-evermyst-text-muted font-mono">
                            {formatTime(play.created_at)}
                          </div>
                        </div>
                        <div className="font-black text-success font-mono text-sm">
                          +{play.points}✦
                        </div>
                      </div>
                    ))}
                  </div>
                </div>
              )}
            </div>
          );
        })}
      </div>
    </div>
  );
}
```

---

### 3.3. Thay Thế 100% `alert()` Mặc Định Sang Toast Notification

Trong toàn bộ dự án, mọi đoạn code đang dùng hàm trình duyệt `alert(...)` phải được thay thế bằng hàm `addToast(...)` từ `useGame()`:

#### (A) Tại `src/pages/StationPage.tsx`:
```tsx
// Trước:
alert('Vui lòng nhập số điểm hợp lệ (> 0).');
// Sau:
addToast('Vui lòng nhập số điểm hợp lệ (> 0).', 'warning');

// Trước:
alert(res.error || res.message || 'Lỗi khi cộng điểm trạm.');
// Sau:
addToast(res.error || res.message || 'Lỗi khi cộng điểm trạm.', 'error');
```

#### (B) Tại `src/pages/AdminPage.tsx`:
```tsx
// Trước:
alert('Đã hoàn tác giao dịch thành công!');
// Sau:
addToast('Đã hoàn tác giao dịch thành công!', 'success');

// Trước:
alert(res.error || res.message || 'Không thể hoàn tác.');
// Sau:
addToast(res.error || res.message || 'Không thể hoàn tác.', 'error');
```

#### (C) Tại `src/components/admin/PendingAdminQueue.tsx`:
```tsx
// Trước:
alert(res.error || res.message || 'Không thể hoàn tác lượt chấm này.');
// Sau:
addToast(res.error || res.message || 'Không thể hoàn tác lượt chấm này.', 'error');
```

---

## 4. TIÊU CHUẨN NGHIỆM THU & KỊCH BẢN KIỂM THỬ (ACCEPTANCE CRITERIA & TEST MATRIX)

| Mã test | Kịch bản kiểm thử | Thao tác thực hiện | Kết quả mong đợi |
| :--- | :--- | :--- | :--- |
| **TC-01** | **Quản Trò chấm điểm tại `/station`** | Đăng nhập Quản Trò Trạm 2 -> Chọn đội -> Nhập 50✦ -> Bấm *"XÁC NHẬN CỘNG ĐIỂM TRẠM"* | **Thành công 100%**: Không còn lỗi `function digest does not exist`. Toast xanh hiện *"Đã cộng +50✦ Lumen"*. Số dư đội tăng ngay, danh sách 20 lượt chấm cập nhật ngay. |
| **TC-02** | **Support xem tiến độ trạm tại `/support`** | Đăng nhập Support Đội 1 -> Mở tab Trạm | **Giao diện Read-only**: Không có form nhập điểm, không có nút cộng điểm. Hiển thị danh sách các trạm, badge trạng thái và tổng điểm trạm của Đội 1. |
| **TC-03** | **Chặn Support gọi RPC cộng điểm** | Gửi RPC `award_station_direct_points` bằng session token của Support qua Postman/Console | **Bị từ chối (403/Forbidden)**: RPC trả về `code: "FORBIDDEN"`, thông báo rõ Support không có quyền cộng điểm. |
| **TC-04** | **Admin hoàn tác giao dịch tại `/admin`** | Vào tab Nhật ký giao dịch -> Bấm *"Hoàn Tác Tiêu Chuẩn"* tại 1 giao dịch trạm | **Thành công 100%**: Không còn lỗi `schema cache`. Giao dịch đảo ngược tạo ra, điểm trừ lại ngay, toast hiện thông báo hoàn tác thành công. |
| **TC-05** | **Kiểm tra Toast thay thế Alert** | Cố tình nhập điểm <= 0 tại `/station` | Toast màu vàng cảnh báo hiện ra góc màn hình. **Tuyệt đối không có dialog `alert()` của trình duyệt**. |
| **TC-06** | **Build & Type Safety** | Chạy `npx tsc --noEmit` và `npm run build` | **0 lỗi TypeScript, 0 lỗi cú pháp Vite**. |

---

## 5. KẾ HOẠCH TRIỂN KHAI CHO LẬP TRÌNH VIÊN (IMPLEMENTATION CHECKLIST)

- [ ] **Bước 1: Chạy SQL Migration 107**
  - Mở Supabase SQL Editor.
  - Tạo và chạy file `supabase/migrations/107_fix_pgcrypto_and_station_support_permissions.sql`.
  - Kiểm tra kết quả trả về `NOTIFY pgrst, 'reload schema'`.
- [ ] **Bước 2: Cập nhật `src/components/support/StationTab.tsx`**
  - Xóa bỏ form nhập điểm, các nút bấm nhanh và hàm `handleSubmitClaim`.
  - Thay thế bằng giao diện Read-only Cards theo đúng Mục 3.2.
- [ ] **Bước 3: Loại bỏ toàn bộ `alert()` trong `StationPage.tsx`, `AdminPage.tsx`, `PendingAdminQueue.tsx`**
  - Chuyển sang dùng `addToast(msg, 'error' | 'warning' | 'success')`.
- [ ] **Bước 4: Kiểm thử tích hợp toàn diện**
  - Chạy `npm run dev`.
  - Kiểm thử 3 tài khoản: Admin (`/admin`), Quản Trò Trạm 2 (`/station`), Support Đội (`/support`).
  - Kiểm tra `npx tsc --noEmit` và `npm run build`.
- [ ] **Bước 5: Commit & Đẩy lên Git Production**
  - Git commit: `fix: resolve pgcrypto digest, reverse tx schema cache, and deprecate support direct scoring`.
