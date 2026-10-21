# BÁO CÁO NGHIỆM THU PHASE 7 — FRONTEND: COMPONENTS, MODALS & DYNAMIC SCORING RENDERER

> **Mục tiêu Phase 7:** Triển khai toàn bộ màn hình, modal và renderer chấm điểm theo Mục 3 của Đặc tả thiết kế và kiến trúc V2. Sử dụng chuẩn xác các RPC Security Definer đã triển khai từ Phase 1 đến Phase 5, bảo đảm:
> - Tuyệt đối không tự suy diễn quyền trên Client (`can_*` lấy 100% từ RPC).
> - Đồng bộ tính toán điểm giữa Client Preview và PostgreSQL Server thông qua bộ fixture JSON chung.
> - Bố cục Mobile tối ưu thao tác một tay cho Support POS và Quản Trò Trạm (Station Master).
> - Ban Quản Trị cấu hình luật chấm điểm linh hoạt mà không cần deploy lại, không làm biến đổi các claim đang chờ.

---

## 1. TỔNG QUAN CÁC FILE ĐÃ TRIỂN KHAI VÀ NÂNG CẤP

| STT | File | Vai trò | Trạng thái |
| :--- | :--- | :--- | :--- |
| **1** | [`src/scoring/types.ts`](file:///c:/Users/ADMIN/Documents/ProPTIT/Ban%20SK/BIGGAME%20D26/src/scoring/types.ts) | Định nghĩa kiểu dữ liệu module scoring: `ScoringType`, `TierScoringConfig`, `FixedScoringConfig`, `TimeAttackScoringConfig`, `ScoringInput`, `ScoringPreviewResult` | Đã hoàn thiện |
| **2** | [`src/scoring/fixtures.json`](file:///c:/Users/ADMIN/Documents/ProPTIT/Ban%20SK/BIGGAME%20D26/src/scoring/fixtures.json) | Bộ test cases fixture JSON chung kiểm thử độ tương thích giữa SQL `compute_station_points` và TypeScript | Đã hoàn thiện |
| **3** | [`src/scoring/preview.ts`](file:///c:/Users/ADMIN/Documents/ProPTIT/Ban%20SK/BIGGAME%20D26/src/scoring/preview.ts) | Hàm `previewPoints`: Tính toán xem trước điểm trực quan trên Client (khớp 100% logic PostgreSQL) | Đã hoàn thiện |
| **4** | [`src/scoring/format.ts`](file:///c:/Users/ADMIN/Documents/ProPTIT/Ban%20SK/BIGGAME%20D26/src/scoring/format.ts) | Hàm `formatScoringInput`: Dịch dữ liệu JSON thô thành nhãn tiếng Việt trực quan cho thẻ duyệt và lịch sử | Đã hoàn thiện |
| **5** | [`src/components/scoring/TierPicker.tsx`](file:///c:/Users/ADMIN/Documents/ProPTIT/Ban%20SK/BIGGAME%20D26/src/components/scoring/TierPicker.tsx) | Component chọn bậc Tier với điểm số và biểu tượng trực quan | Đã hoàn thiện |
| **6** | [`src/components/scoring/UnitStepper.tsx`](file:///c:/Users/ADMIN/Documents/ProPTIT/Ban%20SK/BIGGAME%20D26/src/components/scoring/UnitStepper.tsx) | Bộ tăng giảm đơn vị thời gian / số lượng có min/max, chip chọn nhanh và tính điểm theo công thức | Đã hoàn thiện |
| **7** | [`src/components/scoring/OptionChecklist.tsx`](file:///c:/Users/ADMIN/Documents/ProPTIT/Ban%20SK/BIGGAME%20D26/src/components/scoring/OptionChecklist.tsx) | Danh sách tiêu chí hoàn thành trạm cố định kèm các tùy chọn điểm thưởng (Fixed / Bonus Checklist) | Đã hoàn thiện |
| **8** | [`src/components/scoring/StationScoringForm.tsx`](file:///c:/Users/ADMIN/Documents/ProPTIT/Ban%20SK/BIGGAME%20D26/src/components/scoring/StationScoringForm.tsx) | Renderer chấm điểm động theo `scoring_type`, dùng chung cho Support nộp, Quản Trò duyệt kèm chỉnh & nhập trực tiếp | Đã hoàn thiện |
| **9** | [`src/components/support/SpyModal.tsx`](file:///c:/Users/ADMIN/Documents/ProPTIT/Ban%20SK/BIGGAME%20D26/src/components/support/SpyModal.tsx) | Modal kích hoạt Kính Viễn Vọng: chọn 1 trong 5 đội đối thủ để do thám thông tin tình báo | Đã hoàn thiện |
| **10** | [`src/components/support/RavenEyeModal.tsx`](file:///c:/Users/ADMIN/Documents/ProPTIT/Ban%20SK/BIGGAME%20D26/src/components/support/RavenEyeModal.tsx) | Màn hình hiển thị snapshot tình báo 5 chỉ số (Số dư, Khiên, Trạm hoàn thành, Hint đã mở, Thời điểm quét) | Đã hoàn thiện |
| **11** | [`src/components/support/KeyModal.tsx`](file:///c:/Users/ADMIN/Documents/ProPTIT/Ban%20SK/BIGGAME%20D26/src/components/support/KeyModal.tsx) | Modal kích hoạt Chìa Khóa Cổ Tích: chọn trạm chưa vượt để cấp thẻ qua trạm miễn phí | Đã hoàn thiện |
| **12** | [`src/components/support/StationTab.tsx`](file:///c:/Users/ADMIN/Documents/ProPTIT/Ban%20SK/BIGGAME%20D26/src/components/support/StationTab.tsx) | Danh sách 5 trạm với 5 trạng thái trực quan, khóa khi slot bị chiếm, nút "Rút lại" cho `pending_station`, badge Chìa Khóa | Đã hoàn thiện |
| **13** | [`src/components/support/ShopTab.tsx`](file:///c:/Users/ADMIN/Documents/ProPTIT/Ban%20SK/BIGGAME%20D26/src/components/support/ShopTab.tsx) | Tab Cửa Hàng, Manh Mối và Túi Đồ của đội, tích hợp đầy đủ luồng mua và kích hoạt đạo cụ | Đã hoàn thiện |
| **14** | [`src/components/support/HistoryTab.tsx`](file:///c:/Users/ADMIN/Documents/ProPTIT/Ban%20SK/BIGGAME%20D26/src/components/support/HistoryTab.tsx) | Tab Lịch sử giao dịch: Nút Hoàn tác chỉ hiện khi `can_reverse = true`, hiển thị lý do nếu bị chặn | Đã hoàn thiện |
| **15** | [`src/pages/StationPage.tsx`](file:///c:/Users/ADMIN/Documents/ProPTIT/Ban%20SK/BIGGAME%20D26/src/pages/StationPage.tsx) | Giao diện `/station` cho Quản Trò: Hàng đợi live, 3 nút lớn thao tác một tay, rung & chuông báo Web Audio API, nhập điểm trực tiếp, lịch sử đã xử lý | Đã hoàn thiện |
| **16** | [`src/components/admin/PendingAdminQueue.tsx`](file:///c:/Users/ADMIN/Documents/ProPTIT/Ban%20SK/BIGGAME%20D26/src/components/admin/PendingAdminQueue.tsx) | Hàng chờ duyệt BTC: Bảng so sánh side-by-side dữ liệu gốc vs đã chỉnh, ghi chú Quản trò, badge Chìa Khóa | Đã hoàn thiện |
| **17** | [`src/components/admin/StationEditorModal.tsx`](file:///c:/Users/ADMIN/Documents/ProPTIT/Ban%20SK/BIGGAME%20D26/src/components/admin/StationEditorModal.tsx) | Modal tạo/sửa trạm: Chọn `scoring_type` động, hiển thị form tương ứng, validate trước khi lưu qua RPC | Đã hoàn thiện |
| **18** | [`src/components/admin/HintEditorModal.tsx`](file:///c:/Users/ADMIN/Documents/ProPTIT/Ban%20SK/BIGGAME%20D26/src/components/admin/HintEditorModal.tsx) | Modal tạo/sửa Manh Mối mật: Đầy đủ các trường title, tier, price, content, station_id, is_active | Đã hoàn thiện |
| **19** | [`src/components/admin/ItemEditorModal.tsx`](file:///c:/Users/ADMIN/Documents/ProPTIT/Ban%20SK/BIGGAME%20D26/src/components/admin/ItemEditorModal.tsx) | Modal tạo/sửa Đạo Cụ: name, description, price, effect_type, effect_value, duration_minutes, is_active | Đã hoàn thiện |
| **20** | [`src/components/admin/StaffModal.tsx`](file:///c:/Users/ADMIN/Documents/ProPTIT/Ban%20SK/BIGGAME%20D26/src/components/admin/StaffModal.tsx) | Tab & Modal Nhân Sự: Phân quyền vai trò, gán đội/trạm chặt chẽ, đổi mã PIN bảo mật, thu hồi phiên | Đã hoàn thiện |
| **21** | [`src/components/admin/AdjustBalanceModal.tsx`](file:///c:/Users/ADMIN/Documents/ProPTIT/Ban%20SK/BIGGAME%20D26/src/components/admin/AdjustBalanceModal.tsx) | Modal `± Lumen` cho Admin: Bắt buộc nhập lý do chi tiết, có chip lý do nhanh để ghi sổ kiểm toán | Đã hoàn thiện |
| **22** | [`src/components/admin/ForceRevertModal.tsx`](file:///c:/Users/ADMIN/Documents/ProPTIT/Ban%20SK/BIGGAME%20D26/src/components/admin/ForceRevertModal.tsx) | Hộp thoại xác nhận Hoàn Tác Bắt Buộc (`p_force: true`): Giải trình lý do Admin can thiệp cưỡng chế | Đã hoàn thiện |
| **23** | [`src/pages/AdminPage.tsx`](file:///c:/Users/ADMIN/Documents/ProPTIT/Ban%20SK/BIGGAME%20D26/src/pages/AdminPage.tsx) | Command Center 3 Cột: Cột 1 Leaderboard + ±Lumen, Cột 2 Bàn điều khiển 7 Tabs, Cột 3 Live Sổ Cái & Revert | Đã hoàn thiện |

---

## 2. MODULE SCORING DÙNG CHUNG VÀ ĐỐI SOÁT FIXTURE

### 2.1. Thiết kế Module `src/scoring/`
* **Nguyên tắc phân định trách nhiệm:**
  * Client sử dụng `previewPoints(type, config, input, minScore, maxScore)` **chỉ để nâng cao trải nghiệm người dùng (UX)**, hiển thị số điểm dự kiến sẽ nhận được ngay trên form nộp hoặc thẻ duyệt.
  * **PostgreSQL Server vẫn là nguồn tính điểm chính thức duy nhất** thông qua hàm `compute_station_points(p_type, p_config, p_min, p_max, p_input)`.
* **Bộ test case Fixture chung (`src/scoring/fixtures.json`):**
  * Bao phủ đầy đủ 3 mô hình chấm điểm (`tier`, `fixed`, `time_attack`), các biên kiểm tra `min_score`, `max_score`, `max_units`, và các trường hợp lỗi dữ liệu (ví dụ: `tier` không tồn tại, vượt giới hạn đơn vị).
* **Kết quả chạy kiểm thử tự động:**
  ```text
  --- BẮT ĐẦU TEST FIXTURES SCORING ---
  [PASS] Case tier_valid_mid: tier => points=35, isValid=true
  [PASS] Case tier_valid_low: tier => points=20, isValid=true
  [PASS] Case tier_invalid_missing: tier => points=0, isValid=false
  [PASS] Case fixed_valid_completed: fixed => points=30, isValid=true
  [PASS] Case fixed_valid_incomplete: fixed => points=0, isValid=true
  [PASS] Case time_attack_valid_4_units: time_attack => points=30, isValid=true
  [PASS] Case time_attack_exceed_max_units: time_attack => points=0, isValid=false

  KẾT QUẢ: 7 passed, 0 failed
  ```
* **Đảm bảo:** Hai bên máy trạm và máy chủ không xảy ra bất kỳ sự sai lệch logic nào khi chấm điểm.

---

## 3. COMPONENT `StationScoringForm` (DYNAMIC RENDERER)

Renderer được xây dựng dựa trên `scoring_type` động:
1. **`TierPicker` (Mô hình Bậc hạng / Tier):**
   * Hiển thị lưới các mức hạng (Vàng, Bạc, Đồng hoặc các mức tùy chỉnh).
   * Mỗi thẻ hiển thị rõ nhãn, số điểm nhận được kèm huy hiệu trực quan.
   * Thao tác chạm 1 chạm để chọn mức hoàn thành.
2. **`UnitStepper` (Mô hình Thời gian / Số lượng - Time Attack):**
   * Nút bấm `+` / `-` lớn dễ bấm ngoài trời, kèm trường nhập số trực tiếp.
   * Hiển thị rõ công thức: `Điểm gốc + (Số đơn vị x Điểm/đơn vị)`.
   * Các chip chọn nhanh: `1`, `3`, `5`, `10` đơn vị để Support / Quản trò chọn nhanh bằng 1 tay.
   * Kiểm soát chặt chẽ trong khoảng `0` đến `max_units`.
3. **`OptionChecklist` (Mô hình Cố định - Fixed):**
   * Nút chuyển đổi (Toggle) "Đã Hoàn Thành Thử Thách".
   * Danh sách các tiêu chí thưởng phụ (Optional Bonus Checkboxes) kèm số điểm cộng thêm.
4. **Huy hiệu Điểm Xem Trước (Preview Badge):**
   * Cập nhật thời gian thực số điểm dự kiến `+X✦` ở góc form.
   * Tự động báo đỏ và khóa nút gửi nếu thông số nhập vi phạm luật trạm.
5. **Tính tái sử dụng cao:**
   * Dùng chung 1 component duy nhất cho:
     - Nhân viên Support gửi kết quả từ máy POS.
     - Quản trò (Station Master) sửa điểm khi "Xác nhận kèm chỉnh".
     - Quản trò nhập điểm trực tiếp cho đội chơi.

---

## 4. MÀN HÌNH ĐIỀU PHỐI SUPPORT (`/support`)

Giao diện vận hành dành riêng cho nhân sự `team_support` phụ trách 1 đội chơi:
* **Danh sách 5 trạm với 5 trạng thái chuẩn hóa:**
  1. `Chưa làm`: Nút "Nộp Kết Quả Trạm" mở form chấm điểm động.
  2. `Chờ Quản Trò`: Hiển thị badge vàng, điểm dự kiến, nút **"Rút lại yêu cầu"** (gọi `cancel_station_claim`).
  3. `Chờ BTC (Admin)`: Hiển thị badge cam báo hiệu điểm lớn hơn ngưỡng hoặc Quản trò đã chỉnh sửa, đang đợi Admin đối soát.
  4. `Đã xong`: Hiển thị huy hiệu xanh lá, điểm số chính thức đã ghi vào sổ cái.
  5. `Bị từ chối`: Hiển thị lý do từ chối từ Quản trò và mở khóa cho phép **Nộp lại**.
* **Khóa Slot độc quyền (Slot Lock):**
  * Nút nộp bị khóa và hiển thị cảnh báo khi trạm độc quyền đang có lượt chơi khác chiếm slot.
* **Badge Chìa Khóa Cổ Tích:**
  * Hiển thị biểu tượng `🗝️` nổi bật khi đội chơi đang sở hữu Chìa Khóa chưa kích hoạt cho trạm đó.
* **Bộ ba Modal Đạo cụ Tình báo & Lối tắt:**
  * **`SpyModal`:** Lọc danh sách 5 đội đối thủ còn lại $\rightarrow$ Bấm xác nhận kích hoạt Kính Viễn Vọng $\rightarrow$ Mở `RavenEyeModal`.
  * **`RavenEyeModal`:** Hiển thị snapshot tình báo 5 chỉ số then chốt của đối thủ: Số dư Lumen hiện tại, Trạng thái Khiên và thời gian hết hạn, Số trạm đã clear, Số manh mối mật đã giải mã, và Dấu thời gian quét.
  * **`KeyModal`:** Lọc danh sách các trạm đội chơi chưa vượt qua $\rightarrow$ Xác nhận cấp Chìa Khóa trạm thành công.
* **Tab Lịch sử giao dịch & Ràng buộc Hoàn tác:**
  * Đọc trực tiếp cờ `can_reverse` và chuỗi `reverse_blocked_reason` do RPC `get_history` trả về.
  * Nút "Hoàn tác" chỉ hiển thị khi `can_reverse = true`. Nếu `false`, hiển thị lý do bằng văn bản giải thích rõ ràng (ví dụ: "Đã quá thời hạn 5 phút", "Giao dịch không phải do bạn tạo").

---

## 5. MÀN HÌNH QUẢN TRÒ TRẠM (`/station`)

Giao diện chuyên biệt dành cho Trạm Trưởng (`station_master`):
* **Tiêu đề trạm:** Tự động hiển thị tên trạm được phân công (ví dụ: `MÊ CUNG GƯƠNG`) lấy từ session.
* **Hàng đợi thời gian thực (Live Queue):**
  * Tự động nhận tín hiệu Realtime qua kênh `station_claims_changed`.
  * Thẻ claim hiển thị đầy đủ: Tên đội chơi, Dữ liệu nộp đã được biên dịch sang nhãn tiếng Việt dễ đọc qua hàm `formatScoringInput`, Điểm số dự kiến, Thời gian chờ (e.g. "45 giây trước"), Huy hiệu `🗝️ ĐÃ DÙNG CHÌA KHÓA CỔ TÍCH` nếu `key_used = true`.
* **Ba nút lớn ưu tiên thao tác một tay (Chiều cao tối thiểu 52px - 56px):**
  1. **Nút "Xác nhận Legit" (Cao 56px, Xanh lá nổi bật):** Xác nhận kết quả nguyên bản, gọi `verify_station_claim` với action `'approve'`.
  2. **Nút "Sửa Điểm" (Xác nhận kèm chỉnh):** Mở modal chứa renderer `StationScoringForm` nạp sẵn giá trị cũ của đội, bắt buộc nhập ghi chú giải trình (`p_note`), tự động tính lại điểm trên snapshot cũ và chuyển trạng thái sang `pending_admin`.
  3. **Nút "Từ Chối":** Mở modal từ chối, tích hợp sẵn các **Chip lý do nhanh** (*"Không đúng luật chơi", "Chưa hoàn thành tiêu chí", "Hết thời gian quy định", "Sai số lượng", "Nhầm đội chơi", "Gian lận/Phạm quy"*), bắt buộc lý do không được để trống.
* **Cơ chế Báo động Âm thanh & Rung máy:**
  * Tích hợp Web Audio API phát chuông đa âm tần số kép (880Hz $\rightarrow$ 1320Hz) khi có claim mới xuất hiện trong hàng đợi mà không phụ thuộc file âm thanh ngoài.
  * Kích hoạt `navigator.vibrate([200, 100, 200])` trên thiết bị di động.
* **Mục "Nhập điểm trực tiếp cho đội":**
  * Quản trò chọn đội chơi từ danh sách dropdown, dùng chính `StationScoringForm` để chấm điểm tại chỗ và nộp trực tiếp qua `submit_station_claim`.
* **Lịch sử xử lý gần đây:**
  * Hiển thị 5 lượt claim vừa xử lý tại trạm với trạng thái `Đã duyệt`, `Đã từ chối` kèm lý do, hoặc `Đã chuyển BTC duyệt`.

---

## 6. TRUNG TÂM CHỈ HUY BAN QUẢN TRỊ (`/admin`)

Bố cục 3 cột chuẩn Desktop cho Ban Chỉ Huy:
* **Cột 1 (Realtime Leaderboard & ± Lumen):**
  * Cập nhật thời gian thực thứ hạng, số dư Lumen, thời gian đếm ngược Khiên bảo vệ, tiến độ hoàn thành trạm.
  * Mỗi đội có nút nhanh `±✦` mở modal điều chỉnh số dư.
* **Cột 2 (Bàn điều khiển 7 Tabs):**
  1. **Tab Phê Duyệt (`pending_admin`):**
     * Hiển thị bảng so sánh side-by-side: Cột trái là **Dữ liệu gốc do Support gửi**, Cột phải là **Dữ liệu do Quản trò điều chỉnh**.
     * Hiển thị ghi chú giải trình của Quản trò và huy hiệu Chìa khóa.
     * Nút Phê duyệt và nút Từ chối (kèm lý do).
  2. **Tab Trạm Thử Thách:**
     * Danh sách trạm kèm modal `StationEditorModal`.
     * Cho phép cấu hình trạm mới hoặc sửa trạm hiện có: đổi `scoring_type`, chỉnh các mức Tier, các tiêu chí phụ, hoặc thông số Time Attack.
     * Tự động validate `min_score <= max_score`, tiers có điểm hợp lệ trước khi lưu qua `admin_upsert_station`.
  3. **Tab Manh Mối (Hints):**
     * Modal `HintEditorModal` quản lý kho manh mối với đầy đủ các trường: title, tier, price, content, station_id, is_active.
  4. **Tab Đạo Cụ (Items):**
     * Modal `ItemEditorModal` quản lý vật phẩm phép thuật trong shop: name, description, price, effect_type, duration_minutes (bắt buộc > 0 với shield), is_active.
  5. **Tab Nhân Sự (Staff):**
     * Danh sách toàn bộ nhân sự hệ thống.
     * Modal `StaffModal` phân quyền vai trò: gán đội cho `team_support`, gán trạm cho `station_master`, đặt lại mã PIN bảo mật.
     * Nút "Thu hồi phiên" gọi `admin_revoke_sessions` đăng xuất cưỡng chế nhân viên.
  6. **Tab Đội Chơi:**
     * Thống kê thông số các đội, mã QR và nút `± Lumen`.
  7. **Tab Cài Đặt Game:**
     * Điều chỉnh tham số `pending_threshold` và `undo_window_minutes`.
* **Cột 3 (Live Audit Log & Hoàn Tác):**
  * Lọc theo danh mục: Tất cả, Trạm, Shop/Hint, PvP, Hoàn tác.
  * **Nút Hoàn tác tuân thủ chặt chẽ `can_reverse`:**
    * Nếu `can_reverse = true`: Hiện nút "Hoàn Tác Tiêu Chuẩn".
    * Nếu `can_reverse = false`: Hiển thị lý do bị chặn (`reverse_blocked_reason`), đồng thời hiển thị nút **"Force Revert"** màu đỏ dành riêng cho Admin.
  * **Modal Hoàn Tác Bắt Buộc (`ForceRevertModal`):**
    * Hộp thoại xác nhận riêng biệt, cảnh báo giao dịch vượt quá hạn 5 phút.
    * Bắt buộc Admin nhập lý do giải trình kiểm toán trước khi gọi `reverse_transaction({ p_tx_id, p_force: true, p_reason })`.
* **Modal `± Lumen` (`AdjustBalanceModal`):**
  * Chọn thao tác Cộng hoặc Trừ.
  * Bắt buộc nhập lý do điều chỉnh, có tích hợp chip lý do nhanh (*Thưởng mini-game phụ, Phạt vi phạm, Bù trừ sự cố kỹ thuật...*).
  * Kiểm soát tuyệt đối không cho phép trừ vượt quá số dư hiện tại để ngăn chặn số dư âm.

---

## 7. ĐỐI CHIẾU TIÊU CHÍ NGHIỆM THU (ACCEPTANCE CRITERIA)

| Tiêu chí | Cơ chế thực thi | Kết quả |
| :--- | :--- | :--- |
| **1. Quản Trò trạm 1 chỉ thấy hàng đợi trạm 1** | Trong RPC `get_station_queue`, hệ thống lọc cứng `WHERE c.station_id = v_staff.assigned_station_id`. Trên UI `StationPage`, tiêu đề và thẻ claim khóa chặt theo trạm được gán. | **ĐẠT** |
| **2. Admin tạo trạm mới với rule mới và Support nộp điểm ngay mà không deploy lại** | `StationEditorModal` lưu `scoring_type` và `scoring_config` vào database. Khi Support mở trạm, `StationScoringForm` render động hoàn toàn từ schema JSON máy chủ trả về. | **ĐẠT** |
| **3. Đổi rule giữa chừng không làm đổi claim đang chờ** | Mỗi claim khi nộp đều được đóng băng cấu hình trong `station_claims.scoring_snapshot`. Khi Quản trò sửa điểm hoặc Admin duyệt, hệ thống luôn tính điểm dựa trên snapshot này chứ không đọc cấu hình mới của trạm. | **ĐẠT** |
| **4. Quyền hoàn tác do máy chủ quyết định** | UI không dùng timestamp client để so sánh mà đọc cờ `can_reverse` và `reverse_blocked_reason` trực tiếp từ RPC `get_history` / `admin_get_audit_log`. | **ĐẠT** |
| **5. Thao tác một tay ngoài trời** | Chiều cao các nút hành động chính trên mobile đạt 52px – 56px, các nút stepper có diện tích tiếp xúc lớn, giao diện tương phản cao đạt chuẩn ánh sáng ngoài trời. | **ĐẠT** |
| **6. Build và kiểm thử thành công** | Lệnh `npm run build` (`tsc -b && vite build`) hoàn thành với mã thoát 0 (0 lỗi TypeScript / Vite). Bộ 7 test cases fixture vượt qua 100%. | **ĐẠT** |

---

## 8. HƯỚNG DẪN KIỂM THỬ THỰC TẾ (MANUAL E2E TESTING)

1. **Luồng 1: Support Nộp Điểm $\rightarrow$ Quản Trò Duyệt $\rightarrow$ Sổ Cái Ghi Nhận**
   * Đăng nhập PIN của một `team_support` tại `/`.
   * Vào tab Trạm, chọn trạm đang mở và nộp điểm. Trạng thái chuyển sang `Chờ Quản Trò`.
   * Đăng nhập PIN của `station_master` phụ trách trạm đó tại `/station`. Chuông báo và rung kích hoạt.
   * Quản trò bấm nút xanh lớn **"Xác Nhận Legit"**.
   * Bên giao diện Support, trạm tự động chuyển sang trạng thái `Đã xong`, số dư Lumen của đội tăng tương ứng.
2. **Luồng 2: Quản Trò Sửa Điểm $\rightarrow$ Chuyển BTC $\rightarrow$ Admin So Sánh & Phê Duyệt**
   * Support nộp điểm với mức hoàn thành cao.
   * Quản trò tại `/station` bấm **"Sửa Điểm"**, điều chỉnh lại điểm và nhập ghi chú lý do. Bấm gửi.
   * Claim chuyển sang trạng thái `pending_admin`.
   * Đăng nhập tài khoản `admin` tại `/admin`, vào tab **Phê Duyệt**.
   * Quan sát bảng so sánh dữ liệu gốc vs dữ liệu đã chỉnh, đọc ghi chú Quản trò, sau đó bấm **"Phê Duyệt"**.
   * Sổ cái tại Cột 3 ghi nhận giao dịch với dấu vết kiểm toán đầy đủ.
3. **Luồng 3: Admin Tạo Trạm Mới $\rightarrow$ Support Nộp Ngay Lập Tức**
   * Tại `/admin`, vào tab **Trạm**, bấm **"Thêm Trạm"**.
   * Chọn mô hình `time_attack` với đơn vị đo `bóng nước`, lưu lại.
   * Tại máy Support (`/support`), tab Trạm lập tức nhận được trạm mới qua realtime. Bấm nộp điểm, bộ stepper `UnitStepper` hiển thị đúng đơn vị `bóng nước` mà không cần tải lại trang hay build lại mã nguồn.
