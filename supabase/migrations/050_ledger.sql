-- ============================================================================
-- MIGRATION 050: IMMUTABLE LEDGER & BALANCE INTEGRITY CONSTRAINTS
-- File: supabase/migrations/050_ledger.sql
-- Mục đích: Biến transactions thành Sổ Cái Bất Biến (ADR-1), chặn Delete, chống âm số dư
-- ============================================================================

-- 1. BỔ SUNG CÁC CỘT QUẢN TRỊ VÀO BẢNG TRANSACTIONS
ALTER TABLE transactions
    ADD COLUMN IF NOT EXISTS claim_id UUID REFERENCES station_claims(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS reverses_tx_id UUID REFERENCES transactions(id),
    ADD COLUMN IF NOT EXISTS metadata JSONB DEFAULT '{}'::jsonb,
    ADD COLUMN IF NOT EXISTS actor_staff_id UUID REFERENCES staff(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS actor_role TEXT;

-- Đảm bảo mỗi giao dịch chỉ được phép bị hoàn tác 1 lần duy nhất (Unique khi reverses_tx_id NOT NULL)
CREATE UNIQUE INDEX IF NOT EXISTS idx_tx_reverses_unique 
ON transactions (reverses_tx_id) 
WHERE reverses_tx_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_tx_claim_id 
ON transactions (claim_id) 
WHERE claim_id IS NOT NULL;

-- 2. CHUẨN HÓA DANH SÁCH TRANSACTION TYPES
ALTER TABLE transactions DROP CONSTRAINT IF EXISTS transactions_type_check;
ALTER TABLE transactions DROP CONSTRAINT IF EXISTS chk_transactions_type;

ALTER TABLE transactions
    ADD CONSTRAINT chk_transactions_type CHECK (
        type IN (
            'station_clear', 
            'buy_hint',
            'hint_purchase',
            'buy_item',
            'shop_item',
            'pvp_steal', 
            'pvp_backlash', 
            'admin_adjust', 
            'reversal',
            'initial_grant',
            'migration_correction'
        )
    );

-- 3. THIẾT LẬP RÀNG BUỘC SỐ DƯ VÀ KHO ĐỒ KHÔNG ĐƯỢC ÂM
-- Chống âm Lumen cho đội chơi
ALTER TABLE teams DROP CONSTRAINT IF EXISTS chk_teams_light_balance_non_negative;
ALTER TABLE teams
    ADD CONSTRAINT chk_teams_light_balance_non_negative 
    CHECK (light_balance >= 0);

-- Chống âm số lượng đạo cụ trong kho
ALTER TABLE team_items DROP CONSTRAINT IF EXISTS team_items_quantity_check;
ALTER TABLE team_items DROP CONSTRAINT IF EXISTS chk_team_items_quantity;
ALTER TABLE team_items
    ADD CONSTRAINT chk_team_items_quantity 
    CHECK (quantity >= 0);

-- 4. THÊM CỘT PURCHASE_TX_ID VÀO TEAM_HINTS ĐỂ THU HỒI CHUẨN XÁC KHI REVERT
ALTER TABLE team_hints
    ADD COLUMN IF NOT EXISTS purchase_tx_id UUID REFERENCES transactions(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_team_hints_purchase_tx 
ON team_hints (purchase_tx_id) 
WHERE purchase_tx_id IS NOT NULL;

-- 5. TRIGGER BẤT BIẾN: CHẶN DELETE VÀ CHẶN UPDATE NGOÀI CỘT CHO PHÉP TRÊN TRANSACTIONS
CREATE OR REPLACE FUNCTION _trg_enforce_ledger_immutability()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    -- Tuyệt đối cấm thao tác DELETE trên sổ cái
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION 'LEDGER_IMMUTABLE: Sổ cái là bất biến! Tuyệt đối không được phép xóa bản ghi transactions.';
    END IF;

    -- Kiểm tra nghiêm ngặt khi UPDATE
    IF TG_OP = 'UPDATE' THEN
        -- Cấm thay đổi các thông số tài chính và định danh gốc
        IF OLD.id <> NEW.id 
           OR OLD.team_id <> NEW.team_id 
           OR OLD.amount <> NEW.amount 
           OR OLD.type <> NEW.type 
           OR OLD.created_at <> NEW.created_at
           OR (OLD.client_request_id IS NOT NULL AND OLD.client_request_id <> NEW.client_request_id) THEN
            RAISE EXCEPTION 'LEDGER_IMMUTABLE: Không được phép sửa đổi id, team_id, amount, type, created_at hoặc client_request_id của giao dịch đã ghi nhận!';
        END IF;

        -- Giao dịch đã đánh dấu hoàn tác thì không thể hủy cờ
        IF OLD.is_reversed = true AND NEW.is_reversed = false THEN
            RAISE EXCEPTION 'LEDGER_IMMUTABLE: Giao dịch đã hoàn tác (is_reversed=true) không thể chuyển ngược lại false.';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_transactions_immutable ON transactions;
CREATE TRIGGER trg_transactions_immutable
BEFORE UPDATE OR DELETE ON transactions
FOR EACH ROW
EXECUTE FUNCTION _trg_enforce_ledger_immutability();
