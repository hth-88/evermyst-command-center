# BÁO CÁO AUDIT HIỆN TRẠNG HỆ THỐNG V1 (PHASE 0)
**Dự án:** Evermyst BigGame Command Center  
**Vai trò:** Principal Full-Stack Architect  
**Tình trạng kiểm tra:** Read-Only Static & Live Data Audit (Không can thiệp sửa đổi DB)  
**Thời điểm thực hiện:** 2026-10-21  

---

## 1. SƠ ĐỒ CƠ SỞ DỮ LIỆU HIỆN TẠI (SCHEMA ARCHITECTURE)

Hệ thống V1 hiện tại được triển khai trên PostgreSQL (Supabase) thông qua file `supabase_schema.sql` gồm **12 bảng**, **16 hàm RPC nghiệp vụ**, **1 hàm helper xác thực**, cơ chế **Realtime** trên 9 bảng và chính sách **RLS** cho phép `SELECT` công khai cho anonymous.

### 1.1. Danh mục Bảng, Cột, Ràng Buộc & Chỉ Mục

| Tên Bảng | Cột & Kiểu Dữ Liệu | Khóa Chính / Ngoại / Ràng Buộc (Constraints) | Chỉ Mục (Indexes) |
| :--- | :--- | :--- | :--- |
| **`staff`** | `id` (UUID)<br>`name` (TEXT)<br>`role` (TEXT)<br>`pin` (TEXT)<br>`station_assigned` (TEXT)<br>`is_active` (BOOL)<br>`created_at` (TIMESTAMPTZ) | PK: `id`<br>`CHECK (role IN ('admin', 'support'))`<br>`name NOT NULL, pin NOT NULL` | `idx_staff_pin(pin)` |
| **`staff_sessions`** | `id` (UUID)<br>`staff_id` (UUID)<br>`token` (TEXT)<br>`expires_at` (TIMESTAMPTZ)<br>`created_at` (TIMESTAMPTZ) | PK: `id`<br>FK: `staff_id REFERENCES staff(id) ON DELETE CASCADE`<br>`token UNIQUE NOT NULL` | `idx_sessions_token(token)` |
| **`game_settings`** | `key` (TEXT)<br>`value` (JSONB)<br>`label` (TEXT)<br>`description` (TEXT)<br>`category` (TEXT)<br>`is_public` (BOOL)<br>`updated_at` (TIMESTAMPTZ)<br>`updated_by` (TEXT) | PK: `key`<br>`category DEFAULT 'general'` | Mặc định theo PK |
| **`game_settings_history`** | `id` (UUID)<br>`key` (TEXT)<br>`old_value` (JSONB)<br>`new_value` (JSONB)<br>`changed_by` (TEXT)<br>`created_at` (TIMESTAMPTZ) | PK: `id` | `idx_settings_hist_key(key, created_at DESC)` |
| **`teams`** | `id` (UUID)<br>`name` (TEXT)<br>`qr_code` (TEXT)<br>`light_balance` (INT)<br>`shield_until` (TIMESTAMPTZ)<br>`unlocked_stations` (TEXT[])<br>`is_active` (BOOL)<br>`created_at` (TIMESTAMPTZ) | PK: `id`<br>`qr_code UNIQUE NOT NULL`<br>`light_balance DEFAULT 100`<br>*(THIẾU: CHECK light_balance >= 0)* | `idx_teams_qr(qr_code)`<br>`idx_teams_balance(light_balance DESC)` |
| **`stations`** | `id` (UUID)<br>`name` (TEXT)<br>`description` (TEXT)<br>`order_index` (INT)<br>`is_active` (BOOL)<br>`created_at` (TIMESTAMPTZ) | PK: `id` | `idx_stations_order(order_index ASC)` |
| **`hints`** | `id` (UUID)<br>`station_id` (UUID)<br>`title` (TEXT)<br>`content` (TEXT)<br>`tier` (TEXT)<br>`order_index` (INT)<br>`is_active` (BOOL)<br>`created_at` (TIMESTAMPTZ) | PK: `id`<br>FK: `station_id REFERENCES stations(id) ON DELETE SET NULL`<br>`CHECK (tier IN ('bronze', 'silver', 'gold'))` | `idx_hints_station(station_id)` |
| **`team_hints`** | `id` (UUID)<br>`team_id` (UUID)<br>`hint_id` (UUID)<br>`unlocked_at` (TIMESTAMPTZ)<br>`unlocked_by` (TEXT) | PK: `id`<br>FK: `team_id REFERENCES teams(id) ON DELETE CASCADE`<br>FK: `hint_id REFERENCES hints(id) ON DELETE CASCADE`<br>`UNIQUE (team_id, hint_id)` | Mặc định theo PK & UNIQUE |
| **`items`** | `id` (UUID)<br>`name` (TEXT)<br>`description` (TEXT)<br>`price` (INT)<br>`effect_type` (TEXT)<br>`duration_minutes` (INT)<br>`is_active` (BOOL)<br>`created_at` (TIMESTAMPTZ) | PK: `id`<br>`CHECK (effect_type IN ('shield', 'spy', 'key'))` | Mặc định theo PK |
| **`team_items`** | `id` (UUID)<br>`team_id` (UUID)<br>`item_id` (UUID)<br>`quantity` (INT)<br>`used_count` (INT)<br>`created_at` (TIMESTAMPTZ)<br>`updated_at` (TIMESTAMPTZ) | PK: `id`<br>FK: `team_id REFERENCES teams(id) ON DELETE CASCADE`<br>FK: `item_id REFERENCES items(id) ON DELETE CASCADE`<br>`UNIQUE (team_id, item_id)`<br>`CHECK (quantity >= 0)` | Mặc định theo PK & UNIQUE |
| **`transactions`** | `id` (UUID)<br>`client_request_id` (TEXT)<br>`team_id` (UUID)<br>`amount` (INT)<br>`type` (TEXT)<br>`description` (TEXT)<br>`created_by` (TEXT)<br>`status` (TEXT)<br>`reviewed_by` (TEXT)<br>`reviewed_at` (TIMESTAMPTZ)<br>`is_reversed` (BOOL)<br>`reversal_for_id` (UUID)<br>`created_at` (TIMESTAMPTZ) | PK: `id`<br>`client_request_id UNIQUE`<br>FK: `team_id REFERENCES teams(id) ON DELETE CASCADE`<br>FK: `reversal_for_id REFERENCES transactions(id)`<br>`CHECK (type IN ('station_clear', 'buy_hint', 'buy_item', 'pvp_steal', 'pvp_backlash', 'admin_adjust', 'reversal'))`<br>`CHECK (status IN ('approved', 'pending', 'rejected'))` | `idx_tx_team(team_id)`<br>`idx_tx_status(status)`<br>`idx_tx_created(created_at DESC)`<br>`idx_tx_client_req(client_request_id)` |
| **`pvp_logs`** | `id` (UUID)<br>`client_request_id` (TEXT)<br>`attacker_team_id` (UUID)<br>`defender_team_id` (UUID)<br>`amount_stolen` (INT)<br>`result` (TEXT)<br>`created_by` (TEXT)<br>`created_at` (TIMESTAMPTZ) | PK: `id`<br>`client_request_id UNIQUE`<br>FK: `attacker_team_id REFERENCES teams(id)`<br>FK: `defender_team_id REFERENCES teams(id)`<br>`CHECK (result IN ('success', 'backlash', 'cooldown_blocked'))` | `idx_pvp_pair(attacker_team_id, defender_team_id, created_at DESC)` |

