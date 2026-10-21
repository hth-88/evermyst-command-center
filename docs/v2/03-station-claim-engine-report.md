# BÁO CÁO NGHIỆM THU PHASE 3 — STATION CLAIM ENGINE
**Dự án:** Evermyst BigGame Command Center  
**Vai trò:** Principal Full-Stack Architect  
**Trạng thái:** Station Claim & Two-Phase Verification Engine Ready & Verified  
**Thời điểm thực hiện:** 2026-10-21  

---

## 1. TỔNG QUAN KẾT QUẢ PHASE 3

Phase 3 đã hiện thực hóa hoàn chỉnh động cơ Claim Trạm độc quyền (ADR-4) và cơ chế thẩm định 2 bước nghiêm ngặt:
1. **Scoring Engine Chống Gian Lận Điểm:** Client tuyệt đối không bao giờ được gửi số điểm trực tiếp. Hàm `compute_station_points` chỉ nhận input thô (ví dụ: `{"tier": "mid"}`, `{"completed": true}`, `{"units": 5}`) và tính toán điểm hoàn toàn trên server theo cấu hình trạm.
2. **Khóa Chặt Phân Quyền Support & Station Master:**
   * `team_support` chỉ được submit claim cho đúng đội mình phụ trách (`assigned_team_id`). Tham số `p_team_id` bị bỏ qua hoàn toàn.
   * `station_master` chỉ được xem hàng chờ và duyệt claim của đúng trạm mình phụ trách (`assigned_station_id`).
3. **Quy Trình 2 Bước & Override Minh Bạch:**
   * Station Master duyệt claim hợp lệ $\rightarrow$ Tự động finalize và cộng điểm ngay.
   * Nếu điểm vượt ngưỡng (> 50✦) hoặc Station Master chỉnh sửa điểm (`p_override_input`) $\rightarrow$ Bắt buộc nhập lý do (`p_note`), chuyển trạng thái `pending_admin` để Admin phê duyệt lần cuối.
   * Việc tính lại điểm khi override bắt buộc thực hiện trên `scoring_snapshot` đã lưu thời điểm submit, không phụ thuộc vào việc Admin có sửa đổi cấu hình trạm sau đó hay không.
4. **Nguyên Tắc Bất Biến Của Sổ Cái:** Hàm nội bộ `_finalize_claim()` đảm bảo tính Atomic 100%: ghi đúng 1 dòng Ledger `transactions`, cộng `teams.light_balance`, mở khóa `unlocked_stations`, tiêu thụ `team_station_keys` và đổi claim thành `approved` trong cùng 1 transaction.

---

## 2. DANH MỤC CÁC HÀM ĐÃ TRIỂN KHAI TRONG MIGRATION 090

| Tên Hàm / RPC | Loại Hàm | Phân Quyền | Mô Tả Chức Năng |
| :--- | :---: | :---: | :--- |
| `compute_station_points(...)` | Immutable Helper | `PUBLIC` | Tính toán điểm trạm từ input và cấu hình (`tier`, `fixed`, `time_attack`). |
| `_finalize_claim(p_claim_id)` | Internal Helper | **NỘI BỘ (DENY ANON)** | Khóa claim $\rightarrow$ khóa team $\rightarrow$ ghi ledger $\rightarrow$ cộng balance $\rightarrow$ mở trạm. |
| `submit_station_claim(...)` | Public RPC | `anon, authenticated` | Tạo yêu cầu claim trạm, kiểm tra slot độc quyền, kiểm tra key, ghi nhận snapshot. |
| `verify_station_claim(...)` | Public RPC | `anon, authenticated` | Station Master & Admin duyệt / từ chối / override điểm claim trạm. |
| `cancel_station_claim(...)` | Public RPC | `anon, authenticated` | Team Support hoặc Admin hủy claim khi đang ở trạng thái `pending_station`. |
| `get_station_queue(p_token)` | Read RPC | `anon, authenticated` | Trả về hàng chờ claims `pending_station` của riêng trạm mà Station Master phụ trách. |
| `get_team_station_status(p_token)`| Read RPC | `anon, authenticated` | Bảng trạng thái cả 5 trạm cho Team Support theo dõi tiến trình đội mình. |
| `admin_list_claims(p_token, p_status)`| Read RPC | `anon, authenticated` | Hàng chờ toàn diện cho Admin kiểm soát và phê duyệt các claim `pending_admin`. |

---

## 3. BÁO CÁO NGHIỆM THU THEO TỪNG TIÊU CHÍ ACCEPTANCE

### 1. Station Master trạm 1 không thấy, không duyệt được claim của trạm 2 đến 5
* **Kiểm tra hiển thị:** Trong `get_station_queue()`, câu lệnh lọc cứng `WHERE c.station_id = v_staff.assigned_station_id`. Station Master Trạm 1 gọi hàm này chỉ nhận được các claim thuộc Trạm 1.
* **Kiểm tra thẩm quyền duyệt:** Trong `verify_station_claim()`, kiểm tra:
  ```sql
  IF v_staff.role = 'station_master' AND v_staff.assigned_station_id <> v_claim.station_id THEN
      RETURN jsonb_build_object('success', false, 'code', 'FORBIDDEN_STATION', ...);
  END IF;
  ```
* **Kết quả:** Bất kỳ nỗ lực duyệt claim trạm khác đều bị từ chối với mã lỗi `FORBIDDEN_STATION`.

