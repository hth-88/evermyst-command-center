// ============================================================================
// DYNAMIC STATION SCORING FORM (src/components/scoring/StationScoringForm.tsx)
// File: src/components/scoring/StationScoringForm.tsx
// Renderer chấm điểm động theo scoring_type (TierPicker, UnitStepper, OptionChecklist)
// Dùng chung cho Support nộp điểm, Station Master nhập trực tiếp & duyệt kèm chỉnh
// ============================================================================
import React, { useState, useEffect, useMemo } from 'react';
import type { ScoringType, ScoringConfig, ScoringInput } from '@/scoring/types';
import { previewPoints } from '@/scoring/preview';
import { TierPicker } from './TierPicker';
import { UnitStepper } from './UnitStepper';
import { OptionChecklist } from './OptionChecklist';
import { Sparkles, AlertCircle, Info } from 'lucide-react';

interface StationScoringFormProps {
  scoringType: ScoringType;
  scoringConfig: ScoringConfig;
  minScore?: number;
  maxScore?: number;
  initialInput?: ScoringInput;
  onChange?: (input: ScoringInput, points: number, isValid: boolean) => void;
  readOnly?: boolean;
  className?: string;
}

export const StationScoringForm: React.FC<StationScoringFormProps> = ({
  scoringType = 'tier',
  scoringConfig = {},
  minScore = 0,
  maxScore = 100,
  initialInput,
  onChange,
  readOnly = false,
  className = '',
}) => {
  // Khởi tạo state input dựa trên scoringType
  const [currentInput, setCurrentInput] = useState<ScoringInput>(() => {
    if (initialInput && Object.keys(initialInput).length > 0) {
      return initialInput;
    }
    if (scoringType === 'tier') {
      const tiers = (scoringConfig as any)?.tiers || [];
      return { tier: tiers[0]?.tier || '' };
    }
    if (scoringType === 'fixed') {
      return { completed: true, selected_options: [] };
    }
    if (scoringType === 'time_attack') {
      return { units: 1 };
    }
    return {};
  });

  // Khi initialInput thay đổi (ví dụ mở modal sửa claim)
  useEffect(() => {
    if (initialInput && Object.keys(initialInput).length > 0) {
      setCurrentInput(initialInput);
    }
  }, [initialInput]);

  // Tính điểm xem trước (Preview)
  const preview = useMemo(() => {
    return previewPoints(scoringType, scoringConfig, currentInput, minScore, maxScore);
  }, [scoringType, scoringConfig, currentInput, minScore, maxScore]);

  // Báo cho component cha mỗi khi input hoặc preview thay đổi
  useEffect(() => {
    if (onChange) {
      onChange(currentInput, preview.points, preview.isValid);
    }
  }, [currentInput, preview.points, preview.isValid, onChange]);

  // Handlers cho từng model
  const handleTierChange = (tier: string) => {
    if (readOnly) return;
    setCurrentInput({ tier });
  };

  const handleUnitsChange = (units: number) => {
    if (readOnly) return;
    setCurrentInput({ units });
  };

  const handleToggleCompleted = (completed: boolean) => {
    if (readOnly) return;
    setCurrentInput((prev) => ({ ...prev, completed }));
  };

  const handleToggleOption = (optionId: string) => {
    if (readOnly) return;
    setCurrentInput((prev: any) => {
      const current = prev.selected_options || [];
      const updated = current.includes(optionId)
        ? current.filter((id: string) => id !== optionId)
        : [...current, optionId];
      return { ...prev, selected_options: updated };
    });
  };

  return (
    <div className={`space-y-4 ${className}`}>
      {/* 1. Dynamic Input Controls */}
      <div className="space-y-3">
        {scoringType === 'tier' && (
          <TierPicker
            tiers={(scoringConfig as any)?.tiers || []}
            selectedTier={(currentInput as any)?.tier}
            onChange={handleTierChange}
            disabled={readOnly}
          />
        )}

        {scoringType === 'time_attack' && (
          <UnitStepper
            units={(currentInput as any)?.units ?? 0}
            basePoints={(scoringConfig as any)?.base_points}
            unitPoints={(scoringConfig as any)?.unit_points}
            maxUnits={(scoringConfig as any)?.max_units}
            unitLabel={(scoringConfig as any)?.unit_label}
            onChange={handleUnitsChange}
            disabled={readOnly}
          />
        )}

        {scoringType === 'fixed' && (
          <OptionChecklist
            completed={Boolean((currentInput as any)?.completed)}
            points={(scoringConfig as any)?.points ?? maxScore}
            options={(scoringConfig as any)?.options || []}
            selectedOptions={(currentInput as any)?.selected_options || []}
            onToggleCompleted={handleToggleCompleted}
            onToggleOption={handleToggleOption}
            disabled={readOnly}
          />
        )}
      </div>

      {/* 2. Điểm Dự Kiến Live Preview Badge */}
      <div className="p-3.5 rounded-2xl bg-gradient-to-r from-lumen/10 via-lumen/5 to-transparent border border-lumen/25 flex items-center justify-between">
        <div className="flex items-center gap-2">
          <div className="w-8 h-8 rounded-xl bg-lumen/20 flex items-center justify-center text-lumen">
            <Sparkles className="w-4 h-4" />
          </div>
          <div>
            <div className="text-xs font-bold text-white uppercase tracking-wider">
              Điểm Dự Kiến
            </div>
            <div className="text-[10px] text-evermyst-text-muted">
              {preview.isValid ? 'Tính theo quy tắc trạm hiện hành' : preview.error}
            </div>
          </div>
        </div>

        <div className="text-right">
          <div className="text-2xl font-black text-lumen font-mono leading-none">
            +{preview.points}✦
          </div>
          <span className="text-[9px] text-evermyst-text-dim uppercase font-bold">
            [{minScore}..{maxScore}✦]
          </span>
        </div>
      </div>

      {/* Error notification nếu input không hợp lệ */}
      {!preview.isValid && preview.error && (
        <div className="p-3 rounded-xl bg-danger/15 border border-danger/30 text-danger-light text-xs flex items-center gap-2">
          <AlertCircle className="w-4 h-4 shrink-0 text-danger" />
          <span>{preview.error}</span>
        </div>
      )}
    </div>
  );
};