---

### 1.2. Chính Sách Bảo Mật RLS Hiện Tại
* **Cơ chế:** Toàn bộ 12 bảng đã bật `ENABLE ROW LEVEL SECURITY`.
* **Quyền Anonymous:** Cấp `FOR SELECT USING (true)` cho tất cả bảng (`teams`, `stations`, `items`, `team_hints`, `team_items`, `transactions`, `pvp_logs`, `staff`, `game_settings`, `hints`).
* **Đánh giá rủi ro theo quy tắc V2:** Vi phạm quy tắc bắt buộc *"Bật RLS trên mọi bảng, không policy cho anon (deny-all). Client chỉ đi qua RPC."*. Cần loại bỏ các public SELECT policies này trong V2.

---

## 2. BẢN ĐỒ RPC CŨ ↔ COMPONENT FRONTEND GỌI NÓ

Bảng đối chiếu toàn bộ 16 RPCs của hệ thống V1, phân loại trạng thái xử lý cho V2:

| STT | Tên RPC Hiện Tại | Component Frontend Gọi | Mục Đích Sử Dụng | Trạng Thái V2 | Lý Do / Phương Án Thay Thế |
| :---: | :--- | :--- | :--- | :---: | :--- |
| 1 | `staff_login` | `LoginPage.tsx` (qua `GameContext.login`) | Đăng nhập bằng mã PIN, tạo token phiên 24h | **GIỮ NGUYÊN / TỐI ƯU** | Cần bổ sung gán `search_path = public, pg_temp` và audit trail. |
| 2 | `staff_list_public` | `LoginPage.tsx` (qua `GameContext.fetchStaffList`) | Lấy danh sách nhân sự cho màn chọn nhanh | **XÓA / ẨN KHỎI ANON** | Lộ danh sách nhân sự ra ngoài internet. Cần deny anon. |
| 3 | `get_server_time` | `GameContext.tsx` (`syncServerTime`) | Lấy epoch server để bù trừ `serverOffsetMs` | **GIỮ NGUYÊN** | Bổ sung `SET search_path = public, pg_temp`. |
| 4 | **`award_station`** | `StationTab.tsx` (qua `GameContext.executeStationReward`) | Thưởng điểm trạm cho đội vượt thử thách | **BỊ THAY THẾ HOÀN TOÀN** | Thay bằng `submit_station_claim` có khóa chống trùng claim và kiểm tra role/station_assigned chặt chẽ. |
| 5 | `buy_hint` | `ShopTab.tsx` (qua `GameContext.buyHint`) | Mua và mở khóa gợi ý bí mật | **GIỮ NGUYÊN / HARDEN** | Bổ sung thứ tự khóa toàn cục và kiểm tra số dư chặt chẽ. |
| 6 | `get_team_hints` | `ShopTab.tsx` (qua `GameContext.fetchTeamHints`) | Đọc lại nội dung hint đã mua | **GIỮ NGUYÊN** | Bổ sung `SET search_path = public, pg_temp`. |
| 7 | `buy_item` | `ShopTab.tsx` (qua `GameContext.buyItem`) | Mua đạo cụ trong cửa hàng | **GIỮ NGUYÊN / HARDEN** | Khóa theo thứ tự toàn cục (teams → team_items). |
| 8 | `use_team_item` | `ShopTab.tsx` (qua `GameContext.activateTeamItem`) | Sử dụng đạo cụ từ kho đồ | **NÂNG CẤP LOGIC** | Bổ sung xử lý hiệu ứng thực tế cho `spy` và `key` thay vì chỉ trừ quantity. |
| 9 | `resolve_pvp` | `PvPTab.tsx` (qua `GameContext.resolvePvP`) | Trọng tài xử lý combat cướp điểm giữa 2 đội | **HARDEN / FIX COOLDOWN** | Sửa lỗ hổng cooldown 1 chiều (A đánh B thì B vẫn đánh được A) thành cooldown 2 chiều cho cả cặp đấu. |
| 10| `decide_pending` | `AdminPage.tsx` (qua `GameContext.decidePending`) | Admin duyệt / từ chối giao dịch vượt ngưỡng | **HARDEN / LEDGER COMPLIANT**| Đảm bảo khi approve tạo dòng ledger đối ứng hoặc ghi nhận đúng chuẩn thay vì sửa ledger mộc. |
| 11| `admin_adjust_balance`| `AdminPage.tsx` (qua `GameContext.adminAdjustBalance`)| Admin cộng/trừ điểm khẩn cấp | **GIỮ NGUYÊN** | Tuân thủ thứ tự khóa toàn cục và ràng buộc không âm. |
| 12| `admin_set_shield` | `AdminPage.tsx` (qua `GameContext.adminSetShield`) | Admin bật/tắt khiên thủ công | **GIỮ NGUYÊN** | Cập nhật quyền `admin`. |
| 13| `reverse_transaction` | `HistoryTab.tsx`, `AdminPage.tsx` (qua `GameContext.reverseTransaction`) | Hoàn tác giao dịch bằng Compensating Tx | **HARDEN** | Bổ sung kiểm tra số dư tối thiểu của đội khi bị revert (chống âm điểm). |
| 14| `update_setting` | `AdminPage.tsx` (qua `GameContext.updateSetting`) | Cập nhật cấu hình game | **GIỮ NGUYÊN** | Giữ nguyên audit trail `game_settings_history`. |
| 15| `admin_list_hints` | `AdminPage.tsx` (qua `GameContext.adminListHints`) | Admin xem mật mã bí mật | **GIỮ NGUYÊN** | Đảm bảo chỉ cấp quyền cho role `admin`. |
| 16| **`upsert_entity`** | `AdminPage.tsx` (qua `upsertTeam`, `upsertStation`, v.v.) | CRUD thực thể qua RPC thay thế client write | **LOẠI BỎ ĐƯỜNG LÁCH SỐ DƯ**| Cấm truyền `light_balance` vào `upsert_entity('team')` vì làm đổi số dư mà không sinh ledger! |

