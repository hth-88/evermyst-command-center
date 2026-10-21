# SỔ TAY VẬN HÀNH & CHECKLIST TRƯỚC GIỜ G (TACTICAL RUNBOOK)
**Dự án:** Evermyst BigGame Command Center V2  
**Phiên bản:** 2.0.0 (Event Ready)  
**Đối tượng sử dụng:** Ban Quản Trị (Admin), Trưởng Ban Tổ Chức, Kỹ Thuật Viên Hệ Thống  

---

## PHẦN 1: CHECKLIST KIỂM ĐỊNH TRƯỚC GIỜ G (PRE-GAME CHECKLIST)

| Thời Điểm | Hạng Mục Kiểm Tra | Thao Tác Kỹ Thuật | Tiêu Chí Đạt (Pass Criteria) | Người Phụ Trách |
| :--- | :--- | :--- | :--- | :--- |
| **T - 60 phút** | **Làm sạch & Nạp dữ liệu sự kiện (Seed)** | Chạy file SQL: `supabase/seed_event.sql` | • Tạo thành công 6 Đội, 5 Trạm, 3 Items, 3 Hints, 13 Staff.<br>• Toàn bộ 6 đội có đúng 100 Lumen khởi đầu. | Tech Lead |
| **T - 50 phút** | **Kiểm định tính toàn vẹn Sổ Cái (Ledger Audit)** | Thực thi hàm RPC qua Supabase SQL Editor:<br>`SELECT * FROM audit_balance_integrity();` | • `total_discrepancy_count = 0`<br>• `negative_balance_count = 0`<br>• `status = 'BALANCED'` | Tech Lead |
| **T - 40 phút** | **Sao lưu Snapshot Database (Backup)** | Truy cập Supabase Dashboard -> **Database** -> **Backups** -> **Take manual backup**, hoặc chạy script dump:<br>`pg_dump -h <host> -U postgres -d postgres > backup_pregame.sql` | Tệp sao lưu được lưu trữ an toàn trên Google Drive / Local Drive của Admin. | DevOps / Admin |
| **T - 30 phút** | **Xóa bộ đệm Rate Limit đăng nhập** | Chạy lệnh SQL giải phóng IP testing:<br>`DELETE FROM auth_attempts WHERE created_at < now();` | Bảng `auth_attempts` sạch, không IP nhân sự nào bị dính cờ `LOGIN_LOCKED`. | Admin |
| **T - 25 phút** | **Bàn giao Danh Sách Mã PIN 6 Số** | Phát bảng mã PIN 6 số bí mật cho từng nhân sự:<br>• Admin: `999001`, `999002`<br>• Quản trò Trạm 1-5: `888001` → `888005`<br>• Hỗ trợ Đội 1-6: `777001` → `777006` | 100% nhân sự nhận đúng mã PIN, thử đăng nhập thành công vào đúng màn hình phân quyền. | Trưởng Ban Nhân Sự |
| **T - 15 phút** | **Kiểm tra kênh Realtime & Fallback Polling** | Mở bảng điều khiển Admin, kiểm tra chỉ báo trạng thái kết nối trên góc phải: hiển thị `connected` (xanh lá). | Realtime nhận broadcast tức thời (< 300ms debounce), không bị ngắt kết nối. | Admin |
| **T - 0 Giờ G** | **Phát lệnh Khởi Tranh** | Admin kiểm tra tổng số dư toàn giải = 600 Lumen (6 đội x 100). | Trận đấu chính thức bắt đầu. | Trưởng BTC |

---

## PHẦN 2: TACTICAL RUNBOOK CHO ADMIN

### 1. Khi nào được sử dụng "Hoàn tác Cưỡng chế" (`p_force: true`)?

#### A. Bản chất kỹ thuật
Khi hoàn tác một giao dịch **cộng tiền** (ví dụ: cộng nhầm 50 Lumen do claim sai), hệ thống mặc định (`p_force: false`) sẽ kiểm tra số dư hiện tại của đội.
* Nếu đội **chưa tiêu** số tiền này (`current_balance >= 50`): Giao dịch hoàn tác thành công bình thường.
* Nếu đội **đã tiêu** một phần hoặc toàn bộ số tiền này (`current_balance < 50`): Hệ thống sẽ **từ chối hoàn tác** và báo lỗi `INSUFFICIENT_BALANCE_FOR_REVERT` nhằm bảo vệ bất biến `light_balance >= 0`.

