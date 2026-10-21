-- ============================================================================
-- MIGRATION 070: STRICT RLS DENY-ALL, REALTIME SIGNALS & BALANCE INTEGRITY AUDIT
-- File: supabase/migrations/070_security_realtime.sql
-- Mục đích: Bảo mật tuyệt đối (ADR-3 Deny-All), bộ phát tín hiệu Realtime & hàm đối soát
-- ============================================================================

-- 1. BẬT ROW LEVEL SECURITY (RLS) VÀ THIẾT LẬP DENY-ALL TRÊN TẤT CẢ CÁC BẢNG
-- Xóa toàn bộ policies cũ (kể cả các policy SELECT public/anon của V1)
DO $$
DECLARE
    pol RECORD;
BEGIN
    FOR pol IN 
        SELECT policyname, tablename 
        FROM pg_policies 
        WHERE schemaname = 'public' 
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON %I', pol.policyname, pol.tablename);
    END LOOP;
END $$;

-- Bật RLS trên toàn bộ danh mục bảng của hệ thống
ALTER TABLE staff                   ENABLE ROW LEVEL SECURITY;
ALTER TABLE staff_sessions          ENABLE ROW LEVEL SECURITY;
ALTER TABLE auth_attempts           ENABLE ROW LEVEL SECURITY;
ALTER TABLE game_settings           ENABLE ROW LEVEL SECURITY;
ALTER TABLE game_settings_history   ENABLE ROW LEVEL SECURITY;
ALTER TABLE teams                   ENABLE ROW LEVEL SECURITY;
ALTER TABLE stations                ENABLE ROW LEVEL SECURITY;
ALTER TABLE hints                   ENABLE ROW LEVEL SECURITY;
ALTER TABLE team_hints              ENABLE ROW LEVEL SECURITY;
ALTER TABLE items                   ENABLE ROW LEVEL SECURITY;
ALTER TABLE team_items              ENABLE ROW LEVEL SECURITY;
ALTER TABLE transactions            ENABLE ROW LEVEL SECURITY;
ALTER TABLE pvp_logs                ENABLE ROW LEVEL SECURITY;
ALTER TABLE station_claims          ENABLE ROW LEVEL SECURITY;
ALTER TABLE team_station_keys       ENABLE ROW LEVEL SECURITY;
ALTER TABLE item_usage_logs         ENABLE ROW LEVEL SECURITY;

-- GHI CHÚ BẢO MẬT: 
-- Khi không có bất kỳ policy nào được định nghĩa, PostgreSQL tự động DENY ALL đối với public/anon!
-- Mọi truy cập dữ liệu bắt buộc 100% phải đi qua RPC Security Definer.

-- 2. HÀM NỘI BỘ PHÁT TÍN HIỆU REALTIME _EMIT_SIGNAL (ADR-3)
CREATE OR REPLACE FUNCTION _emit_signal(
    p_topic     TEXT,
    p_payload   JSONB DEFAULT '{}'::jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    -- Phát thông điệp qua kênh pg_notify
    PERFORM pg_notify('realtime_signals', jsonb_build_object(
        'topic', p_topic,
        'payload', p_payload,
        'emitted_at', now()
    )::text);
END;
$$;

-- Hàm nội bộ (tiền tố _) tuyệt đối KHÔNG cấp quyền cho anon / public
REVOKE ALL ON FUNCTION _emit_signal(TEXT, JSONB) FROM PUBLIC;
REVOKE ALL ON FUNCTION _emit_signal(TEXT, JSONB) FROM anon;

-- 3. TRIGGERS TỰ ĐỘNG PHÁT TÍN HIỆU SIGNAL
-- 3a. Trigger trên station_claims
CREATE OR REPLACE FUNCTION _trg_signal_station_claims()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    PERFORM _emit_signal('station_claims_changed', jsonb_build_object(
        'id', NEW.id,
        'team_id', NEW.team_id,
        'station_id', NEW.station_id,
        'status', NEW.status,
        'final_points', NEW.final_points
    ));
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_signal_station_claims ON station_claims;
CREATE TRIGGER trg_signal_station_claims
AFTER INSERT OR UPDATE ON station_claims
FOR EACH ROW
EXECUTE FUNCTION _trg_signal_station_claims();

-- 3b. Trigger trên transactions
CREATE OR REPLACE FUNCTION _trg_signal_transactions()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    PERFORM _emit_signal('transactions_changed', jsonb_build_object(
        'id', NEW.id,
        'team_id', NEW.team_id,
        'amount', NEW.amount,
        'type', NEW.type,
        'is_reversed', NEW.is_reversed,
        'status', NEW.status
    ));
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_signal_transactions ON transactions;
CREATE TRIGGER trg_signal_transactions
AFTER INSERT OR UPDATE ON transactions
FOR EACH ROW
EXECUTE FUNCTION _trg_signal_transactions();

-- 3c. Trigger trên teams (khi đổi số dư hoặc khiên)
CREATE OR REPLACE FUNCTION _trg_signal_teams()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF OLD.light_balance <> NEW.light_balance 
       OR (OLD.shield_until IS DISTINCT FROM NEW.shield_until) 
       OR (OLD.unlocked_stations IS DISTINCT FROM NEW.unlocked_stations) THEN
        PERFORM _emit_signal('teams_changed', jsonb_build_object(
            'team_id', NEW.id,
            'light_balance', NEW.light_balance,
            'shield_until', NEW.shield_until
        ));
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_signal_teams ON teams;
CREATE TRIGGER trg_signal_teams
AFTER UPDATE ON teams
FOR EACH ROW
EXECUTE FUNCTION _trg_signal_teams();

-- 4. HÀM KIỂM ĐỊNH TOÀN VẸN SỐ DƯ TỰ ĐỘNG AUDIT_BALANCE_INTEGRITY()
CREATE OR REPLACE FUNCTION audit_balance_integrity()
RETURNS TABLE (
    team_id         UUID,
    team_name       TEXT,
    cached_balance  INT,
    ledger_sum      BIGINT,
    discrepancy     BIGINT,
    status          TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    RETURN QUERY
    WITH ledger_summary AS (
        SELECT 
            tx.team_id AS tx_team_id,
            COALESCE(SUM(tx.amount), 0) AS total_lumen
        FROM transactions tx
        WHERE tx.status = 'approved'
        GROUP BY tx.team_id
    )
    SELECT 
        t.id AS team_id,
        t.name AS team_name,
        t.light_balance AS cached_balance,
        COALESCE(ls.total_lumen, 0)::BIGINT AS ledger_sum,
        (t.light_balance - COALESCE(ls.total_lumen, 0))::BIGINT AS discrepancy,
        CASE 
            WHEN (t.light_balance - COALESCE(ls.total_lumen, 0)) = 0 THEN 'BALANCED'
            ELSE 'UNBALANCED_MISMATCH'
        END AS status
    FROM teams t
    LEFT JOIN ledger_summary ls ON ls.tx_team_id = t.id
    WHERE t.light_balance <> COALESCE(ls.total_lumen, 0);
END;
$$;

-- Chỉ cấp quyền gọi audit_balance_integrity cho Admin (hoặc nội bộ qua service_role)
REVOKE ALL ON FUNCTION audit_balance_integrity() FROM PUBLIC;
REVOKE ALL ON FUNCTION audit_balance_integrity() FROM anon;
