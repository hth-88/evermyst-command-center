// ============================================================================
// STATION PLAYS AUDIT COMPONENT (PendingAdminQueue.tsx)
// File: src/components/admin/PendingAdminQueue.tsx
// Đối Soát Lượt Chấm Điểm Trạm Gần Nhất (Migration 104)
// Cho phép Admin xem toàn bộ lượt chấm từ station_plays và 1 chạm Hoàn tác/Thu hồi
// ============================================================================
import React, { useState } from 'react';
import { useGame } from '@/contexts/GameContext';
import type { StationPlay } from '@/lib/types';
import {
  RotateCcw,
  CheckCircle2,
  XCircle,
  Loader2,
  Clock,
  Sparkles,
} from 'lucide-react';

interface StationPlaysAuditProps {
  plays: StationPlay[];
  onRefresh: () => void;
}

export const PendingAdminQueue: React.FC<StationPlaysAuditProps> = ({
  plays,
  onRefresh,
}) => {
  const { reverseStationPlay, addToast } = useGame();
  const [reversingId, setReversingId] = useState<string | null>(null);

  const handleReverse = async (play: StationPlay) => {
    const teamName = play.team_name || 'Đội chơi';
    const confirmMsg = `XÁC NHẬN THU HỒI ĐIỂM:\nBạn có chắc muốn hoàn tác lượt chấm của ${teamName} (${play.points > 0 ? `+${play.points}✦` : `${play.points}✦`})?\nĐiểm sẽ bị trừ lại ngay lập tức.`;
    if (!window.confirm(confirmMsg)) return;

    setReversingId(play.id);
    try {
      const res = await reverseStationPlay(play.id, 'Admin thu hồi / hoàn tác từ bảng đối soát');
      if (res.success) {
        addToast(`Đã thu hồi -${play.points}✦ của ${teamName}!`, 'info');
        onRefresh();
      } else {
        alert(res.error || res.message || 'Không thể hoàn tác lượt chấm này.');
      }
    } catch (err: any) {
      alert(err.message || 'Lỗi kết nối khi hoàn tác.');
    } finally {
      setReversingId(null);
    }
  };

  const formatTime = (isoString?: string) => {
    if (!isoString) return '';
    const d = new Date(isoString);
    return `${d.getHours().toString().padStart(2, '0')}:${d.getMinutes().toString().padStart(2, '0')} - ${d.getDate()}/${d.getMonth() + 1}`;
  };

  if (!plays || plays.length === 0) {
    return (
      <div className="p-12 text-center rounded-3xl bg-evermyst-card/40 border border-evermyst-border space-y-2">
        <CheckCircle2 className="w-10 h-10 text-success/60 mx-auto" />
        <p className="text-sm font-bold text-evermyst-text">Chưa có lượt chấm trạm nào</p>
        <p className="text-xs text-evermyst-text-dim">
          Mọi kết quả thi đấu tại các trạm sẽ xuất hiện tại đây để Admin đối soát trực tiếp.
        </p>
      </div>
    );
  }

  return (
    <div className="space-y-3">
      {plays.map((play) => {
        const isActive = play.status === 'active';
        const teamName = play.team_name || 'Đội chơi';
        const stationName = play.station_name || 'Trạm Thử Thách';

        return (
          <div
            key={play.id}
            className={`p-4 rounded-2xl border transition-all text-xs space-y-2.5 ${
              isActive
                ? 'bg-evermyst-card border-evermyst-border hover:border-evermyst-border-light'
                : 'bg-danger/5 border-danger/20 opacity-60'
            }`}
          >
            <div className="flex items-start justify-between gap-3">
              <div className="space-y-1">
                <div className="flex items-center gap-2 flex-wrap">
                  <span className="font-black text-white text-sm">{teamName}</span>
                  <span className="text-evermyst-text-dim">•</span>
                  <span className="font-bold text-lumen text-xs">{stationName}</span>
                  <span className="px-2 py-0.5 rounded-full bg-evermyst-surface border border-evermyst-border text-[10px] font-mono text-evermyst-text-dim">
                    Lượt #{play.play_no}
                  </span>
                  {isActive ? (
                    <span className="px-2 py-0.5 rounded-full bg-success/15 text-success text-[10px] font-bold border border-success/30 flex items-center gap-1">
                      <CheckCircle2 className="w-3 h-3" /> Đã cộng điểm
                    </span>
                  ) : (
                    <span className="px-2 py-0.5 rounded-full bg-danger/15 text-danger text-[10px] font-bold border border-danger/30 flex items-center gap-1">
                      <XCircle className="w-3 h-3" /> Đã hoàn tác
                    </span>
                  )}
                </div>

                <div className="text-[11px] text-evermyst-text-dim flex items-center gap-2">
                  <span>Chấm bởi: <strong className="text-white">{play.staff_name}</strong></span>
                  <span>•</span>
                  <span className="flex items-center gap-1 font-mono">
                    <Clock className="w-3 h-3" />
                    {formatTime(play.created_at)}
                  </span>
                </div>

                {play.note && (
                  <p className="text-[11px] text-evermyst-text-muted italic pt-0.5">
                    "{play.note}"
                  </p>
                )}
              </div>

              <div className="text-right shrink-0 space-y-2">
                <div
                  className={`text-lg font-black font-mono ${
                    isActive ? 'text-success' : 'text-danger line-through'
                  }`}
                >
                  +{play.points}✦
                </div>

                {/* Nút Thu hồi / Hoàn tác 1 chạm */}
                {isActive && (
                  <button
                    type="button"
                    disabled={reversingId === play.id}
                    onClick={() => handleReverse(play)}
                    className="px-3 py-1.5 rounded-xl bg-danger/15 hover:bg-danger/25 text-danger border border-danger/30 text-xs font-bold transition-all active:scale-95 flex items-center gap-1"
                  >
                    {reversingId === play.id ? (
                      <Loader2 className="w-3.5 h-3.5 animate-spin" />
                    ) : (
                      <RotateCcw className="w-3.5 h-3.5" />
                    )}
                    Thu hồi (-Điểm)
                  </button>
                )}
              </div>
            </div>
          </div>
        );
      })}
    </div>
  );
};
