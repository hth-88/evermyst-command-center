# BÁO CÁO NGHIỆM THU PHASE 6 — FRONTEND: ROUTING, GUARD, LỚP GỌI API & REALTIME

> **Mục tiêu Phase 6:** Xây dựng tầng giao diện người dùng (Frontend) tuân thủ chặt chẽ các quyết định kiến trúc ADR-2, ADR-3 và ADR-4. Đảm bảo UI không bao giờ hiển thị bất kỳ tài nguyên nào ngoài phạm vi Role, bảo vệ điều hướng bằng SessionProvider chặn flash giao diện, chuẩn hóa lớp gọi API RPC định danh với mã lỗi Tiếng Việt, triển khai hook Realtime chống nghẽn với cơ chế Fallback Polling 10s khi mất mạng, và loại bỏ hoàn toàn bộ chọn đội (team switcher) ở giao diện Support.

---

## 1. TỔNG QUAN CÁC FILE ĐÃ TRIỂN KHAI VÀ CẬP NHẬT

| STT | File | Vai trò | Trạng thái |
| :--- | :--- | :--- | :--- |
| **1** | [`src/contexts/SessionContext.tsx`](file:///c:/Users/ADMIN/Documents/ProPTIT/Ban%20SK/BIGGAME%20D26/src/contexts/SessionContext.tsx) | `SessionProvider`: Quản lý phiên token, gọi `auth_verify_session` khi load trang, chặn render khi chưa xác thực xong | Đã hoàn thiện |
| **2** | [`src/components/guards/RoleRoute.tsx`](file:///c:/Users/ADMIN/Documents/ProPTIT/Ban%20SK/BIGGAME%20D26/src/components/guards/RoleRoute.tsx) | Route Guard phân quyền UX theo Role, tự động chuyển hướng về trang chủ của Role nếu truy cập trái phép | Đã hoàn thiện |
| **3** | [`src/lib/errors.vi.ts`](file:///c:/Users/ADMIN/Documents/ProPTIT/Ban%20SK/BIGGAME%20D26/src/lib/errors.vi.ts) | Từ điển ánh xạ toàn bộ mã lỗi nghiệp vụ của hệ thống sang Tiếng Việt thân thiện | Đã hoàn thiện |
| **4** | [`src/lib/rpc.ts`](file:///c:/Users/ADMIN/Documents/ProPTIT/Ban%20SK/BIGGAME%20D26/src/lib/rpc.ts) | Hàm trung tâm `callRpc`: Tự đính kèm `p_token`, sinh `client_request_id` cho mutation, auto-logout khi `UNAUTHENTICATED` | Đã hoàn thiện |
| **5** | [`src/hooks/useSignal.ts`](file:///c:/Users/ADMIN/Documents/ProPTIT/Ban%20SK/BIGGAME%20D26/src/hooks/useSignal.ts) | Hook Realtime theo ADR-3: Lắng nghe signal, debounce 300ms, tự reconnect, fallback polling 10s khi offline | Đã hoàn thiện |
| **6** | [`src/components/common/ConnectionIndicator.tsx`](file:///c:/Users/ADMIN/Documents/ProPTIT/Ban%20SK/BIGGAME%20D26/src/components/common/ConnectionIndicator.tsx) | Widget hiển thị trạng thái mạng (Trực tuyến, Polling 10s, Đang kết nối, Ngoại tuyến) chuẩn ngoài trời | Đã hoàn thiện |
| **7** | [`src/pages/LoginPage.tsx`](file:///c:/Users/ADMIN/Documents/ProPTIT/Ban%20SK/BIGGAME%20D26/src/pages/LoginPage.tsx) | Trang đăng nhập PIN bảo mật tại `/`, hỗ trợ bàn phím ảo & phím số vật lý, tự chuyển về trang chủ theo Role | Đã hoàn thiện |
| **8** | [`src/pages/StationPage.tsx`](file:///c:/Users/ADMIN/Documents/ProPTIT/Ban%20SK/BIGGAME%20D26/src/pages/StationPage.tsx) | Giao diện `/station` dành riêng cho Trạm Trưởng (`station_master`): Duyệt/Từ chối claim theo thời gian thực | Đã hoàn thiện |
| **9** | [`src/components/support/TopBar.tsx`](file:///c:/Users/ADMIN/Documents/ProPTIT/Ban%20SK/BIGGAME%20D26/src/components/support/TopBar.tsx) | Header Support: Hiển thị cố định đội được gán từ token, đã xóa hoàn toàn dropdown và camera quét QR | Đã hoàn thiện |
| **10** | [`src/pages/SupportPage.tsx`](file:///c:/Users/ADMIN/Documents/ProPTIT/Ban%20SK/BIGGAME%20D26/src/pages/SupportPage.tsx) | Màn hình `/support` cho `team_support`: Cố định làm việc trên `assigned_team`, tích hợp `useSignal` | Đã hoàn thiện |
| **11** | [`src/App.tsx`](file:///c:/Users/ADMIN/Documents/ProPTIT/Ban%20SK/BIGGAME%20D26/src/App.tsx) | Cây định tuyến Router: Bọc `SessionProvider` + `GameProvider`, thiết lập Role Guard cho 4 nhóm route | Đã hoàn thiện |
| **12** | [`src/contexts/GameContext.tsx`](file:///c:/Users/ADMIN/Documents/ProPTIT/Ban%20SK/BIGGAME%20D26/src/contexts/GameContext.tsx) | Đồng bộ dữ liệu game: Tích hợp `useSession`, chuyển toàn bộ RPC sang `callRpc` bảo mật và chuẩn hóa | Đã hoàn thiện |
| **13** | [`src/lib/types.ts`](file:///c:/Users/ADMIN/Documents/ProPTIT/Ban%20SK/BIGGAME%20D26/src/lib/types.ts) | Định nghĩa kiểu TypeScript đầy đủ cho 32 RPC và ánh xạ `RpcMap` kiểm soát type-safe khi build | Đã hoàn thiện |

---

## 2. CHI TIẾT CÁC TÍNH NĂNG ĐÃ HOÀN THIỆN

### 1. SessionProvider & Vòng Đời Phiên Đăng Nhập
* **Lưu trữ & Khởi tạo:** Token được giữ an toàn tại `localStorage` với key `evermyst_token`.
* **Cơ chế chặn render khi chưa Verify:**
  * Khi mở ứng dụng hoặc tải lại trang, `SessionProvider` đặt cờ `isVerifying = true`.
  * Trong thời gian gọi RPC `auth_verify_session(p_token)` với máy chủ, hệ thống **chỉ hiển thị màn hình chờ Evermyst** với biểu tượng Khiên phát sáng (`animate-pulse`), tuyệt đối không render nội dung các trang con bên dưới để tránh rò rỉ layout hay flash UI.
* **Xác thực thành công:**
  * Thông tin nhân sự được lưu vào context: `{ id, name, role, assigned_team, assigned_station, token, expires_at }`.
  * Cờ `isVerifying` chuyển sang `false` và mở khóa render các route tương ứng.
* **Tự động đăng xuất (Reactive Auto-Logout):**
  * Lắng nghe sự kiện toàn cục `evermyst:unauthenticated` phát ra từ `callRpc`.
  * Nếu token hết hạn, bị thu hồi hoặc phiên không hợp lệ, ứng dụng tự động xóa token khỏi `localStorage`, xóa user state và đưa người dùng về trang đăng nhập `/`.

---

### 2. Định Tuyến & Bảo Vệ Route Theo Role (Role-Based Route Guard)
* **Bảng phân quyền route:**
  * `/`: Trang đăng nhập PIN. Nếu đã đăng nhập, tự động chuyển về trang chủ của Role.
  * `/support`: Chỉ dành riêng cho nhân viên điều phối đội (`team_support`).
  * `/station`: Chỉ dành riêng cho Trạm Trưởng chấm điểm (`station_master`).
  * `/admin`: Chỉ dành riêng cho Ban Quản Trị chỉ huy (`admin`).
  * `*`: Mọi URL lạ tự động chuyển hướng về `/`.
* **Hành vi chuyển hướng khi sai Role:**
  * Guard `RoleRoute` so khớp `user.role` với danh sách `allowedRoles`.
  * Nếu chưa đăng nhập: Chuyển về `/`.
  * Nếu đã đăng nhập nhưng sai role: Chuyển về trang chủ của Role hiện tại thông qua hàm `getRoleHomePath(user.role)`:
    * `team_support` truy cập `/admin` hoặc `/station` $\rightarrow$ Tự động chuyển về `/support`.
    * `station_master` truy cập `/admin` hoặc `/support` $\rightarrow$ Tự động chuyển về `/station`.
    * `admin` truy cập `/support` hoặc `/station` $\rightarrow$ Tự động chuyển về `/admin`.
* **Ràng buộc:** Route Guard trên frontend được thiết kế tối ưu trải nghiệm (UX). Toàn bộ tính bảo mật, toàn vẹn dữ liệu được bảo vệ tầng sâu bởi hàm `_require_staff` và RLS Deny-All trong PostgreSQL.

---

### 3. Lớp Gọi API Tập Trung: `callRpc`
* **Tự động đính kèm `p_token`:**
  * Tự động lấy token hợp lệ từ `localStorage` và gán vào tham số `p_token` của RPC (trừ RPC công khai `staff_login`).
* **Cơ chế Idempotency chống Duplicate:**
  * Mọi RPC thực hiện ghi nhận thay đổi số dư hoặc dữ liệu game (`submit_station_claim`, `purchase_hint`, `purchase_item`, `resolve_pvp`, `reverse_transaction`, `admin_adjust_balance`) được tự động sinh một mã `client_request_id` theo chuẩn: `req_<timestamp>_<random>`.
  * Khi gặp lỗi mạng hoặc retry, mã `client_request_id` này **được giữ nguyên** cho cùng một ý định của người dùng, đảm bảo cơ chế Idempotent ở DB hoạt động chuẩn xác, không tạo thêm giao dịch trùng lặp.
* **Từ điển lỗi Tiếng Việt (`errors.vi.ts`):**
  * Ánh xạ toàn bộ mã lỗi từ tài liệu `error-codes.md` (bao gồm lỗi Auth, Claim trạm, Kinh tế Shop, PvP, Reversal, Admin CRUD).
  * Chuyển đổi mã lỗi khô khan từ PostgreSQL thành thông điệp tiếng Việt dễ hiểu cho nhân sự thao tác ngoài thực địa.
* **Xử lý `UNAUTHENTICATED`:**
  * Bắt cả trường hợp lỗi PostgreSQL RPC và JSON `{ success: false, code: 'UNAUTHENTICATED' }`.
  * Kích hoạt sự kiện `evermyst:unauthenticated` để `SessionProvider` dọn dẹp phiên và đưa về đăng nhập.
* **TypeScript Types an toàn:**
  * Bổ sung bảng ánh xạ `RpcMap` cho toàn bộ 32 RPC trong hệ thống.
  * Hỗ trợ nạp chồng (overload) `callRpc<K>(rpcName: K, args?: RpcMap[K]['args'])`, đảm bảo gõ code có gợi ý tham số và kiểu trả về chuẩn xác 100%.

---

### 4. Hook Realtime `useSignal` & Widget Kết Nối
* **Đăng ký kênh tín hiệu nhẹ (ADR-3):**
  * Khởi tạo kênh `realtime_signals_<topic>` lắng nghe các thông điệp `broadcast` gọn nhẹ được kích hoạt từ trigger database (`station_claims_changed`, `transactions_changed`, `teams_changed`).
* **Debounce 300 ms:**
  * Khi nhiều sự kiện dồn dập đến cùng lúc, hook gom lại và chờ 300ms trước khi gọi hàm refetch dữ liệu, triệt tiêu hiện tượng lag giật và bão request lên máy chủ.
* **Tự động phục hồi & Fallback Polling 10 giây:**
  * Khi WebSocket Supabase bị ngắt kết nối (`CLOSED`, `CHANNEL_ERROR`, hoặc thiết bị mất mạng), hook chuyển trạng thái sang `polling` và tự động kích hoạt bộ đếm Polling chu kỳ 10 giây một lần.
  * Khi đường truyền phục hồi (`SUBSCRIBED`), Polling tự động dừng và chuyển lại trạng thái `connected`.
* **Chỉ báo trạng thái kết nối (`ConnectionIndicator.tsx`):**
  * Thiết kế theo phong cách Cyberpunk Glow, hiển thị rõ ràng trên thiết bị di động ngoài trời:
    * 🟢 **Trực tuyến:** Icon Wifi xanh lục, kết nối Realtime ổn định.
    * 🟡 **Mất kết nối • Polling 10s:** Icon vàng nhấp nháy, ứng dụng đang tự động lấy dữ liệu nền định kỳ.
    * 🔵 **Đang kết nối...:** Icon xoay tròn, đang thiết lập lại kênh truyền.
    * 🔴 **Ngoại tuyến:** Mất kết nối hoàn toàn.
    * Tích hợp nút làm mới tức thì (Refetch Now) để nhân viên chủ động tải lại khi cần.

---

### 5. Loại Bỏ Hoàn Toàn Bộ Chọn Đội (Team Switcher) Ở UI Support
* **Giao diện Support:**
  * Xóa bỏ hoàn toàn thanh dropdown chọn đội chơi.
  * Xóa bỏ camera quét mã QR đổi đội chơi.
* **Khóa chặt vào `assigned_team`:**
  * Thanh `TopBar` của Support hiển thị cố định tên đội được phân công từ Token phiên đăng nhập (`user.assigned_team`).
  * Mọi tab nghiệp vụ (Chấm trạm, Mua Manh mối, Cửa hàng Đạo cụ, Lịch sử) chỉ hiển thị và thao tác trên đội phụ trách duy nhất này.
  * Nếu tài khoản Support chưa được gán đội trong database, hệ thống hiển thị thông báo yêu cầu liên hệ Admin để gán đội, không cho phép tự ý chọn đội khác.

---

## 3. BẢNG KIỂM TRA CHẤP NHẬN (ACCEPTANCE CHECKLIST)

| Kịch bản kiểm thử | Hành vi kỳ vọng | Kết quả |
| :--- | :--- | :--- |
| **1. Đăng nhập PIN tại `/`** | Nhập đúng mã PIN của nhân sự `team_support` $\rightarrow$ Tự động chuyển hướng về `/support`. Nhập mã của `station_master` $\rightarrow$ chuyển về `/station`. Nhập mã `admin` $\rightarrow$ chuyển về `/admin`. | **ĐẠT** |
| **2. Truy cập trái phép URL `/admin` bằng Support** | Đăng nhập tài khoản Support, gõ URL `/admin` trên thanh địa chỉ trình duyệt $\rightarrow$ Bị chặn và tự động đưa về `/support`. | **ĐẠT** |
| **3. Truy cập trái phép URL `/station` bằng Support** | Đăng nhập tài khoản Support, gõ URL `/station` $\rightarrow$ Bị chặn và tự động đưa về `/support`. | **ĐẠT** |
| **4. Truy cập trái phép URL bằng Station Master** | Đăng nhập tài khoản Trạm Trưởng, gõ `/admin` hoặc `/support` $\rightarrow$ Bị chặn và tự động đưa về `/station`. | **ĐẠT** |
| **5. Chưa đăng nhập truy cập route nội bộ** | Truy cập `/support`, `/station` hoặc `/admin` khi chưa có token $\rightarrow$ Bị đưa về `/`. | **ĐẠT** |
| **6. Flash màn hình khi tải trang (F5)** | Bấm F5 tải lại trang $\rightarrow$ `SessionProvider` chỉ render màn hình chờ Evermyst Shield, không xuất hiện chớp flash nội dung trước khi xác thực xong. | **ĐẠT** |
| **7. Không còn Team Switcher ở Support** | Màn hình `/support` không còn dropdown chọn đội và không còn nút bật camera quét QR đổi đội. Toàn bộ thông tin gắn liền với `assigned_team`. | **ĐẠT** |
| **8. Token hết hạn hoặc bị thu hồi** | Khi RPC trả về mã lỗi `UNAUTHENTICATED` $\rightarrow$ Tự động dọn token khỏi localStorage và đưa người dùng về trang đăng nhập `/`. | **ĐẠT** |
| **9. Mất kết nối mạng / WebSocket gián đoạn** | Ngắt kết nối $\rightarrow$ Indicator chuyển sang màu vàng nhấp nháy "Mất kết nối • Polling 10s" và tự động gửi request polling mỗi 10 giây. | **ĐẠT** |
| **10. Khôi phục kết nối mạng** | Bật lại mạng $\rightarrow$ WebSocket kết nối lại thành công, Polling tự dừng, Indicator chuyển về xanh lục "Trực tuyến". | **ĐẠT** |
| **11. Kiểm tra build TypeScript** | Chạy `npm run build` (`tsc -b && vite build`) $\rightarrow$ Mã nguồn biên dịch thành công 100%, 0 lỗi type. | **ĐẠT** |

---

## 4. KẾT LUẬN

Phase 6 đã hoàn thành xuất sắc toàn bộ các mục tiêu đề ra:
1. **Kiến trúc phân quyền UI vững chắc:** Đảm bảo trải nghiệm trực quan, ngăn chặn triệt để nhân sự nhìn thấy hoặc can thiệp vào các trang ngoài phạm vi nhiệm vụ của mình.
2. **Lớp API RPC chuẩn hóa:** Tự động hóa việc gắn token, sinh mã Idempotency duy nhất, dịch mã lỗi sang Tiếng Việt và phản ứng tức thì khi phiên hết hạn.
3. **Cơ chế Realtime & Offline bền bỉ:** Lắng nghe tín hiệu nhẹ với Debounce 300ms và tự động chuyển sang Polling 10s khi gặp sự cố mạng thực địa, kèm chỉ báo trực quan.
4. **Giao diện Support tinh giản:** Loại bỏ hoàn toàn bộ chọn đội, gắn chặt quyền hạn và nghiệp vụ vào đội chơi được phân công.
5. **Biên dịch Production Bundle hoàn tất:** Mã nguồn đạt chuẩn TypeScript nghiêm ngặt, sẵn sàng đưa vào vận hành thực địa.
