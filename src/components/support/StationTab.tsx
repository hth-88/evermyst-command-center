import React, { useState, useEffect, useCallback } from 'react';
import { useGame } from '@/contexts/GameContext';
import type { Team } from '@/lib/types';
import {
  MapPin,
  CheckCircle2,
  Clock,
  RotateCcw,
  Award,
  Layers,
} from 'lucide-react';

interface StationTabProps {
  selectedTeam: Team | null;
}

interface StationStatusItem {
  station_id: string;
  station_name: string;
  order_index: number;
  scoring_type: string;
  allow_multiple_attempts: boolean;
  total_points: number;
  play_count: number;
  is_completed: boolean;
  recent_plays: Array<{
    id: string;
    points: number;
    play_no: number;
    staff_name: string;
    created_at: string;
    note?: string;
  }>;
}

export default function StationTab({ selectedTeam }: StationTabProps) {
  const { stations, transactions, refreshAll } = useGame();
  const [stationStatuses, setStationStatuses] = useState<StationStatusItem[]>([]);
  const [, setIsLoading] = useState(true);

  const fetchStationStatuses = useCallback(async () => {
    if (!selectedTeam) return;
    setIsLoading(true);
    try {
      const activeStations = stations
        .filter((s: any) => !s.deleted_at && s.is_active)
        .sort((a, b) => a.order_index - b.order_index);

      const teamStationTx = transactions.filter(
        (t) => t.team_id === selectedTeam.id && t.type === 'station_clear' && !t.is_reversed
      );

      const mapped: StationStatusItem[] = activeStations.map((st) => {
        // Lấy toàn bộ giao dịch vượt trạm này của đội
        const relatedTxs = teamStationTx.filter((tx) =>
          tx.description?.includes(st.name) || (tx.metadata as any)?.station_id === st.id
        );

        const totalPoints = relatedTxs.reduce((sum, tx) => sum + (tx.amount || 0), 0);
        const playCount = relatedTxs.length;
        const isCompleted = selectedTeam.unlocked_stations?.includes(st.id) || playCount > 0;

        return {
          station_id: st.id,
          station_name: st.name,
          order_index: st.order_index,
          scoring_type: st.scoring_type,
          allow_multiple_attempts: st.allow_multiple_attempts,
          total_points: totalPoints,
          play_count: playCount,
          is_completed: isCompleted,
          recent_plays: relatedTxs.map((tx, idx) => ({
            id: tx.id,
            points: tx.amount,
            play_no: idx + 1,
            staff_name: tx.created_by || 'Quản trò',
            created_at: tx.created_at,
            note: tx.description,
          })),
        };
      });

      setStationStatuses(mapped);
    } catch (err) {
      console.error('Lỗi tính toán lộ trình trạm:', err);
    } finally {
      setIsLoading(false);
    }
  }, [selectedTeam, stations, transactions]);

  useEffect(() => {
    fetchStationStatuses();
  }, [fetchStationStatuses]);

  const formatTime = (isoString?: string) => {
    if (!isoString) return '';
    const d = new Date(isoString);
    return `${d.getHours().toString().padStart(2, '0')}:${d.getMinutes().toString().padStart(2, '0')} - ${d.getDate()}/${d.getMonth() + 1}`;
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

  return (
    <div className="p-4 space-y-4 pb-28 animate-fadeIn">
      {/* Header Info */}
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-base font-black text-white flex items-center gap-2">
            <MapPin className="w-4 h-4 text-lumen" />
            Tiến Độ Lộ Trình Thử Thách
          </h2>
          <p className="text-[11px] text-evermyst-text-muted">
            Theo dõi kết quả thi đấu tại các trạm của {selectedTeam.name} (Chế độ xem Support)
          </p>
        </div>

        <button
          onClick={async () => {
            await refreshAll();
            await fetchStationStatuses();
          }}
          className="text-[11px] font-bold text-lumen hover:underline flex items-center gap-1 cursor-pointer"
        >
          <RotateCcw className="w-3 h-3" /> Làm mới
        </button>
      </div>

      {/* Danh sách các Trạm dạng Read-Only Cards */}
      <div className="space-y-3">
        {stationStatuses.map((item, idx) => {
          return (
            <div
              key={item.station_id}
              className={`rounded-2xl border transition-all overflow-hidden ${
                item.is_completed
                  ? 'bg-success/5 border-success/30'
                  : 'bg-evermyst-card border-evermyst-border opacity-85'
              }`}
            >
              {/* Header Card */}
              <div className="p-4 flex items-start justify-between gap-3">
                <div className="space-y-1.5 flex-1">
                  <div className="flex items-center gap-2 flex-wrap">
                    <span className="w-6 h-6 rounded-lg bg-evermyst-surface text-lumen text-xs font-mono font-black flex items-center justify-center border border-evermyst-border">
                      {idx + 1}
                    </span>
                    <h3 className="text-sm font-black text-white leading-tight">
                      {item.station_name}
                    </h3>
                  </div>

                  <div className="text-[11px] text-evermyst-text-muted flex items-center gap-2 flex-wrap">
                    <span className="uppercase font-semibold tracking-wider px-2 py-0.5 rounded-md bg-evermyst-surface border border-evermyst-border text-[10px]">
                      {item.scoring_type}
                    </span>
                    {item.allow_multiple_attempts && (
                      <span className="text-lumen font-bold text-[10px] flex items-center gap-1">
                        <Layers className="w-3 h-3" /> Đa lượt chơi
                      </span>
                    )}
                  </div>
                </div>

                {/* Status & Points Badge */}
                <div className="shrink-0 text-right space-y-1">
                  {item.is_completed ? (
                    <div className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-xl bg-success/20 text-success border border-success/30 font-black text-xs">
                      <CheckCircle2 className="w-4 h-4" />
                      <span>+{item.total_points}✦ Lumen</span>
                    </div>
                  ) : (
                    <div className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-xl bg-evermyst-surface text-evermyst-text-dim border border-evermyst-border text-xs font-semibold">
                      <Clock className="w-3.5 h-3.5" />
                      <span>Chưa hoàn thành</span>
                    </div>
                  )}

                  {item.play_count > 0 && (
                    <div className="text-[10px] text-evermyst-text-dim font-mono">
                      Đã chơi: <strong>{item.play_count} lượt</strong>
                    </div>
                  )}
                </div>
              </div>

              {/* Lịch sử các lượt chơi của trạm này (nếu có) */}
              {item.recent_plays.length > 0 && (
                <div className="px-4 pb-3 pt-1 border-t border-evermyst-border/50 bg-evermyst-surface/40 space-y-2">
                  <div className="text-[10px] font-bold text-evermyst-text-dim uppercase tracking-wider flex items-center gap-1">
                    <Award className="w-3 h-3 text-lumen" /> Lịch sử chấm điểm:
                  </div>
                  <div className="space-y-1.5">
                    {item.recent_plays.map((play) => (
                      <div
                        key={play.id}
                        className="flex items-center justify-between text-xs p-2 rounded-xl bg-evermyst-card border border-evermyst-border"
                      >
                        <div className="space-y-0.5">
                          <div className="font-semibold text-white flex items-center gap-1.5">
                            <span className="text-lumen font-mono text-[10px]">Lượt #{play.play_no}</span>
                            <span>•</span>
                            <span className="text-[11px] text-evermyst-text-dim">Chấm bởi: {play.staff_name}</span>
                          </div>
                          <div className="text-[10px] text-evermyst-text-muted font-mono">
                            {formatTime(play.created_at)}
                          </div>
                        </div>
                        <div className="font-black text-success font-mono text-sm">
                          +{play.points}✦
                        </div>
                      </div>
                    ))}
                  </div>
                </div>
              )}
            </div>
          );
        })}
      </div>
    </div>
  );
}
