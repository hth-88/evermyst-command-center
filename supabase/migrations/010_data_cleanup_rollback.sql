-- ============================================================================
-- ROLLBACK 010: DATA CLEANUP ROLLBACK
-- File: supabase/migrations/010_data_cleanup_rollback.sql
-- Mục đích: Hoàn tác các giao dịch bù đắp migration tạo bởi 010_data_cleanup.sql
-- ============================================================================

DO $$
BEGIN
    -- 1. Xóa các giao dịch migration bù đắp đã tạo trong đợt cleanup
    DELETE FROM transactions
    WHERE client_request_id LIKE 'mig-init-grant-%'
       OR client_request_id LIKE 'mig-corr-%';

    RAISE NOTICE 'ROLLBACK_010: Đã hoàn tất rollback các dòng transaction bù đắp của migration 010.';
END $$;
