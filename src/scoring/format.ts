// ============================================================================
// SCORING INPUT FORMATTER (src/scoring/format.ts)
// File: src/scoring/format.ts
// Chuyển đổi input JSON thô thành nhãn tiếng Việt dễ đọc trên thẻ duyệt và lịch sử
// ============================================================================
import type { ScoringType, ScoringConfig, ScoringInput, TierScoringConfig } from './types';

/**
 * Format input thành chuỗi nhãn hiển thị trực quan
 */
export function formatScoringInput(
  type?: ScoringType | string,
  input?: ScoringInput | null,
  config?: ScoringConfig | null
): string {
  if (!input || typeof input !== 'object') {
    return 'Chưa có thông tin';
  }

  // Model 1: TIER
  if (type === 'tier' || 'tier' in input) {
    const tier = (input as any).tier;
    if (!tier) return 'Chưa chọn mức';

    const tiers = (config as TierScoringConfig)?.tiers || [];
    const matched = tiers.find((t) => t.tier === tier);
    const label = matched?.label || tier;

    return `Mức: ${label.toUpperCase()} (${matched?.points ?? '?'}✦)`;
  }

  // Model 2: FIXED
  if (type === 'fixed' || 'completed' in input) {
    const isCompleted = (input as any).completed;
    return isCompleted ? 'Hoàn thành thử thách' : 'Chưa hoàn thành';
  }

  // Model 3: TIME ATTACK
  if (type === 'time_attack' || 'units' in input) {
    const units = (input as any).units ?? 0;
    const unitLabel = (config as any)?.unit_label || 'lượt';
    return `Đạt được: ${units} ${unitLabel}`;
  }

  // Fallback: render JSON key-value
  try {
    return Object.entries(input)
      .map(([k, v]) => `${k}: ${v}`)
      .join(', ');
  } catch {
    return 'Dữ liệu không xác định';
  }
}
