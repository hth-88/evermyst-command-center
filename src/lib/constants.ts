// ============================================================================
// CONSTANTS - Dữ liệu mặc định và cấu hình tĩnh (constants.ts)
// ============================================================================
import type { Item, Hint, GameConfig } from './types';

export const DEFAULT_CONFIG: GameConfig = {
  starting_balance: 100,
  station_reward_low: 20,
  station_reward_mid: 35,
  station_reward_high: 50,
  pending_threshold: 50,
  hint_price_bronze: 20,
  hint_price_silver: 50,
  hint_price_gold: 100,
  pvp_cooldown_minutes: 30,
  pvp_steal_percent: 15,
  pvp_backlash_amount: 10,
  shield_duration_minutes: 20,
  undo_window_minutes: 5,
};

export const DEFAULT_ITEMS: Item[] = [
  {
    id: '30000000-0000-0000-0000-000000000001',
    item_code: 'shield',
    name: 'Khiên Màn Sương',
    description: 'Kích hoạt bảo vệ đội khỏi tấn công PvP trong 20 phút. Nếu bị đánh lén, kẻ địch bị phạt phản phệ 10 Lumen.',
    price: 30,
    effect_type: 'shield',
    duration_minutes: 20,
    is_active: true,
    created_at: new Date().toISOString(),
  },
  {
    id: '30000000-0000-0000-0000-000000000002',
    item_code: 'spyglass',
    name: 'Kính Vọng Tầm',
    description: 'Soi ngay số dư Lumen hiện tại và trạng thái Khiên bảo vệ của 1 đội đối thủ bất kỳ.',
    price: 20,
    effect_type: 'spyglass',
    duration_minutes: 0,
    is_active: true,
    created_at: new Date().toISOString(),
  },
  {
    id: '30000000-0000-0000-0000-000000000003',
    item_code: 'master_key',
    name: 'Chìa Khóa Vạn Năng',
    description: 'Kích hoạt huy hiệu Chìa Khóa tại trạm mục tiêu, giúp đội vượt qua câu đố khó hoặc mở lối tắt.',
    price: 60,
    effect_type: 'master_key',
    duration_minutes: 0,
    is_active: true,
    created_at: new Date().toISOString(),
  },
];

export const DEFAULT_HINTS: Hint[] = [
  {
    id: '40000000-0000-0000-0000-000000000001',
    title: 'Mật Thư Cổ Tự (Đồng)',
    content: 'Đọc ngược các chữ cái in hoa đầu mỗi khổ thơ trên bảng hiệu trạm: "L-U-M-E-N" chính là chìa khóa khởi động.',
    tier: 'bronze',
    station_id: null,
    price: 20,
    order_index: 1,
    is_active: true,
    created_at: new Date().toISOString(),
  },
  {
    id: '40000000-0000-0000-0000-000000000002',
    title: 'Mật Thư Bản Đồ (Bạc)',
    content: 'Dưới chân tảng đá hình lăng kính có khắc tọa độ phụ. Đi về hướng Bắc 15 bước chân sẽ thấy hộp mật mã thứ hai.',
    tier: 'silver',
    station_id: null,
    price: 50,
    order_index: 2,
    is_active: true,
    created_at: new Date().toISOString(),
  },
  {
    id: '40000000-0000-0000-0000-000000000003',
    title: 'Bí Mật Đỉnh Tháp (Vàng)',
    content: 'Đáp án câu đố cuối cùng là chuỗi số Fibonacci: 1 - 1 - 2 - 3 - 5 - 8. Tổng số nhân đôi = 40 Lumen quà tặng ẩn.',
    tier: 'gold',
    station_id: null,
    price: 100,
    order_index: 3,
    is_active: true,
    created_at: new Date().toISOString(),
  },
];
