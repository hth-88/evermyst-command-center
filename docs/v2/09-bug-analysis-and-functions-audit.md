# BÁO CÁO PHÂN TÍCH LỖI VÀ KIỂM TOÁN HÀM HỆ THỐNG
**Dự án:** Evermyst Command Center v2.0  
**Ngày lập:** 21/10/2026  
**Mục đích:** Tài liệu kỹ thuật chi tiết phục vụ lập kế hoạch Prompts khắc phục sự cố cho Claude.

---

## I. TỔNG QUAN 3 VẤN ĐỀ NGHIỆP VỤ PHÁT SINH

Dựa trên phản hồi thực tế từ người dùng và 4 ảnh chụp màn hình hiện trường:
1. **Vấn đề 1: Không chọn được mức điểm ở trạm ("k chọn được mức")**
   - *Hiện tượng:* Support mở tab Trạm (Trạm 1: Cổng Sương Mù), bấm "Nộp kết quả trạm" $\rightarrow$ Khung hiển thị: *"Chưa có cấu hình phân hạng cho trạm này."* và báo lỗi đỏ *"Vui lòng chọn mức độ hoàn thành (Tier)."*. Nút gửi bị vô hiệu hóa hoặc không thể submit.
2. **Vấn đề 2: Cắm được cùng lúc 2 chìa khóa vào 1 trạm ("cắm được cùng lúc 2 chìa khóa vạn năng vào 1 trạm")**
   - *Hiện tượng:* Đội sở hữu $\ge 2$ Chìa Khóa Vạn Năng. Khi mở modal cắm chìa khóa, người dùng bấm chọn Trạm 1 đã cắm chìa khóa trước đó $\rightarrow$ Hệ thống vẫn cho bấm, tiếp tục trừ mất 1 chìa khóa trong kho đồ, khiến người dùng nghĩ rằng trạm nhận được 2 chìa khóa (hoặc bị nuốt mất chìa khóa vô lý).
3. **Vấn đề 3: Đã bật Khiên bảo vệ nhưng vẫn bị cướp điểm trong PvP ("rõ ràng dùng khiên r vẫn bị cướp là sao")**
   - *Hiện tượng:* Đội 1 (Lửa Thiêng) đã dùng Khiên Màn Sương, TopBar đếm ngược hiển thị rõ: `Khiên: 18p 44s` và `Khiên: 39p 53s`. Tuy nhiên khi diễn ra trận đấu PvP, Đội 1 vẫn bị trừ tiền (số dư tụt từ 1020✦ xuống 670✦) thay vì kích hoạt phản phệ phạt kẻ tấn công 10 Lumen.

---

## II. PHÂN TÍCH NGUYÊN NHÂN CỐT LÕI (ROOT CAUSE ANALYSIS)

### 1. Phân tích Vấn đề 1: Không chọn được mức điểm (Mô hình Tier rỗng)

#### A. Nguyên nhân Database
- Khi khởi tạo hoặc sau khi chạy migration ban đầu trên Supabase, bảng `stations` bị thiếu cột `scoring_config` hoặc dữ liệu `scoring_config` của các trạm đang là `{}` hoặc `NULL`.
- Khi Admin mở modal `StationEditorModal` để cấu hình danh sách Tier và bấm **LƯU TRẠM**, RPC `admin_upsert_station` bị lỗi `column "scoring_type" of relation "stations" does not exist` (do thiếu migration 102 trên Cloud), làm cho cấu hình Tier không bao giờ được ghi xuống Database.