---

## 3. CƠ CHẾ TOKEN, GUARD ROUTE & REALTIME HIỆN TẠI

### 3.1. Lưu Trữ Token & Phiên Đăng Nhập
* **Vị trí lưu:** `localStorage` với key `'evermyst_session_user'`.
* **Cấu trúc lưu trữ:** Chuỗi JSON chứa đối tượng `AuthUser`:
  ```json
  {
    "id": "uuid-nhân-sự",
    "name": "Tên Nhân Sự",
    "role": "admin | support",
    "station_assigned": "Trạm 1 | null",
    "token": "hex-token-64-ký-tự"
  }
  ```
* **Thời hạn phiên:** Được server đặt cứng `24 hours` trong bảng `staff_sessions`.
* **Xác thực:** Mỗi khi gọi RPC, client truyền `user.token` vào tham số `p_token`. Hàm `auth_verify_session(p_token, p_required_role)` truy vấn `staff_sessions JOIN staff` để chứng thực.

### 3.2. Nơi Đặt Route Guards
* **Client Router:** Sử dụng `react-router-dom` tại `src/App.tsx`.
* **Root Redirect Guard (`src/App.tsx:L11-31`):**
  * `isLoading`: hiển thị spinner chờ tải session từ `localStorage`.
  * `!user`: chuyển hướng về `/login`.
  * `user.role === 'admin'`: chuyển hướng về `/admin`.
  * `user.role === 'support'`: chuyển hướng về `/support`.
