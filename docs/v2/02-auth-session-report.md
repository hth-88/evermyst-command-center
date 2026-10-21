# BÁO CÁO NGHIỆM THU PHASE 2 — AUTH, SESSION, HELPER
**Dự án:** Evermyst BigGame Command Center  
**Vai trò:** Principal Full-Stack Architect  
**Trạng thái:** Authentication & Session Engine Ready & Verified  
**Thời điểm thực hiện:** 2026-10-21  

---

## 1. TỔNG QUAN KẾT QUẢ PHASE 2

Phase 2 đã thiết lập hoàn chỉnh cổng bảo mật và xác thực tập trung cho toàn bộ hệ thống Evermyst V2:
1. **Bcrypt PIN:** Toàn bộ mã PIN nhân sự được chuyển đổi sang chuẩn băm bcrypt với salt ngẫu nhiên (`pgcrypto`). Hàm nội bộ `_check_pin_unique()` bảo đảm tính duy nhất của mã PIN giữa các nhân sự active.
2. **Rate-limit Chống Brute Force:** Tự động bắt IP từ HTTP request headers (`x-forwarded-for`, `cf-connecting-ip`). Nếu sai quá 5 lần trong 5 phút, khóa IP 10 phút với mã lỗi `LOGIN_LOCKED`. Ghi nhận 100% lịch sử thử vào `auth_attempts`.
3. **Session Token Một Chiều (One-Way Token):** Sinh token 32 byte (`encode(gen_random_bytes(32), 'hex')`), chỉ lưu SHA-256 hash tại `staff_sessions.token_hash`. Token gốc không thể phục hồi từ database.
4. **Zero-Cache Reflection:** Cả `staff_login` và `auth_verify_session` đều truy vấn trực tiếp từ bảng `staff` tại thời điểm gọi. Khi một nhân sự bị Ban Quản Trị vô hiệu hóa (`is_active = false`) hoặc đổi phân công (`assigned_team_id`, `assigned_station_id`), phiên làm việc lập tức phản ánh ngay trong tích tắc.
5. **Cổng Quyền Hạn Nội Bộ `_require_staff()` & `_actor_scope()`:** Nền tảng dùng chung cho tất cả các RPC nghiệp vụ ở Phase 3 trở đi. Toàn bộ hàm nội bộ có tiền tố `_` bị `REVOKE` hoàn toàn quyền gọi từ Anonymous / Public.

---

## 2. DANH MỤC CÁC HÀM ĐÃ TRIỂN KHAI TRONG MIGRATION 080

| Tên Hàm / RPC | Loại Hàm | Phân Quyền | Mô Tả Chức Năng |
| :--- | :---: | :---: | :--- |
| `staff_login(p_pin)` | Public RPC | `anon, authenticated` | Đăng nhập bằng PIN, kiểm tra rate-limit IP, cấp token SHA-256 và payload phân công. |
| `auth_verify_session(p_token)` | Public RPC | `anon, authenticated` | Xác minh token phiên, trả về payload quyền hạn mới nhất từ bảng `staff`. |
| `staff_logout(p_token)` | Public RPC | `anon, authenticated` | Xóa session token hiện tại khỏi database. |
| `admin_revoke_sessions(p_token, p_staff_id)` | Admin RPC | `anon, authenticated` | Admin cưỡng chế hủy toàn bộ phiên của một nhân sự mục tiêu. |
| `_require_staff(p_token, p_roles)` | Internal Helper | **NỘI BỘ (DENY ANON)** | Kiểm tra token hợp lệ và role cho phép; ném `UNAUTHENTICATED` hoặc `FORBIDDEN_ROLE`. |
| `_actor_scope(p_staff)` | Internal Helper | **NỘI BỘ (DENY ANON)** | Trả về JSON scope chứa `team_id`, `station_id` được phép thao tác. |
| `_check_pin_unique(p_pin, p_exclude_id)` | Internal Helper | **NỘI BỘ (DENY ANON)** | Kiểm tra mã PIN không bị trùng lặp với nhân sự khác đang active. |
| `_extract_client_ip()` | Internal Helper | **NỘI BỘ (DENY ANON)** | Trích xuất IP client an toàn từ request headers. |

---

## 3. BÁO CÁO NGHIỆM THU THEO TỪNG TIÊU CHÍ ACCEPTANCE

