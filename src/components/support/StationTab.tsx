// ============================================================================
// SUPPORT STATION TAB (src/components/support/StationTab.tsx)
// File: src/components/support/StationTab.tsx
// Danh sách các trạm với Direct Station Scoring (Migration 104)
// Giữ nguyên form nhập điểm trực tiếp (> 0) và các nút chọn nhanh
// ============================================================================
import React, { useState, useEffect, useCallback } from 'react';
import { useGame } from '@/contexts/GameContext';
import { StationScoringForm } from '@/components/scoring/StationScoringForm';
import type { Team, Station } from '@/lib/types';
import type { ScoringInput } from '@/scoring/types';
import {
  MapPin,
  CheckCircle2,
  XCircle,
  RotateCcw,
  Send,
  Loader2,
  ChevronDown,
  ChevronUp,
  Sparkles,
} from 'lucide-react';

interface StationTabProps {
  selectedTeam: Team | null;
}

interface StationStatusItem {
  station_id: string;
  station_name: string;
  order_index: number;
  scoring_type: string;
  scoring_config: Record<string, any>;
  allow_multiple_attempts: boolean;
  has_key: boolean;
  active_claim?: {
    id: string;
    status: 'approved' | 'unattempted';
    points: number;
    created_at: string;
  } | null;
}

