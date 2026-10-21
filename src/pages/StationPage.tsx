// ============================================================================
// STATION MASTER PAGE (StationPage.tsx)
// File: src/pages/StationPage.tsx
// Màn hình vận hành dành riêng cho Quản Trò (station_master) tại /station
// Theo dõi hàng đợi chấm điểm realtime, duyệt legit, duyệt kèm chỉnh, từ chối,
// nhập điểm trực tiếp cho đội, chuông & rung thông báo theo Phase 7 spec.
import React, { useState, useEffect, useCallback, useRef } from 'react';
import { useSession } from '@/contexts/SessionContext';
import { useGame } from '@/contexts/GameContext';
import { callRpc } from '@/lib/rpc';
import { useSignal } from '@/hooks/useSignal';
import { ConnectionIndicator } from '@/components/common/ConnectionIndicator';
import { StationScoringForm } from '@/components/scoring/StationScoringForm';
import { formatScoringInput } from '@/scoring/format';
import type { ScoringInput, ScoringType } from '@/scoring/types';
import type { StationClaim } from '@/lib/types';
import {
  MapPin,
  CheckCircle2,
  XCircle,
  Clock,
  LogOut,
  AlertCircle,
  Sparkles,
  Edit3,
  UserCheck,
  ChevronDown,
  ChevronUp,
  Volume2,
  BellRing,
  History,
  Key,
  PlusCircle,
} from 'lucide-react';

// Danh sách chip lý do từ chối nhanh
const QUICK_REJECT_REASONS = [
  'Không đúng luật chơi',
  'Chưa hoàn thành tiêu chí',
  'Hết thời gian quy định',
  'Sai số lượng / kết quả',
  'Nhầm đội chơi',
  'Gian lận / Phạm quy',
];