#### B. Nguyên nhân Frontend Client
- Tại [`src/components/scoring/TierPicker.tsx`](file:///c:/Users/ADMIN/Documents/ProPTIT/Ban%20SK/BIGGAME%20D26/src/components/scoring/TierPicker.tsx#L23-L29):
  ```tsx
  if (tiers.length === 0) {
    return (
      <div className="p-4 rounded-xl bg-evermyst-card border border-evermyst-border text-center text-xs text-evermyst-text-muted">
        Chưa có cấu hình phân hạng cho trạm này.
      </div>
    );
  }
  ```
- Tại [`src/components/scoring/StationScoringForm.tsx`](file:///c:/Users/ADMIN/Documents/ProPTIT/Ban%20SK/BIGGAME%20D26/src/components/scoring/StationScoringForm.tsx#L41-L44):
  ```tsx
  if (scoringType === 'tier') {
    const tiers = (scoringConfig as any)?.tiers || [];
    return { tier: tiers[0]?.tier || '' };
  }
  ```
- Tại [`src/components/support/StationTab.tsx`](file:///c:/Users/ADMIN/Documents/ProPTIT/Ban%20SK/BIGGAME%20D26/src/components/support/StationTab.tsx#L76-L91):
  Khi RPC `get_team_station_status` trả về hoặc khi fallback từ `stations`, trường `scoring_config` là `{}`.
- **Điểm yếu chí mạng:** Hệ thống hoàn toàn **không có default tiers fallback**. Nếu trạm chưa có config trong DB, frontend không tự động nạp cấu hình mặc định (ví dụ: Tier 1: 50✦, Tier 2: 30✦, Tier 3: 15✦), khiến danh sách `tiers` bị rỗng hoàn toàn $\rightarrow$ UI tê liệt.

---

### 2. Phân tích Vấn đề 2: Cắm 2 Chìa Khóa Vạn Năng vào cùng 1 Trạm

#### A. Nguyên nhân Frontend
- Tại [`src/components/support/ShopTab.tsx`](file:///c:/Users/ADMIN/Documents/ProPTIT/Ban%20SK/BIGGAME%20D26/src/components/support/ShopTab.tsx#L808-L834):
  ```tsx
  {activeStations.map((st) => {
    const alreadyHasKey = activeKeyStationIds.includes(st.id);
    return (
      <button
        key={st.id}
        onClick={() => setSelectedStationId(st.id)}
        // THIẾU: disabled={alreadyHasKey}
        className={...}
      >
        ...
        {alreadyHasKey && (
          <span className="text-[10px] font-bold text-amber-400 flex items-center gap-0.5">
            <CheckCircle2 className="w-3 h-3" /> Đã cắm
          </span>
        )}
      </button>
    );
  })}
  ```
  Nút trạm đã cắm chìa khóa hiển thị nhãn `Đã cắm` nhưng **KHÔNG CÓ thuộc tính `disabled={alreadyHasKey}`** và nút submit "KÍCH HOẠT TẠI TRẠM NÀY" vẫn cho bấm tiếp!
- Tại [`src/components/support/KeyModal.tsx`](file:///c:/Users/ADMIN/Documents/ProPTIT/Ban%20SK/BIGGAME%20D26/src/components/support/KeyModal.tsx#L104-L119):
  Nút chỉ kiểm tra `isCleared = unlockedStationIds.includes(st.id)` chứ **không kiểm tra xem trạm đã có chìa khóa chưa (`has_key`)**.

#### B. Nguyên nhân Database / Backend RPC & Client Fallback
- Tại [`src/contexts/GameContext.tsx`](file:///c:/Users/ADMIN/Documents/ProPTIT/Ban%20SK/BIGGAME%20D26/src/contexts/GameContext.tsx#L977-L990) (`executeUseItem`):
  Hệ thống **trừ số lượng vật phẩm trong kho TRƯỚC** (`setTeamItems` trừ -1), rồi mới kiểm tra:
  ```ts
  setTeamStationKeys((prev) => {
    const currentList = prev[teamId] || [];
    if (!currentList.includes(targetStationId)) {
      // Chỉ add nếu chưa có
      return { ...prev, [teamId]: [...currentList, targetStationId] };
    }
    return prev; // Đã có rồi thì không add thêm
  });
  ```
  Kết quả: Vì không chặn ở đầu hàm, người dùng bị **trừ mất 1 chìa khóa**, nhưng trạm thì không được add thêm gì mới (vì đã có rồi).
- Trong SQL [`101_shop_inventory_rpc_fix.sql`](file:///c:/Users/ADMIN/Documents/ProPTIT/Ban%20SK/BIGGAME%20D26/supabase/migrations/101_shop_inventory_rpc_fix.sql#L607-L612 & L681-L685):
  Hàm RPC cũng chạy `UPDATE team_items SET quantity = quantity - 1` trước, sau đó mới `INSERT INTO team_station_keys ... ON CONFLICT DO NOTHING`. Ràng buộc `UNIQUE(team_id, station_id)` chặn không cho insert dòng thứ 2, nhưng chìa khóa trong kho đã bị trừ mất!

---

### 3. Phân tích Vấn đề 3: Đã dùng Khiên nhưng vẫn bị cướp trong PvP

Đây là lỗi kết hợp giữa **lệch chữ ký RPC**, **logic role phân quyền trong SQL cũ**, và **đồng bộ trạng thái DB**.

#### A. Lệch tên tham số RPC `resolve_pvp`
- Trong [`src/contexts/GameContext.tsx`](file:///c:/Users/ADMIN/Documents/ProPTIT/Ban%20SK/BIGGAME%20D26/src/contexts/GameContext.tsx#L1031-L1034):
  ```ts
  const res = await callRpc<any>('resolve_pvp', {
    p_attacker_id: attackerId,
    p_defender_id: defenderId,
  });
  ```
- Trong SQL [`101_shop_inventory_rpc_fix.sql`](file:///c:/Users/ADMIN/Documents/ProPTIT/Ban%20SK/BIGGAME%20D26/supabase/migrations/101_shop_inventory_rpc_fix.sql#L846-L851):
  ```sql
  CREATE OR REPLACE FUNCTION resolve_pvp(
      p_token TEXT,
      p_client_request_id TEXT,
      p_attacker_team_id UUID,  -- KHÁC VỚI p_attacker_id
      p_defender_team_id UUID   -- KHÁC VỚI p_defender_id
  )
  ```
  Vì `callRpc` tự động bổ sung `p_token` và `p_client_request_id`, PostgREST trên Supabase tìm hàm có 4 tham số: `p_token`, `p_client_request_id`, `p_attacker_id`, `p_defender_id`. Do tên tham số không khớp (`p_attacker_id` vs `p_attacker_team_id`), PostgREST báo lỗi `Could not find function resolve_pvp in schema cache`.

#### B. Logic ép quyền trong `100_economy_engine.sql`
- Trong SQL [`100_economy_engine.sql`](file:///c:/Users/ADMIN/Documents/ProPTIT/Ban%20SK/BIGGAME%20D26/supabase/migrations/100_economy_engine.sql#L530-L535):
  ```sql
  v_staff := _require_staff(p_token, ARRAY['team_support', 'admin']);
  IF v_staff.role = 'admin' AND p_attacker_id IS NOT NULL THEN
      v_attacker_id := p_attacker_id;
  ELSE
      v_attacker_id := v_staff.assigned_team_id;
  END IF;
  ```
  Người dùng đang đăng nhập bằng PIN `777001` (vai trò là `team_support` của Đội 1 - Lửa Thiêng).
  Khi mở tab PvP để đóng vai Trọng tài test trận đấu giữa các đội:
  - Dù trên giao diện người dùng chọn **Đội Tấn Công = Đội 2**, **Đội Phòng Thủ = Đội 1 (Lửa Thiêng)**.
  - Khi gửi token của `777001`, SQL **ép cứng `v_attacker_id := v_staff.assigned_team_id` (tức là Đội 1)**!
  - Nghĩa là trong mắt Database, **Đội 1 là kẻ đi tấn công**, chứ không phải bị tấn công! Kẻ phòng thủ thực sự là Đội 2 (không có khiên). Vì thế Đội 1 cướp điểm hoặc giao dịch bị tính sai lệch hoàn toàn.

#### C. Lỗi đồng bộ `shield_until` giữa Frontend Fallback và Supabase
- Khi người dùng bấm kích hoạt khiên ở client fallback (`GameContext.tsx:918`):
  ```ts
  await supabase.from('teams').update({ shield_until: newShieldUntil }).eq('id', teamId);
  ```
  Nếu bảng `teams` trên Cloud chưa có cột `shield_until` (do chưa chạy migration 101/102), câu lệnh update thất bại âm thầm.
- Giá trị `newShieldUntil` chỉ tồn tại trong React state cục bộ của component lúc đó (TopBar hiển thị đếm ngược được nhờ state này).
- Tuy nhiên, khi tab PvP hoặc bất kỳ thao tác nào gọi `refreshAll()`, dữ liệu tải lại từ Supabase (`supabase.from('teams').select('*')`) trả về `shield_until = null`.
- Khi client fallback kiểm tra:
  ```ts
  const isShielded = defender.shield_until ? new Date(defender.shield_until).getTime() > Date.now() : false;
  ```
  Biến `isShielded` đánh giá thành `false` $\rightarrow$ Hệ thống thực thi cướp 15% số dư của Đội 1 bình thường!

---

## III. KIỂM TOÁN CHI TIẾT TỪNG HÀM HIỆN TẠI (SYSTEM FUNCTIONS AUDIT)

### 1. Nhóm Chấm Điểm & Mức Trạm (Scoring & Tiers)

| Tên Hàm / Component | File | Dòng | Trách nhiệm hiện tại | Lỗi & Điểm nghẽn phát hiện |
| :--- | :--- | :--- | :--- | :--- |
| `TierPicker` | `src/components/scoring/TierPicker.tsx` | L17–L29 | Render các nút chọn Tier theo mảng `tiers`. | Nếu `tiers.length === 0` thì render box báo lỗi *"Chưa có cấu hình phân hạng cho trạm này"*, chặn toàn bộ thao tác. Không có fallback tự sinh. |
| `StationScoringForm` | `src/components/scoring/StationScoringForm.tsx` | L26–L60 | Quản lý form nộp điểm động, tính toán `previewPoints`. | `const tiers = (scoringConfig as any)?.tiers || [];` $\rightarrow$ Nếu `scoringConfig` rỗng, `tiers = []`. Input `tier` bị gán chuỗi rỗng `''`. |
| `fetchStationStatuses` | `src/components/support/StationTab.tsx` | L65–L97 | Gọi RPC `get_team_station_status` hoặc fallback từ mảng `stations`. | Fallback gán `scoring_config: st.scoring_config`. Nếu trạm từ DB có `scoring_config = {}` thì form nhận `{}` và chết đứng. |
| `handleSubmitClaim` | `src/components/support/StationTab.tsx` | L104–L140 | Gửi yêu cầu claim trạm qua `submit_station_claim`. | Bị chặn ngay từ `if (!data || !data.isValid)` vì `currentInput.tier` rỗng nên không bao giờ bấm gửi được. |
| `StationEditorModal:handleSubmit` | `src/components/admin/StationEditorModal.tsx` | L140–L178 | Admin chỉnh sửa cấu hình trạm và lưu qua `admin_upsert_station`. | Bị crash với lỗi SQL `column "scoring_type" does not exist` do Cloud chưa có schema migration 102. |
| `admin_upsert_station` (RPC) | `supabase/migrations/102_admin_stations_items_pvp_fix.sql` | L100–L170 | Upsert cấu hình trạm trong PostgreSQL. | Đã được chuẩn hóa ở migration 102 (nhận UUID, hỗ trợ default config), cần đảm bảo được chạy trên Supabase Cloud. |
| `get_team_station_status` (RPC) | `supabase/migrations/090_station_claim_engine.sql` | L728–L790 | Lấy danh sách 5 trạm kèm trạng thái claim và key của đội. | Trả về `s.scoring_config`. Nếu DB lưu null/rỗng thì trả về null/rỗng mà không có default tier object. |

---

### 2. Nhóm Chìa Khóa Vạn Năng (Master Key & Inventory)

| Tên Hàm / Component | File | Dòng | Trách nhiệm hiện tại | Lỗi & Điểm nghẽn phát hiện |
| :--- | :--- | :--- | :--- | :--- |
| `ShopTab:Modal cắm chìa` | `src/components/support/ShopTab.tsx` | L808–L835 | Render danh sách trạm để Support chọn cắm chìa khóa. | Nút trạm chỉ hiện nhãn `Đã cắm`, **thiếu `disabled={alreadyHasKey}`**. Người dùng bấm chọn lại trạm cũ vẫn được. |
| `handleExecuteKey` | `src/components/support/ShopTab.tsx` | L200–L209 | Gọi `useItem(teamId, 'master_key', undefined, stationId)`. | Không validate phía client xem `activeKeyStationIds.includes(selectedStationId)` hay chưa trước khi gọi API. |
| `KeyModal:handleConfirmKey` | `src/components/support/KeyModal.tsx` | L37–L63 | Modal gán chìa khóa mở lối tắt. | Chỉ kiểm tra `unlockedStationIds` (đã clear hay chưa), không kiểm tra `teamKeys` (đã cắm chìa khóa hay chưa). |
| `executeUseItem` (nhánh `isKey`) | `src/contexts/GameContext.tsx` | L967–L1010 | Trừ kho và ghi nhận chìa khóa vào `teamStationKeys`. | **Trừ vật phẩm trong kho trước** khi kiểm tra `currentList.includes(targetStationId)`. Nếu trạm đã có chìa khóa, hệ thống vẫn trừ mất 1 chìa khóa trong kho! |
| `use_item` (RPC) | `supabase/migrations/101_shop_inventory_rpc_fix.sql` | L668–L700 | Xử lý kích hoạt vật phẩm trong PostgreSQL. | Thực hiện `UPDATE team_items SET quantity = quantity - 1` trước. Sau đó mới `INSERT ... ON CONFLICT DO NOTHING`. Bị nuốt mất vật phẩm nếu trùng khóa! |

---

### 3. Nhóm Khiên Màn Sương & Trọng Tài PvP (Shield & Combat)

| Tên Hàm / Component | File | Dòng | Trách nhiệm hiện tại | Lỗi & Điểm nghẽn phát hiện |
| :--- | :--- | :--- | :--- | :--- |
| `handleUseShield` | `src/components/support/ShopTab.tsx` | L180–L190 | Bấm nút KÍCH HOẠT (+20P) của Khiên Màn Sương. | Gọi `useItem(teamId, 'shield')`. Hoạt động tốt trên UI local nhưng phụ thuộc vào việc DB Cloud đã có cột `shield_until` hay chưa. |
| `executeUseItem` (nhánh `isShield`) | `src/contexts/GameContext.tsx` | L909–L936 | Tính toán `newShieldUntil = now() + 20m`, cập nhật state và update table `teams`. | Nếu DB chưa có cột `shield_until`, update Supabase âm thầm thất bại. Khi reload hoặc `refreshAll()`, state bị reset về null. |
| `PvPTab:handleFight` | `src/components/support/PvPTab.tsx` | L149–L157 | Trọng tài/Support kích hoạt trận đánh giữa 2 đội. | Gọi `resolvePvP(attackerId, defenderId)`. |
| `resolvePvP` (Client Fallback) | `src/contexts/GameContext.tsx` | L1028–L1118 | Gọi RPC `resolve_pvp`. Nếu lỗi thì vào Client Fallback tự tính toán. | - RPC bị lỗi do lệch tên tham số (`p_attacker_id` vs `p_attacker_team_id`).<br>- Khi vào fallback, `defender.shield_until` bị rỗng do DB không lưu được trước đó, khiến `isShielded = false` $\rightarrow$ Đội bật khiên vẫn bị cướp điểm! |
| `resolve_pvp` (RPC Migration 100) | `supabase/migrations/100_economy_engine.sql` | L520–L620 | RPC xử lý PvP chính thống trong DB. | Có lỗi logic: Ép `v_attacker_id := v_staff.assigned_team_id` nếu role là `team_support`. Làm Support không thể trọng tài trận đánh hoặc bị đảo ngược vai kẻ tấn công. |
| `resolve_pvp` (RPC Migration 101) | `supabase/migrations/101_shop_inventory_rpc_fix.sql` | L741–L859 | RPC xử lý PvP độc lập chống deadlock. | Đã có logic phản phệ trừ 10 Lumen, nhưng overload 4 tham số đặt tên là `p_attacker_team_id` thay vì `p_attacker_id`. |

---

## IV. BẢNG TỔNG HỢP GIẢI PHÁP ĐỀ XUẤT (ACTION PLAN)

Tài liệu này đề xuất 4 nhóm giải pháp kỹ thuật cụ thể để Claude đưa vào kế hoạch Prompts:

### 1. Khắc phục Lỗi Mức Trạm (Scoring & Tiers)
1. **Fallback Tầng Renderer:** Trong `StationScoringForm.tsx`, nếu `scoringType === 'tier'` mà `scoringConfig?.tiers` bị rỗng hoặc không có phần tử nào, tự động fallback về cấu hình Tier chuẩn:
   ```ts
   const DEFAULT_FALLBACK_TIERS = [
     { tier: 'tier_1', label: 'Giải mã hoàn hảo', points: 50 },
     { tier: 'tier_2', label: 'Hoàn thành tiêu chuẩn', points: 30 },
     { tier: 'tier_3', label: 'Hoàn thành trễ hạn', points: 15 },
   ];
   ```
2. **Fallback Tầng Context:** Trong `GameContext.tsx` hàm `refreshAll`, khi map danh sách `stations`, nếu `st.scoring_config` rỗng thì tự động bổ sung cấu hình Tier chuẩn trước khi lưu vào state `stations`.
3. **Thực thi Migration 102 trên DB:** Chạy file `102_admin_stations_items_pvp_fix.sql` để bảo đảm các cột `scoring_type`, `scoring_config` tồn tại và được backfill đầy đủ.

### 2. Khắc phục Lỗi Cắm Chìa Khóa Vạn Năng (Master Key)
1. **Khóa UI Modal:** Trong `ShopTab.tsx` và `KeyModal.tsx`, thêm thuộc tính `disabled={alreadyHasKey}` vào nút chọn trạm, hiển thị badge xám rõ ràng `"Đã có chìa khóa - Không thể cắm thêm"`.
2. **Validate Phía Client Trước Khi Trừ Đồ:** Trong `executeUseItem` (`GameContext.tsx`), kiểm tra ngay từ đầu:
   ```ts
   const currentKeys = teamStationKeys[teamId] || [];
   if (currentKeys.includes(targetStationId)) {
     addToast('Trạm này đã được cắm Chìa Khóa Vạn Năng từ trước!', 'warning');
     return { success: false, error: 'STATION_ALREADY_HAS_KEY' };
   }
   ```
   Chỉ khi trạm **chưa có chìa khóa** thì mới tiến hành trừ số lượng vật phẩm trong kho (`setTeamItems` và update DB).
3. **Khóa Tầng Database RPC:** Trong hàm RPC `use_item`, thêm bước kiểm tra:
   ```sql
   IF EXISTS (SELECT 1 FROM team_station_keys WHERE team_id = p_team_id AND station_id = p_target_station_id) THEN
       RETURN jsonb_build_object('success', false, 'code', 'KEY_ALREADY_EXISTS', 'error', 'Trạm này đã có chìa khóa.');
   END IF;
   ```
   Nếu đã có thì `RETURN` ngay, tuyệt đối không trừ `team_items.quantity`.

### 3. Khắc phục Lỗi Khiên Màn Sương & PvP (Shield & Combat)
1. **Đồng Bộ Tên Tham Số RPC `resolve_pvp`:**
   Cung cấp các overloads trong PostgreSQL nhận cả hai kiểu đặt tên tham số:
   - `resolve_pvp(p_token, p_client_request_id, p_attacker_id, p_defender_id)`
   - `resolve_pvp(p_token, p_client_request_id, p_attacker_team_id, p_defender_team_id)`
2. **Loại Bỏ Logic Ép Cứng Attacker Khi Trọng Tài Gọi PvP:**
   Nếu `p_attacker_id` và `p_defender_id` được truyền tường minh từ giao diện, RPC phải tôn trọng đúng `attacker` và `defender` được truyền vào, không tự ý gán đè `v_attacker_id := v_staff.assigned_team_id`.
3. **Bảo Đảm Lưu Trữ Bền Vững `shield_until`:**
   Chạy migration 101/102 để bảo đảm bảng `teams` trên Cloud có cột `shield_until TIMESTAMPTZ`. Khi Support kích hoạt khiên, giá trị `shield_until` phải được ghi thành công xuống Postgres và broadcast realtime tới tất cả client.
4. **Hiển Thị Cảnh Báo Khiên Trên Giao Diện PvP:**
   Trong `PvPTab.tsx`, khi chọn Đội Phòng Thủ đang có khiên bảo vệ còn hiệu lực (`defenderShield.active === true`), hiển thị hộp cảnh báo viền đỏ nổi bật:
   `"⚠️ CẢNH BÁO: Đội phòng thủ đang bật Khiên Màn Sương! Tấn công sẽ bị phản phệ trừ 10 Lumen!"` để người bấm biết trước kết quả trận đấu.
