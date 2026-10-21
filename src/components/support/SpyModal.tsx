// ============================================================================
// SPY MODAL (src/components/support/SpyModal.tsx)
// File: src/components/support/SpyModal.tsx
// Chọn đội mục tiêu (5 đội còn lại) để sử dụng đạo cụ Kính Viễn Vọng (Spy)
// ============================================================================
import React, { useState } from 'react';
import { callRpc } from '@/lib/rpc';
import type { Team } from '@/lib/types';
import { Eye, Shield, AlertCircle, X, Loader2 } from 'lucide-react';

interface SpyModalProps {
  isOpen: boolean;
  onClose: () => void;
  itemId: string;
  teams: Team[];
  currentTeamId: string;
  onSuccess: (snapshot: any) => void;
}

export const SpyModal: React.FC<SpyModalProps> = ({
  isOpen,
  onClose,
  itemId,
  teams = [],
  currentTeamId,
  onSuccess,
}) => {
  const [selectedTargetId, setSelectedTargetId] = useState<string>('');
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);

  if (!isOpen) return null;

  // Lọc ra 5 đội đối thủ (không phải đội của mình)
  const rivalTeams = teams.filter((t) => t.id !== currentTeamId && t.is_active);

  const handleConfirmSpy = async () => {
    if (!selectedTargetId) {
      setErrorMsg('Vui lòng chọn một đội đối thủ để do thám.');
      return;
    }

    setIsSubmitting(true);
    setErrorMsg(null);

    try {
      const res = await callRpc<any>('use_team_item', {
        p_item_id: itemId,
        p_target_team_id: selectedTargetId,
      });

      if (res.success && res.spy_data) {
        onSuccess(res.spy_data);
        onClose();
      } else if (res.success && res.data?.spy_data) {
        onSuccess(res.data.spy_data);
        onClose();
      } else {
        setErrorMsg(res.error || res.message || 'Không thể thực hiện do thám.');
      }
    } catch (err: any) {
      setErrorMsg(err?.message || 'Lỗi mạng khi kết nối máy chủ.');
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/80 backdrop-blur-sm animate-fadeIn">
      <div className="bg-evermyst-card border border-evermyst-border rounded-3xl w-full max-w-sm overflow-hidden shadow-2xl space-y-4 p-5 animate-scaleUp">
        {/* Header */}
        <div className="flex items-center justify-between border-b border-evermyst-border pb-3">
          <div className="flex items-center gap-2.5">
            <div className="w-9 h-9 rounded-xl bg-info/15 text-info flex items-center justify-center">
              <Eye className="w-5 h-5" />
            </div>
            <div>
              <h3 className="text-base font-black text-white leading-tight">
                Kính Viễn Vọng Quạ Đen
              </h3>
              <p className="text-[11px] text-evermyst-text-muted">
                Chọn 1 trong 5 đội đối thủ để thám báo
              </p>
            </div>
          </div>

          <button
            onClick={onClose}
            className="p-1.5 rounded-xl hover:bg-evermyst-surface text-evermyst-text-dim hover:text-white"
          >
            <X className="w-4 h-4" />
          </button>
        </div>

        {/* Rival Teams Selection */}
        <div className="space-y-2">
          <label className="text-xs font-bold text-evermyst-text-dim uppercase tracking-wider block">
            Mục tiêu do thám ({rivalTeams.length} đội)
          </label>

          <div className="space-y-1.5 max-h-56 overflow-y-auto pr-1">
            {rivalTeams.map((team) => {
              const isSelected = selectedTargetId === team.id;
              const hasShield = team.shield_until && new Date(team.shield_until) > new Date();

              return (
                <button
                  key={team.id}
                  type="button"
                  onClick={() => {
                    setSelectedTargetId(team.id);
                    setErrorMsg(null);
                  }}
                  className={`w-full p-3 rounded-2xl border flex items-center justify-between text-left transition-all ${
                    isSelected
                      ? 'bg-info/15 border-info text-white shadow-md shadow-info/10 ring-1 ring-info'
                      : 'bg-evermyst-surface border-evermyst-border text-evermyst-text hover:border-evermyst-border-light'
                  }`}
                >
                  <div className="flex items-center gap-2.5 truncate">
                    <span className="font-bold text-sm truncate">{team.name}</span>
                    {hasShield && (
                      <span className="px-1.5 py-0.5 rounded bg-props/15 text-props text-[9px] font-bold flex items-center gap-0.5 shrink-0">
                        <Shield className="w-2.5 h-2.5" /> Khiên
                      </span>
                    )}
                  </div>

                  <span className="text-xs font-mono font-bold text-lumen shrink-0">
                    {team.light_balance}✦
                  </span>
                </button>
              );
            })}
          </div>
        </div>

        {/* Error notification */}
        {errorMsg && (
          <div className="p-3 rounded-xl bg-danger/15 border border-danger/30 text-danger-light text-xs flex items-center gap-2">
            <AlertCircle className="w-4 h-4 shrink-0 text-danger" />
            <span>{errorMsg}</span>
          </div>
        )}

        {/* Action Buttons */}
        <div className="grid grid-cols-2 gap-2.5 pt-2">
          <button
            type="button"
            onClick={onClose}
            disabled={isSubmitting}
            className="h-12 rounded-xl bg-evermyst-surface border border-evermyst-border text-xs font-bold text-evermyst-text hover:text-white"
          >
            Hủy bỏ
          </button>

          <button
            type="button"
            onClick={handleConfirmSpy}
            disabled={isSubmitting || !selectedTargetId}
            className="h-12 rounded-xl bg-gradient-to-r from-info to-info-dark text-evermyst-bg font-black text-xs uppercase tracking-wider flex items-center justify-center gap-2 shadow-lg shadow-info/20 disabled:opacity-50"
          >
            {isSubmitting ? (
              <Loader2 className="w-4 h-4 animate-spin" />
            ) : (
              <>
                <Eye className="w-4 h-4" /> Kích hoạt
              </>
            )}
          </button>
        </div>
      </div>
    </div>
  );
};