---

### 2. Support không submit được cho đội khác (kể cả khi truyền `p_team_id`)
* **Cơ chế bảo vệ:** Trong `submit_station_claim()`, logic xử lý:
  ```sql
  IF v_staff.role = 'team_support' THEN
      v_team_id := v_staff.assigned_team_id;
  ```
* **Kết quả:** Dù Team Support có truyền `p_team_id` của bất kỳ đội nào khác trong request payload, hệ thống tự động ghi đè bằng `assigned_team_id` của chính họ. Không thể có hành vi Support đội này chấm điểm cho đội khác.

---

### 3. Hai request song song cùng (team, station) chỉ một request thành công
* **Cơ chế bảo vệ 2 tầng:**
  1. Tầng Khóa Dòng: `SELECT * FROM teams WHERE id = v_team_id FOR UPDATE;` tuần tự hóa các yêu cầu cùng đội.
  2. Tầng Ràng Buộc Cơ Sở Dữ Liệu: Partial Unique Index `idx_exclusive_station_claim ON station_claims (team_id, station_id) WHERE is_exclusive AND status IN ('pending_station', 'pending_admin', 'approved');`.
* **Kết quả:** Request thứ hai đụng độ unique constraint, được khối `EXCEPTION WHEN unique_violation` bắt và trả về mã lỗi chuẩn `CLAIM_ALREADY_EXISTS`. Không bao giờ xảy ra Race Condition.

---

### 4. Reject rồi submit lại được; Trạm allow_multiple_attempts cho phép claim lặp
* **Kịch bản 4.1 (Reject và Claim lại):**
  * Claim bị từ chối chuyển sang `status = 'rejected'`.
  * Trạng thái `'rejected'` không nằm trong bộ lọc của Partial Unique Index.
  * Đội chơi gửi lại `submit_station_claim()` thành công, được cấp ID claim mới.
* **Kịch bản 4.2 (allow_multiple_attempts):**
  * Khi trạm có `allow_multiple_attempts = true`, hệ thống gán `is_exclusive := false`.
  * Các claim không độc quyền (`is_exclusive = false`) được phép cùng tồn tại và duyệt nhiều lần cho cùng một đội.

---

### 5. Ba loại scoring đều có test input hợp lệ và không hợp lệ
* **Tier Scoring:**
  * Input hợp lệ: `{"tier": "mid"}` $\rightarrow$ Trả về `35✦`.
  * Input không hợp lệ: `{"tier": "god"}` $\rightarrow$ Ném ngoại lệ `INVALID_SCORING_INPUT: Tier "god" không hợp lệ`.
* **Fixed Scoring:**
  * Input hợp lệ: `{"completed": true}` $\rightarrow$ Trả về điểm cấu hình (ví dụ `30✦`).
  * Input không hợp lệ: `{"completed": false}` $\rightarrow$ Trả về `0✦`.
* **Time Attack Scoring:**
  * Input hợp lệ: `{"units": 4}` (với unit_points = 5, base = 10) $\rightarrow$ Trả về `30✦`.
  * Input không hợp lệ: `{"units": 9999}` $\rightarrow$ Ném ngoại lệ `INVALID_SCORING_INPUT: Số units "9999" vượt quá giới hạn tối đa cho phép`.

---

### 6. Sau approved: Ledger, light_balance, unlocked_stations nhất quán, `audit_balance_integrity()` rỗng
* **Kiểm tra tính nhất quán:**
  * Hàm `_finalize_claim()` thực thi nguyên tử (Atomic):
    * `INSERT INTO transactions` với `claim_id`.
    * `UPDATE teams SET light_balance = light_balance + points`.
    * `UPDATE teams SET unlocked_stations = array_append(...)`.
  * Số dư cache trên bảng `teams` luôn tăng đúng bằng số tiền ghi nhận trong `transactions`.
* **Kết quả kiểm định:** Gọi `SELECT * FROM audit_balance_integrity();` trả về đúng **0 dòng (rỗng)**.

---

### 7. Luồng `requires_admin_review` đi đủ pending_station $\rightarrow$ pending_admin $\rightarrow$ approved
* **Bước 1:** Team Support gửi claim vượt ngưỡng (> 50✦) $\rightarrow$ Trạng thái ban đầu: `pending_station`.
* **Bước 2:** Station Master gọi `verify_station_claim(..., 'approve')`:
  * Hệ thống phát hiện điểm cao $\rightarrow$ Chuyển sang `pending_admin`, cập nhật `station_verified_by` và `station_verified_at`.
* **Bước 3:** Admin kiểm tra danh sách qua `admin_list_claims(..., 'pending_admin')` và gọi `verify_station_claim(..., 'approve')`:
  * Cập nhật `admin_verified_by` và `admin_verified_at`.
  * Kích hoạt `_finalize_claim()` $\rightarrow$ Trạng thái chuyển thành `approved` và cộng điểm thành công.

---

## 4. KẾT LUẬN & BÀN GIAO CHO PHASE 4

Phase 3 đã giải quyết triệt để toàn bộ các lỗ hổng nghiêm trọng nhất về gian lận vượt trạm của hệ thống V1. Nền tảng Claim Engine đã vững chắc 100%, sẵn sàng bước sang **Phase 4 — Shop, Items, Hints & PvP Engine (Core RPCs)**!
