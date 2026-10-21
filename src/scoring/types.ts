// ============================================================================
// SCORING ENGINE TYPES (src/scoring/types.ts)
// File: src/scoring/types.ts
// Các kiểu dữ liệu chấm điểm trạm dùng chung giữa Client và Server (ADR-4)
// ============================================================================

export type ScoringType = 'tier' | 'fixed' | 'time_attack';

export interface TierItem {
  tier: string;
  label?: string;
  points: number;
}

export interface TierScoringConfig {
  tiers: TierItem[];
}

export interface FixedScoringConfig {
  points?: number;
  options?: Array<{ id: string; label: string; points?: number }>;
}

export interface TimeAttackScoringConfig {
  base_points?: number;
  unit_points?: number;
  max_units?: number;
  unit_label?: string;
}

export type ScoringConfig = TierScoringConfig | FixedScoringConfig | TimeAttackScoringConfig | Record<string, any>;

export interface TierScoringInput {
  tier: string;
}

export interface FixedScoringInput {
  completed: boolean;
  selected_options?: string[];
}

export interface TimeAttackScoringInput {
  units: number;
}

export type ScoringInput = TierScoringInput | FixedScoringInput | TimeAttackScoringInput | Record<string, any>;

export interface ScoringPreviewResult {
  points: number;
  isValid: boolean;
  error?: string;
}
