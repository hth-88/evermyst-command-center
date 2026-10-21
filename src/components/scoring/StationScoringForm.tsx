// ============================================================================
// DIRECT STATION SCORING FORM (src/components/scoring/StationScoringForm.tsx)
// File: src/components/scoring/StationScoringForm.tsx
// Nhập điểm dương trực tiếp cho đội tại trạm (Direct Points Input)
// Hỗ trợ nút chọn nhanh (+50, +100, +150, +200, +250, +500) & chặn nhập số âm
// ============================================================================
import React, { useState, useEffect } from 'react';
import type { ScoringType, ScoringConfig, ScoringInput } from '@/scoring/types';
import { Sparkles, AlertCircle, PlusCircle } from 'lucide-react';

interface StationScoringFormProps {
  scoringType?: ScoringType;
  scoringConfig?: ScoringConfig;
  minScore?: number;
  maxScore?: number;
  initialInput?: ScoringInput;
  onChange?: (input: ScoringInput, points: number, isValid: boolean) => void;
  readOnly?: boolean;
  className?: string;
}

export const DEFAULT_FALLBACK_TIERS = [
  { tier: 'tier_1', label: 'Giải mã hoàn hảo', points: 50 },
  { tier: 'tier_2', label: 'Hoàn thành tiêu chuẩn', points: 30 },
  { tier: 'tier_3', label: 'Hoàn thành trễ hạn', points: 15 },
];

const QUICK_FILL_POINTS = [50, 100, 150, 200, 250, 500];

