// ============================================================================
// TIER PICKER COMPONENT (src/components/scoring/TierPicker.tsx)
// File: src/components/scoring/TierPicker.tsx
// Bộ chọn phân hạng điểm lớn, tối ưu bấm 1 tay ngoài trời (min 54px)
// ============================================================================
import React from 'react';
import type { TierItem } from '@/scoring/types';
import { Check, Star, Shield, Trophy } from 'lucide-react';

interface TierPickerProps {
  tiers: TierItem[];
  selectedTier?: string;
  onChange: (tier: string) => void;
  disabled?: boolean;
}

export const TierPicker: React.FC<TierPickerProps> = ({
  tiers = [],
  selectedTier,
  onChange,
  disabled = false,
}) => {
  if (tiers.length === 0) {
    return (
      <div className="p-4 rounded-xl bg-evermyst-card border border-evermyst-border text-center text-xs text-evermyst-text-muted">
        Chưa có cấu hình phân hạng cho trạm này.
      </div>
    );
  }

  const getTierIcon = (index: number) => {
    if (index === 0) return <Shield className="w-5 h-5 text-amber-500" />;
    if (index === 1) return <Star className="w-5 h-5 text-slate-300" />;
    return <Trophy className="w-5 h-5 text-lumen" />;
  };

  return (
    <div className="space-y-2.5">
      <label className="block text-xs font-bold uppercase tracking-wider text-evermyst-text-dim">
        Chọn Mức Độ Đạt Được
      </label>

      <div className="grid grid-cols-1 gap-2.5">
        {tiers.map((t, idx) => {
          const isSelected = selectedTier === t.tier;

          return (
            <button
              key={t.tier}
              type="button"
              disabled={disabled}
              onClick={() => onChange(t.tier)}
              className={`min-h-[58px] p-3.5 rounded-2xl border flex items-center justify-between text-left transition-all active:scale-[0.98] select-none ${
                isSelected
                  ? 'bg-lumen/15 border-lumen text-white shadow-lg shadow-lumen/20 ring-1 ring-lumen'
                  : 'bg-evermyst-card/80 border-evermyst-border hover:border-evermyst-border-light text-evermyst-text hover:bg-evermyst-card'
              } ${disabled ? 'opacity-50 pointer-events-none' : 'cursor-pointer'}`}
            >
              <div className="flex items-center gap-3">
                <div
                  className={`w-10 h-10 rounded-xl flex items-center justify-center shrink-0 ${
                    isSelected ? 'bg-lumen/25 text-lumen' : 'bg-evermyst-surface text-evermyst-text-muted'
                  }`}
                >
                  {getTierIcon(idx)}
                </div>

                <div>
                  <div className="text-sm font-black leading-tight">
                    {t.label || t.tier.toUpperCase()}
                  </div>
                  <div className="text-[11px] text-evermyst-text-muted mt-0.5">
                    Hạng: <span className="font-mono font-bold text-evermyst-text">{t.tier}</span>
                  </div>
                </div>
              </div>

              <div className="flex items-center gap-3">
                <div className="text-right">
                  <span className="text-lg font-black text-lumen font-mono">
                    +{t.points}
                  </span>
                  <span className="text-xs text-lumen ml-0.5 font-bold">✦</span>
                </div>

                <div
                  className={`w-6 h-6 rounded-full flex items-center justify-center border transition-all ${
                    isSelected
                      ? 'bg-lumen border-lumen text-evermyst-bg'
                      : 'border-evermyst-border bg-evermyst-surface'
                  }`}
                >
                  {isSelected && <Check className="w-3.5 h-3.5 stroke-[3]" />}
                </div>
              </div>
            </button>
          );
        })}
      </div>
    </div>
  );
};
