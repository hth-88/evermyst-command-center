-- ============================================================================
-- MIGRATION 040: STATION CLAIMS CORE ENGINE
-- File: supabase/migrations/040_station_claims.sql
-- Mục đích: Bảng cốt lõi quản lý tiến trình vượt trạm, chống claim trùng & quy trình 2 bước
-- ============================================================================

-- 1. TẠO BẢNG STATION_CLAIMS
CREATE TABLE IF NOT EXISTS station_claims (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    team_id                 UUID NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
    station_id              UUID NOT NULL REFERENCES stations(id) ON DELETE CASCADE,
    status                  TEXT NOT NULL DEFAULT 'draft',
    input                   JSONB NOT NULL DEFAULT '{}'::jsonb,
    original_input          JSONB NOT NULL DEFAULT '{}'::jsonb,
    scoring_snapshot        JSONB NOT NULL DEFAULT '{}'::jsonb,
    computed_points         INT NOT NULL DEFAULT 0,
    final_points            INT NOT NULL DEFAULT 0,
    is_exclusive            BOOLEAN NOT NULL DEFAULT true,
    requires_admin_review   BOOLEAN NOT NULL DEFAULT false,
    key_used                BOOLEAN NOT NULL DEFAULT false,
    submitted_by            UUID REFERENCES staff(id) ON DELETE SET NULL,
    submitted_by_role       TEXT,
    station_verified_by     UUID REFERENCES staff(id) ON DELETE SET NULL,
    station_verified_at     TIMESTAMPTZ,
    admin_verified_by       UUID REFERENCES staff(id) ON DELETE SET NULL,
    admin_verified_at       TIMESTAMPTZ,
    reject_reason           TEXT,
    correction_note         TEXT,
    client_request_id       TEXT UNIQUE,
    tx_id                   UUID,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),

    -- CHECK constraint cho 6 trạng thái vòng đời claim
    CONSTRAINT chk_station_claims_status CHECK (
        status IN ('draft', 'pending_station', 'pending_admin', 'approved', 'rejected', 'cancelled')
    )
);

-- 2. PARTIAL UNIQUE INDEX (CƠ CHẾ BẢO VỆ ĐỘC QUYỀN - ANTI SPAM CLAIM)
-- Đảm bảo mỗi đội chỉ có DUY NHẤT 1 claim đang xử lý hoặc đã duyệt trên 1 trạm
CREATE UNIQUE INDEX IF NOT EXISTS idx_exclusive_station_claim 
ON station_claims (team_id, station_id) 
WHERE is_exclusive AND status IN ('pending_station', 'pending_admin', 'approved');

-- 3. INDEXES TỐI ƯU TRUY VẤN REALTIME & GIÁM SÁT
CREATE INDEX IF NOT EXISTS idx_station_claims_status_created 
ON station_claims (station_id, status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_station_claims_team_created 
ON station_claims (team_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_station_claims_tx 
ON station_claims (tx_id) WHERE tx_id IS NOT NULL;

-- 4. TRIGGER TỰ ĐỘNG CẬP NHẬT UPDATED_AT
CREATE OR REPLACE FUNCTION _trg_station_claims_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_station_claims_updated_at ON station_claims;
CREATE TRIGGER trg_station_claims_updated_at
BEFORE UPDATE ON station_claims
FOR EACH ROW
EXECUTE FUNCTION _trg_station_claims_updated_at();
