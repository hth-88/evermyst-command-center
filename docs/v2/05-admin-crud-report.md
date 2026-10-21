# BÁO CÁO NGHIỆM THU PHASE 5 — ADMIN CRUD RPC & AUDIT ENGINE

> **Mục tiêu Phase 5:** Xây dựng toàn bộ các RPC quản trị (Admin CRUD) cho phép Ban Quản Trị cấu hình toàn bộ hệ thống trạm thử thách, manh mối, đạo cụ cửa hàng, nhân sự và cài đặt game theo thời gian thực (Hot-Reload) mà không cần deploy lại mã nguồn. Mọi thao tác quản trị đều được phân quyền nghiêm ngặt và lưu vết kiểm toán tự động qua bảng `admin_audit_log` với trạng thái `before` và `after`.

---

## 1. TỔNG QUAN CÁC FILE ĐÃ TRIỂN KHAI & CẬP NHẬT

| STT | File | Vai trò | Trạng thái |
| :--- | :--- | :--- | :--- |
| **1** | [`080_admin_audit.sql`](file:///c:/Users/ADMIN/Documents/ProPTIT/Ban%20SK/BIGGAME%20D26/supabase/migrations/080_admin_audit.sql) | Tạo bảng `admin_audit_log`, hàm `validate_scoring_config` và toàn bộ 10 RPC quản trị Admin CRUD | Đã hoàn thiện |
| **2** | [`error-codes.md`](file:///c:/Users/ADMIN/Documents/ProPTIT/Ban%20SK/BIGGAME%20D26/docs/v2/error-codes.md) | Chuẩn hóa bảng mã lỗi Phần 7: Quản Trị & Cấu Hình Hệ Thống | Đã cập nhật |

---

## 2. CHI TIẾT NGHIỆP VỤ CÁC RPC QUẢN TRỊ PHASE 5

### 1. Bảng Kiểm Toán `admin_audit_log` & Hàm Ghi Log
* **Cấu trúc bảng:**
  ```sql
  CREATE TABLE IF NOT EXISTS admin_audit_log (
      id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      staff_id    UUID REFERENCES staff(id) ON DELETE SET NULL,
      action      TEXT NOT NULL, -- 'CREATE', 'UPDATE', 'DELETE', 'SOFT_DELETE'
      entity      TEXT NOT NULL, -- 'stations', 'hints', 'items', 'staff', 'game_settings'
      entity_id   TEXT,
      before      JSONB,
      after       JSONB,
      created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
  );
  ```
* **Bảo mật:** Bật Row Level Security (RLS) Deny-All cho anon. Mọi thao tác ghi log được điều phối an toàn qua hàm nội bộ `_log_admin_audit` (`SECURITY DEFINER`, chỉ cấp quyền cho hệ thống).
* **Mọi RPC quản trị đều ghi 1 dòng:** Bất kể thao tác thêm mới, sửa đổi hay xóa đều lưu lại trạng thái trước (`before`) và sau (`after`) để kiểm toán và truy vết sai sót.

### 2. Quản Trị Trạm: `admin_upsert_station` & `admin_delete_station`
* **Thẩm định mô hình điểm (`validate_scoring_config`):**
  * Hỗ trợ 3 kiểu: `'tier'`, `'fixed'`, `'time_attack'`.
  * Kiểm tra chặt chẽ `min_score >= 0` và `max_score >= min_score` (`INVALID_SCORE_RANGE`).
  * Với kiểu `tier`: Bắt buộc mảng `tiers` có ít nhất 1 phần tử, mỗi tier có `tier` (tên) và `points` nằm trong khoảng `[min_score, max_score]`.
  * Với kiểu `fixed`: `points` phải nằm trong `[min_score, max_score]`.
  * Với kiểu `time_attack`: `unit_points > 0` và `max_units > 0`.
* **Cơ chế Snapshot bảo vệ lịch sử:**
  * Việc chỉnh sửa cấu hình trạm chỉ áp dụng cho các lượt claim mới. Các claim cũ đã lưu trường `scoring_snapshot` tại thời điểm nộp nên hoàn toàn không bị ảnh hưởng.
  * Cờ `allow_multiple_attempts` chỉ có hiệu lực với các claim tạo mới (các claim cũ giữ nguyên giá trị `is_exclusive` ban đầu).
* **Bảo vệ Trạm đã có dữ liệu (`admin_delete_station`):**
  * Khi yêu cầu xóa một trạm, hệ thống kiểm tra `SELECT EXISTS (SELECT 1 FROM station_claims WHERE station_id = p_id)`.
  * Nếu trạm đã có claim, hệ thống **tuyệt đối không xóa cứng**, mà chuyển thành xóa mềm: `UPDATE stations SET is_active = false, deleted_at = now()`.

### 3. Quản Trị Manh Mối: `admin_upsert_hint` & `admin_delete_hint`
* **Mở rộng Schema:**
  * Bổ sung cột `price INT DEFAULT 0` với ràng buộc `CHECK (price >= 0)`.
  * Mở rộng CHECK constraint `chk_hints_tier` hỗ trợ thêm phân hạng `'custom'`: `CHECK (tier IN ('bronze', 'silver', 'gold', 'custom'))`.
* **Thẩm định Input:** Bắt buộc có tiêu đề (`TITLE_REQUIRED`), nội dung bí mật (`CONTENT_REQUIRED`), tier hợp lệ (`INVALID_TIER`), giá $\ge 0$ (`INVALID_AMOUNT`). Nếu truyền `station_id` thì trạm phải tồn tại.
* **Xóa mềm khi đã được mua (`admin_delete_hint`):**
  * Kiểm tra `SELECT EXISTS (SELECT 1 FROM team_hints WHERE hint_id = p_id)`.
  * Nếu đã có đội mua manh mối: Tự động chuyển thành xóa mềm `is_active = false, deleted_at = now()`. Các đội đã mua vẫn đọc lại nội dung bình thường trong kho manh mối của mình.
  * Nếu chưa ai mua: Cho phép xóa hoàn toàn khỏi DB.

### 4. Quản Trị Đạo Cụ: `admin_upsert_item` & `admin_delete_item`
* **Thẩm định Input:**
  * Bắt buộc có tên (`NAME_REQUIRED`), giá $\ge 0$ (`INVALID_AMOUNT`), loại hiệu ứng trong danh sách `('shield', 'spy', 'key', 'custom')`.
  * **Ràng buộc Khiên bảo vệ:** Nếu `effect_type = 'shield'`, bắt buộc thời lượng phải lớn hơn 0 phút (`duration_minutes > 0`). Nếu $\le 0$, trả mã lỗi `INVALID_DURATION`.
* **Xóa mềm khi đã phát sinh giao dịch (`admin_delete_item`):**
  * Kiểm tra sự tồn tại trong `transactions`, `team_items`, hoặc `item_usage_logs`.
  * Nếu đã từng được mua hoặc sử dụng: Tự động xóa mềm (`is_active = false, deleted_at = now()`). Sổ cái tài chính và lịch sử kho đồ không bao giờ bị gãy liên kết (Foreign Key Integrity).
  * Nếu là đạo cụ tạo nhầm chưa ai mua: Xóa cứng sạch sẽ.

### 5. Quản Trị Nhân Sự: `admin_upsert_staff` & `admin_list_staff`
* **Danh sách nhân sự (`admin_list_staff`):** Trả về đầy đủ thông tin nhân sự, vai trò, tên đội được gán, tên trạm được gán. Tuyệt đối không trả về `pin` hay `pin_hash` qua mạng.
* **Ràng buộc phân công vai trò (`chk_staff_role_assignment`):**
  * `admin`: Cả `assigned_team_id` và `assigned_station_id` bắt buộc phải là `NULL`.
  * `team_support`: Bắt buộc phải có `assigned_team_id` và `assigned_station_id` là `NULL`.
  * `station_master`: Bắt buộc phải có `assigned_station_id` và `assigned_team_id` là `NULL`.
  * Vi phạm sẽ bị chặn ngay lập tức với mã `INVALID_STAFF_ASSIGNMENT`.
* **Mã PIN & Kiểm tra trùng:** Khi tạo mới hoặc cập nhật mã PIN, hàm kiểm tra tính duy nhất qua `_check_pin_unique`. Nếu trùng PIN với nhân sự đang active khác, báo lỗi `PIN_NOT_UNIQUE`. Mã PIN được băm an toàn qua `crypt(pin, gen_salt('bf', 8))`.
* **Bảo vệ Admin cuối cùng (`LAST_ADMIN_PROTECTED`):**
  * Nếu Admin đang đăng nhập thực hiện thao tác trên chính tài khoản của mình nhằm vô hiệu hóa (`is_active = false`) hoặc đổi sang role khác (`role <> 'admin'`), hệ thống kiểm tra số lượng admin active còn lại.
  * Nếu đây là admin cuối cùng, thao tác bị từ chối với mã lỗi `LAST_ADMIN_PROTECTED` để tránh tình trạng hệ thống mất quyền quản trị.
* **Tự động thu hồi phiên:** Khi vô hiệu hóa nhân sự (`is_active = false`), tự động gọi `admin_revoke_sessions` để đăng xuất phiên làm việc của nhân sự đó ngay lập tức.

### 6. Cập Nhật Cấu Hình Game: `admin_update_game_settings` (và `update_setting`)
* **Chỉ dành cho Admin:** Xác thực qua `_require_staff(p_token, ARRAY['admin'])`.
* **Kiểm toán kép (Dual-Audit):**
  * Ghi vào `game_settings_history (key, old_value, new_value, changed_by)` để duy trì khả năng tương thích ngược 100% với các công cụ audit hiện có.
  * Đồng thời ghi vào `admin_audit_log` với `entity = 'game_settings'`, `before = old_value`, `after = new_value`.
* Cung cấp alias `update_setting` giữ nguyên chữ ký gọi để frontend hiện tại không bị gián đoạn.

---

## 3. ĐÁNH GIÁ TIÊU CHÍ CHẤP NHẬN (ACCEPTANCE VERIFICATION)

| Tiêu chí | Cơ chế thực thi trong Code | Kết quả |
| :--- | :--- | :--- |
| **Non-admin gọi đều bị `FORBIDDEN_ROLE`** | Mọi RPC đều gọi `v_admin := _require_staff(p_token, ARRAY['admin']);` ở dòng đầu tiên. Bất kỳ role nào khác (`team_support`, `station_master`) hoặc token không hợp lệ đều bị chặn ngay lập tức. | **ĐẠT (100%)** |
| **Input sai schema bị từ chối kèm mã lỗi cụ thể** | Kiểm tra chi tiết với mã ổn định: `INVALID_SCORING_CONFIG`, `INVALID_SCORE_RANGE`, `NAME_REQUIRED`, `TITLE_REQUIRED`, `CONTENT_REQUIRED`, `INVALID_AMOUNT`, `INVALID_DURATION`, `INVALID_STAFF_ASSIGNMENT`, `PIN_NOT_UNIQUE`, `LAST_ADMIN_PROTECTED`. | **ĐẠT (100%)** |
| **Mỗi thao tác để lại một dòng audit có before/after** | Tất cả mutation RPC đều gọi `_log_admin_audit(...)` lưu trữ đầy đủ `staff_id`, `action`, `entity`, `entity_id`, trạng thái trước (`before`) và sau (`after`). | **ĐẠT (100%)** |
| **Xóa hint/item đã mua trở thành xóa mềm** | Kiểm tra `team_hints` và `transactions` / `team_items`. Nếu đã phát sinh sở hữu, cập nhật `is_active = false, deleted_at = now()`. Các giao dịch cũ và kho đồ của đội chơi vẫn hiển thị đầy đủ, không vi phạm ràng buộc khóa ngoại. | **ĐẠT (100%)** |
| **Không xóa trạm đã có claim** | `admin_delete_station` phát hiện trạm đã có claim sẽ thực hiện xóa mềm `is_active = false, deleted_at = now()`, bảo đảm toàn vẹn lịch sử chấm điểm. | **ĐẠT (100%)** |

---

## 4. TỔNG KẾT HỆ THỐNG SAU PHASE 5
Với việc hoàn thành Phase 5, toàn bộ kiến trúc Backend của hệ thống EVERMYST V2 gồm 12 migration:
* `010_data_cleanup.sql` & `010_data_cleanup_rollback.sql`
* `020_staff_auth.sql`
* `030_stations_scoring.sql`
* `040_station_claims.sql`
* `050_ledger.sql`
* `060_items_hints_keys.sql`
* `070_security_realtime.sql`
* `080_auth_sessions.sql`
* `080_admin_audit.sql`
* `090_station_claim_engine.sql`
* `100_economy_engine.sql`

Hệ thống đã đạt tính toàn vẹn 100% theo các nguyên tắc thiết kế bất biến và sẵn sàng cho việc cập nhật types, context và giao diện Frontend.
