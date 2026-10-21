// ============================================================================
// UTILS - Utility functions cho Evermyst
// ============================================================================
import { clsx, type ClassValue } from 'clsx';
import type { StandardErrorCode } from './types';

/** Merge TailwindCSS classes */
export function cn(...inputs: ClassValue[]) {
  return clsx(inputs);
}

// ---------------------------------------------------------------------------
// Server Time Synchronization (Nguyên tắc 5)
// ---------------------------------------------------------------------------
let globalServerOffsetMs = 0;

/** Set độ lệch giữa giờ server và giờ client (ms) */
export function setServerOffset(offsetMs: number) {
  globalServerOffsetMs = offsetMs;
}

/** Lấy timestamp hiện tại đã hiệu chỉnh theo giờ server */
export function getServerNow(): number {
  return Date.now() + globalServerOffsetMs;
}

/** Lấy đối tượng Date chuẩn theo giờ server */
export function getServerDate(): Date {
  return new Date(getServerNow());
}

/** Sinh UUIDv4 client_request_id cho Idempotency (Nguyên tắc 2) */
export function generateClientId(): string {
  if (typeof crypto !== 'undefined' && crypto.randomUUID) {
    return crypto.randomUUID();
  }
  return 'req-' + Date.now().toString(36) + '-' + Math.random().toString(36).slice(2, 9);
}

// ---------------------------------------------------------------------------
// Shield & Cooldown Calculation
// ---------------------------------------------------------------------------

/** Tính thời gian còn lại của Shield dựa trên giờ server */
export function getShieldRemaining(shieldUntil: string | null): {
  active: boolean;
  minutes: number;
  seconds: number;
  totalSeconds: number;
  label: string;
} {
  if (!shieldUntil) {
    return { active: false, minutes: 0, seconds: 0, totalSeconds: 0, label: 'Không có khiên' };
  }

  const until = new Date(shieldUntil).getTime();
  const now = getServerNow();
  const diff = until - now;

  if (diff <= 0) {
    return { active: false, minutes: 0, seconds: 0, totalSeconds: 0, label: 'Khiên đã hết hạn' };
  }

  const totalSeconds = Math.floor(diff / 1000);
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;

  return {
    active: true,
    minutes,
    seconds,
    totalSeconds,
    label: `🛡️ Khiên: ${minutes}p ${seconds < 10 ? '0' : ''}${seconds}s`,
  };
}

/** Tính thời gian còn lại của Cooldown PvP */
export function getCooldownRemaining(cooldownUntil: string | null): {
  active: boolean;
  minutes: number;
  seconds: number;
  label: string;
} {
  if (!cooldownUntil) return { active: false, minutes: 0, seconds: 0, label: 'Sẵn sàng' };

  const until = new Date(cooldownUntil).getTime();
  const now = getServerNow();
  const diff = until - now;

  if (diff <= 0) return { active: false, minutes: 0, seconds: 0, label: 'Sẵn sàng' };

  const totalSeconds = Math.floor(diff / 1000);
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;

  return {
    active: true,
    minutes,
    seconds,
    label: `⏳ Cooldown: ${minutes}p ${seconds < 10 ? '0' : ''}${seconds}s`,
  };
}

/** Tính thời gian còn lại của cửa sổ hoàn tác Reversal */
export function getUndoTimeRemaining(
  createdAt: string,
  windowMinutes: number = 5
): {
  canUndo: boolean;
  secondsRemaining: number;
  label: string;
} {
  const created = new Date(createdAt).getTime();
  const now = getServerNow();
  const windowMs = windowMinutes * 60 * 1000;
  const diff = created + windowMs - now;

  if (diff <= 0) {
    return { canUndo: false, secondsRemaining: 0, label: 'Hết hạn hoàn tác' };
  }

  const totalSeconds = Math.floor(diff / 1000);
  const mins = Math.floor(totalSeconds / 60);
  const secs = totalSeconds % 60;

  return {
    canUndo: true,
    secondsRemaining: totalSeconds,
    label: `Còn ${mins}p ${secs < 10 ? '0' : ''}${secs}s`,
  };
}

// ---------------------------------------------------------------------------
// Formatters
// ---------------------------------------------------------------------------

/** Format timestamp -> "HH:mm:ss" */
export function formatTime(isoString: string): string {
  const d = new Date(isoString);
  return d.toLocaleTimeString('vi-VN', { hour: '2-digit', minute: '2-digit', second: '2-digit' });
}