* **Support Page Guard (`src/pages/SupportPage.tsx:L30-34`):**
  * `useEffect` kiểm tra: nếu `!isLoading && !user` -> `navigate('/login')`.
* **Admin Page Guard (`src/pages/AdminPage.tsx:L64-68`):**
  * `useEffect` kiểm tra: nếu `!isLoading && (!user || user.role !== 'admin')` -> `navigate('/login')`.
* **Đánh giá:** Guard hiện tại đặt ở tầng React Component (`useEffect`), có độ trễ render ngắn (flash UI) trước khi redirect.

### 3.3. Đăng Ký Kênh Realtime (Supabase Realtime)
Hệ thống mở **1 kênh duy nhất** mang tên `'evermyst-core-channel'` trong `src/contexts/GameContext.tsx:L322-408`:

| STT | Bảng Theo Dõi | Sự Kiện Lắng Nghe | Hành Vi Xử Lý State Frontend |
| :---: | :--- | :---: | :--- |
| 1 | `teams` | `*` (INSERT, UPDATE, DELETE) | Cập nhật mảng `teams`, tự động sort theo `light_balance DESC`. |
| 2 | `transactions` | `*` (INSERT, UPDATE) | Chèn vào đầu danh sách (giới hạn 200 dòng gần nhất). |
| 3 | `team_hints` | `INSERT` | Nối thêm vào mảng `teamHints`. |
| 4 | `team_items` | `*` | Gọi query lại `supabase.from('team_items').select('*, item:items(*)')`. |
| 5 | `pvp_logs` | `INSERT` | Chèn vào đầu danh sách (giới hạn 100 dòng gần nhất). |
| 6 | `game_settings` | `*` | Gọi query lại toàn bộ cấu hình và đồng bộ `config`. |
| 7 | `stations` | `*` | Re-fetch danh sách trạm sắp xếp theo `order_index`. |
| 8 | `items` | `*` | Re-fetch danh sách đạo cụ sắp xếp theo `price`. |
| 9 | `hints` | `*` | Re-fetch danh sách gợi ý công khai (không gồm content). |

