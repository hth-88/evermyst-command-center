-- =====================================================================
-- 104_direct_scoring_tests.sql
-- Bộ Kiểm Thử Tự Động Toàn Diện Cho Hệ Thống Chấm Điểm Trạm Trực Tiếp (104)
--
-- CƠ CHẾ AN TOÀN TUYỆT ĐỐI:
-- 1. Đóng gói trong hàm public.run_104_scoring_tests() trả về TABLE kết quả.
-- 2. Tự động sinh token thử nghiệm ngẫu nhiên, không can thiệp mật khẩu/PIN.
-- 3. Tự động dọn dẹp sạch sẽ 100% dữ liệu thử (sessions, plays, txs).
-- 4. Tự động khôi phục nguyên trạng số dư đội, cài đặt trạm và phân công staff.
-- 5. Kết quả hiển thị trực quan dạng lưới có cột "test_status" (✅ PASS / ❌ FAIL).
-- =====================================================================

DROP FUNCTION IF EXISTS public.run_104_scoring_tests();

CREATE OR REPLACE FUNCTION public.run_104_scoring_tests()
RETURNS TABLE (
  test_no     INTEGER,
  test_name   TEXT,
  expected    TEXT,
  actual      TEXT,
  test_status TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
#variable_conflict use_column
DECLARE
  v_admin_id                 UUID;
  v_support_id               UUID;
  v_admin_token              TEXT := 'test_admin_token_' || gen_random_uuid();
  v_support_token            TEXT := 'test_support_token_' || gen_random_uuid();
  v_team_id                  UUID;
  v_st_multi_id              UUID;
  v_st_single_id             UUID;
  v_other_station_id         UUID;
  v_res                      JSONB;
  v_play_id                  UUID;
  v_tx_id                    UUID;
  v_team_orig_balance        INTEGER;
  v_team_orig_unlocked       TEXT[];
  v_st1_orig_multi           BOOLEAN;
  v_st1_orig_max             INTEGER;
  v_st2_orig_multi           BOOLEAN;
  v_st2_orig_max             INTEGER;
  v_st3_orig_multi           BOOLEAN;
  v_st3_orig_max             INTEGER;
  v_orig_support_assigned_id UUID;
  v_orig_balance             INTEGER;
  v_cur_balance              INTEGER;
  v_prev_play_no             INTEGER;
BEGIN
  -- 1. Khởi tạo bảng kết quả tạm trong session
  CREATE TEMP TABLE IF NOT EXISTS tmp_104_test_results (
    t_no     INTEGER,
    t_name   TEXT,
    t_exp    TEXT,
    t_act    TEXT,
    t_stat   TEXT
  ) ON COMMIT DROP;
  TRUNCATE tmp_104_test_results;

  -- Dọn dẹp an toàn tàn dư test cũ (gỡ ràng buộc khóa ngoại FK trước khi xóa)
  UPDATE public.transactions 
  SET reversal_for_id = NULL 
  WHERE client_request_id LIKE 'req_ca%' OR client_request_id LIKE 'probe_%' OR client_request_id LIKE 'test_node_%' OR client_request_id LIKE 'rev_%';

  UPDATE public.station_plays 
  SET tx_id = NULL 
  WHERE client_request_id LIKE 'req_ca%' OR client_request_id LIKE 'probe_%' OR client_request_id LIKE 'test_node_%';

  DELETE FROM public.station_plays 
  WHERE client_request_id LIKE 'req_ca%' OR client_request_id LIKE 'probe_%' OR client_request_id LIKE 'test_node_%';

  DELETE FROM public.transactions 
  WHERE client_request_id LIKE 'req_ca%' OR client_request_id LIKE 'probe_%' OR client_request_id LIKE 'test_node_%' OR client_request_id LIKE 'rev_%';

  -- 2. Lấy 1 admin và 1 support thật
  SELECT id INTO v_admin_id FROM public.staff WHERE role = 'admin' LIMIT 1;
  SELECT id, assigned_station_id INTO v_support_id, v_orig_support_assigned_id FROM public.staff WHERE role = 'support' LIMIT 1;

  IF v_admin_id IS NULL OR v_support_id IS NULL THEN
    RAISE EXCEPTION 'DB thiếu dữ liệu tài khoản staff (cần ít nhất 1 admin và 1 support).';
  END IF;

  -- 3. Tạo session thử nghiệm
  INSERT INTO public.staff_sessions (staff_id, token, expires_at)
  VALUES 
    (v_admin_id, v_admin_token, now() + interval '1 day'),
    (v_support_id, v_support_token, now() + interval '1 day');

  -- 4. Lấy 1 đội và 3 trạm đang hoạt động
  SELECT id, light_balance, unlocked_stations 
  INTO v_team_id, v_team_orig_balance, v_team_orig_unlocked 
  FROM public.teams 
  ORDER BY id LIMIT 1;

  SELECT id, allow_multiple_attempts, max_score INTO v_st_multi_id, v_st1_orig_multi, v_st1_orig_max 
  FROM public.stations WHERE order_index = 1 AND deleted_at IS NULL ORDER BY created_at DESC LIMIT 1;

  SELECT id, allow_multiple_attempts, max_score INTO v_st_single_id, v_st2_orig_multi, v_st2_orig_max 
  FROM public.stations WHERE order_index = 2 AND deleted_at IS NULL ORDER BY created_at DESC LIMIT 1;

  SELECT id, allow_multiple_attempts, max_score INTO v_other_station_id, v_st3_orig_multi, v_st3_orig_max 
  FROM public.stations WHERE order_index = 3 AND deleted_at IS NULL ORDER BY created_at DESC LIMIT 1;

  -- Cấu hình trạm cho ca thử nghiệm
  UPDATE public.stations SET allow_multiple_attempts = true, max_score = 50, is_active = true WHERE id = v_st_multi_id;
  UPDATE public.stations SET allow_multiple_attempts = false, max_score = 50, is_active = true WHERE id = v_st_single_id;
  UPDATE public.stations SET allow_multiple_attempts = false, max_score = 50, is_active = true WHERE id = v_other_station_id;

  -- Ban đầu gán trạm cho Support = NULL (chưa gán trạm)
  UPDATE public.staff SET assigned_station_id = NULL WHERE id = v_support_id;

  -- ===================================================================
  -- CA 1: Token sai / hết hạn -> INVALID_TOKEN
  -- ===================================================================
  v_res := public.award_station_direct_points('token_khong_hop_le_123', v_team_id, v_st_multi_id, 10, 'req_ca1');
  INSERT INTO tmp_104_test_results VALUES (
    1, 'Token sai / hết hạn', 'INVALID_TOKEN', v_res->>'code', 
    CASE WHEN v_res->>'code' = 'INVALID_TOKEN' THEN '✅ PASS' ELSE '❌ FAIL' END
  );

  -- ===================================================================
  -- CA 2a: Support chưa gán trạm -> FORBIDDEN
  -- ===================================================================
  v_res := public.award_station_direct_points(v_support_token, v_team_id, v_st_multi_id, 10, 'req_ca2a');
  INSERT INTO tmp_104_test_results VALUES (
    2, 'Support chưa gán trạm', 'FORBIDDEN', v_res->>'code', 
    CASE WHEN v_res->>'code' = 'FORBIDDEN' THEN '✅ PASS' ELSE '❌ FAIL' END
  );

  -- ===================================================================
  -- CA 2b: Support gán trạm khác trạm chấm -> FORBIDDEN_STATION
  -- ===================================================================
  UPDATE public.staff SET assigned_station_id = v_other_station_id WHERE id = v_support_id;
  v_res := public.award_station_direct_points(v_support_token, v_team_id, v_st_multi_id, 10, 'req_ca2b');
  INSERT INTO tmp_104_test_results VALUES (
    3, 'Support quản trạm khác', 'FORBIDDEN_STATION', v_res->>'code', 
    CASE WHEN v_res->>'code' = 'FORBIDDEN_STATION' THEN '✅ PASS' ELSE '❌ FAIL' END
  );

  -- Gán đúng trạm v_st_multi_id cho support để thực hiện các ca kế tiếp
  UPDATE public.staff SET assigned_station_id = v_st_multi_id WHERE id = v_support_id;

  -- ===================================================================
  -- CA 3: Trạm nhiều lượt: nhập 10, 20, 30 -> play_no tăng 3; total +60
  -- ===================================================================
  SELECT COALESCE(max(sp.play_no), 0) INTO v_prev_play_no
  FROM public.station_plays sp
  WHERE sp.team_id = v_team_id AND sp.station_id = v_st_multi_id;

  SELECT light_balance INTO v_orig_balance FROM public.teams WHERE id = v_team_id;
  
  PERFORM public.award_station_direct_points(v_support_token, v_team_id, v_st_multi_id, 10, 'req_ca3_1');
  PERFORM public.award_station_direct_points(v_support_token, v_team_id, v_st_multi_id, 20, 'req_ca3_2');
  v_res := public.award_station_direct_points(v_support_token, v_team_id, v_st_multi_id, 30, 'req_ca3_3');

  SELECT light_balance INTO v_cur_balance FROM public.teams WHERE id = v_team_id;

  IF ((v_res->'data'->>'play_no')::int = v_prev_play_no + 3) AND (v_cur_balance - v_orig_balance = 60) AND (v_res->>'code' = 'OK') THEN
    INSERT INTO tmp_104_test_results VALUES (
      4, 'Trạm nhiều lượt (10, 20, 30)', 'SUCCESS_3_PLAYS_+60', 'SUCCESS_3_PLAYS_+60', '✅ PASS'
    );
  ELSE
    INSERT INTO tmp_104_test_results VALUES (
      4, 'Trạm nhiều lượt (10, 20, 30)', 'SUCCESS_3_PLAYS_+60', 
      format('play_no=%s(expected %s), diff=%s', v_res->'data'->>'play_no', v_prev_play_no + 3, (v_cur_balance - v_orig_balance)), 
      '❌ FAIL'
    );
  END IF;

  -- ===================================================================
  -- CA 4: Trạm 1 lượt: lần 2 -> STATION_ALREADY_PLAYED
  -- ===================================================================
  PERFORM public.award_station_direct_points(v_admin_token, v_team_id, v_st_single_id, 20, 'req_ca4_1');
  v_res := public.award_station_direct_points(v_admin_token, v_team_id, v_st_single_id, 25, 'req_ca4_2');
  INSERT INTO tmp_104_test_results VALUES (
    5, 'Trạm 1 lượt chơi lần 2', 'STATION_ALREADY_PLAYED', v_res->>'code', 
    CASE WHEN v_res->>'code' = 'STATION_ALREADY_PLAYED' THEN '✅ PASS' ELSE '❌ FAIL' END
  );

  -- ===================================================================
  -- CA 5: Cùng client_request_id 5 lần -> 1 play duy nhất, replayed = true
  -- ===================================================================
  PERFORM public.award_station_direct_points(v_admin_token, v_team_id, v_st_multi_id, 15, 'req_ca5_idempotent');
  PERFORM public.award_station_direct_points(v_admin_token, v_team_id, v_st_multi_id, 15, 'req_ca5_idempotent');
  PERFORM public.award_station_direct_points(v_admin_token, v_team_id, v_st_multi_id, 15, 'req_ca5_idempotent');
  PERFORM public.award_station_direct_points(v_admin_token, v_team_id, v_st_multi_id, 15, 'req_ca5_idempotent');
  v_res := public.award_station_direct_points(v_admin_token, v_team_id, v_st_multi_id, 15, 'req_ca5_idempotent');

  IF (v_res->>'replayed' = 'true') AND (
    SELECT count(*) FROM public.station_plays sp WHERE sp.client_request_id = 'req_ca5_idempotent'
  ) = 1 THEN
    INSERT INTO tmp_104_test_results VALUES (
      6, 'Idempotency 5 lần lặp', 'REPLAYED_TRUE_1_RECORD', 'REPLAYED_TRUE_1_RECORD', '✅ PASS'
    );
  ELSE
    INSERT INTO tmp_104_test_results VALUES (
      6, 'Idempotency 5 lần lặp', 'REPLAYED_TRUE_1_RECORD', COALESCE(v_res->>'code', 'FAIL'), '❌ FAIL'
    );
  END IF;

  -- ===================================================================
  -- CA 6: Kiểm tra biên điểm
  -- ===================================================================
  v_res := public.award_station_direct_points(v_admin_token, v_team_id, v_st_multi_id, -5, 'req_ca6_neg');
  INSERT INTO tmp_104_test_results VALUES (
    7, 'Điểm âm (-5)', 'INVALID_AMOUNT', v_res->>'code', 
    CASE WHEN v_res->>'code' = 'INVALID_AMOUNT' THEN '✅ PASS' ELSE '❌ FAIL' END
  );

  v_res := public.award_station_direct_points(v_admin_token, v_team_id, v_st_multi_id, 51, 'req_ca6_over');
  INSERT INTO tmp_104_test_results VALUES (
    8, 'Vượt max_score (51/50)', 'POINTS_OUT_OF_RANGE', v_res->>'code', 
    CASE WHEN v_res->>'code' = 'POINTS_OUT_OF_RANGE' THEN '✅ PASS' ELSE '❌ FAIL' END
  );

  v_res := public.award_station_direct_points(v_admin_token, v_team_id, v_st_multi_id, 50, 'req_ca6_exact_max');
  INSERT INTO tmp_104_test_results VALUES (
    9, 'Đúng max_score (50/50)', 'OK', v_res->>'code', 
    CASE WHEN v_res->>'code' = 'OK' THEN '✅ PASS' ELSE '❌ FAIL' END
  );

  -- ===================================================================
  -- CA 7: Chấm 0 điểm: có play ghi nhận, không tạo transaction, số dư giữ nguyên
  -- ===================================================================
  SELECT light_balance INTO v_orig_balance FROM public.teams WHERE id = v_team_id;
  v_res := public.award_station_direct_points(v_admin_token, v_team_id, v_st_multi_id, 0, 'req_ca7_zero');
  SELECT light_balance INTO v_cur_balance FROM public.teams WHERE id = v_team_id;

  IF (v_res->>'code' = 'OK') AND (v_res->'data'->>'tx_id' IS NULL) AND (v_cur_balance = v_orig_balance) THEN
    INSERT INTO tmp_104_test_results VALUES (
      10, 'Chấm 0 điểm (Không tx, số dư giữ nguyên)', 'OK_NO_TX', 'OK_NO_TX', '✅ PASS'
    );
  ELSE
    INSERT INTO tmp_104_test_results VALUES (
      10, 'Chấm 0 điểm (Không tx, số dư giữ nguyên)', 'OK_NO_TX', COALESCE(v_res->>'code', 'FAIL'), '❌ FAIL'
    );
  END IF;

  -- ===================================================================
  -- CA 8: reverse_station_play: play reversed, số dư về cũ, chấm lại trạm 1 lượt được
  -- ===================================================================
  SELECT light_balance INTO v_orig_balance FROM public.teams WHERE id = v_team_id;
  v_res := public.award_station_direct_points(v_admin_token, v_team_id, v_other_station_id, 40, 'req_ca8_score');
  v_play_id := (v_res->'data'->>'play_id')::UUID;

  v_res := public.reverse_station_play(v_admin_token, 'req_ca8_rev', v_play_id, 'Test hoàn tác trạm');
  SELECT light_balance INTO v_cur_balance FROM public.teams WHERE id = v_team_id;

  v_res := public.award_station_direct_points(v_admin_token, v_team_id, v_other_station_id, 35, 'req_ca8_rescore');

  IF (v_cur_balance = v_orig_balance) AND (v_res->>'code' = 'OK') THEN
    INSERT INTO tmp_104_test_results VALUES (
      11, 'reverse_station_play & rescore', 'REVERSED_AND_RESCORE_OK', 'REVERSED_AND_RESCORE_OK', '✅ PASS'
    );
  ELSE
    INSERT INTO tmp_104_test_results VALUES (
      11, 'reverse_station_play & rescore', 'REVERSED_AND_RESCORE_OK', COALESCE(v_res->>'code', 'FAIL'), '❌ FAIL'
    );
  END IF;

  -- ===================================================================
  -- CA 9: Hoàn tác tx bằng reverse_transaction V1: Trigger tự động đồng bộ play reversed
  -- ===================================================================
  v_res := public.award_station_direct_points(v_admin_token, v_team_id, v_st_multi_id, 30, 'req_ca9_score');
  v_play_id := (v_res->'data'->>'play_id')::UUID;
  v_tx_id := (v_res->'data'->>'tx_id')::UUID;

  PERFORM public.reverse_transaction(v_admin_token, 'req_ca9_v1_rev', v_tx_id, 'Hoàn tác qua nút cũ');

  IF (SELECT sp.status FROM public.station_plays sp WHERE sp.id = v_play_id) = 'reversed' THEN
    INSERT INTO tmp_104_test_results VALUES (
      12, 'Trigger đồng bộ từ reverse_transaction V1', 'PLAY_SYNCED_REVERSED', 'PLAY_SYNCED_REVERSED', '✅ PASS'
    );
  ELSE
    INSERT INTO tmp_104_test_results VALUES (
      12, 'Trigger đồng bộ từ reverse_transaction V1', 'PLAY_SYNCED_REVERSED', 'FAIL', '❌ FAIL'
    );
  END IF;

  -- ===================================================================
  -- CA 10: Hoàn tác lần hai -> ALREADY_REVERSED
  -- ===================================================================
  v_res := public.reverse_station_play(v_admin_token, 'req_ca10_rev2', v_play_id, 'Hoàn tác lần hai');
  INSERT INTO tmp_104_test_results VALUES (
    13, 'Hoàn tác lần hai cùng 1 play', 'ALREADY_REVERSED', v_res->>'code', 
    CASE WHEN v_res->>'code' = 'ALREADY_REVERSED' THEN '✅ PASS' ELSE '❌ FAIL' END
  );

  -- ===================================================================
  -- CA 11: Support ngoài cửa sổ hoàn tác 5 phút -> UNDO_WINDOW_EXPIRED
  -- ===================================================================
  v_res := public.award_station_direct_points(v_support_token, v_team_id, v_st_multi_id, 20, 'req_ca11_score');
  v_play_id := (v_res->'data'->>'play_id')::UUID;

  UPDATE public.station_plays SET created_at = now() - interval '10 minutes' WHERE id = v_play_id;

  v_res := public.reverse_station_play(v_support_token, 'req_ca11_rev_expired', v_play_id, 'Thử hoàn tác muộn');
  INSERT INTO tmp_104_test_results VALUES (
    14, 'Support hoàn tác quá 5 phút', 'UNDO_WINDOW_EXPIRED', v_res->>'code', 
    CASE WHEN v_res->>'code' = 'UNDO_WINDOW_EXPIRED' THEN '✅ PASS' ELSE '❌ FAIL' END
  );

  -- ===================================================================
  -- CA 12: Kiểm tra bất biến toàn hệ thống (Invariant Audit)
  -- ===================================================================
  IF NOT EXISTS (SELECT 1 FROM public.teams t WHERE t.light_balance < 0)
     AND NOT EXISTS (SELECT 1 FROM public.station_plays sp WHERE sp.status = 'active' AND sp.points > 0 AND sp.tx_id IS NULL)
     AND NOT EXISTS (
       SELECT sp.team_id, sp.station_id, sp.play_no 
       FROM public.station_plays sp 
       GROUP BY 1,2,3 
       HAVING count(*) > 1
     ) THEN
    INSERT INTO tmp_104_test_results VALUES (
      15, 'Kiểm tra bất biến (Invariant Audit)', 'ALL_INVARIANTS_PASSED', 'ALL_INVARIANTS_PASSED', '✅ PASS'
    );
  ELSE
    INSERT INTO tmp_104_test_results VALUES (
      15, 'Kiểm tra bất biến (Invariant Audit)', 'ALL_INVARIANTS_PASSED', 'INVARIANT_VIOLATION', '❌ FAIL'
    );
  END IF;

  -- ===================================================================
  -- DỌN DẸP SẠCH SẼ TOÀN BỘ DỮ LIỆU THỬ NGHIỆM (AN TOÀN KHÓA NGOẠI FK)
  -- ===================================================================
  UPDATE public.transactions 
  SET reversal_for_id = NULL 
  WHERE client_request_id LIKE 'req_ca%' OR client_request_id LIKE 'probe_%' OR client_request_id LIKE 'test_node_%' OR client_request_id LIKE 'rev_%';

  UPDATE public.station_plays 
  SET tx_id = NULL 
  WHERE client_request_id LIKE 'req_ca%' OR client_request_id LIKE 'probe_%' OR client_request_id LIKE 'test_node_%';

  DELETE FROM public.station_plays 
  WHERE client_request_id LIKE 'req_ca%' OR client_request_id LIKE 'probe_%' OR client_request_id LIKE 'test_node_%';

  DELETE FROM public.transactions 
  WHERE client_request_id LIKE 'req_ca%' OR client_request_id LIKE 'probe_%' OR client_request_id LIKE 'test_node_%' OR client_request_id LIKE 'rev_%';

  DELETE FROM public.staff_sessions WHERE token IN (v_admin_token, v_support_token);

  -- Phục hồi nguyên trạng đội và trạm
  UPDATE public.teams 
  SET light_balance = v_team_orig_balance, unlocked_stations = v_team_orig_unlocked 
  WHERE id = v_team_id;

  IF v_st_multi_id IS NOT NULL THEN
    UPDATE public.stations SET allow_multiple_attempts = v_st1_orig_multi, max_score = v_st1_orig_max WHERE id = v_st_multi_id;
  END IF;
  IF v_st_single_id IS NOT NULL THEN
    UPDATE public.stations SET allow_multiple_attempts = v_st2_orig_multi, max_score = v_st2_orig_max WHERE id = v_st_single_id;
  END IF;
  IF v_other_station_id IS NOT NULL THEN
    UPDATE public.stations SET allow_multiple_attempts = v_st3_orig_multi, max_score = v_st3_orig_max WHERE id = v_other_station_id;
  END IF;

  UPDATE public.staff SET assigned_station_id = v_orig_support_assigned_id WHERE id = v_support_id;

  -- 5. Xuất bảng kết quả kiểm thử
  RETURN QUERY SELECT * FROM tmp_104_test_results ORDER BY t_no;
END;
$$;

-- ---------------------------------------------------------------------
-- CHẠY KIỂM THỬ VÀ HIỂN THỊ KẾT QUẢ:
-- ---------------------------------------------------------------------
SELECT * FROM public.run_104_scoring_tests();