/** Format timestamp -> "HH:mm DD/MM" */
export function formatDateTime(isoString: string): string {
  const d = new Date(isoString);
  return d.toLocaleString('vi-VN', {
    hour: '2-digit',
    minute: '2-digit',
    day: '2-digit',
    month: '2-digit',
  });
}

/** Format Lumen balance with sign */
export function formatLumen(amount: number): string {
  return amount >= 0 ? `+${amount}` : `${amount}`;
}

/** Transaction type -> Vietnamese label */
export function getTransactionLabel(type: string): string {
  const labels: Record<string, string> = {
    station_clear: '🏰 Thưởng Trạm',
    buy_hint: '🔍 Mua Hint',
    buy_item: '🎒 Mua Đạo Cụ',
    pvp_steal: '⚔️ PvP Cướp',
    pvp_backlash: '🛡️ Phản Phệ PvP',
    admin_adjust: '👑 Admin Can Thiệp',
    reversal: '↩️ Hoàn Tác (Revert)',
  };
  return labels[type] || type;
}

/** Tier -> Vietnamese label + color class */
export function getTierInfo(tier: string): { label: string; color: string; bgColor: string } {
  const tiers: Record<string, { label: string; color: string; bgColor: string }> = {
    bronze: { label: '🥉 Đồng', color: 'text-amber-500', bgColor: 'bg-amber-500/10 border-amber-500/30' },
    silver: { label: '🥈 Bạc', color: 'text-slate-300', bgColor: 'bg-slate-300/10 border-slate-300/30' },
    gold: { label: '🥇 Vàng', color: 'text-yellow-400', bgColor: 'bg-yellow-400/10 border-yellow-400/30' },
  };
  return tiers[tier] || { label: tier, color: 'text-slate-400', bgColor: 'bg-slate-400/10 border-slate-400/30' };
}

/** Dịch mã lỗi tiêu chuẩn sang thông điệp tiếng Việt thân thiện */
export function getStandardErrorMessage(code?: StandardErrorCode | string, fallback?: string): string {
  const messages: Record<string, string> = {
    INVALID_TOKEN: 'Phiên đăng nhập đã hết hạn hoặc không hợp lệ. Vui lòng đăng nhập lại.',
    FORBIDDEN: 'Bạn không có quyền thực hiện hành động này.',
    GAME_NOT_RUNNING: 'Trò chơi hiện chưa bắt đầu hoặc đang tạm dừng.',
    INVALID_AMOUNT: 'Số lượng hoặc số điểm không hợp lệ.',
    TEAM_NOT_FOUND: 'Không tìm thấy thông tin đội chơi.',
    INSUFFICIENT_FUNDS: 'Số dư Lumen của đội không đủ để thực hiện.',
    PRICE_CHANGED: 'Giá vật phẩm hoặc gợi ý đã bị thay đổi.',
    ALREADY_OWNED: 'Đội đã sở hữu manh mối hoặc vật phẩm này.',
    LIMIT_REACHED: 'Đã đạt giới hạn tối đa cho phép.',
    ALREADY_REWARDED: 'Đội này đã được ghi nhận hoàn thành trạm này.',
    COOLDOWN_ACTIVE: 'Đang trong thời gian chờ (cooldown). Vui lòng thử lại sau.',
    NOTHING_TO_STEAL: 'Đội phòng thủ không còn Lumen để cướp.',
    NOT_PENDING: 'Giao dịch không ở trạng thái chờ duyệt.',
    ALREADY_REVERSED: 'Giao dịch này đã được hoàn tác trước đó.',
    NOT_REVERSIBLE: 'Giao dịch không thể hoàn tác.',
    UNDO_WINDOW_EXPIRED: 'Đã hết thời hạn hoàn tác (vui lòng liên hệ Admin).',
    NOT_FOUND: 'Không tìm thấy dữ liệu yêu cầu.',
    INVALID_CREDENTIALS: 'Mã PIN không đúng hoặc tài khoản bị khóa.',
    NOT_OWNED: 'Đội không sở hữu vật phẩm này.',
  };

  if (code && messages[code]) return messages[code];
  return fallback || 'Đã có lỗi xảy ra. Vui lòng thử lại.';
}

/** Generate simple unique ID */
export function generateId(): string {
  return Date.now().toString(36) + Math.random().toString(36).slice(2, 6);
}
