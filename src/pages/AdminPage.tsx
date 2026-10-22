// ============================================================================
// ADMIN COMMAND CENTER (AdminPage.tsx)
// File: src/pages/AdminPage.tsx
// Bố cục 3 Cột Desktop theo Phase 7:
// Cột 1: Realtime Leaderboard & ± Lumen
// Cột 2: Bàn điều khiển 7 Tabs (Phê Duyệt, Đội, Trạm, Hint, Shop, Nhân Sự, Cài Đặt)
// Cột 3: Live Audit Log với Revert theo can_reverse & Force Revert qua modal riêng
// ============================================================================
import React, { useState, useEffect, useCallback, useMemo } from 'react';
import { useSession } from '@/contexts/SessionContext';
import { useGame } from '@/contexts/GameContext';
import { supabase } from '@/lib/supabase';
import { callRpc } from '@/lib/rpc';
import { useSignal } from '@/hooks/useSignal';
import { ConnectionIndicator } from '@/components/common/ConnectionIndicator';
import { PendingAdminQueue } from '@/components/admin/PendingAdminQueue';
import { StationEditorModal } from '@/components/admin/StationEditorModal';
import { HintEditorModal } from '@/components/admin/HintEditorModal';
import { ItemEditorModal } from '@/components/admin/ItemEditorModal';
import { StaffModal } from '@/components/admin/StaffModal';
import { AdjustBalanceModal } from '@/components/admin/AdjustBalanceModal';
import { ForceRevertModal } from '@/components/admin/ForceRevertModal';
import type { Team, Station, Hint, Item, Staff, Transaction, StationPlay } from '@/lib/types';
import {
  Shield,
  Trophy,
  Sliders,
  CheckCircle2,
  XCircle,
  Plus,
  RefreshCw,
  LogOut,
  MapPin,
  Package,
  History,
  RotateCcw,
  Users,
  KeyRound,
  HelpCircle,
  Eye,
  Smartphone,
  AlertTriangle,
  Flame,
  Key,
  ShieldAlert,
} from 'lucide-react';
import { formatTime, getShieldRemaining } from '@/lib/utils';

