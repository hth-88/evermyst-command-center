// ============================================================================
// STATION MASTER PAGE (StationPage.tsx)
// File: src/pages/StationPage.tsx
// Màn hình vận hành dành riêng cho Quản Trò tại /station theo Migration 104
// Chấm điểm trực tiếp cho đội tại trạm + Quản lý 20 lượt chấm gần nhất & Hoàn tác
// ============================================================================
import React, { useState, useEffect, useCallback, useMemo } from 'react';
import { useSession } from '@/contexts/SessionContext';
import { useGame } from '@/contexts/GameContext';
import { supabase } from '@/lib/supabase';
import { StationScoringForm } from '@/components/scoring/StationScoringForm';
import type { ScoringInput } from '@/scoring/types';
import type { StationPlay } from '@/lib/types';
import {
  MapPin,
  CheckCircle2,
  RotateCcw,
  LogOut,
  Send,
  Loader2,
  Sparkles,
  History,
  AlertTriangle,
  ChevronDown,
  Shield,
  Clock,
} from 'lucide-react';

export default function StationPage() {
  const { user, logout } = useSession();
  const {
    stations,
    teams,
    refreshAll,
    awardStationDirectPoints,
    reverseStationPlay,
    getStationRecentPlays,
    addToast,
  } = useGame();

  // Xác định trạm được phân công cho quản trò
  const currentStation = useMemo(() => {
    if (!user) return null;
    const activeStations = stations.filter((s: any) => !s.deleted_at);

    if (user.assigned_station_id) {
      const match = activeStations.find((s) => s.id === user.assigned_station_id);
      if (match) return match;
    }
    // Fallback khớp theo số thứ tự trạm hoặc tên từ tài khoản Quản trò
    const uName = (user.name || '').toLowerCase();
    let targetOrder = 0;
    if (uName.includes('trạm 1') || uName.includes('cổng sương mù')) targetOrder = 1;
    else if (uName.includes('trạm 2') || uName.includes('rừng thì thầm') || uName.includes('đền cổ')) targetOrder = 2;
    else if (uName.includes('trạm 3') || uName.includes('đầm lầy ảo ảnh') || uName.includes('rừng bóng tối')) targetOrder = 3;
    else if (uName.includes('trạm 4') || uName.includes('hang pha lê') || uName.includes('hồ gương')) targetOrder = 4;
    else if (uName.includes('trạm 5') || uName.includes('đỉnh thiên giới') || uName.includes('đỉnh tháp')) targetOrder = 5;

    if (targetOrder > 0) {
      const matchByOrder = activeStations.find((s) => s.order_index === targetOrder);
      if (matchByOrder) return matchByOrder;
    }

    return activeStations[0] || null;
  }, [user, stations]);

  // Form chấm điểm state
  const [selectedTeamId, setSelectedTeamId] = useState<string>('');
  const [scoreInput, setScoreInput] = useState<{ input: ScoringInput; points: number; isValid: boolean }>({
    input: {},
    points: 50,
    isValid: true,
  });
  const [scoringNote, setScoringNote] = useState<string>('');
  const [isSubmitting, setIsSubmitting] = useState(false);

  // Danh sách 20 lượt chấm gần nhất
  const [recentPlays, setRecentPlays] = useState<StationPlay[]>([]);
  const [isLoadingPlays, setIsLoadingPlays] = useState(true);
  const [reversingPlayId, setReversingPlayId] = useState<string | null>(null);

  // Set default team
  useEffect(() => {
    if (teams.length > 0 && !selectedTeamId) {
      setSelectedTeamId(teams[0].id);
    }
  }, [teams, selectedTeamId]);

  // Tải 20 lượt chấm gần nhất tại trạm
  const fetchRecentPlays = useCallback(async () => {
    if (!currentStation) return;
    setIsLoadingPlays(true);
    try {
      // Gọi RPC get_station_recent_plays của Migration 104
      const res = await getStationRecentPlays(currentStation.id, 20);
      if (res.success && Array.isArray((res.data as any)?.plays)) {
        setRecentPlays((res.data as any).plays);
      } else {
        // Fallback: query trực tiếp từ public.station_plays trên Supabase DB
        const { data, error } = await supabase
          .from('station_plays')
          .select('*')
          .eq('station_id', currentStation.id)
          .order('created_at', { ascending: false })
          .limit(20);

        if (!error && data) {
          // Bổ sung team_name
          const enriched = data.map((p: any) => ({
            ...p,
            team_name: teams.find((t) => t.id === p.team_id)?.name || 'Đội chơi',
          }));
          setRecentPlays(enriched);
        }
      }
    } catch (err) {
      console.error('Lỗi tải danh sách lượt chấm:', err);
    } finally {
      setIsLoadingPlays(false);
    }
  }, [currentStation, getStationRecentPlays, teams]);

  useEffect(() => {
    fetchRecentPlays();
  }, [fetchRecentPlays]);

  // Handler chấm điểm trực tiếp
  const handleAwardPoints = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!currentStation || !selectedTeamId || isSubmitting) return;

    if (!scoreInput.isValid || scoreInput.points <= 0) {
      alert('Vui lòng nhập số điểm hợp lệ (> 0).');
      return;
    }

    const team = teams.find((t) => t.id === selectedTeamId);
    const confirmMsg = `Xác nhận cộng +${scoreInput.points}✦ Lumen cho đội ${team?.name || 'này'} tại trạm ${currentStation.name}?`;
    if (!window.confirm(confirmMsg)) return;

    setIsSubmitting(true);
    try {
      const res = await awardStationDirectPoints(
        selectedTeamId,
        currentStation.id,
        scoreInput.points,
        scoringNote.trim() || `Quản trò ${user?.name || ''} chấm điểm`
      );

      if (res.success) {
        addToast(`+${scoreInput.points}✦ Lumen đã được cộng trực tiếp cho ${team?.name}!`, 'success');
        setScoringNote('');
        await fetchRecentPlays();
        await refreshAll();
      } else {
        alert(res.error || res.message || 'Lỗi khi cộng điểm trạm.');
      }
    } catch (err: any) {
      alert(err.message || 'Lỗi kết nối khi cộng điểm trạm.');
    } finally {
      setIsSubmitting(false);
    }
  };

  // Handler hoàn tác lượt chấm
  const handleReversePlay = async (play: StationPlay) => {
    const teamName = play.team_name || teams.find((t) => t.id === play.team_id)?.name || 'Đội';
    const confirmMsg = `Bạn có chắc muốn HOÀN TÁC lượt chấm này? Điểm của ${teamName} sẽ bị trừ lại -${play.points}✦ Lumen.`;
    if (!window.confirm(confirmMsg)) return;

    setReversingPlayId(play.id);
    try {
      const res = await reverseStationPlay(play.id, `Quản trò ${user?.name || ''} hoàn tác`);
      if (res.success) {
        addToast(`Đã thu hồi -${play.points}✦ Lumen từ ${teamName}`, 'info');
        await fetchRecentPlays();
        await refreshAll();
      } else {
        alert(res.error || res.message || 'Không thể hoàn tác lượt chấm này.');
      }
    } catch (err: any) {
      alert(err.message || 'Lỗi khi hoàn tác lượt chấm.');
    } finally {
      setReversingPlayId(null);
    }
  };

  const formatTime = (isoString?: string) => {
    if (!isoString) return '';
    const d = new Date(isoString);
    return `${d.getHours().toString().padStart(2, '0')}:${d.getMinutes().toString().padStart(2, '0')} - ${d.getDate()}/${d.getMonth() + 1}`;
  };

  return (
    <div className="min-h-screen bg-evermyst-bg text-evermyst-text flex flex-col font-sans select-none">
      {/* Top Bar */}
      <header className="h-14 bg-evermyst-surface border-b border-evermyst-border px-4 flex items-center justify-between shrink-0 shadow-md">
        <div className="flex items-center gap-3">
          <div className="w-9 h-9 rounded-xl bg-gradient-to-br from-lumen to-lumen-dark flex items-center justify-center text-evermyst-bg shadow-md">
            <MapPin className="w-5 h-5" />
          </div>
          <div>
            <div className="flex items-center gap-2">
              <span className="text-sm font-black uppercase text-white tracking-wide">
                {currentStation ? currentStation.name : 'TRẠM THỬ THÁCH'}
              </span>
              <span className="px-2 py-0.5 rounded-full bg-lumen/20 text-lumen text-[10px] font-black border border-lumen/40 uppercase">
                QUẢN TRÒ
              </span>
            </div>
            <div className="text-[10px] text-evermyst-text-dim">
              Thứ tự: Trạm #{currentStation?.order_index || 1} • {currentStation?.allow_multiple_attempts ? 'Đa lượt chơi' : 'Một lượt duy nhất'}
            </div>
          </div>
        </div>

        <div className="flex items-center gap-2">
          <button
            onClick={() => {
              fetchRecentPlays();
              refreshAll();
            }}
            className="p-2 rounded-xl bg-evermyst-card border border-evermyst-border text-evermyst-text-dim hover:text-lumen transition-all"
            title="Làm mới dữ liệu"
          >
            <RotateCcw className="w-4 h-4" />
          </button>
          <button
            onClick={logout}
            className="flex items-center gap-1.5 px-3 py-1.5 rounded-xl bg-danger/10 hover:bg-danger/20 text-danger border border-danger/30 text-xs font-bold transition-all"
          >
            <LogOut className="w-3.5 h-3.5" />
            Thoát ({user?.name})
          </button>
        </div>
      </header>

      {/* Main Container */}
      <div className="flex-1 max-w-5xl w-full mx-auto p-4 md:p-6 grid grid-cols-1 lg:grid-cols-12 gap-6">
        {/* =================================================================== */}
        {/* CỘT TRÁI (5/12): BIỂU MẪU CHẤM ĐIỂM TRỰC TIẾP */}
        {/* =================================================================== */}
        <div className="lg:col-span-5 space-y-4">
          <div className="p-5 rounded-3xl bg-evermyst-card border border-evermyst-border shadow-xl space-y-5">
            <div className="flex items-center gap-2 pb-3 border-b border-evermyst-border">
              <Sparkles className="w-5 h-5 text-lumen" />
              <h2 className="text-sm font-black uppercase tracking-wider text-white">
                Chấm Điểm Trực Tiếp
              </h2>
            </div>

            <form onSubmit={handleAwardPoints} className="space-y-4">
              {/* Chọn Đội */}
              <div className="space-y-1.5">
                <label className="block text-xs font-bold text-evermyst-text-muted uppercase tracking-wider">
                  Chọn Đội Chơi:
                </label>
                <div className="relative">
                  <select
                    value={selectedTeamId}
                    onChange={(e) => setSelectedTeamId(e.target.value)}
                    className="w-full h-12 bg-evermyst-surface border border-evermyst-border rounded-xl px-3.5 text-sm font-bold text-white focus:outline-none focus:border-lumen appearance-none"
                  >
                    {teams.map((t) => (
                      <option key={t.id} value={t.id} className="bg-evermyst-card text-white">
                        {t.name} (Số dư: {t.light_balance}✦)
                      </option>
                    ))}
                  </select>
                  <ChevronDown className="w-4 h-4 text-evermyst-text-dim absolute right-3.5 top-4 pointer-events-none" />
                </div>
              </div>

              {/* Nhập Điểm với Quick Fill */}
              <div className="space-y-1.5">
                <label className="block text-xs font-bold text-evermyst-text-muted uppercase tracking-wider">
                  Số Điểm Cộng Trực Tiếp (&gt; 0):
                </label>
                <StationScoringForm
                  scoringType={currentStation?.scoring_type as any}
                  scoringConfig={currentStation?.scoring_config}
                  minScore={0}
                  maxScore={500}
                  onChange={(input, points, isValid) => {
                    setScoreInput({ input, points, isValid });
                  }}
                />
              </div>

              {/* Ghi chú */}
              <div className="space-y-1.5">
                <label className="block text-xs font-bold text-evermyst-text-muted uppercase tracking-wider">
                  Ghi Chú Lượt Chơi (Tùy chọn):
                </label>
                <input
                  type="text"
                  placeholder="VD: Giải mã xuất sắc, thưởng thêm..."
                  value={scoringNote}
                  onChange={(e) => setScoringNote(e.target.value)}
                  className="w-full h-10 px-3 bg-evermyst-surface border border-evermyst-border rounded-xl text-xs text-white placeholder:text-evermyst-text-dim focus:outline-none focus:border-lumen"
                />
              </div>

              {/* Nút Submit */}
              <button
                type="submit"
                disabled={isSubmitting || !scoreInput.isValid || scoreInput.points <= 0}
                className="w-full h-13 rounded-2xl bg-gradient-to-r from-lumen to-lumen-dark text-evermyst-bg font-black text-sm uppercase tracking-wider shadow-lg shadow-lumen/25 active:scale-[0.98] transition-all flex items-center justify-center gap-2 disabled:opacity-40"
              >
                {isSubmitting ? (
                  <>
                    <Loader2 className="w-5 h-5 animate-spin" />
                    ĐANG CỘNG ĐIỂM...
                  </>
                ) : (
                  <>
                    <Send className="w-5 h-5" />
                    XÁC NHẬN CỘNG ĐIỂM TRẠM (+{scoreInput.points}✦)
                  </>
                )}
              </button>
            </form>
          </div>
        </div>

        {/* =================================================================== */}
        {/* CỘT PHẢI (7/12): 20 LƯỢT CHẤM GẦN NHẤT & NÚT HOÀN TÁC */}
        {/* =================================================================== */}
        <div className="lg:col-span-7 space-y-4">
          <div className="p-5 rounded-3xl bg-evermyst-card border border-evermyst-border shadow-xl space-y-4 flex flex-col min-h-[500px]">
            <div className="flex items-center justify-between pb-3 border-b border-evermyst-border">
              <div className="flex items-center gap-2">
                <History className="w-5 h-5 text-lumen" />
                <h2 className="text-sm font-black uppercase tracking-wider text-white">
                  20 Lượt Chấm Gần Nhất
                </h2>
              </div>
              <span className="text-xs text-evermyst-text-dim font-mono">
                {recentPlays.length} lượt
              </span>
            </div>

            <div className="flex-1 overflow-y-auto space-y-2.5 max-h-[600px] pr-1">
              {isLoadingPlays ? (
                <div className="py-16 text-center space-y-2">
                  <div className="w-6 h-6 border-2 border-lumen border-t-transparent rounded-full animate-spin mx-auto" />
                  <p className="text-xs text-evermyst-text-dim">Đang tải lịch sử chấm điểm...</p>
                </div>
              ) : recentPlays.length === 0 ? (
                <div className="py-16 text-center space-y-2">
                  <History className="w-8 h-8 text-evermyst-text-dim mx-auto" />
                  <p className="text-sm font-bold text-evermyst-text">Chưa có lượt chấm nào tại trạm</p>
                  <p className="text-xs text-evermyst-text-dim">
                    Nhập điểm ở form bên trái để ghi nhận kết quả đầu tiên.
                  </p>
                </div>
              ) : (
                recentPlays.map((play) => {
                  const teamName = play.team_name || teams.find((t) => t.id === play.team_id)?.name || 'Đội chơi';
                  const isActive = play.status === 'active';

                  return (
                    <div
                      key={play.id}
                      className={`p-3.5 rounded-2xl border transition-all text-xs space-y-2 ${
                        isActive
                          ? 'bg-evermyst-surface border-evermyst-border'
                          : 'bg-danger/5 border-danger/20 opacity-60'
                      }`}
                    >
                      <div className="flex items-start justify-between gap-3">
                        <div className="space-y-0.5">
                          <div className="flex items-center gap-2">
                            <span className="font-black text-white text-sm">{teamName}</span>
                            <span className="px-2 py-0.5 rounded-full bg-evermyst-card border border-evermyst-border text-[10px] font-mono text-evermyst-text-dim">
                              Lượt #{play.play_no}
                            </span>
                            {isActive ? (
                              <span className="px-2 py-0.5 rounded-full bg-success/15 text-success text-[10px] font-bold border border-success/30">
                                Đã cộng điểm
                              </span>
                            ) : (
                              <span className="px-2 py-0.5 rounded-full bg-danger/15 text-danger text-[10px] font-bold border border-danger/30">
                                Đã hoàn tác
                              </span>
                            )}
                          </div>

                          <div className="text-[11px] text-evermyst-text-dim flex items-center gap-2">
                            <span>Người chấm: {play.staff_name}</span>
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

                        <div className="text-right shrink-0 space-y-1">
                          <div
                            className={`text-base font-black font-mono ${
                              isActive ? 'text-success' : 'text-danger line-through'
                            }`}
                          >
                            +{play.points}✦
                          </div>

                          {/* Nút Hoàn Tác (-Điểm) nếu còn active */}
                          {isActive && (
                            <button
                              type="button"
                              disabled={reversingPlayId === play.id}
                              onClick={() => handleReversePlay(play)}
                              className="px-2.5 py-1 rounded-lg bg-danger/15 hover:bg-danger/25 text-danger border border-danger/30 text-[11px] font-bold transition-all active:scale-95 flex items-center gap-1"
                            >
                              {reversingPlayId === play.id ? (
                                <Loader2 className="w-3 h-3 animate-spin" />
                              ) : (
                                <RotateCcw className="w-3 h-3" />
                              )}
                              Hoàn tác (-Điểm)
                            </button>
                          )}
                        </div>
                      </div>
                    </div>
                  );
                })
              )}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
