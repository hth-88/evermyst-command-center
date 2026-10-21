-- ============================================================================
-- MIGRATION 020: STAFF AUTHENTICATION & STRICT ROLE ASSIGNMENT
-- File: supabase/migrations/020_staff_auth.sql
-- Mục đích: Phân định 3 role (admin, team_support, station_master) & ràng buộc phân công
-- ============================================================================

-- Đảm bảo extension pgcrypto sẵn sàng
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- 1. BỔ SUNG CỘT VÀO BẢNG STAFF
ALTER TABLE staff
    ADD COLUMN IF NOT EXISTS assigned_team_id UUID REFERENCES teams(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS assigned_station_id UUID REFERENCES stations(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS pin_hash TEXT;

-- Đảm bảo cột is_active tồn tại và có default true
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'staff' AND column_name = 'is_active'
    ) THEN
        ALTER TABLE staff ADD COLUMN is_active BOOLEAN DEFAULT true;
    END IF;
END $$;

-- 2. ĐỒNG BỘ PIN_HASH CHO TOÀN BỘ NHÂN SỰ HIỆN TẠI (DÙNG SHA256)
UPDATE staff
SET pin_hash = encode(digest(pin, 'sha256'), 'hex')
WHERE pin_hash IS NULL AND pin IS NOT NULL;

-- 3. CHUYỂN ĐỔI ROLE CŨ SANG ROLE MỚI
-- Role cũ 'support' chuyển thành 'team_support' với is_active = false
-- Gán tạm team đầu tiên cho các staff chuyển đổi để thỏa mãn ràng buộc khóa ngoại trước khi Admin phân bổ chính thức
DO $$
DECLARE
    v_first_team_id UUID;
BEGIN
    SELECT id INTO v_first_team_id FROM teams ORDER BY created_at ASC LIMIT 1;

    -- Xóa constraint role cũ nếu có
    ALTER TABLE staff DROP CONSTRAINT IF EXISTS staff_role_check;
    ALTER TABLE staff DROP CONSTRAINT IF EXISTS chk_staff_role;
    ALTER TABLE staff DROP CONSTRAINT IF EXISTS chk_staff_role_assignment;

    -- Cập nhật role cũ
    UPDATE staff
    SET role = 'team_support',
        is_active = false,
        assigned_team_id = COALESCE(assigned_team_id, v_first_team_id),
        assigned_station_id = NULL
    WHERE role = 'support';

    -- Đảm bảo admin có cả 2 trường null
    UPDATE staff
    SET assigned_team_id = NULL,
        assigned_station_id = NULL
    WHERE role = 'admin';
END $$;

-- 4. THIẾT LẬP CHECK RÀNG BUỘC ROLE & PHÂN CÔNG CHẶT CHẼ
-- Ràng buộc 1: Role chỉ nhận 3 giá trị: admin, team_support, station_master
ALTER TABLE staff
    ADD CONSTRAINT chk_staff_role 
    CHECK (role IN ('admin', 'team_support', 'station_master'));

-- Ràng buộc 2: Phân công bất biến theo vai trò
-- - team_support: BẮT BUỘC có assigned_team_id VÀ KHÔNG CÓ assigned_station_id
-- - station_master: BẮT BUỘC có assigned_station_id VÀ KHÔNG CÓ assigned_team_id
-- - admin: CẢ HAI BẮT BUỘC NULL
ALTER TABLE staff
    ADD CONSTRAINT chk_staff_role_assignment
    CHECK (
        (role = 'admin' AND assigned_team_id IS NULL AND assigned_station_id IS NULL)
        OR (role = 'team_support' AND assigned_team_id IS NOT NULL AND assigned_station_id IS NULL)
        OR (role = 'station_master' AND assigned_station_id IS NOT NULL AND assigned_team_id IS NULL)
    );

-- Tạo Index tăng tốc truy vấn theo vai trò và phân công
CREATE INDEX IF NOT EXISTS idx_staff_assigned_team ON staff(assigned_team_id);
CREATE INDEX IF NOT EXISTS idx_staff_assigned_station ON staff(assigned_station_id);
CREATE INDEX IF NOT EXISTS idx_staff_role ON staff(role);

-- 5. NÂNG CẤP BẢNG STAFF_SESSIONS
ALTER TABLE staff_sessions
    ADD COLUMN IF NOT EXISTS token_hash TEXT;

-- Cập nhật token_hash cho các session hiện có và vô hiệu hóa toàn bộ phiên cũ
UPDATE staff_sessions
SET token_hash = encode(digest(token, 'sha256'), 'hex'),
    expires_at = now() - INTERVAL '1 second'
WHERE expires_at > now();

-- 6. TẠO BẢNG THEO DÕI ĐĂNG NHẬP (AUTH_ATTEMPTS)
CREATE TABLE IF NOT EXISTS auth_attempts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ip TEXT,
    success BOOLEAN NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_auth_attempts_created ON auth_attempts(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_auth_attempts_ip ON auth_attempts(ip, created_at DESC);