export default function StationTab({ selectedTeam }: StationTabProps) {
  const { stations, transactions, refreshAll, awardStationDirectPoints, addToast } = useGame();
  const [stationStatuses, setStationStatuses] = useState<StationStatusItem[]>([]);
  const [, setIsLoading] = useState(true);
  const [activeFormStationId, setActiveFormStationId] = useState<string | null>(null);

  // Form input state
  const [formData, setFormData] = useState<Record<string, { input: ScoringInput; points: number; isValid: boolean }>>({});
  const [isSubmitting, setIsSubmitting] = useState(false);

  // Tải trạng thái các trạm của đội từ DB thật qua GameContext
  const fetchStationStatuses = useCallback(async () => {
    if (!selectedTeam) return;
    try {
      const activeStations = stations.filter((s: any) => !s.deleted_at && s.is_active);
      const teamStationTx = transactions.filter(
        (t) => t.team_id === selectedTeam.id && t.type === 'station_clear' && !t.is_reversed
      );

      const mapped = activeStations.map((st) => {
        const isUnlocked = selectedTeam.unlocked_stations?.includes(st.id);
        const relatedTx = teamStationTx.find((tx) =>
          tx.description?.includes(st.name) || (tx.metadata as any)?.station_id === st.id
        );
        const pointsEarned = relatedTx ? relatedTx.amount : (isUnlocked ? (st.max_score || 50) : 0);

        return {
          station_id: st.id,
          station_name: st.name,
          order_index: st.order_index,
          scoring_type: st.scoring_type,
          scoring_config: st.scoring_config || {},
          allow_multiple_attempts: st.allow_multiple_attempts,
          has_key: false,
          active_claim: isUnlocked
            ? {
                id: relatedTx?.id || 'done',
                status: 'approved' as const,
                points: pointsEarned,
                created_at: relatedTx?.created_at || new Date().toISOString(),
              }
            : null,
        };
      });

      setStationStatuses(mapped);
    } catch (err) {
      console.error('Lỗi tính toán trạng thái trạm:', err);
    } finally {
      setIsLoading(false);
    }
  }, [selectedTeam, stations, transactions]);

  useEffect(() => {
    fetchStationStatuses();
  }, [fetchStationStatuses]);

  // Handler nộp điểm trạm trực tiếp qua RPC Migration 104
  const handleSubmitClaim = async (station: Station | StationStatusItem) => {
    if (!selectedTeam || isSubmitting) return;

    const stId = (station as any).station_id || (station as any).id;
    const data = formData[stId];
    if (!data || !data.isValid) {
      alert('Vui lòng nhập số điểm cộng hợp lệ (> 0).');
      return;
    }

    const pointsToAward = data.points || Number((data.input as any)?.custom_points) || 50;
    setIsSubmitting(true);
    try {
      const res = await awardStationDirectPoints(
        selectedTeam.id,
        stId,
        pointsToAward,
        `Support chấm điểm trạm cho đội ${selectedTeam.name}`
      );

      if (res.success) {
        addToast(`+${pointsToAward}✦ Lumen đã được cộng trực tiếp cho đội!`, 'success');
        setActiveFormStationId(null);
        // Cập nhật điểm tức thì trên thẻ trạm
        setStationStatuses((prev) =>
          prev.map((item) => {
            if (item.station_id === stId) {
              const prevPoints = item.active_claim?.points || 0;
              return {
                ...item,
                active_claim: {
                  id: (res.data as any)?.play_id || 'done',
                  status: 'approved',
                  points: item.allow_multiple_attempts ? prevPoints + pointsToAward : pointsToAward,
                  created_at: new Date().toISOString(),
                },
              };
            }
            return item;
          })
        );
        await refreshAll();
        await fetchStationStatuses();
      } else {
        alert(res.error || res.message || 'Không thể cộng điểm trạm.');
      }
    } catch (err: any) {
      alert(err.message || 'Lỗi khi cộng điểm trạm.');
    } finally {
      setIsSubmitting(false);
    }
  };

  if (!selectedTeam) {
    return (
      <div className="flex flex-col items-center justify-center py-24 px-4 text-center">
        <div className="w-16 h-16 rounded-3xl bg-evermyst-card border border-evermyst-border flex items-center justify-center mb-3">
          <MapPin className="w-8 h-8 text-lumen" />
        </div>
        <h3 className="text-base font-bold text-evermyst-text">Chưa phân công đội chơi</h3>
        <p className="text-xs text-evermyst-text-muted mt-1 max-w-xs">
          Tài khoản Support chưa được phân công đội phụ trách. Vui lòng liên hệ Admin.
        </p>
      </div>
    );
  }

  // Danh sách hiển thị: kết hợp giữa stations và status, chỉ các trạm chưa bị soft delete và active
  const displayItems = (stationStatuses.length > 0 ? stationStatuses : stations.map((s) => ({
    station_id: s.id,
    station_name: s.name,
    order_index: s.order_index,
    scoring_type: s.scoring_type,
    scoring_config: s.scoring_config || {},
    allow_multiple_attempts: s.allow_multiple_attempts,
    has_key: false,
    active_claim: selectedTeam.unlocked_stations?.includes(s.id)
      ? { id: 'done', status: 'approved' as const, points: s.max_score || 50, created_at: new Date().toISOString() }
      : null,
  }))).filter((st: any) => !st.deleted_at);

  return (
    <div className="p-4 space-y-4 pb-28 animate-fadeIn">
      {/* Header Info */}
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-base font-black text-white flex items-center gap-2">
            <MapPin className="w-4 h-4 text-lumen" />
            Lộ Trình Thử Thách
          </h2>
          <p className="text-[11px] text-evermyst-text-muted">
            Danh sách trạm thử thách cho {selectedTeam.name}
          </p>
        </div>

        <button
          onClick={async () => {
            await refreshAll();
            await fetchStationStatuses();
          }}
          className="text-[11px] font-bold text-lumen hover:underline flex items-center gap-1"
        >
          <RotateCcw className="w-3 h-3" /> Làm mới
        </button>
      </div>

      {/* Danh sách các Trạm */}
      <div className="space-y-3">
        {displayItems.map((item, idx) => {
          const stationId = item.station_id;
          const claim = item.active_claim;
          const isUnlocked = selectedTeam.unlocked_stations?.includes(stationId) || claim?.status === 'approved';
          const isFormOpen = activeFormStationId === stationId;

          // Cho phép chấm nếu chưa hoàn thành hoặc trạm cho phép đa lượt
          const canScore = !isUnlocked || item.allow_multiple_attempts;

          return (
            <div
              key={stationId}
              className={`rounded-2xl border transition-all overflow-hidden ${
                isUnlocked
                  ? 'bg-success/5 border-success/30'
                  : 'bg-evermyst-card border-evermyst-border'
              }`}
            >
              {/* Header Card */}
              <div className="p-4 flex items-start justify-between gap-3">
                <div className="space-y-1 flex-1">
                  <div className="flex items-center gap-2 flex-wrap">
                    <span className="w-5 h-5 rounded-lg bg-evermyst-surface text-lumen text-[11px] font-mono font-black flex items-center justify-center">
                      {idx + 1}
                    </span>
                    <h3 className="text-sm font-black text-white leading-tight">
                      {item.station_name}
                    </h3>
                  </div>

                  <div className="text-[11px] text-evermyst-text-muted flex items-center gap-2">
                    <span className="uppercase font-semibold tracking-wider">
                      {item.scoring_type}
                    </span>
                    {item.allow_multiple_attempts && (
                      <span className="text-lumen font-bold">• Đa lượt</span>
                    )}
                  </div>
                </div>

                {/* Status Badge */}
                <div className="shrink-0 text-right">
                  {isUnlocked ? (
                    <div className="inline-flex items-center gap-1 px-2.5 py-1 rounded-xl bg-success/15 text-success font-bold text-xs">
                      <CheckCircle2 className="w-3.5 h-3.5" />
                      <span>+{claim?.points ?? ''}✦ Đã hoàn thành</span>
                    </div>
                  ) : (
                    <div className="inline-flex items-center gap-1 px-2.5 py-1 rounded-xl bg-evermyst-surface text-evermyst-text-dim text-xs font-semibold">
                      <span>Chưa thực hiện</span>
                    </div>
                  )}
                </div>
              </div>

              {/* Actions & Form Chấm Điểm */}
              <div className="px-4 pb-4 space-y-3">
                {canScore && (
                  <div>
                    {!isFormOpen ? (
                      <button
                        type="button"
                        onClick={() => setActiveFormStationId(stationId)}
                        className="w-full h-12 rounded-xl bg-evermyst-surface border border-evermyst-border hover:border-lumen/40 text-evermyst-text hover:text-white text-xs font-bold flex items-center justify-center gap-2 transition-all active:scale-[0.99]"
                      >
                        <Send className="w-3.5 h-3.5 text-lumen" />
                        {isUnlocked ? 'Cộng thêm điểm lượt mới' : 'Nhập điểm trạm trực tiếp'}
                        <ChevronDown className="w-3.5 h-3.5 text-evermyst-text-dim" />
                      </button>
                    ) : (
                      <div className="p-4 rounded-2xl bg-evermyst-surface border border-evermyst-border space-y-4 animate-scaleUp">
                        <div className="flex items-center justify-between border-b border-evermyst-border pb-2">
                          <span className="text-xs font-bold text-white flex items-center gap-1.5">
                            <Sparkles className="w-3.5 h-3.5 text-lumen" />
                            Biểu Mẫu Chấm Điểm
                          </span>
                          <button
                            type="button"
                            onClick={() => setActiveFormStationId(null)}
                            className="text-xs text-evermyst-text-dim hover:text-white flex items-center gap-0.5"
                          >
                            Đóng <ChevronUp className="w-3.5 h-3.5" />
                          </button>
                        </div>

                        {/* Nhập điểm trực tiếp với quick fill buttons */}
                        <StationScoringForm
                          scoringType={item.scoring_type as any}
                          scoringConfig={item.scoring_config}
                          minScore={0}
                          maxScore={500}
                          onChange={(input, points, isValid) => {
                            setFormData((prev) => ({
                              ...prev,
                              [stationId]: { input, points, isValid },
                            }));
                          }}
                        />

                        {/* Submit Button */}
                        <button
                          type="button"
                          disabled={isSubmitting || !formData[stationId]?.isValid}
                          onClick={() => handleSubmitClaim(item)}
                          className="w-full h-12 rounded-xl bg-gradient-to-r from-lumen to-lumen-dark text-evermyst-bg font-black text-xs uppercase tracking-wider flex items-center justify-center gap-2 shadow-lg shadow-lumen/20 active:scale-[0.99] disabled:opacity-50 transition-all"
                        >
                          {isSubmitting ? (
                            <Loader2 className="w-4 h-4 animate-spin" />
                          ) : (
                            <>
                              <Send className="w-4 h-4" /> XÁC NHẬN CỘNG ĐIỂM TRẠM
                            </>
                          )}
                        </button>
                      </div>
                    )}
                  </div>
                )}
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}