* **Cơ chế Reconnect Snapshot:** Có cờ `wasDisconnectedRef.current`. Khi status chuyển từ `CLOSED/CHANNEL_ERROR` sang `SUBSCRIBED`, hệ thống tự động kích hoạt `refreshAll()` để đồng bộ lại snapshot mới nhất từ DB.

---

## 4. KẾT QUẢ AUDIT DỮ LIỆU THỰC TẾ (EXECUTED VIA 001_AUDIT.SQL)

Dữ liệu được truy vấn trực tiếp từ cơ sở dữ liệu Supabase đang hoạt động của hệ thống:

```
================================================================================
KẾT QUẢ TRUY VẤN AUDIT HIỆN TRẠNG (DATABASE TELEMETRY)
================================================================================
(a) Số đội có light_balance < 0                           : 0 đội
(b) Cặp (team_id, station) có >1 station_reward active    : 0 cặp
(c) Số staff có role nằm ngoài 3 role mới V2              : 18 nhân sự (100%)
(d) Số đội có chênh lệch giữa light_balance và Ledger      : 6 đội (100%)
(e) Số giao dịch đang ở trạng thái Pending                : 0 giao dịch
(f) Số lượng đạo cụ trong kho bị âm (quantity < 0)        : 0 bản ghi
(g) Số đường sửa light_balance trực tiếp không qua Ledger : 2 đường (upsert_entity, seed data)
================================================================================
```

---

## 5. BẢNG TỔNG HỢP VI PHẠM DỮ LIỆU & ĐỀ XUẤT XỬ LÝ CHO V2