export const StationScoringForm: React.FC<StationScoringFormProps> = ({
  initialInput,
  onChange,
  readOnly = false,
  className = '',
}) => {
  // Khởi tạo điểm từ initialInput nếu có (hỗ trợ sửa claim)
  const [pointsStr, setPointsStr] = useState<string>(() => {
    if (initialInput) {
      const initVal =
        (initialInput as any).custom_points ??
        (initialInput as any).points ??
        (initialInput as any).units;
      if (typeof initVal === 'number' && initVal > 0) {
        return String(initVal);
      }
    }
    return '50';
  });

  const [hasInteracted, setHasInteracted] = useState(false);

  // Parse & validate nghiêm ngặt số nguyên dương
  const trimmed = pointsStr.trim();
  const parsedPoints = parseInt(trimmed, 10);
  const isNumericOnly = /^\d+$/.test(trimmed);
  const isPositiveInteger = isNumericOnly && !isNaN(parsedPoints) && parsedPoints > 0;
  const isValid = isPositiveInteger;

  const errorMessage = !trimmed
    ? 'Vui lòng nhập số điểm cộng cho đội.'
    : !isValid
    ? 'Điểm cộng tại trạm phải lớn hơn 0 (Chỉ Admin mới có quyền trừ điểm).'
    : null;

  // Báo cho component cha mỗi khi điểm thay đổi
  useEffect(() => {
    if (onChange) {
      const validPoints = isValid ? parsedPoints : 0;
      const formattedInput: ScoringInput = {
        custom_points: validPoints,
        points: validPoints,
        tier: 'tier_1',
        completed: true,
        units: validPoints,
      };
      onChange(formattedInput, validPoints, isValid);
    }
  }, [pointsStr, isValid, parsedPoints, onChange]);

  // Ngăn chặn các phím dấu trừ, dấu chấm, ký tự e/E
  const handleKeyDown = (e: React.KeyboardEvent<HTMLInputElement>) => {
    if (['-', '+', 'e', 'E', '.'].includes(e.key)) {
      e.preventDefault();
    }
  };

  const handleChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    setHasInteracted(true);
    const val = e.target.value.replace(/[^0-9]/g, '');
    setPointsStr(val);
  };

  const handleQuickFill = (val: number) => {
    if (readOnly) return;
    setHasInteracted(true);
    setPointsStr(String(val));
  };

  return (
    <div className={`space-y-4 ${className}`}>
      {/* 1. Ô Nhập Điểm Trực Tiếp */}
      <div className="space-y-2">
        <label className="text-xs font-bold text-evermyst-text-muted uppercase tracking-wider flex items-center justify-between">
          <span className="flex items-center gap-1.5 text-white">
            <PlusCircle className="w-3.5 h-3.5 text-lumen" />
            Nhập số điểm cộng trực tiếp:
          </span>
          <span className="text-[10px] text-evermyst-text-dim">Chỉ số nguyên &gt; 0</span>
        </label>

        <div className="relative">
          <input
            type="number"
            min="1"
            step="1"
            disabled={readOnly}
            value={pointsStr}
            onChange={handleChange}
            onKeyDown={handleKeyDown}
            placeholder="Nhập số điểm cộng cho đội (VD: 250, 500)..."
            className="w-full h-14 px-4 bg-evermyst-surface border border-evermyst-border rounded-2xl text-lg font-black font-mono text-white placeholder:text-evermyst-text-muted focus:outline-none focus:border-lumen focus:ring-1 focus:ring-lumen transition-all"
          />
          <div className="absolute right-4 top-1/2 -translate-y-1/2 text-sm font-bold text-lumen font-mono pointer-events-none">
            ✦ Lumen
          </div>
        </div>

        {/* Nút Gợi Ý Bấm Nhanh (Quick-fill Pills) */}
        {!readOnly && (
          <div className="space-y-1 pt-0.5">
            <div className="text-[11px] text-evermyst-text-muted">Chọn nhanh mức điểm:</div>
            <div className="flex items-center gap-1.5 flex-wrap">
              {QUICK_FILL_POINTS.map((pts) => {
                const isSelected = pointsStr === String(pts);
                return (
                  <button
                    key={pts}
                    type="button"
                    onClick={() => handleQuickFill(pts)}
                    className={`px-3 py-1.5 rounded-xl text-xs font-bold font-mono transition-all border active:scale-95 ${
                      isSelected
                        ? 'bg-lumen text-evermyst-bg border-lumen font-black shadow-md shadow-lumen/25'
                        : 'bg-evermyst-card border-evermyst-border text-evermyst-text hover:border-evermyst-border-light hover:text-white'
                    }`}
                  >
                    +{pts}✦
                  </button>
                );
              })}
            </div>
          </div>
        )}
      </div>

      {/* 2. Live Preview Badge */}
      <div className="p-3.5 rounded-2xl bg-gradient-to-r from-lumen/10 via-lumen/5 to-transparent border border-lumen/25 flex items-center justify-between">
        <div className="flex items-center gap-2">
          <div className="w-8 h-8 rounded-xl bg-lumen/20 flex items-center justify-center text-lumen">
            <Sparkles className="w-4 h-4" />
          </div>
          <div>
            <div className="text-xs font-bold text-white uppercase tracking-wider">
              Tổng Điểm Cộng
            </div>
            <div className="text-[10px] text-evermyst-text-muted">
              {isValid ? 'Cộng trực tiếp vào số dư đội sau khi gửi' : 'Chưa nhập điểm hợp lệ'}
            </div>
          </div>
        </div>

        <div className="text-right">
          <div className="text-2xl font-black text-lumen font-mono leading-none">
            +{isValid ? parsedPoints : 0}✦
          </div>
          <span className="text-[9px] text-evermyst-text-dim uppercase font-bold">
            [Khởi điểm &gt; 0✦]
          </span>
        </div>
      </div>

      {/* 3. Thông báo lỗi khi không hợp lệ */}
      {hasInteracted && !isValid && errorMessage && (
        <div className="p-3 rounded-xl bg-danger/15 border border-danger/30 text-danger-light text-xs flex items-center gap-2 animate-fadeIn">
          <AlertCircle className="w-4 h-4 shrink-0 text-danger" />
          <span>{errorMessage}</span>
        </div>
      )}
    </div>
  );
};
