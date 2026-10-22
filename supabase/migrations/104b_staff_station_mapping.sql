-- =====================================================================
-- 104b_staff_station_mapping.sql
-- Gán trạm (assigned_station_id) cho Quản trò & Support Trạm 1 - 5
--
-- DỮ LIỆU ĐÃ ĐỐI CHIẾU:
-- 1. Bảng stations có 2 bộ trạm (16:38:29 và 16:42:32).
--    Bộ trạm đang hoạt động thực tế trên giao diện và trong teams.unlocked_stations
--    chính là bộ mới nhất (created_at 16:42:32).
-- 2. Bước A: Ẩn 5 bản ghi trạm cũ (soft-delete bằng deleted_at).
-- 3. Bước B: Gán UUID trạm chính xác cho 5 Quản Trò và 10 Support Trạm.
-- 4. Bước C: Truy vấn kiểm tra lại trạng thái sau khi gán.
-- =====================================================================

-- ---------------------------------------------------------------------
-- BƯỚC A: ẨN 5 BẢN GHI TRẠM CŨ BỊ TRÙNG (created_at lúc 16:38:29)
-- ---------------------------------------------------------------------
UPDATE public.stations 
SET deleted_at = now() 
WHERE id IN (
  '7a8d9016-1587-46e5-9a8e-4b96d821c454', -- Cổng Sương Mù (cũ)
  '8e1a6eb0-eed3-424c-a437-a75c845b1e4a', -- Đền Cổ Lumen (cũ)
  'f78844f3-38f4-4326-9c3e-798652ad3ff2', -- Rừng Bóng Tối (cũ)
  '1dd43ca4-ab24-4bac-a093-ce0a1543f569', -- Hồ Gương Phản Chiếu (cũ)
  'b6ed2a2b-e790-4fc3-9d9b-a8a1c0243e65'  -- Đỉnh Tháp Evermyst (cũ)
) AND deleted_at IS NULL;


-- ---------------------------------------------------------------------
-- BƯỚC B: GÁN TRẠM CHÍNH XÁC CHO QUẢN TRÒ VÀ SUPPORT TRẠM (15 NGƯỜI)
-- ---------------------------------------------------------------------

-- 1. Năm Quản Trò Trạm 1 - 5:
UPDATE public.staff SET assigned_station_id = '62c1aea6-d4cc-437a-8367-a2f6f831f143' WHERE id = 'f7e14023-f66b-4b9e-b74e-9c32686df32f'; -- Quản Trò Trạm 1
UPDATE public.staff SET assigned_station_id = 'e24d72fa-d0f7-4cb3-b766-9f791e996c6e' WHERE id = '9fb23580-6d6a-4dc9-ba09-d68177fb7e16'; -- Quản Trò Trạm 2
UPDATE public.staff SET assigned_station_id = 'a8089f77-4358-49f8-ab5a-9290ee66cba9' WHERE id = '048bc38a-2182-4d27-a92e-ab74004aa883'; -- Quản Trò Trạm 3
UPDATE public.staff SET assigned_station_id = '00ebfdd9-ab16-4cb4-a8e0-6ba9d2836e78' WHERE id = '05d48f1c-1f66-4229-a880-f84e0d13bc94'; -- Quản Trò Trạm 4
UPDATE public.staff SET assigned_station_id = '3283b49e-4e1d-47a5-9ef6-a31a15159a4e' WHERE id = 'a1892371-e756-4a1f-aba4-590651e4d949'; -- Quản Trò Trạm 5

-- 2. Support Trạm (Bộ 1):
UPDATE public.staff SET assigned_station_id = '62c1aea6-d4cc-437a-8367-a2f6f831f143' WHERE id = 'c8e4aa50-a693-4687-9c66-f7aed64c3a83'; -- Support Trạm 1
UPDATE public.staff SET assigned_station_id = 'e24d72fa-d0f7-4cb3-b766-9f791e996c6e' WHERE id = '43792836-f4fa-47e6-bca3-e1ed6f64e503'; -- Support Trạm 2
UPDATE public.staff SET assigned_station_id = 'a8089f77-4358-49f8-ab5a-9290ee66cba9' WHERE id = '8fc85bc9-02cd-41f2-9692-34d5f0aa5d2e'; -- Support Trạm 3
UPDATE public.staff SET assigned_station_id = '00ebfdd9-ab16-4cb4-a8e0-6ba9d2836e78' WHERE id = 'b5ea1d69-bcd0-478c-b475-3d3b016fe910'; -- Support Trạm 4
UPDATE public.staff SET assigned_station_id = '3283b49e-4e1d-47a5-9ef6-a31a15159a4e' WHERE id = '970e8ada-a32a-4d93-938b-96144822b368'; -- Support Trạm 5

-- 3. Support Trạm (Bộ 2):
UPDATE public.staff SET assigned_station_id = '62c1aea6-d4cc-437a-8367-a2f6f831f143' WHERE id = '7b974201-1afd-418b-893a-dc23e1a41eca'; -- Support Trạm 1
UPDATE public.staff SET assigned_station_id = 'e24d72fa-d0f7-4cb3-b766-9f791e996c6e' WHERE id = 'b6a8d924-ba51-4c55-850e-0dd4a7aa2f76'; -- Support Trạm 2
UPDATE public.staff SET assigned_station_id = 'a8089f77-4358-49f8-ab5a-9290ee66cba9' WHERE id = '39ab7935-15a5-4967-8a8c-c7da89f5bdf5'; -- Support Trạm 3
UPDATE public.staff SET assigned_station_id = '00ebfdd9-ab16-4cb4-a8e0-6ba9d2836e78' WHERE id = '8a3c7e11-6eae-4900-a6a5-16d17d12edf4'; -- Support Trạm 4
UPDATE public.staff SET assigned_station_id = '3283b49e-4e1d-47a5-9ef6-a31a15159a4e' WHERE id = '59945819-8ff8-4fe8-a148-e7bddf135e2b'; -- Support Trạm 5


-- ---------------------------------------------------------------------
-- BƯỚC C: TRUY VẤN KIỂM TRA LẠI KẾT QUẢ ĐÃ GÁN
-- ---------------------------------------------------------------------
SELECT 
  st.id AS staff_id,
  st.name AS staff_name,
  st.station_assigned AS text_assignment,
  s.name AS assigned_station_name,
  s.order_index AS station_order,
  st.assigned_station_id,
  CASE 
    WHEN st.assigned_station_id IS NOT NULL THEN '✅ ĐÃ_GÁN_XONG'
    WHEN st.station_assigned IS NULL THEN 'ℹ️ KHÔNG_PHẢI_SUPPORT_TRẠM'
    ELSE '⚠️ CHƯA_GÁN'
  END AS status
FROM public.staff st
LEFT JOIN public.stations s ON s.id = st.assigned_station_id
WHERE st.role = 'support'
ORDER BY s.order_index NULLS LAST, st.name;