| Mã Vi Phạm | Mô Tả Chi Tiết Vi Phạm Hiện Trạng | Số Lượng Thực Tế | Đánh Giá Mức Độ | Đề Xuất Xử Lý Kỹ Thuật Cho Phase Tiếp Theo |
| :--- | :--- | :---: | :---: | :--- |
| **VIO-01: UNLOGGED_INITIAL_BALANCE** | Cả 6 đội chơi ban đầu đều có `light_balance = 100`, nhưng trong bảng `transactions` **hoàn toàn không có dòng giao dịch khởi tạo nào**. Tổng Ledger của các đội hiện bằng 0, dẫn tới độ lệch `light_balance - sum(ledger) = 100` cho mọi đội. | **6 / 6 đội** (100%) | **NGHIÊM TRỌNG** (Vi phạm tính toàn vẹn Ledger) | Tạo migration V2 chèn 6 bản ghi giao dịch bù đắp: `type = 'admin_adjust'`, `amount = 100`, `description = 'Cấp số dư khởi đầu giải đấu (Initial Grant)'` với `created_by = 'system'` để cân bằng khớp 100% với Ledger. |
| **VIO-02: LEGACY_STAFF_ROLES** | Toàn bộ 18 nhân sự hiện tại chỉ mang 2 role cũ: `admin` (4 records) và `support` (14 records). Chưa có các role chuyên biệt theo kiến trúc mới: `admin`, `station_support`, `pvp_referee`. Đồng thời phát hiện 9 nhân sự bị duplicate 2 lần. | **18 nhân sự** | **TRUNG BÌNH** (Ảnh hưởng phân quyền V2) | 1. Dọn dẹp bản ghi trùng lặp (deduplicate).<br>2. Cập nhật `CHECK (role IN ('admin', 'station_support', 'pvp_referee'))`.<br>3. Map role cũ: các tài khoản Support Trạm chuyển thành `station_support`, tài khoản Trọng Tài PvP chuyển thành `pvp_referee`. |
| **VIO-03: DIRECT_BALANCE_MUTATION** | Hàm `upsert_entity(p_entity_type = 'team')` cho phép Admin truyền `light_balance` vào JSON để `UPDATE teams SET light_balance = ...` trực tiếp mà không sinh bất kỳ dòng `transactions` nào. | **1 điểm code** (`supabase_schema.sql:1219`) | **NGHIÊM TRỌNG** (Lỗ hổng gian lận / lệch Ledger) | Xóa bỏ trường `light_balance` khỏi `upsert_entity`. Mọi can thiệp số dư bắt buộc 100% phải đi qua `admin_adjust_balance` (có `INSERT INTO transactions`). |
| **VIO-04: MISSING_STATION_CLAIM_LOCK** | Bảng `transactions` không lưu `station_id` mà chỉ lưu tên trạm vào `description`. Không có ràng buộc `UNIQUE(team_id, station_id)` dẫn đến việc Support có thể vô tình hoặc cố ý bấm duyệt trạm nhiều lần cho cùng 1 đội. | **Tiềm ẩn** (Hiện có 1 tx station_clear hợp lệ) | **CAO** (Lỗ hổng gian lận vượt trạm) | Tạo bảng mới `station_claims` với ràng buộc `UNIQUE(team_id, station_id)`. RPC mới `submit_station_claim` sẽ khóa bảng này trước tiên theo thứ tự toàn cục. |
| **VIO-05: MISSING_NON_NEGATIVE_CONSTRAINT** | Bảng `teams` thiếu ràng buộc `CHECK (light_balance >= 0)`. Khi bị phạt phản phệ PvP (10 Lumen) hoặc khi Revert giao dịch, nếu số dư hiện tại của đội nhỏ hơn số tiền bị trừ, số dư sẽ bị âm. | **Tiềm ẩn** (Hiện tại số dư nhỏ nhất = 100) | **CAO** (Lỗi logic kinh tế) | Bổ sung ràng buộc `ALTER TABLE teams ADD CONSTRAINT chk_teams_light_balance_non_negative CHECK (light_balance >= 0);`. |
| **VIO-06: PUBLIC_RLS_EXPOSURE** | Anon key có thể `SELECT` đọc toàn bộ các bảng trong hệ thống do các policy `FOR SELECT USING (true)` đang mở. | **10 bảng** có public select policy | **CAO** (Vi phạm quy tắc V2 Deny-All) | Xóa toàn bộ policies cũ, cấu hình Deny-all cho public/anon. Mọi thao tác lấy dữ liệu của client đều chuyển qua các hàm RPC Security Definer có xác thực token. |

---

## 6. KẾT LUẬN & ĐIỀU KIỆN TIÊN QUYẾT CHO PHASE 1

1. **Hiện trạng mã nguồn:** Hoạt động ổn định ở quy mô thử nghiệm nhỏ, nhưng tồn tại các lỗ hổng kiến trúc về tính toàn vẹn sổ cái và phân quyền nhân sự.
2. **Hiện trạng dữ liệu:** Dữ liệu mẫu ban đầu gồm 6 đội và 3 giao dịch thực tế. Toàn bộ 6 đội đều cần được tạo dòng ledger bù đắp ban đầu (100 Lumen) để đảm bảo nguyên tắc bất biến: **Không thay đổi số dư mà không có dòng ledger tương ứng**.
3. **Mục tiêu Phase 1:** Thiết kế migration DDL tạo bảng `station_claims`, bổ sung các constraint còn thiếu, cập nhật thứ tự khóa toàn cục và thay thế `award_station` bằng `submit_station_claim`.
