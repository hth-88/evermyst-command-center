-- ============================================================================
-- MIGRATION 030: STATIONS SCORING SCHEMAS & CONFIGURATION
-- File: supabase/migrations/030_stations_scoring.sql
-- Mục đích: Đa dạng hóa mô hình chấm điểm (tier, fixed, time_attack) & backfill 5 trạm
-- ============================================================================

-- 1. THÊM CỘT VÀO BẢNG STATIONS
ALTER TABLE stations
    ADD COLUMN IF NOT EXISTS scoring_type TEXT DEFAULT 'tier',
    ADD COLUMN IF NOT EXISTS scoring_config JSONB DEFAULT '{}'::jsonb,
    ADD COLUMN IF NOT EXISTS min_score INT DEFAULT 0,
    ADD COLUMN IF NOT EXISTS max_score INT DEFAULT 50,
    ADD COLUMN IF NOT EXISTS allow_multiple_attempts BOOLEAN DEFAULT false,
    ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ DEFAULT NULL;

-- 2. THIẾT LẬP CHECK CONSTRAINTS CHO SCORING
ALTER TABLE stations DROP CONSTRAINT IF EXISTS chk_stations_scoring_type;
ALTER TABLE stations DROP CONSTRAINT IF EXISTS chk_stations_score_bounds;

ALTER TABLE stations
    ADD CONSTRAINT chk_stations_scoring_type 
    CHECK (scoring_type IN ('tier', 'fixed', 'time_attack'));

ALTER TABLE stations
    ADD CONSTRAINT chk_stations_score_bounds 
    CHECK (min_score >= 0 AND max_score >= min_score);

-- 3. INDEX PHỤC VỤ TRUY VẤN ACTIVE STATIONS (SOFT DELETE SUPPORT)
CREATE INDEX IF NOT EXISTS idx_stations_active_order 
ON stations (order_index ASC) 
WHERE deleted_at IS NULL AND is_active = true;

-- 4. BACKFILL 5 TRẠM HIỆN CÓ VỚI TIER MODEL 20/35/50
UPDATE stations
SET 
    scoring_type = 'tier',
    scoring_config = jsonb_build_object(
        'type', 'tier',
        'tiers', jsonb_build_array(
            jsonb_build_object('tier', 'low', 'points', 20, 'label', 'Mức Vớt'),
            jsonb_build_object('tier', 'mid', 'points', 35, 'label', 'Mức Đạt'),
            jsonb_build_object('tier', 'high', 'points', 50, 'label', 'Xuất Sắc')
        ),
        'pending_threshold', 50
    ),
    min_score = 0,
    max_score = 50,
    allow_multiple_attempts = false,
    deleted_at = NULL
WHERE deleted_at IS NULL;
