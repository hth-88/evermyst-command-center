-- ============================================================================
-- MIGRATION 080: AUTHENTICATION, SESSIONS & SECURITY HELPERS
-- File: supabase/migrations/080_auth_sessions.sql
-- Mục đích: Cổng xác thực tập trung, Bcrypt PIN, Rate-limit IP, Token SHA-256
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ----------------------------------------------------------------------------
-- 1. CHUYỂN ĐỔI TOÀN BỘ PIN SANG CHUẨN BCRYPT (PGCRYPTO) & ĐẢM BẢO DUY NHẤT
-- ----------------------------------------------------------------------------
-- Đảm bảo cột token trong staff_sessions cho phép NULL vì V2 chỉ lưu token_hash
ALTER TABLE staff_sessions ALTER COLUMN token DROP NOT NULL;

-- Cập nhật pin_hash bằng bcrypt salt ngẫu nhiên cho toàn bộ nhân sự hiện có
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN SELECT id, pin FROM staff WHERE pin IS NOT NULL LOOP
        UPDATE staff
        SET pin_hash = crypt(r.pin, gen_salt('bf', 8))
        WHERE id = r.id;
    END LOOP;
END $$;

-- ----------------------------------------------------------------------------
-- 2. HÀM NỘI BỘ: KIỂM TRA TÍNH DUY NHẤT CỦA MÃ PIN GIỮA CÁC STAFF ĐANG ACTIVE
-- ----------------------------------------------------------------------------
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
            RETURN false; -- Trùng PIN với nhân sự khác
        END IF;
    END LOOP;
    RETURN true; -- PIN duy nhất
END;
$$;

