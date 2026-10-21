// ============================================================================
// UNIT STEPPER COMPONENT (src/components/scoring/UnitStepper.tsx)
// File: src/components/scoring/UnitStepper.tsx
// Bộ tăng giảm số lượng lượt / đơn vị với nút lớn, giới hạn min/max và tính trước điểm
// ============================================================================
import React from 'react';
import { Plus, Minus, Flame, Zap } from 'lucide-react';

interface UnitStepperProps {
  units: number;
  basePoints?: number;
  unitPoints?: number;
  maxUnits?: number;
  unitLabel?: string;
  onChange: (units: number) => void;
  disabled?: boolean;
}

export const UnitStepper: React.FC<UnitStepperProps> = ({
  units = 0,
  basePoints = 0,
  unitPoints = 5,
  maxUnits = 20,
  unitLabel = 'lượt',
  onChange,
  disabled = false,
}) => {
  const handleDecrement = () => {
    if (disabled || units <= 0) return;
    onChange(Math.max(0, units - 1));
  };

  const handleIncrement = () => {
    if (disabled || units >= maxUnits) return;
    onChange(Math.min(maxUnits, units + 1));
  };

  const handleQuickAdd = (amount: number) => {
    if (disabled) return;
    onChange(Math.min(maxUnits, Math.max(0, units + amount)));
  };

  const totalCalculated = basePoints + units * unitPoints;

  return (
    <div className="space-y-3">
      <div className="flex items-center justify-between">
        <label className="text-xs font-bold uppercase tracking-wider text-evermyst-text-dim">
          Số Lượng Đạt Được
        </label>
        <span className="text-[11px] text-evermyst-text-muted font-medium">
          Tối đa: <strong className="text-evermyst-text">{maxUnits}</strong> {unitLabel}
        </span>
      </div>

      {/* Main Big Stepper */}
      <div className="p-4 rounded-2xl bg-evermyst-card border border-evermyst-border flex items-center justify-between gap-4 select-none">
        {/* Nút Trừ */}
        <button
          type="button"
          disabled={disabled || units <= 0}
          onClick={handleDecrement}
          className="w-14 h-14 rounded-2xl bg-evermyst-surface border border-evermyst-border flex items-center justify-center text-evermyst-text hover:bg-evermyst-border hover:text-white active:scale-90 transition-all disabled:opacity-30 disabled:pointer-events-none"
        >
          <Minus className="w-6 h-6 stroke-[3]" />
        </button>

        {/* Màn hình hiển thị số */}
        <div className="flex-1 text-center">
          <div className="text-4xl font-black text-white font-mono tracking-tight leading-none">
            {units}
          </div>
          <div className="text-xs font-semibold text-evermyst-text-muted mt-1 uppercase">
            {unitLabel}
          </div>
        </div>

        {/* Nút Cộng */}
        <button
          type="button"
          disabled={disabled || units >= maxUnits}
          onClick={handleIncrement}
          className="w-14 h-14 rounded-2xl bg-lumen/15 border border-lumen/40 flex items-center justify-center text-lumen hover:bg-lumen/25 active:scale-90 transition-all disabled:opacity-30 disabled:pointer-events-none shadow-md shadow-lumen/10"
        >
          <Plus className="w-6 h-6 stroke-[3]" />
        </button>
      </div>

      {/* Quick Add Chips */}
      <div className="flex items-center gap-2">
        <button
          type="button"
          disabled={disabled || units >= maxUnits}
          onClick={() => handleQuickAdd(1)}
          className="flex-1 py-2 px-3 rounded-xl bg-evermyst-surface border border-evermyst-border text-xs font-bold text-evermyst-text hover:bg-evermyst-border active:scale-95 transition-all disabled:opacity-40"
        >
          +1
        </button>
        <button
          type="button"
          disabled={disabled || units >= maxUnits}
          onClick={() => handleQuickAdd(5)}
          className="flex-1 py-2 px-3 rounded-xl bg-evermyst-surface border border-evermyst-border text-xs font-bold text-evermyst-text hover:bg-evermyst-border active:scale-95 transition-all disabled:opacity-40"
        >
          +5
        </button>
        <button
          type="button"
          disabled={disabled || units >= maxUnits}
          onClick={() => onChange(maxUnits)}
          className="flex-1 py-2 px-3 rounded-xl bg-lumen/10 border border-lumen/25 text-xs font-bold text-lumen hover:bg-lumen/20 active:scale-95 transition-all disabled:opacity-40"
        >
          Max ({maxUnits})
        </button>
        <button
          type="button"
          disabled={disabled || units <= 0}
          onClick={() => onChange(0)}
          className="py-2 px-3 rounded-xl bg-evermyst-surface border border-evermyst-border text-xs font-bold text-evermyst-text-dim hover:text-white active:scale-95 transition-all disabled:opacity-40"
        >
          Reset
        </button>
      </div>

      {/* Công thức tính điểm minh bạch */}
      <div className="p-3 rounded-xl bg-evermyst-surface/60 border border-evermyst-border/60 text-xs flex items-center justify-between text-evermyst-text-dim">
        <div className="flex items-center gap-1.5">
          <Zap className="w-3.5 h-3.5 text-lumen" />
          <span>
            {basePoints > 0 ? `${basePoints} điểm gốc + ` : ''}
            {units} × {unitPoints}✦/{unitLabel}
          </span>
        </div>
        <div className="font-mono font-bold text-lumen text-sm">
          = {totalCalculated}✦
        </div>
      </div>
    </div>
  );
};
