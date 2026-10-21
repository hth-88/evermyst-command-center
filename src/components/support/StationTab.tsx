// ============================================================================
// SUPPORT STATION TAB (src/components/support/StationTab.tsx)
// File: src/components/support/StationTab.tsx
// Danh sách 5 trạm với 5 trạng thái (Chưa làm, Chờ Quản Trò, Chờ BTC, Đã xong, Bị từ chối)
// Nút nộp bị khóa khi slot bị chiếm, có nút "Rút lại", hiện badge Chìa Khóa (ADR-4)
// ============================================================================
import React, { useState, useEffect, useCallback } from 'react';
import { useGame } from '@/contexts/GameContext';
import { callRpc } from '@/lib/rpc';
import { StationScoringForm } from '@/components/scoring/StationScoringForm';
import { formatScoringInput } from '@/scoring/format';
import type { Team, Station } from '@/lib/types';
import type { ScoringInput } from '@/scoring/types';
import {
  MapPin,
  Clock,
  CheckCircle2,
  XCircle,
  AlertCircle,
  Key,
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
    status: 'draft' | 'pending_station' | 'pending_admin' | 'approved' | 'rejected' | 'cancelled';
    points: number;
    created_at: string;
    input?: Record<string, any>;
    reject_reason?: string;
  } | null;
}