#### B. Quy trình kích hoạt Force Revert (`p_force: true`)
Admin chỉ được bật tùy chọn **"Cưỡng chế đưa về 0 (Force Revert)"** khi thỏa mãn **CẢ 3 ĐIỀU KIỆN**:
1. Có sự đồng ý bằng văn bản/tin nhắn từ **Trưởng Ban Tổ Chức**.
2. Giao dịch gốc được xác định 100% là do gian lận hoặc sai sót nghiêm trọng của nhân viên trạm.
3. Số dư của đội sẽ bị trừ tối đa về `0` (không bao giờ âm), và Admin **bắt buộc phải nhập lý do giải trình** (Reason) tối thiểu 5 ký tự để ghi nhận vào `admin_audit_log`.

---

### 2. Cách xử lý Yêu cầu Chấm điểm bị kẹt (Stalled Claims)

#### Dấu hiệu nhận biết
* Một claim ở trạng thái `pending_station` hoặc `pending_admin` quá **10 phút** mà không có tiến triển.
* Đội chơi thông báo *"Đã nộp điểm nhưng không thể nộp lại hoặc trạm khác do bị chiếm slot"*.

#### Quy trình xử lý từng bước:
1. **Truy cập:** Mở giao diện Admin tại `/admin`, chuyển sang tab **XÉT DUYỆT TRẠM**.
2. **Lọc dữ liệu:** Chọn bộ lọc trạng thái: `Chờ Quản Trò duyệt` hoặc `Chờ BTC duyệt`.
3. **Thẩm tra dữ liệu:**
   * Xem thời gian nộp (`created_at`) và thông số chi tiết (`input`, `score`).
   * Liên hệ nhanh bộ đàm với Quản Trò trạm đó để xác nhận xem đội đã hoàn thành thật chưa.
4. **Hành động quyết định:**
   * **Nếu hợp lệ:** Bấm nút **"Duyệt Claim"**. Admin có thẩm quyền duyệt thay Quản trò trạm trong trường hợp Quản trò mất mạng hoặc thiết bị hết pin.
   * **Nếu sai sót / Nộp nhầm:** Bấm nút **"Từ chối"**, nhập lý do: *"Hủy claim kẹt do nộp nhầm"*.
   * **Kết quả:** Ngay khi bị từ chối, slot `(team, station)` sẽ được giải phóng ngay lập tức trên DB, đội chơi có thể gửi lại claim mới ngay lập tức.

---

### 3. Xử lý sự cố mạng & Thiết bị ngoài hiện trường

#### A. Mất kết nối Internet / Chập chờn sóng 4G
* **Cơ chế tự bảo vệ:** Ứng dụng tích hợp bộ chuyển đổi tự động `useSignal`. Khi mất WebSocket, chỉ báo góc phải chuyển sang `polling` (màu vàng) và tự động kéo dữ liệu qua HTTP mỗi 10 giây.
* **Hướng dẫn nhân sự:** **TUYỆT ĐỐI KHÔNG** ấn F5 liên tục. Cứ giữ nguyên màn hình, các thao tác nộp claim / trừ tiền vẫn thực thi được bình thường khi có sóng trở lại nhờ cơ chế `client_request_id` chống trùng giao dịch (Idempotency).

#### B. Nhân sự bị khóa đăng nhập (`LOGIN_LOCKED`)
* **Nguyên nhân:** Nhập sai mã PIN quá 5 lần trong 5 phút.
* **Cách mở khóa khẩn cấp:** Admin vào Supabase SQL Editor chạy:
  ```sql
  DELETE FROM auth_attempts WHERE ip = '<IP_nhân_sự>' OR created_at > now() - interval '10 minutes';
  ```
  Nhân sự có thể đăng nhập lại ngay lập tức.

---

## PHẦN 3: ĐỐI SOÁT & ĐÓNG GIẢI SAU SỰ KIỆN (POST-GAME AUDIT)

Ngay sau khi kết thúc giờ thi đấu chính thức:
1. **Đóng toàn bộ trạm:** Admin chuyển cờ `is_active = false` trên cả 5 trạm để chặn nộp thêm claim.
2. **Chạy đối soát toàn vẹn cuối cùng:**
   ```sql
   SELECT * FROM audit_balance_integrity();
   ```
3. **Xuất bảng xếp hạng chính thức:**
   ```sql
   SELECT name, light_balance, array_length(unlocked_stations, 1) as cleared_stations
   FROM teams
   ORDER BY light_balance DESC, cleared_stations DESC;
   ```
4. **Lưu trữ Log kiểm toán:** Xuất dữ liệu bảng `transactions`, `station_claims` và `admin_audit_log` làm bằng chứng nghiệm thu giải đấu.