export default function AdminPage() {
  const { user, logout } = useSession();
  const {
    teams,
    stations,
    hints,
    items,
    transactions,
    refreshAll,
    isConnected,
    config,
  } = useGame();

  // Active Tab của Cột 2
  const [activeTab, setActiveTab] = useState<
    'approvals' | 'teams' | 'stations' | 'hints' | 'items' | 'staff' | 'settings'
  >('approvals');

  // Dữ liệu đối soát lượt chấm điểm trạm của Admin
  const [stationPlays, setStationPlays] = useState<StationPlay[]>([]);
  const [isLoadingPlays, setIsLoadingPlays] = useState(false);

  // Danh sách nhân sự
  const [staffList, setStaffList] = useState<Staff[]>([]);
  const [isLoadingStaff, setIsLoadingStaff] = useState(false);

  // Danh sách Audit Log
  const [auditLogs, setAuditLogs] = useState<any[]>([]);
  const [auditFilter, setAuditFilter] = useState<'all' | 'station' | 'shop' | 'pvp' | 'reversal'>('all');
  const [isLoadingAudit, setIsLoadingAudit] = useState(false);

  // Modals state
  const [editingStation, setEditingStation] = useState<Station | null | undefined>(undefined);
  const [editingHint, setEditingHint] = useState<Hint | null | undefined>(undefined);
  const [editingItem, setEditingItem] = useState<Item | null | undefined>(undefined);
  const [editingStaff, setEditingStaff] = useState<Staff | null | undefined>(undefined);
  const [adjustingTeam, setAdjustingTeam] = useState<Team | null>(null);
  const [forceRevertTx, setForceRevertTx] = useState<any | null>(null);

  // Cài đặt game draft
  const [settingsDraft, setSettingsDraft] = useState({
    pending_threshold: config?.pending_threshold ?? 50,
    undo_window_minutes: 5,
  });
  const [settingsSaving, setSettingsSaving] = useState(false);
  const [settingsMsg, setSettingsMsg] = useState<string | null>(null);

  // Tải danh sách lượt chấm điểm trạm từ bảng station_plays trên Supabase DB
  const fetchStationPlays = useCallback(async () => {
    setIsLoadingPlays(true);
    try {
      const { data, error } = await supabase
        .from('station_plays')
        .select('*')
        .order('created_at', { ascending: false })
        .limit(50);

      if (!error && data) {
        setStationPlays(data);
      }
    } catch (err) {
      console.error('Lỗi tải danh sách lượt chấm station_plays:', err);
    } finally {
      setIsLoadingPlays(false);
    }
  }, []);

  // Tải danh sách nhân sự
  const fetchStaffList = useCallback(async () => {
    setIsLoadingStaff(true);
    try {
      const res = await callRpc<{ success: boolean; staff: Staff[] }>('admin_list_staff', {});
      if (res.success && Array.isArray((res as any).staff)) {
        setStaffList((res as any).staff);
      }
    } catch (err) {
      console.error('Lỗi tải danh sách nhân sự:', err);
    } finally {
      setIsLoadingStaff(false);
    }
  }, []);

  // Tải danh sách Audit Log từ RPC hoặc fallback transactions
  const fetchAuditLogs = useCallback(async () => {
    setIsLoadingAudit(true);
    try {
      const res = await callRpc<{ success: boolean; audit_logs: any[] }>('admin_get_audit_log', {
        p_filter: auditFilter,
        p_limit: 80,
      });
      if (res.success && Array.isArray((res as any).audit_logs)) {
        setAuditLogs((res as any).audit_logs);
      }
    } catch (err) {
      console.error('Lỗi tải audit log:', err);
    } finally {
      setIsLoadingAudit(false);
    }
  }, [auditFilter]);

  // Làm giàu dữ liệu lượt chấm trạm bằng useMemo lúc render
  const enrichedStationPlays = useMemo(() => {
    return stationPlays.map((play: any) => ({
      ...play,
      team_name: play.team_name || teams.find((t) => t.id === play.team_id)?.name || 'Đội chơi',
      station_name: play.station_name || stations.find((s) => s.id === play.station_id)?.name || 'Trạm Thử Thách',
    }));
  }, [stationPlays, teams, stations]);

  // Bộ lọc giao dịch: Luôn đảm bảo đọc đủ mọi transaction từ PostgreSQL trên cả tab Ẩn Danh
  const displayTransactions = useMemo(() => {
    const rawList: any[] = auditLogs.length > 0 ? auditLogs : transactions;
    const enriched = rawList.map((tx: any) => ({
      ...tx,
      team_name: tx.team_name || teams.find((t: any) => t.id === tx.team_id)?.name || 'Đội chơi',
      can_reverse: !tx.is_reversed && tx.type !== 'reversal',
    }));

    if (auditFilter === 'all') return enriched;
    if (auditFilter === 'station') return enriched.filter((t: any) => t.type === 'station_clear');
    if (auditFilter === 'shop') return enriched.filter((t: any) => t.type === 'buy_item' || t.type === 'shop_item' || t.type === 'buy_hint' || t.type === 'hint_purchase');
    if (auditFilter === 'pvp') return enriched.filter((t: any) => t.type === 'pvp_steal' || t.type === 'pvp_backlash');
    if (auditFilter === 'reversal') return enriched.filter((t: any) => t.type === 'reversal' || t.is_reversed);
    return enriched;
  }, [auditLogs, transactions, teams, auditFilter]);

  // Đăng ký Realtime signals
  const { status: claimSignalStatus, refetchNow: refetchClaims } = useSignal(
    'station_claims_changed',
    fetchStationPlays
  );
  const { refetchNow: refetchLedger } = useSignal('transactions_changed', () => {
    fetchAuditLogs();
    fetchStationPlays();
    refreshAll();
  });
  const { refetchNow: refetchTeamsSignal } = useSignal('teams_changed', refreshAll);

  useEffect(() => {
    fetchStationPlays();
    fetchStaffList();
    fetchAuditLogs();
  }, [fetchStationPlays, fetchStaffList, fetchAuditLogs]);

  // Hoàn tác tiêu chuẩn (standard revert)
  const handleStandardRevert = async (txId: string) => {
    if (!confirm('Xác nhận hoàn tác giao dịch này theo luồng chuẩn?')) return;
    try {
      const res = await callRpc('reverse_transaction', {
        p_tx_id: txId,
        p_force: false,
      });

      if (res.success) {
        alert('Đã hoàn tác giao dịch thành công!');
        fetchAuditLogs();
        refreshAll();
      } else {
        alert(res.error || res.message || 'Không thể hoàn tác.');
      }
    } catch (err: any) {
      alert(err.message || 'Lỗi hệ thống khi hoàn tác.');
    }
  };

  // Thu hồi phiên nhân sự
  const handleRevokeStaffSessions = async (staffId: string, staffName: string) => {
    if (!confirm(`Bạn có chắc chắn muốn đăng xuất cưỡng chế toàn bộ phiên của nhân viên ${staffName}?`)) {
      return;
    }
    try {
      const res = await callRpc('admin_revoke_sessions', {
        p_staff_id: staffId,
      });

      if (res.success) {
        alert(`Đã thu hồi thành công ${res.revoked_count ?? 1} phiên làm việc của ${staffName}!`);
      } else {
        alert(res.error || res.message || 'Không thể thu hồi phiên.');
      }
    } catch (err: any) {
      alert(err.message || 'Lỗi khi thu hồi phiên.');
    }
  };

  // Lưu cài đặt game
  const handleSaveSettings = async (e: React.FormEvent) => {
    e.preventDefault();
    setSettingsSaving(true);
    setSettingsMsg(null);
    try {
      const res = await callRpc('admin_update_game_settings', {
        p_settings: settingsDraft,
      });

      if (res.success) {
        setSettingsMsg('Đã lưu thành công cài đặt game!');
        setTimeout(() => setSettingsMsg(null), 3500);
      } else {
        setSettingsMsg(res.error || res.message || 'Lỗi khi lưu cài đặt.');
      }
    } catch (err: any) {
      setSettingsMsg(err.message || 'Lỗi kết nối.');
    } finally {
      setSettingsSaving(false);
    }
  };

  // Tính tổng Lumen lưu thông
  const totalLumenCirculation = useMemo(() => {
    return teams.reduce((sum, t) => sum + (t.light_balance || 0), 0);
  }, [teams]);

  return (
    <div className="min-h-screen bg-evermyst-bg text-evermyst-text flex flex-col select-none overflow-hidden font-sans">
      {/* ===================================================================== */}
      {/* TOP COMMAND NAVBAR */}
      {/* ===================================================================== */}
      <header className="h-14 bg-evermyst-surface border-b border-evermyst-border px-4 flex items-center justify-between shrink-0 z-30 shadow-md">
        <div className="flex items-center gap-3">
          <div className="w-9 h-9 rounded-xl bg-gradient-to-br from-lumen to-lumen-dark flex items-center justify-center text-evermyst-bg shadow-md">
            <Shield className="w-5 h-5" />
          </div>
          <div>
            <div className="flex items-center gap-2">
              <span className="text-base font-black tracking-wider uppercase">EVERMYST</span>
              <span className="px-2 py-0.5 rounded-full bg-lumen/20 text-lumen text-[10px] font-black tracking-widest border border-lumen/40">
                ADMIN CONSOLE
              </span>
              <ConnectionIndicator status={claimSignalStatus} onRefresh={refetchClaims} compact />
            </div>
            <div className="text-[10px] text-evermyst-text-dim">Ban Chỉ Huy & Kiểm Toán Toàn Diện</div>
          </div>
        </div>

        {/* Global Stats & Connection */}
        <div className="flex items-center gap-3">
          <div className="hidden lg:flex items-center gap-3 text-xs font-mono">
            <div className="px-3 py-1 rounded-xl bg-evermyst-card border border-evermyst-border">
              <span className="text-evermyst-text-dim">Tổng Lưu Thông: </span>
              <span className="text-lumen font-bold">{totalLumenCirculation}✦</span>
            </div>
            <div className="px-3 py-1 rounded-xl bg-evermyst-card border border-evermyst-border">
              <span className="text-evermyst-text-dim">Đội Chơi: </span>
              <span className="text-evermyst-text font-bold">{teams.length}</span>
            </div>
          </div>

          <button
            onClick={() => {
              refreshAll();
              fetchStationPlays();
              fetchAuditLogs();
            }}
            className="p-2 rounded-xl bg-evermyst-card border border-evermyst-border text-evermyst-text-dim hover:text-lumen transition-colors"
            title="Đồng bộ snapshot toàn cục"
          >
            <RefreshCw className="w-4 h-4" />
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

      {/* ===================================================================== */}
      {/* 3-COLUMN DESKTOP LAYOUT */}
      {/* ===================================================================== */}
      <div className="flex-1 grid grid-cols-12 gap-0 overflow-hidden">
        {/* =================================================================== */}
        {/* CỘT 1 (3/12 - 25%): REALTIME LEADERBOARD & ± LUMEN */}
        {/* =================================================================== */}
        <aside className="col-span-12 md:col-span-3 bg-evermyst-surface/60 border-r border-evermyst-border flex flex-col overflow-hidden">
          <div className="p-3.5 border-b border-evermyst-border flex items-center justify-between">
            <div className="flex items-center gap-2">
              <Trophy className="w-4 h-4 text-lumen" />
              <h2 className="text-xs font-black uppercase tracking-wider text-evermyst-text">
                Bảng Xếp Hạng Trực Tiếp
              </h2>
            </div>
            <span className="text-[10px] text-evermyst-text-dim font-mono">
              {teams.length} Đội
            </span>
          </div>

          <div className="flex-1 overflow-y-auto p-3 space-y-2.5">
            {teams.map((team, idx) => {
              const shield = getShieldRemaining(team.shield_until);
              const stationsCount = team.unlocked_stations?.length || 0;
              const totalStations = stations.length || 5;

              return (
                <div
                  key={team.id}
                  className={`p-3 rounded-2xl border transition-all ${
                    idx === 0
                      ? 'bg-gradient-to-r from-lumen/15 via-evermyst-card to-evermyst-card border-lumen/50 shadow-md shadow-lumen/5'
                      : idx === 1
                      ? 'bg-evermyst-card border-slate-400/30'
                      : idx === 2
                      ? 'bg-evermyst-card border-amber-700/30'
                      : 'bg-evermyst-card/60 border-evermyst-border'
                  }`}
                >
                  <div className="flex items-center justify-between gap-2">
                    <div className="flex items-center gap-2.5 truncate">
                      <div
                        className={`w-7 h-7 rounded-lg flex items-center justify-center font-black text-xs shrink-0 ${
                          idx === 0
                            ? 'bg-lumen text-evermyst-bg font-extrabold'
                            : idx === 1
                            ? 'bg-slate-300 text-evermyst-bg'
                            : idx === 2
                            ? 'bg-amber-600 text-white'
                            : 'bg-evermyst-surface text-evermyst-text-dim border border-evermyst-border'
                        }`}
                      >
                        {idx + 1}
                      </div>
                      <div className="truncate">
                        <div className="text-sm font-bold text-evermyst-text truncate">
                          {team.name}
                        </div>
                        <div className="text-[10px] text-evermyst-text-dim">
                          Trạm: {stationsCount}/{totalStations} đã vượt
                        </div>
                      </div>
                    </div>

                    <div className="text-right shrink-0 flex items-center gap-2">
                      <div className="text-base font-black font-mono text-lumen">
                        {team.light_balance}✦
                      </div>

                      {/* NÚT ± LUMEN (BẮT BUỘC NHẬP LÝ DO) */}
                      <button
                        onClick={() => setAdjustingTeam(team)}
                        title="Cộng/Trừ Lumen thủ công"
                        className="px-2 py-1 rounded-lg bg-lumen/15 hover:bg-lumen/25 text-lumen border border-lumen/30 text-[11px] font-black transition-all"
                      >
                        ±✦
                      </button>
                    </div>
                  </div>

                  {/* Shield Status Badge */}
                  {shield.active && (
                    <div className="mt-2 pt-1.5 border-t border-props/20 flex items-center justify-between text-[11px] text-props font-semibold">
                      <span className="flex items-center gap-1">
                        <Shield className="w-3 h-3" /> Khiên bảo vệ
                      </span>
                      <span className="font-mono text-props-light">
                        {shield.label.replace('🛡️ Khiên: ', '')}
                      </span>
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        </aside>

        {/* =================================================================== */}
        {/* CỘT 2 (5/12 - 42%): BÀN ĐIỀU KHIỂN 7 TABS */}
        {/* =================================================================== */}
        <main className="col-span-12 md:col-span-5 flex flex-col border-r border-evermyst-border bg-evermyst-bg overflow-hidden">
          {/* Navigation 7 Tabs */}
          <div className="flex bg-evermyst-surface border-b border-evermyst-border overflow-x-auto text-xs shrink-0 scrollbar-none">
            <button
              onClick={() => setActiveTab('approvals')}
              className={`px-3 py-3 font-bold border-b-2 flex items-center gap-1.5 whitespace-nowrap transition-all ${
                activeTab === 'approvals'
                  ? 'border-lumen text-lumen bg-lumen/5'
                  : 'border-transparent text-evermyst-text-muted hover:text-white'
              }`}
            >
              <CheckCircle2 className="w-3.5 h-3.5" />
              Đối Soát Trạm
              {stationPlays.filter((p) => p.status === 'active').length > 0 && (
                <span className="px-1.5 py-0.2 rounded-full bg-lumen text-evermyst-bg text-[10px] font-black">
                  {stationPlays.filter((p) => p.status === 'active').length}
                </span>
              )}
            </button>

            <button
              onClick={() => setActiveTab('stations')}
              className={`px-3 py-3 font-bold border-b-2 flex items-center gap-1.5 whitespace-nowrap transition-all ${
                activeTab === 'stations'
                  ? 'border-lumen text-lumen bg-lumen/5'
                  : 'border-transparent text-evermyst-text-muted hover:text-white'
              }`}
            >
              <MapPin className="w-3.5 h-3.5" />
              Trạm ({stations.length})
            </button>

            <button
              onClick={() => setActiveTab('hints')}
              className={`px-3 py-3 font-bold border-b-2 flex items-center gap-1.5 whitespace-nowrap transition-all ${
                activeTab === 'hints'
                  ? 'border-lumen text-lumen bg-lumen/5'
                  : 'border-transparent text-evermyst-text-muted hover:text-white'
              }`}
            >
              <HelpCircle className="w-3.5 h-3.5" />
              Hint ({hints.length})
            </button>

            <button
              onClick={() => setActiveTab('items')}
              className={`px-3 py-3 font-bold border-b-2 flex items-center gap-1.5 whitespace-nowrap transition-all ${
                activeTab === 'items'
                  ? 'border-lumen text-lumen bg-lumen/5'
                  : 'border-transparent text-evermyst-text-muted hover:text-white'
              }`}
            >
              <Package className="w-3.5 h-3.5" />
              Đạo Cụ ({items.length})
            </button>

            <button
              onClick={() => setActiveTab('staff')}
              className={`px-3 py-3 font-bold border-b-2 flex items-center gap-1.5 whitespace-nowrap transition-all ${
                activeTab === 'staff'
                  ? 'border-lumen text-lumen bg-lumen/5'
                  : 'border-transparent text-evermyst-text-muted hover:text-white'
              }`}
            >
              <Users className="w-3.5 h-3.5" />
              Nhân Sự
            </button>

            <button
              onClick={() => setActiveTab('teams')}
              className={`px-3 py-3 font-bold border-b-2 flex items-center gap-1.5 whitespace-nowrap transition-all ${
                activeTab === 'teams'
                  ? 'border-lumen text-lumen bg-lumen/5'
                  : 'border-transparent text-evermyst-text-muted hover:text-white'
              }`}
            >
              <Flame className="w-3.5 h-3.5" />
              Đội Chơi
            </button>

            <button
              onClick={() => setActiveTab('settings')}
              className={`px-3 py-3 font-bold border-b-2 flex items-center gap-1.5 whitespace-nowrap transition-all ${
                activeTab === 'settings'
                  ? 'border-lumen text-lumen bg-lumen/5'
                  : 'border-transparent text-evermyst-text-muted hover:text-white'
              }`}
            >
              <Sliders className="w-3.5 h-3.5" />
              Cài Đặt
            </button>
          </div>

          {/* Console Content */}
          <div className="flex-1 overflow-y-auto p-4 space-y-4">
            {/* ------------------------------------------------------------- */}
            {/* TAB 1: ĐỐI SOÁT LƯỢT CHẤM ĐIỂM TRẠM GẦN NHẤT */}
            {/* ------------------------------------------------------------- */}
            {activeTab === 'approvals' && (
              <div className="space-y-3">
                <div className="flex items-center justify-between">
                  <h3 className="text-xs font-bold text-evermyst-text-muted uppercase tracking-wider">
                    Đối Soát Lượt Chấm Điểm Trạm Gần Nhất ({stationPlays.length})
                  </h3>
                  <button
                    onClick={() => {
                      fetchStationPlays();
                      refreshAll();
                    }}
                    className="text-xs text-lumen font-bold hover:underline"
                  >
                    Làm mới
                  </button>
                </div>

                <PendingAdminQueue
                  plays={enrichedStationPlays}
                  onRefresh={() => {
                    fetchStationPlays();
                    refreshAll();
                  }}
                />
              </div>
            )}

            {/* ------------------------------------------------------------- */}
            {/* TAB 2: TRẠM THỬ THÁCH (STATION EDITOR) */}
            {/* ------------------------------------------------------------- */}
            {activeTab === 'stations' && (
              <div className="space-y-3">
                <div className="flex items-center justify-between">
                  <h3 className="text-xs font-bold text-evermyst-text-muted uppercase tracking-wider">
                    Danh Sách Trạm & Cấu Hình Luật Chấm Điểm
                  </h3>
                  <button
                    onClick={() => setEditingStation(null)}
                    className="h-8 px-2.5 rounded-xl bg-lumen text-evermyst-bg text-xs font-black flex items-center gap-1 hover:bg-lumen/90 transition-all shadow-sm"
                  >
                    <Plus className="w-3.5 h-3.5" /> Thêm Trạm
                  </button>
                </div>

                <div className="space-y-2.5">
                  {stations.map((st) => (
                    <div
                      key={st.id}
                      className="p-3.5 rounded-2xl bg-evermyst-card border border-evermyst-border flex items-center justify-between gap-3 hover:border-lumen/30 transition-all"
                    >
                      <div>
                        <div className="flex items-center gap-2">
                          <span className="font-mono text-xs font-bold text-lumen">
                            #{st.order_index}
                          </span>
                          <span className="text-sm font-black text-evermyst-text">{st.name}</span>
                          <span className="text-[10px] px-2 py-0.5 rounded-full bg-evermyst-surface border border-evermyst-border text-evermyst-text-dim font-bold uppercase">
                            {st.scoring_type}
                          </span>
                        </div>
                        <div className="text-[11px] text-evermyst-text-dim mt-0.5">
                          Hạn mức: {st.min_score}✦ ~ {st.max_score}✦ •{' '}
                          {st.allow_multiple_attempts ? 'Thi lại: Có' : 'Thi lại: 1 lần'} •{' '}
                          {st.is_active ? (
                            <span className="text-success font-semibold">Đang mở</span>
                          ) : (
                            <span className="text-danger font-semibold">Đã đóng</span>
                          )}
                        </div>
                      </div>

                      <button
                        onClick={() => setEditingStation(st)}
                        className="px-3 py-1.5 rounded-xl bg-evermyst-surface hover:bg-evermyst-card border border-evermyst-border text-xs font-bold text-white transition-colors"
                      >
                        Sửa Luật
                      </button>
                    </div>
                  ))}
                </div>
              </div>
            )}

            {/* ------------------------------------------------------------- */}
            {/* TAB 3: MANH MỐI MẬT (HINTS) */}
            {/* ------------------------------------------------------------- */}
            {activeTab === 'hints' && (
              <div className="space-y-3">
                <div className="flex items-center justify-between">
                  <h3 className="text-xs font-bold text-evermyst-text-muted uppercase tracking-wider">
                    Kho Manh Mối Mật Trong Trận
                  </h3>
                  <button
                    onClick={() => setEditingHint(null)}
                    className="h-8 px-2.5 rounded-xl bg-lumen text-evermyst-bg text-xs font-black flex items-center gap-1 hover:bg-lumen/90 transition-all shadow-sm"
                  >
                    <Plus className="w-3.5 h-3.5" /> Thêm Manh Mối
                  </button>
                </div>

                <div className="space-y-2.5">
                  {hints.map((h) => (
                    <div
                      key={h.id}
                      className="p-3.5 rounded-2xl bg-evermyst-card border border-evermyst-border flex items-center justify-between gap-3"
                    >
                      <div>
                        <div className="flex items-center gap-2">
                          <span className="text-xs font-bold text-white">{h.title}</span>
                          <span className="text-[10px] px-2 py-0.5 rounded bg-amber-500/15 text-amber-400 font-bold uppercase">
                            {h.tier}
                          </span>
                        </div>
                        <div className="text-[11px] text-evermyst-text-dim mt-0.5 font-mono">
                          Giá bán: <span className="text-lumen font-bold">{h.price}✦</span> •{' '}
                          {h.station_id
                            ? `Gắn trạm: ${stations.find((s) => s.id === h.station_id)?.name || 'Trạm'}`
                            : 'Manh mối chung'}
                        </div>
                      </div>

                      <button
                        onClick={() => setEditingHint(h)}
                        className="px-3 py-1.5 rounded-xl bg-evermyst-surface hover:bg-evermyst-card border border-evermyst-border text-xs font-bold text-white"
                      >
                        Sửa
                      </button>
                    </div>
                  ))}
                </div>
              </div>
            )}

            {/* ------------------------------------------------------------- */}
            {/* TAB 4: ĐẠO CỤ SHOP (ITEMS) */}
            {/* ------------------------------------------------------------- */}
            {activeTab === 'items' && (
              <div className="space-y-3">
                <div className="flex items-center justify-between">
                  <h3 className="text-xs font-bold text-evermyst-text-muted uppercase tracking-wider">
                    Vật Phẩm Phép Thuật Trong Shop
                  </h3>
                  <button
                    onClick={() => setEditingItem(null)}
                    className="h-8 px-2.5 rounded-xl bg-lumen text-evermyst-bg text-xs font-black flex items-center gap-1 hover:bg-lumen/90 transition-all shadow-sm"
                  >
                    <Plus className="w-3.5 h-3.5" /> Thêm Đạo Cụ
                  </button>
                </div>

                <div className="space-y-2.5">
                  {items.map((item) => (
                    <div
                      key={item.id}
                      className="p-3.5 rounded-2xl bg-evermyst-card border border-evermyst-border flex items-center justify-between gap-3"
                    >
                      <div>
                        <div className="flex items-center gap-2">
                          <span className="text-xs font-bold text-white">{item.name}</span>
                          <span className="text-[10px] px-2 py-0.5 rounded bg-lumen/15 text-lumen font-bold uppercase">
                            {item.effect_type}
                          </span>
                        </div>
                        <div className="text-[11px] text-evermyst-text-dim mt-0.5 font-mono">
                          Giá: <span className="text-lumen font-bold">{item.price}✦</span> •{' '}
                          {item.effect_type === 'shield'
                            ? `Thời lượng: ${item.duration_minutes || 15} phút`
                            : item.description}
                        </div>
                      </div>

                      <button
                        onClick={() => setEditingItem(item)}
                        className="px-3 py-1.5 rounded-xl bg-evermyst-surface hover:bg-evermyst-card border border-evermyst-border text-xs font-bold text-white"
                      >
                        Sửa
                      </button>
                    </div>
                  ))}
                </div>
              </div>
            )}

            {/* ------------------------------------------------------------- */}
            {/* TAB 5: NHÂN SỰ & PHÂN CÔNG (STAFF) */}
            {/* ------------------------------------------------------------- */}
            {activeTab === 'staff' && (
              <div className="space-y-3">
                <div className="flex items-center justify-between">
                  <h3 className="text-xs font-bold text-evermyst-text-muted uppercase tracking-wider">
                    Danh Sách Nhân Sự & Phân Quyền ({staffList.length})
                  </h3>
                  <button
                    onClick={() => setEditingStaff(null)}
                    className="h-8 px-2.5 rounded-xl bg-lumen text-evermyst-bg text-xs font-black flex items-center gap-1 hover:bg-lumen/90 transition-all shadow-sm"
                  >
                    <Plus className="w-3.5 h-3.5" /> Thêm Nhân Sự
                  </button>
                </div>

                <div className="space-y-2.5">
                  {staffList.map((st) => {
                    const assignedTeam = teams.find((t) => t.id === st.assigned_team_id);
                    const assignedStation = stations.find((s) => s.id === st.assigned_station_id);

                    return (
                      <div
                        key={st.id}
                        className="p-3.5 rounded-2xl bg-evermyst-card border border-evermyst-border flex items-center justify-between gap-3"
                      >
                        <div>
                          <div className="flex items-center gap-2">
                            <span className="text-xs font-black text-white">{st.name}</span>
                            <span className="text-[10px] px-2 py-0.5 rounded-md bg-evermyst-surface border border-evermyst-border font-bold uppercase text-evermyst-text-dim">
                              {st.role}
                            </span>
                          </div>
                          <div className="text-[11px] text-evermyst-text-dim mt-0.5">
                            {st.role === 'team_support' && (
                              <span>Đội gán: <strong className="text-lumen">{assignedTeam?.name || 'Chưa gán'}</strong></span>
                            )}
                            {st.role === 'station_master' && (
                              <span>Trạm gán: <strong className="text-lumen">{assignedStation?.name || 'Chưa gán'}</strong></span>
                            )}
                            {st.role === 'admin' && <span className="text-props">Toàn quyền hệ thống</span>}
                            {' • '}
                            {st.is_active ? (
                              <span className="text-success font-semibold">Active</span>
                            ) : (
                              <span className="text-danger font-semibold">Disabled</span>
                            )}
                          </div>
                        </div>

                        <div className="flex items-center gap-1.5">
                          <button
                            onClick={() => handleRevokeStaffSessions(st.id, st.name)}
                            title="Đăng xuất cưỡng chế toàn bộ phiên"
                            className="p-1.5 rounded-lg bg-danger/10 hover:bg-danger/20 text-danger border border-danger/30 text-xs"
                          >
                            <LogOut className="w-3.5 h-3.5" />
                          </button>
                          <button
                            onClick={() => setEditingStaff(st)}
                            className="px-3 py-1.5 rounded-xl bg-evermyst-surface hover:bg-evermyst-card border border-evermyst-border text-xs font-bold text-white"
                          >
                            Sửa / Đổi PIN
                          </button>
                        </div>
                      </div>
                    );
                  })}
                </div>
              </div>
            )}

            {/* ------------------------------------------------------------- */}
            {/* TAB 6: ĐỘI CHƠI (TEAMS) */}
            {/* ------------------------------------------------------------- */}
            {activeTab === 'teams' && (
              <div className="space-y-3">
                <div className="flex items-center justify-between">
                  <h3 className="text-xs font-bold text-evermyst-text-muted uppercase tracking-wider">
                    Quản Lý Danh Sách Đội Chơi ({teams.length})
                  </h3>
                </div>

                <div className="space-y-2.5">
                  {teams.map((team) => (
                    <div
                      key={team.id}
                      className="p-3.5 rounded-2xl bg-evermyst-card border border-evermyst-border flex items-center justify-between gap-3"
                    >
                      <div>
                        <div className="text-sm font-bold text-white">{team.name}</div>
                        <div className="text-[11px] text-evermyst-text-dim font-mono">
                          Mã QR: {team.qr_code} • Số dư: <span className="text-lumen font-bold">{team.light_balance}✦</span>
                        </div>
                      </div>

                      <button
                        onClick={() => setAdjustingTeam(team)}
                        className="px-3 py-1.5 rounded-xl bg-lumen/15 hover:bg-lumen/25 text-lumen border border-lumen/30 text-xs font-bold flex items-center gap-1"
                      >
                        ± Lumen
                      </button>
                    </div>
                  ))}
                </div>
              </div>
            )}

            {/* ------------------------------------------------------------- */}
            {/* TAB 7: CÀI ĐẶT GAME (SETTINGS) */}
            {/* ------------------------------------------------------------- */}
            {activeTab === 'settings' && (
              <form onSubmit={handleSaveSettings} className="space-y-4">
                <div className="flex items-center justify-between">
                  <h3 className="text-xs font-bold text-evermyst-text-muted uppercase tracking-wider">
                    Thông Số Cấu Hình Game
                  </h3>
                </div>

                <div className="p-4 rounded-2xl bg-evermyst-card border border-evermyst-border space-y-3 text-xs">
                  <div className="space-y-1">
                    <label className="block text-[11px] font-bold text-evermyst-text-dim uppercase tracking-wider">
                      Ngưỡng Điểm Bắt Buộc Admin Phê Duyệt (Pending Threshold)
                    </label>
                    <input
                      type="number"
                      value={settingsDraft.pending_threshold}
                      onChange={(e) =>
                        setSettingsDraft({
                          ...settingsDraft,
                          pending_threshold: parseInt(e.target.value) || 50,
                        })
                      }
                      className="w-full h-10 rounded-xl bg-evermyst-surface border border-evermyst-border px-3 font-mono font-bold text-evermyst-text"
                    />
                    <p className="text-[10px] text-evermyst-text-dim">
                      * Bất kỳ điểm claim trạm nào vượt quá ngưỡng này sẽ tự động chuyển sang trạng thái pending_admin.
                    </p>
                  </div>

                  <div className="space-y-1 pt-2 border-t border-evermyst-border">
                    <label className="block text-[11px] font-bold text-evermyst-text-dim uppercase tracking-wider">
                      Thời Hạn Hoàn Tác Tiêu Chuẩn (Undo Window - Phút)
                    </label>
                    <input
                      type="number"
                      value={settingsDraft.undo_window_minutes}
                      onChange={(e) =>
                        setSettingsDraft({
                          ...settingsDraft,
                          undo_window_minutes: parseInt(e.target.value) || 5,
                        })
                      }
                      className="w-full h-10 rounded-xl bg-evermyst-surface border border-evermyst-border px-3 font-mono font-bold text-evermyst-text"
                    />
                    <p className="text-[10px] text-evermyst-text-dim">
                      * Support chỉ được hoàn tác trong khoảng thời gian này sau khi tạo giao dịch.
                    </p>
                  </div>

                  {settingsMsg && (
                    <div className="p-3 rounded-xl bg-success/20 border border-success/40 text-success font-bold text-xs">
                      {settingsMsg}
                    </div>
                  )}

                  <button
                    type="submit"
                    disabled={settingsSaving}
                    className="w-full h-11 rounded-xl bg-lumen text-evermyst-bg font-black uppercase text-xs hover:bg-lumen/90 transition-all shadow-md shadow-lumen/20"
                  >
                    {settingsSaving ? 'Đang lưu...' : 'Lưu Thay Đổi Cài Đặt'}
                  </button>
                </div>
              </form>
            )}
          </div>
        </main>

        {/* =================================================================== */}
        {/* CỘT 3 (4/12 - 33%): LIVE AUDIT LOG & REVERT THEO CAN_REVERSE */}
        {/* =================================================================== */}
        <section className="col-span-12 md:col-span-4 bg-evermyst-surface/40 flex flex-col overflow-hidden">
          {/* Header & Filter */}
          <div className="p-3.5 border-b border-evermyst-border space-y-2.5 shrink-0">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2">
                <History className="w-4 h-4 text-lumen" />
                <h2 className="text-xs font-black uppercase tracking-wider text-evermyst-text">
                  Nhật Ký Giao Dịch & Sổ Cái
                </h2>
              </div>
              <button
                onClick={fetchAuditLogs}
                className="text-[11px] text-lumen font-bold hover:underline"
              >
                Làm mới
              </button>
            </div>

            {/* Filter Buttons */}
            <div className="flex items-center gap-1 overflow-x-auto text-[11px] font-bold scrollbar-none">
              {(['all', 'station', 'shop', 'pvp', 'reversal'] as const).map((filter) => (
                <button
                  key={filter}
                  onClick={() => setAuditFilter(filter)}
                  className={`px-2.5 py-1 rounded-lg border transition-all ${
                    auditFilter === filter
                      ? 'bg-lumen text-evermyst-bg border-lumen'
                      : 'bg-evermyst-card text-evermyst-text-dim border-evermyst-border hover:text-white'
                  }`}
                >
                  {filter === 'all' && 'Tất cả'}
                  {filter === 'station' && 'Trạm'}
                  {filter === 'shop' && 'Shop'}
                  {filter === 'pvp' && 'PvP'}
                  {filter === 'reversal' && 'Hoàn tác'}
                </button>
              ))}
            </div>
          </div>

          {/* Audit Logs List */}
          <div className="flex-1 overflow-y-auto p-3 space-y-2.5">
            {isLoadingAudit && displayTransactions.length === 0 ? (
              <div className="py-12 text-center space-y-2">
                <div className="w-6 h-6 border-2 border-lumen border-t-transparent rounded-full animate-spin mx-auto" />
                <p className="text-xs text-evermyst-text-dim">Đang tải sổ cái...</p>
              </div>
            ) : displayTransactions.length === 0 ? (
              <div className="py-12 text-center text-xs text-evermyst-text-dim">
                Không tìm thấy giao dịch nào phù hợp bộ lọc.
              </div>
            ) : (
              displayTransactions.map((tx: any) => {
                const canReverse = tx.can_reverse === true;
                const isReversal = tx.type === 'reversal';

                return (
                  <div
                    key={tx.id}
                    className={`p-3 rounded-2xl border text-xs space-y-2 ${
                      isReversal
                        ? 'bg-purple-950/20 border-purple-800/40'
                        : tx.is_reversed
                        ? 'bg-evermyst-card/30 border-evermyst-border opacity-70'
                        : 'bg-evermyst-card border-evermyst-border'
                    }`}
                  >
                    <div className="flex items-start justify-between gap-2">
                      <div>
                        <div className="flex items-center gap-1.5">
                          <span className="font-bold text-white">{tx.team_name}</span>
                          <span className="text-[10px] px-1.5 py-0.5 rounded bg-evermyst-surface border border-evermyst-border text-evermyst-text-dim font-mono">
                            {tx.type}
                          </span>
                        </div>
                        <p className="text-[11px] text-evermyst-text-muted mt-0.5 line-clamp-1">
                          {tx.description}
                        </p>
                      </div>

                      <div className="text-right shrink-0">
                        <span
                          className={`font-mono font-black text-sm ${
                            tx.amount > 0 ? 'text-success' : 'text-danger'
                          }`}
                        >
                          {tx.amount > 0 ? `+${tx.amount}` : tx.amount}✦
                        </span>
                        <div className="text-[10px] text-evermyst-text-dim font-mono">
                          {formatTime(tx.created_at)}
                        </div>
                      </div>
                    </div>

                    {/* VÙNG NÚT HOÀN TÁC THEO CAN_REVERSE HOẶC FORCE REVERT */}
                    <div className="pt-2 border-t border-evermyst-border/50 flex items-center justify-between">
                      {canReverse ? (
                        <button
                          onClick={() => handleStandardRevert(tx.id)}
                          className="h-8 px-2.5 rounded-lg bg-amber-500/15 hover:bg-amber-500/25 text-amber-400 border border-amber-500/30 font-bold text-[11px] flex items-center gap-1 transition-all"
                        >
                          <RotateCcw className="w-3.5 h-3.5" /> Hoàn Tác Tiêu Chuẩn
                        </button>
                      ) : (
                        <div className="flex items-center gap-1.5">
                          <span className="text-[10px] text-evermyst-text-dim italic">
                            {tx.reverse_blocked_reason || 'Không hỗ trợ hoàn tác tiêu chuẩn'}
                          </span>
                          {!tx.is_reversed && !isReversal && (
                            <button
                              onClick={() => setForceRevertTx(tx)}
                              title="Ép buộc hoàn tác (vượt hạn mức 5 phút)"
                              className="h-7 px-2 rounded-lg bg-danger/15 hover:bg-danger/25 text-danger border border-danger/30 font-bold text-[10px] flex items-center gap-1 transition-all"
                            >
                              <ShieldAlert className="w-3 h-3" /> Force
                            </button>
                          )}
                        </div>
                      )}

                      <span className="text-[10px] text-evermyst-text-dim font-mono">
                        Bởi: {tx.created_by || tx.actor_role || 'System'}
                      </span>
                    </div>
                  </div>
                );
              })
            )}
          </div>
        </section>
      </div>

      {/* ===================================================================== */}
      {/* MODALS PHÂN QUYỀN & CHỈNH SỬA */}
      {/* ===================================================================== */}
      {/* 1. Modal Chỉnh Sửa Trạm */}
      {editingStation !== undefined && (
        <StationEditorModal
          station={editingStation}
          onClose={() => setEditingStation(undefined)}
          onSuccess={() => {
            refreshAll();
          }}
        />
      )}

      {/* 2. Modal Chỉnh Sửa Manh Mối */}
      {editingHint !== undefined && (
        <HintEditorModal
          hint={editingHint}
          stations={stations}
          onClose={() => setEditingHint(undefined)}
          onSuccess={() => {
            refreshAll();
          }}
        />
      )}

      {/* 3. Modal Chỉnh Sửa Đạo Cụ */}
      {editingItem !== undefined && (
        <ItemEditorModal
          item={editingItem}
          onClose={() => setEditingItem(undefined)}
          onSuccess={() => {
            refreshAll();
          }}
        />
      )}

      {/* 4. Modal Quản Lý Nhân Sự */}
      {editingStaff !== undefined && (
        <StaffModal
          staff={editingStaff}
          teams={teams}
          stations={stations}
          onClose={() => setEditingStaff(undefined)}
          onSuccess={() => {
            fetchStaffList();
          }}
        />
      )}

      {/* 5. Modal ± Lumen Bắt Buộc Nhập Lý Do */}
      {adjustingTeam && (
        <AdjustBalanceModal
          team={adjustingTeam}
          onClose={() => setAdjustingTeam(null)}
          onSuccess={() => {
            refreshAll();
            fetchAuditLogs();
          }}
        />
      )}

      {/* 6. Modal Force Revert */}
      {forceRevertTx && (
        <ForceRevertModal
          transaction={forceRevertTx}
          onClose={() => setForceRevertTx(null)}
          onSuccess={() => {
            fetchAuditLogs();
            refreshAll();
          }}
        />
      )}
    </div>
  );
}
