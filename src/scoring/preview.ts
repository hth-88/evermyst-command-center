// ============================================================================
// SCORING PREVIEW CALCULATOR (src/scoring/preview.ts)
// File: src/scoring/preview.ts
// Hàm tính trước điểm (Preview) khớp 100% với hàm SQL compute_station_points
// Chú ý: Server luôn là nguồn tính điểm chính thức. Hàm này chỉ dùng để hiển thị UX.
// ============================================================================
import type {
  ScoringType,
  ScoringConfig,
  ScoringInput,
  ScoringPreviewResult,
  TierScoringConfig,
  TimeAttackScoringConfig,
} from './types';

/**
 * Tính toán điểm dự kiến dựa trên loại trạm, cấu hình và input người dùng
 */
export function previewPoints(
  type: ScoringType,
  config: ScoringConfig = {},
  input: ScoringInput = {},
  minScore = 0,
  maxScore = 100
): ScoringPreviewResult {
  if (!input || typeof input !== 'object') {
    return { points: 0, isValid: false, error: 'Input không hợp lệ.' };
  }

  let computedPoints = 0;

  try {
    // Model 1: TIER SCORING
    if (type === 'tier') {
      const tierConfig = config as TierScoringConfig;
      const tierReq = (input as any)?.tier;

      if (!tierReq || typeof tierReq !== 'string' || !tierReq.trim()) {
        return { points: 0, isValid: false, error: 'Vui lòng chọn mức độ hoàn thành (Tier).' };
      }

      const tiers = Array.isArray(tierConfig?.tiers) ? tierConfig.tiers : [];
      const matchedTier = tiers.find((t) => t.tier === tierReq.trim());

      if (!matchedTier) {
        return {
          points: 0,
          isValid: false,
          error: `Mức "${tierReq}" không tồn tại trong cấu hình trạm.`,
        };
      }

      computedPoints = Number(matchedTier.points) || 0;
    }

    // Model 2: FIXED SCORING
    else if (type === 'fixed') {
      const isCompleted = Boolean((input as any)?.completed);
      if (!isCompleted) {
        computedPoints = 0;
      } else {
        computedPoints = Number((config as any)?.points ?? maxScore ?? 30);
      }
    }

    // Model 3: TIME ATTACK / UNIT SCORING
    else if (type === 'time_attack') {
      const timeConfig = config as TimeAttackScoringConfig;
      const rawUnits = (input as any)?.units;

      if (rawUnits === undefined || rawUnits === null || isNaN(Number(rawUnits))) {
        return { points: 0, isValid: false, error: 'Vui lòng nhập số lượng đơn vị đạt được.' };
      }

      const units = Number(rawUnits);
      if (units < 0) {
        return { points: 0, isValid: false, error: 'Số lượng không được âm.' };
      }

      const maxUnits = Number(timeConfig?.max_units ?? 100);
      if (units > maxUnits) {
        return {
          points: 0,
          isValid: false,
          error: `Số lượng (${units}) vượt quá giới hạn tối đa (${maxUnits}).`,
        };
      }

      const basePoints = Number(timeConfig?.base_points ?? 0);
      const unitPoints = Number(timeConfig?.unit_points ?? 5);
      computedPoints = basePoints + units * unitPoints;
    } else {
      return { points: 0, isValid: false, error: `Loại chấm điểm "${type}" không được hỗ trợ.` };
    }

    // Ràng buộc trong ngưỡng min / max
    if (computedPoints < minScore) computedPoints = minScore;
    if (computedPoints > maxScore) computedPoints = maxScore;

    return {
      points: computedPoints,
      isValid: true,
    };
  } catch (err: any) {
    return {
      points: 0,
      isValid: false,
      error: err?.message || 'Lỗi tính toán điểm.',
    };
  }
}