export default function StationPage() {
  const { user, logout } = useSession();
  const { stations: allStations, teams: allTeams, transactions } = useGame();

  // State hàng đợi và dữ liệu trạm
  const [queue, setQueue] = useState<StationClaim[]>([]);
  const [recentProcessed, setRecentProcessed] = useState<any[]>([]);
  const [stationInfo, setStationInfo] = useState<any>(null);
  const [teamsList, setTeamsList] = useState<Array<{ id: string; name: string }>>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [actionLoadingId, setActionLoadingId] = useState<string | null>(null);

  // Âm thanh và rung khi có claim mới
  const isInitialLoad = useRef(true);
  const prevQueueIdsRef = useRef<Set<string>>(new Set());

  // Modal Từ chối
  const [rejectModalClaim, setRejectModalClaim] = useState<StationClaim | null>(null);
  const [rejectReason, setRejectReason] = useState('');
  const [rejectError, setRejectError] = useState<string | null>(null);

  // Modal Chỉnh sửa & Duyệt kèm chỉnh
  const [editModalClaim, setEditModalClaim] = useState<StationClaim | null>(null);
  const [overrideInput, setOverrideInput] = useState<ScoringInput | null>(null);
  const [overrideNote, setOverrideNote] = useState('');
  const [overrideError, setOverrideError] = useState<string | null>(null);

  // Section Nhập điểm trực tiếp
  const [showManualEntry, setShowManualEntry] = useState(false);
  const [manualTeamId, setManualTeamId] = useState<string>('');
  const [manualInput, setManualInput] = useState<ScoringInput>({});
  const [manualSubmitting, setManualSubmitting] = useState(false);
  const [manualSuccessMsg, setManualSuccessMsg] = useState<string | null>(null);
  const [manualErrorMsg, setManualErrorMsg] = useState<string | null>(null);

  // Phát chuông báo bằng Web Audio API
  const playAlertSound = useCallback(() => {
    try {
      const AudioCtx = window.AudioContext || (window as any).webkitAudioContext;
      if (!AudioCtx) return;
      const ctx = new AudioCtx();
      const osc = ctx.createOscillator();
      const gain = ctx.createGain();

      osc.type = 'sine';
      osc.frequency.setValueAtTime(880, ctx.currentTime); // A5
      osc.frequency.exponentialRampToValueAtTime(1320, ctx.currentTime + 0.15); // E6

      gain.gain.setValueAtTime(0.3, ctx.currentTime);
      gain.gain.exponentialRampToValueAtTime(0.01, ctx.currentTime + 0.35);

      osc.connect(gain);
      gain.connect(ctx.destination);

      osc.start();
      osc.stop(ctx.currentTime + 0.35);
    } catch (e) {
      console.warn('AudioContext alert notification skipped:', e);
    }
  }, []);

  // Rung máy trên thiết bị di động
  const triggerHaptic = useCallback(() => {
    if (typeof navigator !== 'undefined' && navigator.vibrate) {
      try {
        navigator.vibrate([200, 100, 200]);
      } catch (e) {
        console.warn('Vibration skipped:', e);
      }
    }
  }, []);

  // Tải danh sách hàng đợi của trạm
  const fetchQueue = useCallback(async () => {
    try {
      const res = await callRpc<{
        success: boolean;
        station_id: string;
        station?: any;
        teams?: Array<{ id: string; name: string }>;
        queue: StationClaim[];
        recent_processed?: any[];
      }>('get_station_queue', {
        p_station_id: user?.assigned_station_id || null,
      });

      if (res && res.success) {
        const newQueue = res.queue || [];
        setQueue(newQueue);

        if (res.recent_processed) {
          setRecentProcessed(res.recent_processed);
        }
        if (res.station) {
          setStationInfo(res.station);
        }
        if (res.teams && res.teams.length > 0) {
          setTeamsList(res.teams);
          if (!manualTeamId) {
            setManualTeamId(res.teams[0].id);
          }
        }

        // Phát hiện claim mới để rung và phát âm báo
        const currentIds = new Set<string>(newQueue.map((c: any) => String(c.claim_id || c.id)));
        if (!isInitialLoad.current) {
          let hasNewClaim = false;
          for (const id of currentIds) {
            if (!prevQueueIdsRef.current.has(id)) {
              hasNewClaim = true;
              break;
            }
          }
          if (hasNewClaim) {
            playAlertSound();
            triggerHaptic();
          }
        } else {
          isInitialLoad.current = false;
        }
        prevQueueIdsRef.current = currentIds;
      } else {
        // Fallback tự nhận diện trạm từ danh sách stations trong game
        let matchedStation = allStations.find((s) => s.id === user?.assigned_station_id);
        if (!matchedStation && user?.name) {
          const uName = user.name.toLowerCase();
          matchedStation = allStations.find((s) => {
            const sName = s.name.toLowerCase();
            return (uName.includes('trạm 1') || uName.includes('mê cung')) && (sName.includes('mê cung') || s.order_index === 1) ||
                   (uName.includes('trạm 2') || uName.includes('tốc độ')) && (sName.includes('tốc độ') || s.order_index === 2) ||
                   (uName.includes('trạm 3') || uName.includes('mật mã')) && (sName.includes('mật mã') || s.order_index === 3) ||
                   (uName.includes('trạm 4') || uName.includes('thu thập')) && (sName.includes('thu thập') || s.order_index === 4) ||
                   (uName.includes('trạm 5') || uName.includes('đền thờ')) && (sName.includes('đền thờ') || s.order_index === 5);
          });
        }
        if (!matchedStation && allStations.length > 0) {
          matchedStation = allStations[0];
        }

        if (matchedStation) {
          setStationInfo(matchedStation);
        }
        if (allTeams.length > 0) {
          setTeamsList(allTeams.map((t) => ({ id: t.id, name: t.name })));
          if (!manualTeamId) {
            setManualTeamId(allTeams[0].id);
          }
        }

        // Tải các giao dịch pending từ transactions
        const pendingClaims = transactions
          .filter((t) => t.type === 'station_clear' && t.status === 'pending')
          .map((t) => ({
            id: t.id,
            claim_id: t.id,
            team_id: t.team_id,
            team_name: allTeams.find((tm) => tm.id === t.team_id)?.name || 'Đội chơi',
            station_id: matchedStation?.id || '',
            station_name: matchedStation?.name || 'Trạm Thử Thách',
            status: 'pending_station' as const,
            points: t.amount,
            created_at: t.created_at,
            input: {},
          }));
        setQueue(pendingClaims as any);
      }
    } catch (err) {
      console.error('Lỗi tải hàng đợi trạm:', err);
    } finally {
      setIsLoading(false);
    }
  }, [user?.assigned_station_id, user?.name, allStations, allTeams, transactions, manualTeamId, playAlertSound, triggerHaptic]);

  // Đăng ký kênh Realtime ADR-3 với debounce 300ms và polling fallback 10s
  const { status, refetchNow } = useSignal('station_claims_changed', fetchQueue);

  useEffect(() => {
    fetchQueue();
  }, [fetchQueue]);

  // Tính thời gian đã chờ
  const formatWaitTime = (createdAtStr?: string) => {
    if (!createdAtStr) return 'Vừa xong';
    const diff = Math.floor((Date.now() - new Date(createdAtStr).getTime()) / 1000);
    if (diff < 60) return `${Math.max(1, diff)} giây trước`;
    const mins = Math.floor(diff / 60);
    if (mins < 60) return `${mins} phút trước`;
    const hours = Math.floor(mins / 60);
    return `${hours} giờ ${mins % 60}p trước`;
  };

  // Hành động 1: Xác nhận Legit (không sửa đổi)
  const handleApproveLegit = async (claim: StationClaim) => {
    const claimId = (claim as any).claim_id || claim.id;
    setActionLoadingId(claimId);
    try {
      const res = await callRpc('verify_station_claim', {
        p_claim_id: claimId,
        p_action: 'approve',
      });

      if (res.success) {
        await fetchQueue();
      } else {
        alert(res.error || res.message || 'Không thể xác nhận claim.');
      }
    } finally {
      setActionLoadingId(null);
    }
  };

  // Hành động 2: Mở modal Xác nhận kèm chỉnh
  const openEditModal = (claim: StationClaim) => {
    setEditModalClaim(claim);
    setOverrideInput(claim.input || {});
    setOverrideNote('');
    setOverrideError(null);
  };

  // Xác nhận kèm chỉnh: gọi verify_station_claim với p_override_input và p_note
  const handleConfirmEditApprove = async () => {
    if (!editModalClaim) return;
    if (!overrideNote.trim()) {
      setOverrideError('Bắt buộc phải nhập ghi chú giải trình khi điều chỉnh điểm.');
      return;
    }

    const claimId = (editModalClaim as any).claim_id || editModalClaim.id;
    setActionLoadingId(claimId);
    try {
      const res = await callRpc('verify_station_claim', {
        p_claim_id: claimId,
        p_action: 'approve',
        p_override_input: overrideInput || editModalClaim.input,
        p_note: overrideNote.trim(),
      });

      if (res.success) {
        setEditModalClaim(null);
        await fetchQueue();
      } else {
        setOverrideError(res.error || res.message || 'Không thể cập nhật claim.');
      }
    } finally {
      setActionLoadingId(null);
    }
  };

  // Hành động 3: Mở modal Từ chối
  const openRejectModal = (claim: StationClaim) => {
    setRejectModalClaim(claim);
    setRejectReason('');
    setRejectError(null);
  };

  // Xác nhận Từ chối: gọi verify_station_claim với p_action = 'reject' và p_note
  const handleConfirmReject = async () => {
    if (!rejectModalClaim) return;
    if (!rejectReason.trim()) {
      setRejectError('Bắt buộc phải nhập lý do khi từ chối yêu cầu.');
      return;
    }

    const claimId = (rejectModalClaim as any).claim_id || rejectModalClaim.id;
    setActionLoadingId(claimId);
    try {
      const res = await callRpc('verify_station_claim', {
        p_claim_id: claimId,
        p_action: 'reject',
        p_note: rejectReason.trim(),
      });

      if (res.success) {
        setRejectModalClaim(null);
        await fetchQueue();
      } else {
        setRejectError(res.error || res.message || 'Không thể từ chối claim.');
      }
    } finally {
      setActionLoadingId(null);
    }
  };

  // Quản trò nhập điểm trực tiếp cho đội chơi
  const handleManualSubmit = async () => {
    if (!manualTeamId) {
      setManualErrorMsg('Vui lòng chọn đội chơi cần chấm điểm.');
      return;
    }
    const stationId = user?.assigned_station_id || stationInfo?.id;
    if (!stationId) {
      setManualErrorMsg('Không xác định được mã trạm của bạn.');
      return;
    }

    setManualSubmitting(true);
    setManualErrorMsg(null);
    setManualSuccessMsg(null);

    try {
      const res = await callRpc('submit_station_claim', {
        p_station_id: stationId,
        p_team_id: manualTeamId,
        p_input: manualInput,
      });

      if (res.success) {
        const teamName = teamsList.find((t) => t.id === manualTeamId)?.name || 'Đội chơi';
        setManualSuccessMsg(`Đã nhập điểm thành công cho ${teamName}!`);
        await fetchQueue();
        setTimeout(() => setManualSuccessMsg(null), 4000);
      } else {
        setManualErrorMsg(res.error || res.message || 'Không thể ghi nhận điểm cho đội.');
      }
    } catch (err: any) {
      setManualErrorMsg(err.message || 'Lỗi hệ thống khi nhập điểm.');
    } finally {
      setManualSubmitting(false);
    }
  };

  const stationName = user?.assigned_station?.name || stationInfo?.name || 'Trạm Thử Thách';
  const effectiveScoringType: ScoringType = stationInfo?.scoring_type || 'tier';
  const effectiveScoringConfig = stationInfo?.scoring_config || {};

  return (
    <div className="min-h-screen bg-evermyst-bg text-evermyst-text flex flex-col justify-between max-w-lg mx-auto shadow-2xl relative select-none pb-16">
      {/* Header Sticky */}
      <header className="sticky top-0 z-40 bg-evermyst-surface/95 backdrop-blur-md border-b border-evermyst-border p-3.5 shadow-md">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2.5">
            <div className="w-10 h-10 rounded-xl bg-lumen/15 border border-lumen/30 flex items-center justify-center text-lumen">
              <MapPin className="w-5 h-5" />
            </div>
            <div>
              <div className="flex items-center gap-2">
                <h1 className="text-sm font-black text-evermyst-text tracking-wide uppercase line-clamp-1">
                  {stationName}
                </h1>
                <ConnectionIndicator status={status} onRefresh={refetchNow} compact />
              </div>
              <p className="text-[11px] text-evermyst-text-dim">
                Quản Trò: <span className="font-semibold text-evermyst-text">{user?.name}</span>
              </p>
            </div>
          </div>

          <div className="flex items-center gap-1.5">
            <button
              onClick={() => {
                playAlertSound();
                triggerHaptic();
              }}
              title="Thử chuông báo"
              className="p-2 rounded-xl bg-evermyst-card border border-evermyst-border text-evermyst-text-dim hover:text-lumen hover:border-lumen/40 transition-colors"
            >
              <Volume2 className="w-4 h-4" />
            </button>
            <button
              onClick={logout}
              title="Đăng xuất"
              className="p-2 rounded-xl bg-evermyst-card border border-evermyst-border text-evermyst-text-dim hover:text-danger hover:border-danger/40 transition-colors"
            >
              <LogOut className="w-4 h-4" />
            </button>
          </div>
        </div>
      </header>

      {/* Main Content Area */}
      <main className="flex-1 p-4 space-y-4 overflow-y-auto">
        {/* Banner Tổng kết hàng đợi */}
        <div className="p-3.5 rounded-2xl bg-evermyst-card border border-evermyst-border flex items-center justify-between shadow-sm">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-xl bg-lumen/10 flex items-center justify-center text-lumen font-black text-base border border-lumen/20">
              {queue.length}
            </div>
            <div>
              <div className="text-xs font-bold text-evermyst-text flex items-center gap-1.5">
                Hàng Đợi Chờ Duyệt
                {queue.length > 0 && (
                  <span className="w-2 h-2 rounded-full bg-lumen animate-ping" />
                )}
              </div>
              <div className="text-[11px] text-evermyst-text-dim">
                {queue.length > 0
                  ? `${queue.length} đội đang chờ bạn xác nhận`
                  : 'Hiện chưa có lượt claim nào'}
              </div>
            </div>
          </div>

          <button
            onClick={() => refetchNow()}
            className="text-xs font-bold text-lumen bg-lumen/10 hover:bg-lumen/20 border border-lumen/30 px-3 py-1.5 rounded-xl transition-colors"
          >
            Làm mới
          </button>
        </div>

        {/* HÀNG ĐỢI LIVE */}
        <div className="space-y-3">
          <div className="text-xs font-black uppercase text-evermyst-text-dim tracking-wider flex items-center gap-1.5 px-1">
            <BellRing className="w-3.5 h-3.5 text-lumen" />
            Yêu cầu đang chờ duyệt ({queue.length})
          </div>

          {isLoading ? (
            <div className="py-14 text-center space-y-2">
              <div className="w-8 h-8 border-2 border-lumen border-t-transparent rounded-full animate-spin mx-auto" />
              <p className="text-xs text-evermyst-text-dim">Đang đồng bộ hàng đợi...</p>
            </div>
          ) : queue.length === 0 ? (
            <div className="py-12 text-center space-y-2.5 p-6 rounded-3xl bg-evermyst-card/50 border border-dashed border-evermyst-border">
              <CheckCircle2 className="w-10 h-10 text-success/60 mx-auto" />
              <div className="text-sm font-bold text-evermyst-text">Hàng Đợi Trống</div>
              <p className="text-xs text-evermyst-text-dim max-w-xs mx-auto">
                Khi có đội hoàn thành và nộp điểm, chuông và tín hiệu báo sẽ lập tức kích hoạt.
              </p>
            </div>
          ) : (
            <div className="space-y-3">
              {queue.map((claim: any) => {
                const claimId = claim.claim_id || claim.id;
                const scoringType =
                  claim.scoring_snapshot?.scoring_type ||
                  stationInfo?.scoring_type ||
                  'tier';
                const scoringConfig =
                  claim.scoring_snapshot?.scoring_config ||
                  stationInfo?.scoring_config ||
                  {};

                const formattedInput = formatScoringInput(
                  scoringType,
                  claim.input,
                  scoringConfig
                );

                return (
                  <div
                    key={claimId}
                    className="p-4 rounded-3xl bg-evermyst-card border-2 border-evermyst-border hover:border-lumen/40 shadow-xl space-y-3.5 transition-all"
                  >
                    {/* Header Thẻ: Tên đội, Thời gian chờ, Điểm dự kiến */}
                    <div className="flex items-start justify-between gap-2">
                      <div>
                        <div className="flex items-center gap-1.5">
                          <span className="text-[10px] font-black uppercase tracking-wider px-2 py-0.5 rounded-md bg-lumen/15 text-lumen">
                            {claim.submitted_by_role === 'station_master'
                              ? 'Quản trò nộp'
                              : 'Support nộp'}
                          </span>
                          <span className="text-[11px] text-evermyst-text-dim flex items-center gap-1">
                            <Clock className="w-3 h-3" />
                            {formatWaitTime(claim.created_at)}
                          </span>
                        </div>
                        <h2 className="text-base font-black text-evermyst-text mt-1">
                          {claim.team_name || 'Đội chơi'}
                        </h2>
                      </div>

                      <div className="text-right shrink-0">
                        <div className="text-[10px] font-bold text-evermyst-text-dim">
                          Điểm dự kiến
                        </div>
                        <div className="text-lg font-black text-success font-mono">
                          +{claim.computed_points}✦
                        </div>
                      </div>
                    </div>

                    {/* Badge Chìa Khóa nếu có */}
                    {claim.key_used && (
                      <div className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-xl bg-lumen/15 border border-lumen/40 text-xs font-black text-lumen">
                        <Key className="w-3.5 h-3.5" />
                        🗝️ ĐÃ DÙNG CHÌA KHÓA CỔ TÍCH
                      </div>
                    )}

                    {/* Input đã dịch sang nhãn tiếng Việt */}
                    <div className="p-3 rounded-2xl bg-evermyst-surface border border-evermyst-border/80 text-xs space-y-1">
                      <div className="text-[10px] font-bold text-evermyst-text-dim uppercase tracking-wider">
                        Kết quả nộp:
                      </div>
                      <div className="text-sm font-bold text-evermyst-text">
                        {formattedInput}
                      </div>
                    </div>

                    {/* BA NÚT LỚN (CHIỀU CAO TỐI THIỂU 52PX - THAO TÁC MỘT TAY) */}
                    <div className="space-y-2 pt-1">
                      {/* Nút 1: Xác nhận Legit (Lớn nhất, màu xanh chủ đạo) */}
                      <button
                        disabled={actionLoadingId === claimId}
                        onClick={() => handleApproveLegit(claim)}
                        className="w-full h-14 rounded-2xl bg-gradient-to-r from-success to-emerald-600 text-evermyst-bg text-sm font-black uppercase tracking-wide hover:opacity-95 active:scale-98 transition-all shadow-lg shadow-success/20 flex items-center justify-center gap-2"
                      >
                        <CheckCircle2 className="w-5 h-5" />
                        Xác Nhận Legit (+{claim.computed_points}✦)
                      </button>

                      {/* Hai nút phụ: Chỉnh & Từ chối */}
                      <div className="grid grid-cols-2 gap-2">
                        {/* Nút 2: Xác nhận kèm chỉnh */}
                        <button
                          disabled={actionLoadingId === claimId}
                          onClick={() => openEditModal(claim)}
                          className="h-13 rounded-2xl bg-amber-500/15 border border-amber-500/30 text-amber-400 text-xs font-black hover:bg-amber-500/25 active:scale-98 transition-all flex items-center justify-center gap-1.5"
                        >
                          <Edit3 className="w-4 h-4" />
                          Sửa Điểm
                        </button>

                        {/* Nút 3: Từ chối */}
                        <button
                          disabled={actionLoadingId === claimId}
                          onClick={() => openRejectModal(claim)}
                          className="h-13 rounded-2xl bg-danger/15 border border-danger/30 text-danger text-xs font-black hover:bg-danger/25 active:scale-98 transition-all flex items-center justify-center gap-1.5"
                        >
                          <XCircle className="w-4 h-4" />
                          Từ Chối
                        </button>
                      </div>
                    </div>
                  </div>
                );
              })}
            </div>
          )}
        </div>

        {/* MỤC "NHẬP ĐIỂM CHO ĐỘI" (COLLAPSIBLE HOẶC DIRECT) */}
        <div className="rounded-3xl bg-evermyst-card border border-evermyst-border overflow-hidden shadow-md">
          <button
            onClick={() => setShowManualEntry(!showManualEntry)}
            className="w-full p-4 flex items-center justify-between text-left hover:bg-evermyst-surface/40 transition-colors"
          >
            <div className="flex items-center gap-2.5">
              <div className="w-9 h-9 rounded-xl bg-primary/20 border border-primary/30 flex items-center justify-center text-primary">
                <PlusCircle className="w-5 h-5" />
              </div>
              <div>
                <div className="text-xs font-black text-evermyst-text">
                  Nhập Điểm Trực Tiếp Cho Đội
                </div>
                <div className="text-[11px] text-evermyst-text-dim">
                  Chấm điểm tại chỗ mà không cần Support gửi trước
                </div>
              </div>
            </div>
            {showManualEntry ? (
              <ChevronUp className="w-5 h-5 text-evermyst-text-dim" />
            ) : (
              <ChevronDown className="w-5 h-5 text-evermyst-text-dim" />
            )}
          </button>

          {showManualEntry && (
            <div className="p-4 pt-1 border-t border-evermyst-border/60 space-y-4 bg-evermyst-surface/20">
              {/* Chọn đội chơi */}
              <div>
                <label className="block text-[11px] font-bold text-evermyst-text-dim uppercase tracking-wider mb-1.5">
                  Chọn Đội Chơi Nhận Điểm
                </label>
                <select
                  value={manualTeamId}
                  onChange={(e) => setManualTeamId(e.target.value)}
                  className="w-full h-12 rounded-xl bg-evermyst-surface border border-evermyst-border px-3 text-xs font-bold text-evermyst-text focus:outline-none focus:border-lumen"
                >
                  {teamsList.map((team) => (
                    <option key={team.id} value={team.id} className="bg-evermyst-card text-white">
                      {team.name}
                    </option>
                  ))}
                </select>
              </div>

              {/* Renderer động chấm điểm */}
              <div className="pt-2">
                <label className="block text-[11px] font-bold text-evermyst-text-dim uppercase tracking-wider mb-2">
                  Cấu Hình Điểm Trạm
                </label>
                <StationScoringForm
                  scoringType={effectiveScoringType}
                  scoringConfig={effectiveScoringConfig}
                  minScore={stationInfo?.min_score ?? 0}
                  maxScore={stationInfo?.max_score ?? 100}
                  onChange={(input) => setManualInput(input)}
                />
              </div>

              {/* Thông báo kết quả */}
              {manualSuccessMsg && (
                <div className="p-3 rounded-xl bg-success/20 border border-success/40 text-success text-xs font-bold flex items-center gap-2">
                  <CheckCircle2 className="w-4 h-4 shrink-0" />
                  {manualSuccessMsg}
                </div>
              )}
              {manualErrorMsg && (
                <div className="p-3 rounded-xl bg-danger/20 border border-danger/40 text-danger text-xs font-bold flex items-center gap-2">
                  <AlertCircle className="w-4 h-4 shrink-0" />
                  {manualErrorMsg}
                </div>
              )}

              {/* Nút gửi điểm */}
              <button
                disabled={manualSubmitting || !manualTeamId}
                onClick={handleManualSubmit}
                className="w-full h-13 rounded-2xl bg-lumen text-evermyst-bg font-black text-xs uppercase tracking-wider hover:bg-lumen/90 active:scale-98 transition-all flex items-center justify-center gap-2 shadow-lg shadow-lumen/20"
              >
                {manualSubmitting ? (
                  <div className="w-5 h-5 border-2 border-evermyst-bg border-t-transparent rounded-full animate-spin" />
                ) : (
                  <>
                    <UserCheck className="w-4 h-4" />
                    Xác Nhận Nhập Điểm Cho Đội
                  </>
                )}
              </button>
            </div>
          )}
        </div>

        {/* DANH SÁCH CLAIM ĐÃ XỬ LÝ GẦN ĐÂY */}
        <div className="space-y-2.5 pt-2">
          <div className="text-xs font-black uppercase text-evermyst-text-dim tracking-wider flex items-center gap-1.5 px-1">
            <History className="w-3.5 h-3.5 text-evermyst-text-dim" />
            Lịch sử đã xử lý gần đây
          </div>

          {recentProcessed.length === 0 ? (
            <div className="p-4 rounded-2xl bg-evermyst-card/40 border border-evermyst-border text-center text-xs text-evermyst-text-dim">
              Chưa có claim nào được xử lý trong phiên làm việc này.
            </div>
          ) : (
            <div className="space-y-2">
              {recentProcessed.map((item: any, idx: number) => {
                const isApproved = item.status === 'approved';
                const isRejected = item.status === 'rejected';
                const isPendingAdmin = item.status === 'pending_admin';

                return (
                  <div
                    key={item.claim_id || idx}
                    className="p-3 rounded-2xl bg-evermyst-card border border-evermyst-border flex items-center justify-between text-xs"
                  >
                    <div>
                      <div className="font-bold text-evermyst-text">{item.team_name}</div>
                      <div className="text-[11px] text-evermyst-text-dim mt-0.5">
                        {isApproved && (
                          <span className="text-success font-semibold">Đã duyệt (+{item.final_points}✦)</span>
                        )}
                        {isRejected && (
                          <span className="text-danger font-semibold">
                            Đã từ chối {item.reject_reason ? `(${item.reject_reason})` : ''}
                          </span>
                        )}
                        {isPendingAdmin && (
                          <span className="text-amber-400 font-semibold">Đã chuyển BTC duyệt</span>
                        )}
                      </div>
                    </div>

                    <div className="text-[10px] text-evermyst-text-dim font-mono">
                      {item.updated_at ? formatWaitTime(item.updated_at) : ''}
                    </div>
                  </div>
                );
              })}
            </div>
          )}
        </div>
      </main>

      {/* MODAL DUYỆT KÈM CHỈNH (StationScoringForm có sẵn giá trị, bắt buộc ghi chú) */}
      {editModalClaim && (
        <div className="fixed inset-0 z-50 bg-black/80 backdrop-blur-sm flex items-center justify-center p-4 animate-fadeIn">
          <div className="bg-evermyst-card border border-evermyst-border rounded-3xl p-5 w-full max-w-md space-y-4 shadow-2xl max-h-[90vh] overflow-y-auto">
            <div className="flex items-center gap-2.5 text-amber-400">
              <Edit3 className="w-5 h-5 shrink-0" />
              <div>
                <h3 className="text-sm font-black text-evermyst-text">
                  Duyệt Kèm Chỉnh Sửa Kết Quả
                </h3>
                <p className="text-[11px] text-evermyst-text-dim">
                  Đội chơi: <strong className="text-white">{editModalClaim.team_name}</strong>
                </p>
              </div>
            </div>

            {/* Renderer chấm điểm động */}
            <div className="p-3 rounded-2xl bg-evermyst-surface border border-evermyst-border space-y-2">
              <div className="text-[11px] font-bold text-evermyst-text-dim uppercase tracking-wider">
                Điều chỉnh thông số chấm điểm
              </div>
              <StationScoringForm
                scoringType={
                  editModalClaim.scoring_snapshot?.scoring_type ||
                  stationInfo?.scoring_type ||
                  'tier'
                }
                scoringConfig={
                  editModalClaim.scoring_snapshot?.scoring_config ||
                  stationInfo?.scoring_config ||
                  {}
                }
                initialInput={editModalClaim.input}
                minScore={editModalClaim.scoring_snapshot?.min_score ?? 0}
                maxScore={editModalClaim.scoring_snapshot?.max_score ?? 100}
                onChange={(input) => setOverrideInput(input)}
              />
            </div>

            {/* Bắt buộc ghi chú lý do */}
            <div className="space-y-1.5">
              <label className="block text-[11px] font-black text-evermyst-text uppercase tracking-wider">
                Ghi chú điều chỉnh (Bắt buộc)
              </label>
              <textarea
                rows={2}
                value={overrideNote}
                onChange={(e) => {
                  setOverrideNote(e.target.value);
                  setOverrideError(null);
                }}
                placeholder="Lý do điều chỉnh (Ví dụ: Trừ 2 đơn vị vì vi phạm biên thời gian)..."
                className="w-full rounded-xl bg-evermyst-surface border border-evermyst-border p-3 text-xs text-evermyst-text focus:outline-none focus:border-amber-400 resize-none"
              />
              <p className="text-[10px] text-evermyst-text-dim">
                * Mọi chỉnh sửa sẽ chuyển claim sang BTC (Admin) đối soát trước khi ghi sổ điểm.
              </p>
            </div>

            {overrideError && (
              <div className="text-xs text-danger font-bold flex items-center gap-1.5 p-2 rounded-xl bg-danger/10 border border-danger/30">
                <AlertCircle className="w-4 h-4 shrink-0" />
                {overrideError}
              </div>
            )}

            <div className="grid grid-cols-2 gap-2 pt-2">
              <button
                onClick={() => setEditModalClaim(null)}
                className="h-12 rounded-xl bg-evermyst-surface border border-evermyst-border text-xs font-bold text-evermyst-text-dim hover:text-white"
              >
                Hủy Bỏ
              </button>
              <button
                disabled={actionLoadingId !== null}
                onClick={handleConfirmEditApprove}
                className="h-12 rounded-xl bg-amber-500 text-evermyst-bg text-xs font-black uppercase hover:bg-amber-400 transition-colors shadow-lg shadow-amber-500/20"
              >
                Lưu & Chuyển BTC
              </button>
            </div>
          </div>
        </div>
      )}

      {/* MODAL TỪ CHỐI (Bắt buộc lý do, kèm chip lý do nhanh) */}
      {rejectModalClaim && (
        <div className="fixed inset-0 z-50 bg-black/80 backdrop-blur-sm flex items-center justify-center p-4 animate-fadeIn">
          <div className="bg-evermyst-card border border-evermyst-border rounded-3xl p-5 w-full max-w-sm space-y-4 shadow-2xl">
            <div className="flex items-center gap-2 text-danger">
              <AlertCircle className="w-5 h-5 shrink-0" />
              <h3 className="text-sm font-black text-evermyst-text">Từ Chối Kết Quả Claim</h3>
            </div>

            <p className="text-xs text-evermyst-text-dim">
              Vui lòng cung cấp lý do từ chối kết quả của đội{' '}
              <strong className="text-white">{rejectModalClaim.team_name}</strong>:
            </p>

            {/* Chip lý do nhanh */}
            <div className="space-y-1.5">
              <div className="text-[10px] font-bold text-evermyst-text-dim uppercase tracking-wider">
                Chọn nhanh lý do:
              </div>
              <div className="flex flex-wrap gap-1.5">
                {QUICK_REJECT_REASONS.map((chip) => (
                  <button
                    key={chip}
                    type="button"
                    onClick={() => {
                      setRejectReason(chip);
                      setRejectError(null);
                    }}
                    className={`px-2.5 py-1 rounded-lg text-[11px] font-semibold border transition-all ${
                      rejectReason === chip
                        ? 'bg-danger text-white border-danger'
                        : 'bg-evermyst-surface text-evermyst-text-dim border-evermyst-border hover:border-danger/40'
                    }`}
                  >
                    {chip}
                  </button>
                ))}
              </div>
            </div>

            <textarea
              rows={3}
              value={rejectReason}
              onChange={(e) => {
                setRejectReason(e.target.value);
                setRejectError(null);
              }}
              placeholder="Nhập lý do chi tiết..."
              className="w-full rounded-xl bg-evermyst-surface border border-evermyst-border p-3 text-xs text-evermyst-text focus:outline-none focus:border-danger transition-colors resize-none"
            />

            {rejectError && (
              <div className="text-[11px] text-danger font-semibold flex items-center gap-1">
                <AlertCircle className="w-3.5 h-3.5 shrink-0" />
                {rejectError}
              </div>
            )}

            <div className="grid grid-cols-2 gap-2 pt-2">
              <button
                onClick={() => setRejectModalClaim(null)}
                className="h-12 rounded-xl bg-evermyst-surface border border-evermyst-border text-xs font-bold text-evermyst-text-muted hover:text-white"
              >
                Hủy Bỏ
              </button>

              <button
                disabled={actionLoadingId !== null}
                onClick={handleConfirmReject}
                className="h-12 rounded-xl bg-danger text-white text-xs font-black uppercase hover:bg-danger/90 transition-colors shadow-lg shadow-danger/25"
              >
                Xác Nhận Từ Chối
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
