// ============================================================================
// KEY MODAL (src/components/support/KeyModal.tsx)
// File: src/components/support/KeyModal.tsx
// Chọn trạm chưa clear để kích hoạt Chìa Khóa Cổ Tích (Mở lối tắt)
// ============================================================================
import React, { useState } from 'react';
import { useGame } from '@/contexts/GameContext';
import { callRpc } from '@/lib/rpc';
import type { Station } from '@/lib/types';
import { Key, MapPin, CheckCircle, AlertCircle, X, Loader2 } from 'lucide-react';

interface KeyModalProps {
  isOpen: boolean;
  onClose: () => void;
  itemId: string;
  stations: Station[];
  unlockedStationIds?: string[];
  teamId?: string;
  onSuccess: () => void;
}

export const KeyModal: React.FC<KeyModalProps> = ({
  isOpen,
  onClose,
  itemId,
  stations = [],
  unlockedStationIds = [],
  teamId,
  onSuccess,
}) => {
  const { teamStationKeys } = useGame();
  const teamKeys = teamId ? teamStationKeys[teamId] || [] : [];
  const [selectedStationId, setSelectedStationId] = useState<string>('');
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);

  if (!isOpen) return null;

  // Lọc các trạm đang hoạt động
  const activeStations = stations.filter((s) => s.is_active);

  const handleConfirmKey = async () => {
    if (!selectedStationId) {
      setErrorMsg('Vui lòng chọn trạm cần gán chìa khóa cổ tích.');
      return;
    }

    setIsSubmitting(true);
    setErrorMsg(null);

    try {
      const res = await callRpc<any>('use_team_item', {
        p_item_id: itemId,
        p_target_station_id: selectedStationId,
      });

      if (res.success) {
        onSuccess();
        onClose();
      } else {
        setErrorMsg(res.error || res.message || 'Không thể kích hoạt chìa khóa.');
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
            <div className="w-9 h-9 rounded-xl bg-amber-500/15 text-amber-500 flex items-center justify-center shadow-md shadow-amber-500/15">
              <Key className="w-5 h-5" />
            </div>
            <div>
              <h3 className="text-base font-black text-white leading-tight">
                Chìa Khóa Cổ Tích
              </h3>
              <p className="text-[11px] text-evermyst-text-muted">
                Chọn trạm để mở quyền nộp lại / vượt qua slot
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

        {/* Station Selection */}
        <div className="space-y-2">
          <label className="text-xs font-bold text-evermyst-text-dim uppercase tracking-wider block">
            Chọn trạm mục tiêu
          </label>

          <div className="space-y-1.5 max-h-56 overflow-y-auto pr-1">
            {activeStations.map((st) => {
              const isCleared = unlockedStationIds.includes(st.id);
              const alreadyHasKey = teamKeys.includes(st.id);
              const isSelected = selectedStationId === st.id;
              const isDisabled = isCleared || alreadyHasKey;

              return (
                <button
                  key={st.id}
                  type="button"
                  disabled={isDisabled}
                  onClick={() => {
                    if (isDisabled) return;
                    setSelectedStationId(st.id);
                    setErrorMsg(null);
                  }}
                  className={`w-full p-3 rounded-2xl border flex items-center justify-between text-left transition-all ${
                    isDisabled
                      ? 'bg-evermyst-surface/40 border-evermyst-border/40 opacity-40 cursor-not-allowed'
                      : isSelected
                      ? 'bg-amber-500/15 border-amber-500 text-white shadow-md shadow-amber-500/10 ring-1 ring-amber-500'
                      : 'bg-evermyst-surface border-evermyst-border text-evermyst-text hover:border-evermyst-border-light'
                  }`}
                >
                  <div className="flex items-center gap-2.5 truncate">
                    <MapPin className="w-4 h-4 text-lumen shrink-0" />
                    <div className="truncate">
                      <div className="font-bold text-sm truncate">{st.name}</div>
                      <div className="text-[10px] text-evermyst-text-muted">
                        {st.scoring_type.toUpperCase()} • Tối đa {st.max_score}✦
                      </div>
                    </div>
                  </div>

                  {isCleared ? (
                    <span className="text-[10px] font-bold text-success px-2 py-0.5 rounded bg-success/15 shrink-0 flex items-center gap-1">
                      <CheckCircle className="w-3 h-3" /> Đã clear
                    </span>
                  ) : alreadyHasKey ? (
                    <span className="text-[10px] font-bold text-amber-400 px-2 py-0.5 rounded bg-amber-500/15 shrink-0 flex items-center gap-1">
                      <Key className="w-3 h-3" /> Đã cắm chìa
                    </span>
                  ) : (
                    <span className="text-xs font-mono font-bold text-amber-400 shrink-0">
                      Chưa clear
                    </span>
                  )}
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
            onClick={handleConfirmKey}
            disabled={isSubmitting || !selectedStationId}
            className="h-12 rounded-xl bg-gradient-to-r from-amber-500 to-amber-600 text-evermyst-bg font-black text-xs uppercase tracking-wider flex items-center justify-center gap-2 shadow-lg shadow-amber-500/20 disabled:opacity-50"
          >
            {isSubmitting ? (
              <Loader2 className="w-4 h-4 animate-spin" />
            ) : (
              <>
                <Key className="w-4 h-4" /> Tra Chìa Khóa
              </>
            )}
          </button>
        </div>
      </div>
    </div>
  );
};
