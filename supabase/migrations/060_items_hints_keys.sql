-- ============================================================================
-- MIGRATION 060: STATION KEYS, ITEM USAGE LOGS & SHOP ITEMS EXPANSION
-- File: supabase/migrations/060_items_hints_keys.sql
-- Mục đích: Quản lý chìa khóa trạm (bypass câu đố), log sử dụng đạo cụ bất biến
-- ============================================================================

-- 1. BẢNG TEAM_STATION_KEYS (CHÌA KHÓA MỞ TRẠM ĐỘC QUYỀN)
CREATE TABLE IF NOT EXISTS team_station_keys (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    team_id             UUID NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
    station_id          UUID NOT NULL REFERENCES stations(id) ON DELETE CASCADE,
    item_usage_id       UUID,
    consumed_claim_id   UUID REFERENCES station_claims(id) ON DELETE SET NULL,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    
    -- Đảm bảo mỗi đội chỉ có thể giữ tối đa 1 chìa khóa hợp lệ cho 1 trạm
    CONSTRAINT uq_team_station_key UNIQUE (team_id, station_id)
);

CREATE INDEX IF NOT EXISTS idx_team_station_keys_claim 
ON team_station_keys (consumed_claim_id) 
WHERE consumed_claim_id IS NOT NULL;

-- 2. BẢNG ITEM_USAGE_LOGS (NHẬT KÝ SỬ DỤNG ĐẠO CỤ BẤT BIẾN)
CREATE TABLE IF NOT EXISTS item_usage_logs (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    team_id             UUID NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
    item_id             UUID NOT NULL,
    item_name           TEXT NOT NULL,
    target_team_id      UUID REFERENCES teams(id) ON DELETE SET NULL,
    target_station_id   UUID REFERENCES stations(id) ON DELETE SET NULL,
    actor_staff_id      UUID REFERENCES staff(id) ON DELETE SET NULL,
    actor_role          TEXT,
    effect_snapshot     JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_item_usage_team_created 
ON item_usage_logs (team_id, created_at DESC);

-- Trigger đảm bảo tính bất biến của item_usage_logs (Chặn UPDATE & DELETE)
CREATE OR REPLACE FUNCTION _trg_enforce_item_usage_immutability()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'LOG_IMMUTABLE: Nhật ký sử dụng vật phẩm item_usage_logs là bất biến, không thể sửa đổi hoặc xóa!';
END;
$$;

DROP TRIGGER IF EXISTS trg_item_usage_immutable ON item_usage_logs;
CREATE TRIGGER trg_item_usage_immutable
BEFORE UPDATE OR DELETE ON item_usage_logs
FOR EACH ROW
EXECUTE FUNCTION _trg_enforce_item_usage_immutability();

-- 3. NÂNG CẤP BẢNG ITEMS / SHOP_ITEMS
-- Bổ sung effect_value và deleted_at vào bảng items
ALTER TABLE items
    ADD COLUMN IF NOT EXISTS effect_value INT DEFAULT 0,
    ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ DEFAULT NULL;

-- Đảm bảo CHECK effect_type chặt chẽ
ALTER TABLE items DROP CONSTRAINT IF EXISTS items_effect_type_check;
ALTER TABLE items DROP CONSTRAINT IF EXISTS chk_items_effect_type;
ALTER TABLE items
    ADD CONSTRAINT chk_items_effect_type 
    CHECK (effect_type IN ('shield', 'spy', 'key', 'custom'));

-- Tạo View / Alias shop_items trỏ tới items để tương thích 100% với đặc tả ADR
CREATE OR REPLACE VIEW shop_items AS
SELECT 
    id,
    name,
    description,
    price,
    effect_type,
    effect_value,
    duration_minutes,
    is_active,
    deleted_at,
    created_at
FROM items;

-- 4. NÂNG CẤP BẢNG HINTS
ALTER TABLE hints
    ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ DEFAULT NULL;

ALTER TABLE hints DROP CONSTRAINT IF EXISTS hints_tier_check;
ALTER TABLE hints DROP CONSTRAINT IF EXISTS chk_hints_tier;
ALTER TABLE hints
    ADD CONSTRAINT chk_hints_tier 
    CHECK (tier IN ('bronze', 'silver', 'gold'));

CREATE INDEX IF NOT EXISTS idx_hints_active_order 
ON hints (order_index ASC) 
WHERE deleted_at IS NULL AND is_active = true;

-- 5. NÂNG CẤP CHỈ MỤC PVP_LOGS (HỖ TRỢ TRA CỨU COOLDOWN 2 CHIỀU)
CREATE INDEX IF NOT EXISTS idx_pvp_pair_created_at 
ON pvp_logs (attacker_team_id, defender_team_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_pvp_reverse_pair_created_at 
ON pvp_logs (defender_team_id, attacker_team_id, created_at DESC);