REVOKE ALL ON FUNCTION _check_pin_unique(TEXT, UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION _check_pin_unique(TEXT, UUID) FROM anon;

-- ----------------------------------------------------------------------------
-- 3. HÀM NỘI BỘ: TRÍCH XUẤT IP CLIENT TỪ REQUEST HEADERS
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION _extract_client_ip()
RETURNS TEXT
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_headers   JSONB;
    v_ip        TEXT;
BEGIN
    BEGIN
        v_headers := current_setting('request.headers', true)::jsonb;
        IF v_headers IS NOT NULL THEN
            v_ip := v_headers->>'x-forwarded-for';
            IF v_ip IS NULL OR v_ip = '' THEN
                v_ip := v_headers->>'cf-connecting-ip';
            END IF;
            IF v_ip IS NULL OR v_ip = '' THEN
                v_ip := v_headers->>'x-real-ip';
            END IF;
        END IF;
    EXCEPTION WHEN OTHERS THEN
        v_ip := '127.0.0.1';
    END;

    IF v_ip IS NULL OR v_ip = '' THEN
        v_ip := '127.0.0.1';
    END IF;

    -- Lấy IP đầu tiên nếu qua nhiều proxy (client, proxy1, proxy2)
    RETURN trim(split_part(v_ip, ',', 1));
END;
$$;

-- ----------------------------------------------------------------------------
-- 4. HÀM NỘI BỘ: _REQUIRE_STAFF (CỔNG XÁC THỰC BẮT BUỘC CHO MỌI RPC V2)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION _require_staff(
    p_token     TEXT,
    p_roles     TEXT[] DEFAULT NULL
)
RETURNS staff
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_token_hash    TEXT;
    v_session       staff_sessions%ROWTYPE;
    v_staff         staff%ROWTYPE;
BEGIN
    IF p_token IS NULL OR trim(p_token) = '' THEN
        RAISE EXCEPTION 'UNAUTHENTICATED: Yêu cầu cung cấp session token.' USING ERRCODE = 'P0001';
    END IF;

    -- Tính SHA-256 hash của token để truy vấn
    v_token_hash := encode(digest(trim(p_token), 'sha256'), 'hex');

    -- Truy vấn session còn hiệu lực
    SELECT * INTO v_session
    FROM staff_sessions
    WHERE token_hash = v_token_hash
      AND expires_at > now();

    IF v_session.id IS NULL THEN
        RAISE EXCEPTION 'UNAUTHENTICATED: Phiên làm việc không tồn tại hoặc đã hết hạn.' USING ERRCODE = 'P0001';
    END IF;

    -- Truy vấn thông tin nhân sự trực tiếp từ bảng staff (Zero-Cache: phản ánh ngay lập tức)
    SELECT * INTO v_staff
    FROM staff
    WHERE id = v_session.staff_id;

    IF v_staff.id IS NULL OR v_staff.is_active = false THEN
        RAISE EXCEPTION 'UNAUTHENTICATED: Tài khoản nhân sự đã bị vô hiệu hóa hoặc không tồn tại.' USING ERRCODE = 'P0001';
    END IF;

    -- Kiểm tra phân quyền role nếu có danh sách yêu cầu
    IF p_roles IS NOT NULL AND array_length(p_roles, 1) > 0 THEN
        IF NOT (v_staff.role = ANY(p_roles)) THEN
            RAISE EXCEPTION 'FORBIDDEN_ROLE: Vai trò "%" không có quyền thực hiện hành động này.', v_staff.role USING ERRCODE = 'P0002';
        END IF;
    END IF;

    RETURN v_staff;
END;
$$;

REVOKE ALL ON FUNCTION _require_staff(TEXT, TEXT[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION _require_staff(TEXT, TEXT[]) FROM anon;

-- ----------------------------------------------------------------------------
-- 5. HÀM NỘI BỘ: _ACTOR_SCOPE (XÁC ĐỊNH PHẠM VI QUYỀN HẠN CỦA NHÂN SỰ)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION _actor_scope(
    p_staff staff
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    RETURN jsonb_build_object(
        'staff_id', p_staff.id,
        'role', p_staff.role,
        'assigned_team_id', p_staff.assigned_team_id,
        'assigned_station_id', p_staff.assigned_station_id,
        'is_admin', (p_staff.role = 'admin')
    );
END;
$$;

REVOKE ALL ON FUNCTION _actor_scope(staff) FROM PUBLIC;
REVOKE ALL ON FUNCTION _actor_scope(staff) FROM anon;

-- ----------------------------------------------------------------------------
-- 6. RPC: STAFF_LOGIN (RATE LIMIT, BCRYPT VERIFICATION & SHA-256 TOKEN)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION staff_login(
    p_pin TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_ip                TEXT;
    v_recent_failures   INT;
    v_last_failure      TIMESTAMPTZ;
    v_staff             RECORD;
    v_matched_staff     staff%ROWTYPE;
    v_raw_token         TEXT;
    v_token_hash        TEXT;
    v_expires_at        TIMESTAMPTZ;
    v_assigned_team     JSONB := NULL;
    v_assigned_station  JSONB := NULL;
BEGIN
    v_ip := _extract_client_ip();

    -- 1. RATE LIMIT THEO IP: Quá 5 lần sai trong 5 phút thì khóa 10 phút
    SELECT COUNT(*), MAX(created_at)
    INTO v_recent_failures, v_last_failure
    FROM auth_attempts
    WHERE ip = v_ip
      AND success = false
      AND created_at > now() - INTERVAL '5 minutes';

    IF v_recent_failures >= 5 AND (now() - v_last_failure) < INTERVAL '10 minutes' THEN
        RETURN jsonb_build_object(
            'success', false,
            'code', 'LOGIN_LOCKED',
            'error', 'IP của bạn tạm thời bị khóa 10 phút do nhập sai mã PIN quá 5 lần. Vui lòng thử lại sau.'
        );
    END IF;

    -- 2. SO KHỚP PIN ĐÃ HASH VỚI STAFF ĐANG ACTIVE
    IF p_pin IS NULL OR trim(p_pin) = '' THEN
        INSERT INTO auth_attempts (ip, success) VALUES (v_ip, false);
        RETURN jsonb_build_object('success', false, 'code', 'INVALID_PIN', 'error', 'Mã PIN không được để trống.');
    END IF;

    FOR v_staff IN 
        SELECT * 
        FROM staff 
        WHERE is_active = true 
          AND pin_hash IS NOT NULL
    LOOP
        IF v_staff.pin_hash = crypt(trim(p_pin), v_staff.pin_hash) THEN
            v_matched_staff := v_staff;
            EXIT;
        END IF;
    END LOOP;

    -- Nếu không tìm thấy nhân sự khớp PIN
    IF v_matched_staff.id IS NULL THEN
        INSERT INTO auth_attempts (ip, success) VALUES (v_ip, false);
        RETURN jsonb_build_object(
            'success', false,
            'code', 'INVALID_CREDENTIALS',
            'error', 'Mã PIN không chính xác hoặc tài khoản nhân sự đã bị khóa.'
        );
    END IF;

    -- Ghi nhận lần đăng nhập thành công
    INSERT INTO auth_attempts (ip, success) VALUES (v_ip, true);

    -- 3. SINH TOKEN NGẪU NHIÊN 32 BYTE & LƯU SHA-256 HASH
    v_raw_token := encode(gen_random_bytes(32), 'hex');
    v_token_hash := encode(digest(v_raw_token, 'sha256'), 'hex');
    v_expires_at := now() + INTERVAL '24 hours';

    INSERT INTO staff_sessions (staff_id, token_hash, token, expires_at)
    VALUES (v_matched_staff.id, v_token_hash, v_token_hash, v_expires_at);

    -- 4. ĐÓNG GÓI ĐỐI TƯỢNG RÚT GỌN ASSIGNED_TEAM HOẶC ASSIGNED_STATION
    IF v_matched_staff.assigned_team_id IS NOT NULL THEN
        SELECT jsonb_build_object('id', id, 'name', name) INTO v_assigned_team
        FROM teams WHERE id = v_matched_staff.assigned_team_id;
    END IF;

    IF v_matched_staff.assigned_station_id IS NOT NULL THEN
        SELECT jsonb_build_object('id', id, 'name', name) INTO v_assigned_station
        FROM stations WHERE id = v_matched_staff.assigned_station_id;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'token', v_raw_token,
        'expires_at', v_expires_at,
        'staff', jsonb_build_object(
            'id', v_matched_staff.id,
            'name', v_matched_staff.name,
            'role', v_matched_staff.role
        ),
        'assigned_team', v_assigned_team,
        'assigned_station', v_assigned_station
    );
END;
$$;

-- ----------------------------------------------------------------------------
-- 7. RPC: AUTH_VERIFY_SESSION (XÁC THỰC PHIÊN LIÊN TỤC VỚI REALTIME REFLECTION)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION auth_verify_session(
    p_token TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_staff             staff%ROWTYPE;
    v_session           staff_sessions%ROWTYPE;
    v_token_hash        TEXT;
    v_assigned_team     JSONB := NULL;
    v_assigned_station  JSONB := NULL;
BEGIN
    IF p_token IS NULL OR trim(p_token) = '' THEN
        RETURN jsonb_build_object('success', false, 'code', 'UNAUTHENTICATED', 'error', 'Token rỗng.');
    END IF;

    v_token_hash := encode(digest(trim(p_token), 'sha256'), 'hex');

    SELECT * INTO v_session
    FROM staff_sessions
    WHERE token_hash = v_token_hash
      AND expires_at > now();

    IF v_session.id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'code', 'UNAUTHENTICATED', 'error', 'Phiên làm việc đã hết hạn hoặc không tồn tại.');
    END IF;

    -- Truy vấn trực tiếp từ bảng staff để phản ánh ngay lập tức nếu bị đổi team/trạm/vô hiệu hóa
    SELECT * INTO v_staff
    FROM staff
    WHERE id = v_session.staff_id;

    IF v_staff.id IS NULL OR v_staff.is_active = false THEN
        RETURN jsonb_build_object('success', false, 'code', 'UNAUTHENTICATED', 'error', 'Tài khoản nhân sự đã bị vô hiệu hóa.');
    END IF;

    IF v_staff.assigned_team_id IS NOT NULL THEN
        SELECT jsonb_build_object('id', id, 'name', name) INTO v_assigned_team
        FROM teams WHERE id = v_staff.assigned_team_id;
    END IF;

    IF v_staff.assigned_station_id IS NOT NULL THEN
        SELECT jsonb_build_object('id', id, 'name', name) INTO v_assigned_station
        FROM stations WHERE id = v_staff.assigned_station_id;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'expires_at', v_session.expires_at,
        'staff', jsonb_build_object(
            'id', v_staff.id,
            'name', v_staff.name,
            'role', v_staff.role
        ),
        'assigned_team', v_assigned_team,
        'assigned_station', v_assigned_station
    );
END;
$$;

-- ----------------------------------------------------------------------------
-- 8. RPC: STAFF_LOGOUT (ĐĂNG XUẤT THU HỒI PHIÊN)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION staff_logout(
    p_token TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_token_hash TEXT;
BEGIN
    IF p_token IS NOT NULL AND trim(p_token) <> '' THEN
        v_token_hash := encode(digest(trim(p_token), 'sha256'), 'hex');
        DELETE FROM staff_sessions WHERE token_hash = v_token_hash;
    END IF;

    RETURN jsonb_build_object('success', true, 'message', 'Đã đăng xuất thành công.');
END;
$$;

-- ----------------------------------------------------------------------------
-- 9. RPC: ADMIN_REVOKE_SESSIONS (ADMIN CƯỠNG CHẾ THU HỒI PHIÊN CỦA NHÂN SỰ)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION admin_revoke_sessions(
    p_token     TEXT,
    p_staff_id  UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_admin         staff%ROWTYPE;
    v_revoked_count INT;
BEGIN
    -- Chỉ admin mới có quyền thực thi
    v_admin := _require_staff(p_token, ARRAY['admin']);

    DELETE FROM staff_sessions
    WHERE staff_id = p_staff_id;

    GET DIAGNOSTICS v_revoked_count = ROW_COUNT;

    RETURN jsonb_build_object(
        'success', true,
        'revoked_count', v_revoked_count,
        'message', 'Đã thu hồi thành công ' || v_revoked_count || ' phiên đăng nhập của nhân sự.'
    );
END;
$$;

-- ----------------------------------------------------------------------------
-- 10. PHÂN QUYỀN EXECUTE CHẶT CHẼ
-- ----------------------------------------------------------------------------
REVOKE ALL ON FUNCTION staff_login(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION staff_login(TEXT) TO anon, authenticated;

REVOKE ALL ON FUNCTION auth_verify_session(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION auth_verify_session(TEXT) TO anon, authenticated;

REVOKE ALL ON FUNCTION staff_logout(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION staff_logout(TEXT) TO anon, authenticated;

REVOKE ALL ON FUNCTION admin_revoke_sessions(TEXT, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION admin_revoke_sessions(TEXT, UUID) TO anon, authenticated;
