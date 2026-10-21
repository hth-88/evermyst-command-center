// ============================================================================
// OPTION CHECKLIST COMPONENT (src/components/scoring/OptionChecklist.tsx)
// File: src/components/scoring/OptionChecklist.tsx
// Bộ xác nhận hoàn thành và checklist tùy chọn cho Fixed Scoring
// ============================================================================
import React from 'react';
import { CheckSquare, Square, CheckCircle2, XCircle } from 'lucide-react';

interface OptionChecklistProps {
  completed: boolean;
  points?: number;
  options?: Array<{ id: string; label: string; points?: number }>;
  selectedOptions?: string[];
  onToggleCompleted: (completed: boolean) => void;
  onToggleOption?: (optionId: string) => void;
  disabled?: boolean;
}

export const OptionChecklist: React.FC<OptionChecklistProps> = ({
  completed = false,
  points = 30,
  options = [],
  selectedOptions = [],
  onToggleCompleted,
  onToggleOption,
  disabled = false,
}) => {
  return (
    <div className="space-y-3">
      <label className="block text-xs font-bold uppercase tracking-wider text-evermyst-text-dim">
        Trạng Thái Hoàn Thành
      </label>

      {/* Main Completed Button */}
      <button
        type="button"
        disabled={disabled}
        onClick={() => onToggleCompleted(!completed)}
        className={`w-full min-h-[64px] p-4 rounded-2xl border flex items-center justify-between text-left transition-all active:scale-[0.98] select-none ${
          completed
            ? 'bg-success/15 border-success/60 text-white shadow-lg shadow-success/15 ring-1 ring-success'
            : 'bg-evermyst-card/80 border-evermyst-border hover:border-evermyst-border-light text-evermyst-text-dim'
        } ${disabled ? 'opacity-50 pointer-events-none' : 'cursor-pointer'}`}
      >
        <div className="flex items-center gap-3">
          <div
            className={`w-10 h-10 rounded-xl flex items-center justify-center shrink-0 ${
              completed ? 'bg-success/25 text-success' : 'bg-evermyst-surface text-evermyst-text-muted'
            }`}
          >
            {completed ? <CheckCircle2 className="w-6 h-6" /> : <XCircle className="w-6 h-6" />}
          </div>

          <div>
            <div className="text-base font-black leading-tight text-white">
              {completed ? 'Đã Vượt Qua Thử Thách' : 'Chưa Hoàn Thành'}
            </div>
            <div className="text-xs text-evermyst-text-muted mt-0.5">
              {completed ? 'Đội đã hoàn thành mọi tiêu chí bắt buộc' : 'Chạm để xác nhận hoàn thành'}
            </div>
          </div>
        </div>

        <div className="text-right">
          <div className={`text-xl font-black font-mono leading-none ${completed ? 'text-success' : 'text-evermyst-text-muted'}`}>
            {completed ? `+${points}` : '0'}✦
          </div>
          <span className="text-[10px] text-evermyst-text-dim uppercase font-bold">
            {completed ? 'Cố định' : 'Chưa đạt'}
          </span>
        </div>
      </button>

      {/* Optional Sub-Checklists */}
      {options.length > 0 && (
        <div className="space-y-2 pt-2 border-t border-evermyst-border/60">
          <div className="text-[11px] font-bold text-evermyst-text-dim uppercase tracking-wider">
            Các mục tiêu phụ (Tùy chọn)
          </div>

          <div className="space-y-1.5">
            {options.map((opt) => {
              const isChecked = selectedOptions.includes(opt.id);

              return (
                <button
                  key={opt.id}
                  type="button"
                  disabled={disabled}
                  onClick={() => onToggleOption && onToggleOption(opt.id)}
                  className={`w-full p-3 rounded-xl border flex items-center justify-between text-left transition-all ${
                    isChecked
                      ? 'bg-evermyst-card border-lumen/40 text-evermyst-text'
                      : 'bg-evermyst-surface/60 border-evermyst-border/60 text-evermyst-text-dim hover:text-white'
                  }`}
                >
                  <div className="flex items-center gap-2.5">
                    {isChecked ? (
                      <CheckSquare className="w-4 h-4 text-lumen shrink-0" />
                    ) : (
                      <Square className="w-4 h-4 text-evermyst-text-muted shrink-0" />
                    )}
                    <span className="text-xs font-semibold">{opt.label}</span>
                  </div>

                  {opt.points && opt.points > 0 && (
                    <span className="text-xs font-mono font-bold text-lumen shrink-0">
                      +{opt.points}✦
                    </span>
                  )}
                </button>
              );
            })}
          </div>
        </div>
      )}
    </div>
  );
};