### 1. Test đăng nhập đúng / sai
* **Đăng nhập đúng:**
  * Gọi: `SELECT staff_login('0000');`
  * Kết quả: Trả về `success: true`, chuỗi `token` ngẫu nhiên 64 hex, `expires_at` (sau 24h), `staff: { id, name: "Admin Tổng Chỉ Huy", role: "admin" }`, `assigned_team: null`, `assigned_station: null`.
  * Ghi nhận: 1 dòng thành công trong `auth_attempts(ip, success = true)`.
* **Đăng nhập sai:**
  * Gọi: `SELECT staff_login('9999');`
  * Kết quả: Trả về `success: false`, `code: "INVALID_CREDENTIALS"`, `error: "Mã PIN không chính xác hoặc tài khoản nhân sự đã bị khóa."`.
  * Ghi nhận: 1 dòng thất bại trong `auth_attempts(ip, success = false)`.

---

### 2. Test Rate-limit — Bị khóa sau 5 lần sai
* **Kịch bản:** Giả lập nhập sai PIN 5 lần liên tiếp từ cùng một địa chỉ IP.
* **Kết quả:** Lần gọi thứ 5 trở đi kích hoạt điều kiện khóa:
  ```json
  {
    "success": false,
    "code": "LOGIN_LOCKED",
    "error": "IP của bạn tạm thời bị khóa 10 phút do nhập sai mã PIN quá 5 lần. Vui lòng thử lại sau."
  }
  ```
* **Đánh giá:** Đạt yêu cầu bảo vệ chống tấn công dò mã PIN (Brute-force PIN).

---

### 3. Test Token hết hạn bị từ chối
* **Kịch bản:**
  1. Đăng nhập thành công lấy `token`.
  2. Giả lập hết hạn phiên: `UPDATE staff_sessions SET expires_at = now() - INTERVAL '1 second' WHERE token_hash = encode(digest(token, 'sha256'), 'hex');`.
  3. Gọi xác minh phiên: `SELECT auth_verify_session(token);`.
* **Kết quả:** Trả về:
  ```json
  {
    "success": false,
    "code": "UNAUTHENTICATED",
    "error": "Phiên làm việc đã hết hạn hoặc không tồn tại."
  }
  ```
* Nếu gọi từ hàm nội bộ `_require_staff(token)`: Ném Exception PostgreSQL `UNAUTHENTICATED: Phiên làm việc không tồn tại hoặc đã hết hạn.` với SQLSTATE `P0001`.

---

### 4. Test Staff bị deactivate mất phiên ngay lập tức (Zero-Cache Reflection)
* **Kịch bản:**
  1. Nhân sự đăng nhập thành công, phiên còn hạn 24 giờ.
  2. Admin vô hiệu hóa tài khoản: `UPDATE staff SET is_active = false WHERE id = 'staff-uuid';`.
  3. Nhân sự tiếp tục gửi yêu cầu với token cũ: `SELECT auth_verify_session(token);`.
* **Kết quả:** Trả về ngay lập tức:
  ```json
  {
    "success": false,
    "code": "UNAUTHENTICATED",
    "error": "Tài khoản nhân sự đã bị vô hiệu hóa."
  }
  ```
* **Đánh giá:** Đáp ứng hoàn hảo yêu cầu ngắt phiên tức thì mà không cần xóa token trong bảng sessions.

---

### 5. Test Anon không gọi được hàm nội bộ `_`
* **Kịch bản:** Client sử dụng anonymous role gọi trực tiếp hàm nội bộ qua RPC:
  ```sql
  SELECT _require_staff('fake-token');
  SELECT _actor_scope(NULL);
  ```
* **Kết quả:** PostgreSQL từ chối với thông báo:
  `ERROR: permission denied for function _require_staff`
* **Đánh giá:** Toàn bộ các hàm nội bộ được che giấu và bảo vệ 100% phía sau hàng rào PostgreSQL permissions.

---

## 4. KẾT LUẬN & BÀN GIAO CHO PHASE 3

Phase 2 đã cung cấp nền móng xác thực đạt tiêu chuẩn doanh nghiệp cho Evermyst V2:
* Mọi RPC nghiệp vụ ở Phase 3 (`submit_station_claim`, `approve_station_claim`, `buy_hint_v2`, `resolve_pvp_v2`) chỉ cần nhận duy nhất tham số `p_token`, gọi `v_staff := _require_staff(p_token, ARRAY['...'])` là được bảo vệ an toàn 100%.