export default function StationTab({ selectedTeam }: StationTabProps) {
  const { stations, teamStationKeys, refreshAll } = useGame();
  const [stationStatuses, setStationStatuses] = useState<StationStatusItem[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [activeFormStationId, setActiveFormStationId] = useState<string | null>(null);

  // Form input state
  const [formData, setFormData] = useState<Record<string, { input: ScoringInput; points: number; isValid: boolean }>>({});
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [actionLoadingId, setActionLoadingId] = useState<string | null>(null);

  const teamKeys = selectedTeam ? teamStationKeys[selectedTeam.id] || [] : [];

  // Tải trạng thái các trạm của đội
  const fetchStationStatuses = useCallback(async () => {
    if (!selectedTeam) return;
    try {
      const res = await callRpc<any>('get_team_station_status');
      if (res.success && Array.isArray(res.stations)) {
        const enriched = res.stations.map((st: StationStatusItem) => ({
          ...st,
          has_key: st.has_key || teamKeys.includes(st.station_id),
        }));
        setStationStatuses(enriched);
      } else {
        // Fallback tự sinh từ danh sách stations và team
        const activeStations = stations.filter((s) => s.is_active);
        const mapped = activeStations.map((st) => ({
          station_id: st.id,
          station_name: st.name,
          order_index: st.order_index,
          scoring_type: st.scoring_type,
          scoring_config: st.scoring_config,
          allow_multiple_attempts: st.allow_multiple_attempts,
          has_key: teamKeys.includes(st.id) || false,
          active_claim: selectedTeam.unlocked_stations?.includes(st.id)
            ? { id: 'done', status: 'approved' as const, points: st.max_score, created_at: new Date().toISOString() }
            : null,
        }));
        setStationStatuses(mapped);
      }
    } catch {
      // ignore
    } finally {
      setIsLoading(false);
    }
  }, [selectedTeam, stations, teamKeys]);

  useEffect(() => {
    fetchStationStatuses();
  }, [fetchStationStatuses]);

  // Handler nộp yêu cầu chấm điểm
  const handleSubmitClaim = async (station: Station | StationStatusItem) => {
    if (!selectedTeam || isSubmitting) return;

    const stId = (station as any).station_id || (station as any).id;
    const data = formData[stId];
    if (!data || !data.isValid) {
      alert('Vui lòng hoàn tất nhập liệu hợp lệ trước khi gửi yêu cầu.');
      return;
    }

    setIsSubmitting(true);
    try {
      let res = await callRpc('submit_station_claim', {
        p_station_id: stId,
        p_input: data.input,
      });

      // Nếu DB là legacy schema chưa có submit_station_claim, fallback sang award_station
      if (!res.success && (res.code === 'PGRST202' || res.error?.includes('schema cache') || res.message?.includes('schema cache'))) {
        res = await callRpc('award_station', {
          p_team_id: selectedTeam.id,
          p_station_id: stId,
          p_amount: data.points || 50,
          p_unlock_station: true,
        });
      }

      if (res.success) {
        setActiveFormStationId(null);
        await fetchStationStatuses();
        await refreshAll();
      } else {
        alert(res.error || res.message || 'Không thể gửi yêu cầu chấm điểm.');
      }
    } finally {
      setIsSubmitting(false);
    }
  };

  // Handler rút lại claim pending_station
  const handleCancelClaim = async (claimId: string) => {
    if (!confirm('Bạn có chắc chắn muốn rút lại yêu cầu chấm điểm này?')) return;

    setActionLoadingId(claimId);
    try {
      const res = await callRpc('cancel_station_claim', {
        p_claim_id: claimId,
      });

      if (res.success) {
        await fetchStationStatuses();
        await refreshAll();
      } else {
        alert(res.error || res.message || 'Không thể rút lại yêu cầu.');
      }
    } finally {
      setActionLoadingId(null);
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

  // Danh sách hiển thị: kết hợp giữa stations và status
  const displayItems = stationStatuses.length > 0 ? stationStatuses : stations.map((s) => ({
    station_id: s.id,
    station_name: s.name,
    order_index: s.order_index,
    scoring_type: s.scoring_type,
    scoring_config: s.scoring_config,
    allow_multiple_attempts: s.allow_multiple_attempts,
    has_key: false,
    active_claim: null,
  }));

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
            5 trạm thử thách độc quyền cho {selectedTeam.name}
          </p>
        </div>

        <button
          onClick={fetchStationStatuses}
          className="text-[11px] font-bold text-lumen hover:underline flex items-center gap-1"
        >
          <RotateCcw className="w-3 h-3" /> Làm mới
        </button>
      </div>

      {/* Danh sách 5 Trạm với 5 Trạng Thái */}
      <div className="space-y-3">
        {displayItems.map((item, idx) => {
          const stationId = item.station_id;
          const claim = item.active_claim;
          const status = claim?.status || 'unattempted';
          const isUnlocked = selectedTeam.unlocked_stations?.includes(stationId) || status === 'approved';
          const isPendingStation = status === 'pending_station';
          const isPendingAdmin = status === 'pending_admin';
          const isRejected = status === 'rejected';
          const isFormOpen = activeFormStationId === stationId;

          // Slot đã bị chiếm nếu là trạm độc quyền (is_exclusive) và đang có claim pending hoặc approved
          const isSlotLocked = !item.allow_multiple_attempts && (isPendingStation || isPendingAdmin || isUnlocked);

          return (
            <div
              key={stationId}
              className={`rounded-2xl border transition-all overflow-hidden ${
                isUnlocked
                  ? 'bg-success/5 border-success/30'
                  : isPendingStation
                  ? 'bg-warning/5 border-warning/30'
                  : isPendingAdmin
                  ? 'bg-props/5 border-props/30'
                  : isRejected
                  ? 'bg-danger/5 border-danger/30'
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

                    {/* Badge Chìa Khóa Vạn Năng */}
                    {item.has_key && (
                      <span className="px-2.5 py-0.5 rounded-full bg-amber-500/20 border border-amber-500/50 text-amber-300 text-[11px] font-black flex items-center gap-1.5 shadow-lg shadow-amber-500/10 animate-pulse">
                        <Key className="w-3.5 h-3.5 text-amber-400" /> 🗝️ CHÌA KHÓA VẠN NĂNG
                      </span>
                    )}
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

                {/* Status Badge 1 trong 5 Trạng Thái */}
                <div className="shrink-0 text-right">
                  {isUnlocked ? (
                    <div className="inline-flex items-center gap-1 px-2.5 py-1 rounded-xl bg-success/15 text-success font-bold text-xs">
                      <CheckCircle2 className="w-3.5 h-3.5" />
                      <span>+{claim?.points ?? ''}✦ Đã xong</span>
                    </div>
                  ) : isPendingStation ? (
                    <div className="inline-flex items-center gap-1 px-2.5 py-1 rounded-xl bg-warning/15 text-warning font-bold text-xs animate-pulse">
                      <Clock className="w-3.5 h-3.5" />
                      <span>Chờ Quản Trò</span>
                    </div>
                  ) : isPendingAdmin ? (
                    <div className="inline-flex items-center gap-1 px-2.5 py-1 rounded-xl bg-props/15 text-props font-bold text-xs">
                      <Sparkles className="w-3.5 h-3.5" />
                      <span>Chờ BTC duyệt</span>
                    </div>
                  ) : isRejected ? (
                    <div className="inline-flex items-center gap-1 px-2.5 py-1 rounded-xl bg-danger/15 text-danger font-bold text-xs">
                      <XCircle className="w-3.5 h-3.5" />
                      <span>Bị từ chối</span>
                    </div>
                  ) : (
                    <div className="inline-flex items-center gap-1 px-2.5 py-1 rounded-xl bg-evermyst-surface text-evermyst-text-dim text-xs font-semibold">
                      <span>Chưa thực hiện</span>
                    </div>
                  )}
                </div>
              </div>

              {/* Status Details / Actions */}
              <div className="px-4 pb-4 space-y-3">
                {/* 1. Trạng thái: Chờ Quản Trò -> Có nút Rút lại */}
                {isPendingStation && claim && (
                  <div className="p-3 rounded-xl bg-warning/10 border border-warning/20 text-xs flex items-center justify-between">
                    <div>
                      <div className="font-bold text-warning">
                        Đang chờ Trạm xác nhận
                      </div>
                      <div className="text-[11px] text-evermyst-text-muted mt-0.5">
                        {claim.input ? formatScoringInput(item.scoring_type, claim.input, item.scoring_config) : 'Đã nộp input'}
                      </div>
                    </div>

                    <button
                      type="button"
                      disabled={actionLoadingId === claim.id}
                      onClick={() => handleCancelClaim(claim.id)}
                      className="px-3 py-1.5 rounded-xl bg-danger/15 border border-danger/30 text-danger-light hover:bg-danger/25 text-xs font-bold transition-all flex items-center gap-1 active:scale-95"
                    >
                      {actionLoadingId === claim.id ? (
                        <Loader2 className="w-3.5 h-3.5 animate-spin" />
                      ) : (
                        'Rút lại'
                      )}
                    </button>
                  </div>
                )}

                {/* 2. Trạng thái: Bị từ chối -> Hiện lý do & Cho phép nộp lại */}
                {isRejected && (
                  <div className="p-3 rounded-xl bg-danger/10 border border-danger/20 text-xs space-y-1">
                    <div className="font-bold text-danger flex items-center gap-1.5">
                      <AlertCircle className="w-3.5 h-3.5" />
                      Lý do: {claim?.reject_reason || 'Chưa đạt yêu cầu trạm'}
                    </div>
                    <p className="text-[11px] text-evermyst-text-muted">
                      Đội chơi được phép nộp lại yêu cầu chấm điểm mới.
                    </p>
                  </div>
                )}

                {/* 3. Nút Nộp Điểm / Mở Form (cho phép khi chưa xong, hoặc bị từ chối, hoặc trạm allow_multiple_attempts) */}
                {(!isSlotLocked || item.allow_multiple_attempts) && (
                  <div>
                    {!isFormOpen ? (
                      <button
                        type="button"
                        onClick={() => setActiveFormStationId(stationId)}
                        className="w-full h-12 rounded-xl bg-evermyst-surface border border-evermyst-border hover:border-lumen/40 text-evermyst-text hover:text-white text-xs font-bold flex items-center justify-center gap-2 transition-all active:scale-[0.99]"
                      >
                        <Send className="w-3.5 h-3.5 text-lumen" />
                        {isRejected ? 'Nộp lại kết quả' : item.allow_multiple_attempts && isUnlocked ? 'Nộp thêm lượt' : 'Nộp kết quả trạm'}
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

                        {/* Renderer động */}
                        <StationScoringForm
                          scoringType={item.scoring_type as any}
                          scoringConfig={item.scoring_config}
                          minScore={0}
                          maxScore={100}
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
                              <Send className="w-4 h-4" /> Gửi Yêu Cầu Chấm Điểm
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
