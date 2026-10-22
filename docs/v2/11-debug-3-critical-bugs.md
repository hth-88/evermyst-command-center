# BÁO CÁO ĐỐI SOÁT VÀ NGUYÊN VĂN MÃ NGUỒN DEBUG 3 LỖI NGHIÊM TRỌNG

> **Trạng thái:** DỪNG TOÀN BỘ VIỆC SỬA CODE — ĐỐI SOÁT VÀ TRÍCH XUẤT NGUYÊN VĂN MÃ NGUỒN HIỆN TẠI.  
> **Tài liệu căn cứ:** Mã nguồn tại các file `src/pages/AdminPage.tsx`, `src/components/admin/PendingAdminQueue.tsx`, `src/contexts/GameContext.tsx`, `src/components/support/StationTab.tsx`, `src/pages/StationPage.tsx`, `src/contexts/SessionContext.tsx`, `supabase/migrations/105_fix_rls_and_direct_scoring_sync.sql`, `supabase/migrations/104b_staff_station_mapping.sql`, `supabase/migrations/080_auth_sessions.sql`.

---

## TỔNG HỢP 3 LỖI NGHIÊM TRỌNG ĐANG GẶP PHẢI

1. **Lỗi 1 (Tại `/admin`):** Cột "NHẬT KÝ GIAO DỊCH & SỔ CÁI" bị lặp vô tận trạng thái *"Đang tải sổ cái..."* không bao giờ dừng.
2. **Lỗi 2 (Tại `/support`):** Khi bấm nút *"XÁC NHẬN CỘNG ĐIỂM TRẠM"*, hệ thống báo lỗi: *"Không tìm thấy trạm thử thách hoặc trạm đã đóng."*
3. **Lỗi 3 (Tại `/station`):** Khi đăng nhập tài khoản "Quản Trò Trạm 1" bấm cộng điểm, hệ thống báo lỗi: *"Bạn không được phân công phụ trách trạm này."*

---

## MỤC 1: NGUYÊN VĂN CÁC `useEffect` VÀ HÀM FETCH TRONG `AdminPage.tsx` & `PendingAdminQueue.tsx`

### 1.1. Các State và Hàm Fetch trong `src/pages/AdminPage.tsx`

#### (A) Khai báo State Loading và State Dữ liệu (Dòng 68 - 79)
```tsx
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
```

#### (B) Hàm `fetchStationPlays` (Dòng 97 - 119)
```tsx
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
        const enriched = data.map((play: any) => ({
          ...play,
          team_name: teams.find((t) => t.id === play.team_id)?.name || 'Đội chơi',
          station_name: stations.find((s) => s.id === play.station_id)?.name || 'Trạm Thử Thách',
        }));
        setStationPlays(enriched);
      }
    } catch (err) {
      console.error('Lỗi tải danh sách lượt chấm station_plays:', err);
    } finally {
      setIsLoadingPlays(false);
    }
  }, [teams, stations]);
```

#### (C) Hàm `fetchStaffList` (Dòng 121 - 134)
```tsx
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
```

#### (D) Hàm `fetchAuditLogs` (Dòng 136 - 154)
```tsx
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
      } else {
        await refreshAll();
      }
    } catch {
      await refreshAll();
    } finally {
      setIsLoadingAudit(false);
    }
  }, [auditFilter, refreshAll]);
```

#### (E) Các Realtime Signals và `useEffect` Khởi Chạy (Dòng 173 - 189)
```tsx
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
```

#### (F) Đoạn Render Spinner "Đang tải sổ cái..." trong `AdminPage.tsx` (Dòng 922 - 932)
```tsx
          {/* Audit Logs List */}
          <div className="flex-1 overflow-y-auto p-3 space-y-2.5">
            {isLoadingAudit ? (
              <div className="py-12 text-center space-y-2">
                <div className="w-6 h-6 border-2 border-lumen border-t-transparent rounded-full animate-spin mx-auto" />
                <p className="text-xs text-evermyst-text-dim">Đang tải sổ cái...</p>
              </div>
            ) : displayTransactions.length === 0 ? (
              <div className="py-12 text-center text-xs text-evermyst-text-dim">
                Không tìm thấy giao dịch nào phù hợp bộ lọc.
              </div>
            ) : (
```

#### (G) Đoạn Render Tab "Đối Soát Trạm" Gọi `PendingAdminQueue` (Dòng 524 - 540)
```tsx
                <PendingAdminQueue
                  plays={stationPlays}
                  onRefresh={() => {
                    fetchStationPlays();
                    refreshAll();
                  }}
                />
              </div>
            )}
```

---

### 1.2. Nguyên Văn Toàn Bộ File `src/components/admin/PendingAdminQueue.tsx`
```tsx
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
```

---

### 1.3. Khai Báo Hàm `refreshAll` và Realtime `postgres_changes` trong `src/contexts/GameContext.tsx`

#### (A) Hàm `refreshAll` (Dòng 255 - 441)
```tsx
  const refreshAll = useCallback(async () => {
    try {
      await syncServerTime();

      const [
        teamsRes,
        stationsRes,
        hintsRes,
        teamHintsRes,
        itemsRes,
        teamItemsRes,
        txRes,
        pvpRes,
        settingsRes,
      ] = await Promise.all([
        supabase.from('teams').select('*').order('light_balance', { ascending: false }),
        supabase.from('stations').select('*').order('order_index', { ascending: true }),
        supabase.from('hints').select('id, station_id, title, content, tier, order_index, is_active, created_at').order('order_index', { ascending: true }),
        supabase.from('team_hints').select('*'),
        supabase.from('items').select('*').order('price', { ascending: true }),
        supabase.from('team_items').select('*, item:items(*)'),
        supabase.from('transactions').select('*').order('created_at', { ascending: false }).limit(200),
        supabase.from('pvp_logs').select('*').order('created_at', { ascending: false }).limit(100),
        supabase.from('game_settings').select('*'),
      ]);

      if (teamsRes.data) {
        const localShields = getLocalShields();
        const mergedTeams = (teamsRes.data as Team[]).map((t) => {
          const localEnd = localShields[t.id];
          const localActive = localEnd && new Date(localEnd).getTime() > Date.now();
          const dbEnd = t.shield_until;
          const dbActive = dbEnd && new Date(dbEnd).getTime() > Date.now();

          let finalShield = dbEnd;
          if (localActive) {
            if (!dbActive || new Date(localEnd).getTime() > new Date(dbEnd!).getTime()) {
              finalShield = localEnd;
            }
          }
          return {
            ...t,
            shield_until: finalShield,
          };
        });
        setTeams(mergedTeams);
      }

      if (stationsRes.data) {
        // Chuẩn hóa mọi trạm có scoring_type === 'tier' nhưng thiếu scoring_config?.tiers
        const normalizedStations = (stationsRes.data as Station[]).map((st) => {
          if (
            st.scoring_type === 'tier' &&
            (!Array.isArray((st.scoring_config as any)?.tiers) ||
              (st.scoring_config as any).tiers.length === 0)
          ) {
            return {
              ...st,
              scoring_config: {
                ...(st.scoring_config || {}),
                tiers: DEFAULT_FALLBACK_TIERS,
              },
            };
          }
          return st;
        });

        // Deduplicate stations by order_index
        const uniqueStations: Station[] = [];
        const seenOrder = new Set<number>();
        normalizedStations.forEach((st: Station) => {
          if (!seenOrder.has(st.order_index)) {
            seenOrder.add(st.order_index);
            uniqueStations.push(st);
          }
        });
        setStations(uniqueStations.length > 0 ? uniqueStations : normalizedStations);
      }

      // Hints standardization & deduplication
      const resolvedHints: Hint[] = [];
      const seenTiers = new Set<string>();
      if (hintsRes.data && hintsRes.data.length > 0) {
        (hintsRes.data as Hint[]).forEach((h) => {
          if (!seenTiers.has(h.tier)) {
            seenTiers.add(h.tier);
            const def = DEFAULT_HINTS.find((dh) => dh.tier === h.tier);
            resolvedHints.push({
              ...h,
              content: h.content || def?.content || '',
            });
          }
        });
      }
      // Fill missing tiers from DEFAULT_HINTS
      DEFAULT_HINTS.forEach((dh) => {
        if (!seenTiers.has(dh.tier)) {
          seenTiers.add(dh.tier);
          resolvedHints.push(dh);
        }
      });
      setHints(resolvedHints.sort((a, b) => (a.order_index || 0) - (b.order_index || 0)));

      if (teamHintsRes.data) setTeamHints(teamHintsRes.data);

      // Items standardization & deduplication (shield, spyglass, master_key)
      const resolvedItems: Item[] = [];
      const seenCodes = new Set<string>();

      if (itemsRes.data && itemsRes.data.length > 0) {
        itemsRes.data.forEach((i: any) => {
          let code = i.item_code;
          let effect = i.effect_type;
          let name = i.name;
          if (effect === 'shield' || name.includes('Khiên')) {
            code = 'shield';
            effect = 'shield';
            name = 'Khiên Màn Sương';
          } else if (effect === 'spy' || effect === 'spyglass' || name.includes('Vọng Tầm') || name.includes('Cú Vọ')) {
            code = 'spyglass';
            effect = 'spyglass';
            name = 'Kính Vọng Tầm';
          } else if (effect === 'key' || effect === 'master_key' || name.includes('Chìa Khóa')) {
            code = 'master_key';
            effect = 'master_key';
            name = 'Chìa Khóa Vạn Năng';
          }

          if (code && !seenCodes.has(code)) {
            seenCodes.add(code);
            resolvedItems.push({
              ...i,
              item_code: code,
              effect_type: effect,
              name,
            });
          }
        });
      }

      // Ensure all 3 standard items exist
      DEFAULT_ITEMS.forEach((di) => {
        if (!seenCodes.has(di.item_code!)) {
          seenCodes.add(di.item_code!);
          resolvedItems.push(di);
        }
      });
      setItems(resolvedItems.sort((a, b) => a.price - b.price));

      if (teamItemsRes.data) {
        const mappedTeamItems = (teamItemsRes.data as TeamItem[]).map((ti) => {
          let code = ti.item_code || ti.item?.item_code;
          if (!code && ti.item) {
            if (ti.item.effect_type === 'shield') code = 'shield';
            else if (ti.item.effect_type === 'spy' || ti.item.effect_type === 'spyglass') code = 'spyglass';
            else if (ti.item.effect_type === 'key' || ti.item.effect_type === 'master_key') code = 'master_key';
          }
          return {
            ...ti,
            item_code: code,
          };
        });
        setTeamItems(mappedTeamItems);
      }


      if (txRes.data) setTransactions(txRes.data);
      if (pvpRes.data) setPvpLogs(pvpRes.data);

      if (settingsRes.data) {
        setSettingsRows(settingsRes.data);
        const parsed: GameConfig = { ...DEFAULT_CONFIG };
        settingsRes.data.forEach((row: GameSetting) => {
          if (row.value && typeof row.value === 'object' && 'v' in row.value) {
            parsed[row.key] = Number(row.value.v);
          }
        });
        setConfig(parsed);
      }

      await fetchStaffList();
    } catch (err) {
      console.error('Lỗi tải dữ liệu Evermyst:', err);
    } finally {
      setIsLoading(false);
    }
  }, [syncServerTime, fetchStaffList]);
```

#### (B) Listener Realtime `postgres_changes` trong `GameContext.tsx` (Dòng 446 - 536)
```tsx
  useEffect(() => {
    refreshAll();

    const channel = supabase
      .channel('evermyst-core-channel')
      // 1. Teams
      .on('postgres_changes', { event: '*', schema: 'public', table: 'teams' }, (payload) => {
        if (payload.eventType === 'INSERT') {
          setTeams((prev) => [...prev, payload.new as Team].sort((a, b) => b.light_balance - a.light_balance));
        } else if (payload.eventType === 'UPDATE') {
          setTeams((prev) =>
            prev.map((t) => (t.id === (payload.new as Team).id ? (payload.new as Team) : t))
              .sort((a, b) => b.light_balance - a.light_balance)
          );
        } else if (payload.eventType === 'DELETE') {
          setTeams((prev) => prev.filter((t) => t.id !== (payload.old as Team).id));
        }
      })
      // 2. Transactions
      .on('postgres_changes', { event: '*', schema: 'public', table: 'transactions' }, (payload) => {
        if (payload.eventType === 'INSERT') {
          setTransactions((prev) => [payload.new as Transaction, ...prev].slice(0, 200));
        } else if (payload.eventType === 'UPDATE') {
          setTransactions((prev) =>
            prev.map((t) => (t.id === (payload.new as Transaction).id ? (payload.new as Transaction) : t))
          );
        }
      })
      // 3. Team Hints
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'team_hints' }, (payload) => {
        setTeamHints((prev) => [...prev, payload.new as TeamHint]);
      })
      // 4. Team Items
      .on('postgres_changes', { event: '*', schema: 'public', table: 'team_items' }, () => {
        supabase.from('team_items').select('*, item:items(*)').then(({ data }) => {
          if (data) setTeamItems(data as TeamItem[]);
        });
      })
      // 5. PvP Logs
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'pvp_logs' }, (payload) => {
        setPvpLogs((prev) => [payload.new as PvPLog, ...prev].slice(0, 100));
      })
      // 6. Game Settings
      .on('postgres_changes', { event: '*', schema: 'public', table: 'game_settings' }, () => {
        supabase.from('game_settings').select('*').then(({ data }) => {
          if (data) {
            setSettingsRows(data);
            const parsed: GameConfig = { ...DEFAULT_CONFIG };
            data.forEach((row: GameSetting) => {
              if (row.value && typeof row.value === 'object' && 'v' in row.value) {
                parsed[row.key] = Number(row.value.v);
              }
            });
            setConfig(parsed);
          }
        });
      })
      // 7. Stations, Hints, Items (Admin CRUD)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'stations' }, () => {
        supabase.from('stations').select('*').order('order_index', { ascending: true }).then(({ data }) => {
          if (data) setStations(data);
        });
      })
      .on('postgres_changes', { event: '*', schema: 'public', table: 'items' }, () => {
        supabase.from('items').select('*').order('price', { ascending: true }).then(({ data }) => {
          if (data) setItems(data);
        });
      })
      .on('postgres_changes', { event: '*', schema: 'public', table: 'hints' }, () => {
        supabase.from('hints').select('id, station_id, title, tier, order_index, is_active, created_at').order('order_index', { ascending: true }).then(({ data }) => {
          if (data) setHints(data as Hint[]);
        });
      })
      .subscribe((status) => {
        if (status === 'SUBSCRIBED') {
          setIsConnected(true);
          // Snapshot Reconciliation khi reconnect sau khi mất mạng
          if (wasDisconnectedRef.current) {
            wasDisconnectedRef.current = false;
            refreshAll();
          }
        } else if (status === 'CLOSED' || status === 'CHANNEL_ERROR') {
          setIsConnected(false);
          wasDisconnectedRef.current = true;
        }
      });

    return () => {
      channel.unsubscribe();
    };
  }, [refreshAll]);
```

### 1.4. Phân Tích Cơ Chế Gây Lỗi 1 (Lặp vô tận "Đang tải sổ cái..."):
1. Tại `AdminPage.tsx` dòng 185: `useEffect` có mảng dependency là `[fetchStationPlays, fetchStaffList, fetchAuditLogs]`.
2. `fetchStationPlays` được bọc bởi `useCallback(..., [teams, stations])`.
3. `fetchAuditLogs` được bọc bởi `useCallback(..., [auditFilter, refreshAll])`.
4. Trong `fetchAuditLogs`:
   ```tsx
   setIsLoadingAudit(true);
   try {
     const res = await callRpc('admin_get_audit_log', ...);
     if (res.success && Array.isArray(res.audit_logs)) {
       setAuditLogs(res.audit_logs);
     } else {
       await refreshAll(); // <--- GỌI REFRESH ALL KHI RPC KHÔNG TRẢ MẢNG
     }
   } catch {
     await refreshAll();   // <--- GỌI REFRESH ALL KHI GẶP LỖI
   } finally {
     setIsLoadingAudit(false);
   }
   ```
5. Khi RPC `admin_get_audit_log` thất bại hoặc chưa có dữ liệu mảng, nhánh `else` hoặc `catch` lập tức gọi `await refreshAll()`.
6. Khi `refreshAll()` thực thi trong `GameContext.tsx`, nó gọi `setTeams(mergedTeams)` và `setStations(...)`. Điều này tạo ra **mảng tham chiếu mới (new array reference)** cho cả `teams` và `stations`.
7. `teams` và `stations` thay đổi tham chiếu khiến `fetchStationPlays` trong `AdminPage.tsx` bị tái tạo lại thành một instance hàm mới.
8. Sự thay đổi của `fetchStationPlays` kích hoạt `useEffect` tại dòng 185 chạy lại ngay lập tức.
9. `useEffect` chạy lại lập tức gọi `fetchAuditLogs()` -> gọi `setIsLoadingAudit(true)` -> lại gọi `refreshAll()` -> tạo vòng lặp vô tận (render loop) khiến `isLoadingAudit` luôn liên tục bị set thành `true` không bao giờ kết thúc!

---

## MỤC 2: NGUYÊN VĂN ĐOẠN GỌI CỘNG ĐIỂM TRẠM Ở FRONTEND

### 2.1. Trong `src/contexts/GameContext.tsx`

#### (A) Hàm `awardStationDirectPoints` (Dòng 541 - 564)
```tsx
  const awardStationDirectPoints = useCallback(
    async (
      teamId: string,
      stationId: string,
      points: number,
      note?: string
    ): Promise<RPCResponse> => {
      const res = await callRpc('award_station_direct_points', {
        p_team_id: teamId,
        p_station_id: stationId,
        p_points: points,
        p_note: note || null,
      });

      if (res.success) {
        addToast(res.message || `+${points}✦ Lumen đã được cộng trực tiếp cho đội!`, 'success');
        await refreshAll();
      } else {
        addToast(res.error || res.message || 'Lỗi khi cộng điểm trạm', 'error');
      }
      return res;
    },
    [addToast, refreshAll]
  );
```

#### (B) Hàm `executeStationReward` (Dòng 604 - 622)
```tsx
  const executeStationReward = useCallback(
    async (
      teamId: string,
      stationId: string,
      amount: number,
      _unlockStation: boolean
    ): Promise<StationRewardResponse> => {
      const res = await awardStationDirectPoints(teamId, stationId, amount);
      return {
        success: res.success,
        message: res.message,
        error: res.error,
        status: res.success ? 'approved' : 'rejected',
        computed_points: amount,
        final_points: amount,
      } as StationRewardResponse;
    },
    [awardStationDirectPoints]
  );
```

---

### 2.2. Trong `src/components/support/StationTab.tsx`

#### (A) Định nghĩa Interface và Cấu trúc Phần tử Trạm (Dòng 28 - 42)
```tsx
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
```

#### (B) Hàm Ánh Xạ Trạng Thái `fetchStationStatuses` & `displayItems` (Dòng 55 - 89, 152 - 163)
```tsx
  // Tải trạng thái các trạm của đội từ DB thật qua GameContext
  const fetchStationStatuses = useCallback(async () => {
    if (!selectedTeam) return;
    try {
      const activeStations = stations.filter((s) => s.is_active);
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
```
```tsx
  // Danh sách hiển thị: kết hợp giữa stations và status
  const displayItems = stationStatuses.length > 0 ? stationStatuses : stations.map((s) => ({
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
  }));
```

#### (C) Hàm Xử Lý Khi Bấm Nút Cộng Điểm `handleSubmitClaim` (Dòng 102 - 135)
```tsx
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
```

#### (D) Đoạn Render Button Bấm Nộp Điểm (Dòng 292 - 306)
```tsx
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
```

> **Ghi chú về phần tử trạm:** Trong `StationTab.tsx`, `displayItems` chứa các phần tử có thuộc tính `station_id: st.id`. Tại `handleSubmitClaim`, biến `stId` lấy `(station as any).station_id || (station as any).id`. Do đó, frontend truyền chính xác giá trị `st.id` từ danh sách `stations` của `GameContext`.

---

### 2.3. Trong `src/pages/StationPage.tsx`

#### (A) Cách Lấy `currentStation` và `stationId` của Quản Trò Đang Đăng Nhập (Dòng 42 - 61)
```tsx
  // Xác định trạm được phân công cho quản trò
  const currentStation = useMemo(() => {
    if (!user) return null;
    if (user.assigned_station_id) {
      const match = stations.find((s) => s.id === user.assigned_station_id);
      if (match) return match;
    }
    // Fallback khớp theo tên
    const uName = (user.name || '').toLowerCase();
    const matchByName = stations.find((s) => {
      const sName = s.name.toLowerCase();
      return (
        (uName.includes('trạm 1') || uName.includes('cổng sương mù')) && s.order_index === 1 ||
        (uName.includes('trạm 2') || uName.includes('rừng thì thầm')) && s.order_index === 2 ||
        (uName.includes('trạm 3') || uName.includes('đầm lầy ảo ảnh')) && s.order_index === 3 ||
        (uName.includes('trạm 4') || uName.includes('hang pha lê')) && s.order_index === 4 ||
        (uName.includes('trạm 5') || uName.includes('đỉnh thiên giới')) && s.order_index === 5
      );
    });
    return matchByName || stations[0] || null;
  }, [user, stations]);
```

#### (B) Hàm Xử Lý Khi Bấm Nút Cộng Điểm `handleAwardPoints` (Dòng 124 - 159)
```tsx
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
```

---

## MỤC 3: NGUYÊN VĂN HÀM SQL `award_station_direct_points`

### 3.1. Thân Hàm SQL `award_station_direct_points` Trong Migration Mới Nhất (`supabase/migrations/105_fix_rls_and_direct_scoring_sync.sql`, Dòng 102 - 307)
```sql
CREATE OR REPLACE FUNCTION public.award_station_direct_points(
  p_token             TEXT,
  p_team_id           UUID,
  p_station_id        UUID,
  p_points            INTEGER,
  p_client_request_id TEXT,
  p_note              TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_auth                  RECORD;
  v_assigned_station_id   UUID;
  v_station               RECORD;
  v_team                  RECORD;
  v_existing_play         RECORD;
  v_active_count          INTEGER;
  v_max_play_no           INTEGER;
  v_play_no               INTEGER;
  v_play_id               UUID;
  v_tx_id                 UUID := NULL;
  v_new_balance           INTEGER;
  v_unlocked              TEXT[];
BEGIN
  -- 1. Xác thực bằng auth_verify_session
  BEGIN
    SELECT s.staff_id, s.staff_name, s.staff_role, s.station_assigned
    INTO v_auth
    FROM public.auth_verify_session(p_token) s;
  EXCEPTION WHEN OTHERS THEN
    RETURN public._direct_scoring_err('INVALID_TOKEN', 'Phiên làm việc không tồn tại hoặc đã hết hạn.');
  END;

  IF v_auth.staff_id IS NULL THEN
    RETURN public._direct_scoring_err('INVALID_TOKEN', 'Phiên làm việc không tồn tại hoặc đã hết hạn.');
  END IF;

  -- 2. Kiểm tra quyền hạn của staff
  SELECT assigned_station_id INTO v_assigned_station_id
  FROM public.staff WHERE id = v_auth.staff_id;

  IF v_auth.staff_role = 'admin' THEN
    -- Admin toàn quyền
    NULL;
  ELSIF v_auth.staff_role IN ('support', 'team_support', 'station_master') THEN
    -- Nếu support có trạm được gán cụ thể và trạm đó khác trạm đang chấm
    IF v_assigned_station_id IS NOT NULL AND v_assigned_station_id IS DISTINCT FROM p_station_id THEN
      RETURN public._direct_scoring_err('FORBIDDEN_STATION', 'Bạn không được phân công quản trạm này.');
    END IF;
  ELSE
    RETURN public._direct_scoring_err('FORBIDDEN', 'Bạn không có quyền nhập điểm trạm.');
  END IF;

  -- 3. Kiểm tra cờ tạm dừng trò chơi
  IF EXISTS (
    SELECT 1 FROM public.game_settings 
    WHERE key = 'game_status' AND (value->>'v' = 'paused' OR value->>'status' = 'paused')
  ) THEN
    RETURN public._direct_scoring_err('GAME_NOT_RUNNING', 'Trò chơi hiện đang tạm dừng.');
  END IF;

  -- 4. Validate client_request_id & points (điểm phải >= 0)
  IF p_client_request_id IS NULL OR length(btrim(p_client_request_id)) = 0 THEN
    RETURN public._direct_scoring_err('INVALID_REQUEST_ID', 'Thiếu mã yêu cầu (client_request_id).');
  END IF;

  IF p_points IS NULL OR p_points < 0 THEN
    RETURN public._direct_scoring_err('INVALID_AMOUNT', 'Số điểm phải là số nguyên không âm.');
  END IF;

  -- 5. Kiểm tra trạm tồn tại và active
  SELECT * INTO v_station
  FROM public.stations
  WHERE id = p_station_id AND deleted_at IS NULL;

  IF NOT FOUND THEN
    RETURN public._direct_scoring_err('STATION_NOT_FOUND', 'Không tìm thấy trạm.');
  END IF;
  IF NOT v_station.is_active THEN
    RETURN public._direct_scoring_err('STATION_INACTIVE', 'Trạm này đang tạm khóa.');
  END IF;

  -- 6. Khóa dòng đội chơi để chống race condition
  SELECT * INTO v_team
  FROM public.teams
  WHERE id = p_team_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN public._direct_scoring_err('TEAM_NOT_FOUND', 'Không tìm thấy đội chơi.');
  END IF;
  IF NOT v_team.is_active THEN
    RETURN public._direct_scoring_err('TEAM_INACTIVE', 'Đội chơi này đang bị vô hiệu hóa.');
  END IF;

  -- 7. Kiểm tra Idempotency
  SELECT * INTO v_existing_play
  FROM public.station_plays
  WHERE client_request_id = p_client_request_id;

  IF FOUND THEN
    RETURN jsonb_build_object(
      'success', true,
      'ok', true,
      'code', 'OK',
      'message', 'Yêu cầu đã được xử lý trước đó.',
      'error', null,
      'replayed', true,
      'idempotent', true,
      'data', jsonb_build_object(
        'play_id', v_existing_play.id,
        'tx_id', v_existing_play.tx_id,
        'points', v_existing_play.points,
        'play_no', v_existing_play.play_no,
        'new_balance', v_team.light_balance
      )
    );
  END IF;

  -- 8. Đếm số lượt active và tính play_no
  SELECT count(*) FILTER (WHERE status = 'active'),
         COALESCE(max(play_no), 0)
  INTO v_active_count, v_max_play_no
  FROM public.station_plays
  WHERE team_id = p_team_id AND station_id = p_station_id;

  IF NOT v_station.allow_multiple_attempts AND v_active_count > 0 THEN
    RETURN public._direct_scoring_err(
      'STATION_ALREADY_PLAYED',
      'Đội này đã hoàn thành trạm 1 lượt này rồi.',
      jsonb_build_object('play_count', v_active_count)
    );
  END IF;

  v_play_no := v_max_play_no + 1;

  -- 9. Ghi lượt chơi vào station_plays
  INSERT INTO public.station_plays (
    team_id, station_id, play_no, points, status,
    staff_id, staff_name, note, client_request_id
  ) VALUES (
    p_team_id, p_station_id, v_play_no, p_points, 'active',
    v_auth.staff_id, v_auth.staff_name, p_note, p_client_request_id
  ) RETURNING id INTO v_play_id;

  -- 10. Ghi sổ cái transactions nếu p_points > 0
  IF p_points > 0 THEN
    INSERT INTO public.transactions (
      team_id,
      amount,
      type,
      description,
      created_by,
      client_request_id,
      is_reversed
    ) VALUES (
      p_team_id,
      p_points,
      'station_clear',
      format('Vượt trạm %s lượt %s (+%s Lumen)', v_station.name, v_play_no, p_points),
      v_auth.staff_name,
      p_client_request_id,
      false
    ) RETURNING id INTO v_tx_id;

    UPDATE public.station_plays
    SET tx_id = v_tx_id
    WHERE id = v_play_id;
  END IF;

  -- 11. Cập nhật số dư và mảng unlocked_stations cho đội
  v_new_balance := v_team.light_balance + p_points;
  v_unlocked := COALESCE(v_team.unlocked_stations, ARRAY[]::TEXT[]);

  IF NOT (p_station_id::TEXT = ANY(v_unlocked)) THEN
    v_unlocked := array_append(v_unlocked, p_station_id::TEXT);
  END IF;

  UPDATE public.teams
  SET light_balance = v_new_balance,
      unlocked_stations = v_unlocked
  WHERE id = p_team_id;

  -- 12. Trả kết quả thành công
  RETURN jsonb_build_object(
    'success', true,
    'ok', true,
    'code', 'OK',
    'message', format('Đã cộng %s Lumen cho đội %s thành công!', p_points, v_team.name),
    'error', null,
    'replayed', false,
    'idempotent', false,
    'data', jsonb_build_object(
      'play_id', v_play_id,
      'tx_id', v_tx_id,
      'points', p_points,
      'play_no', v_play_no,
      'new_balance', v_new_balance,
      'station_name', v_station.name,
      'team_name', v_team.name
    )
  );
END;
$$;
```

---

### 3.2. Đối Chiếu Nguyên Nhân Văng 2 Lỗi Tại SQL:

#### 1. Tại sao văng lỗi: *"Không tìm thấy trạm thử thách hoặc trạm đã đóng."*?
- **Đoạn mã SQL (Dòng 175 - 181):**
  ```sql
  SELECT * INTO v_station
  FROM public.stations
  WHERE id = p_station_id AND deleted_at IS NULL;

  IF NOT FOUND THEN
    RETURN public._direct_scoring_err('STATION_NOT_FOUND', 'Không tìm thấy trạm.');
  END IF;
  ```
- **Ánh xạ mã lỗi phía Client (`src/lib/errors.vi.ts` dòng 23):**
  ```ts
  STATION_NOT_FOUND: 'Không tìm thấy trạm thử thách hoặc trạm đã đóng.',
  ```
- **Nguyên nhân thực tế:** `p_station_id` truyền từ giao diện lên là ID của trạm cũ đã bị gán `deleted_at = now()` bởi migration `104b`. Khi hàm SQL truy vấn `WHERE id = p_station_id AND deleted_at IS NULL`, bản ghi không tìm thấy (`NOT FOUND`) -> hàm trả về mã lỗi `STATION_NOT_FOUND` -> `callRpc` dịch thành chuỗi thông báo lỗi trên.

#### 2. Tại sao văng lỗi: *"Bạn không được phân công phụ trách trạm này."*?
- **Đoạn mã SQL (Dòng 142 - 153):**
  ```sql
  SELECT assigned_station_id INTO v_assigned_station_id
  FROM public.staff WHERE id = v_auth.staff_id;

  IF v_auth.staff_role = 'admin' THEN
    NULL;
  ELSIF v_auth.staff_role IN ('support', 'team_support', 'station_master') THEN
    IF v_assigned_station_id IS NOT NULL AND v_assigned_station_id IS DISTINCT FROM p_station_id THEN
      RETURN public._direct_scoring_err('FORBIDDEN_STATION', 'Bạn không được phân công quản trạm này.');
    END IF;
  ELSE
    RETURN public._direct_scoring_err('FORBIDDEN', 'Bạn không có quyền nhập điểm trạm.');
  END IF;
  ```
- **Ánh xạ mã lỗi phía Client (`src/lib/errors.vi.ts` dòng 18):**
  ```ts
  FORBIDDEN_STATION: 'Bạn không được phân công phụ trách trạm này.',
  ```
- **Nguyên nhân thực tế:** Trong bảng `public.staff`, tài khoản "Quản Trò Trạm 1" có `assigned_station_id` mang giá trị UUID của **Trạm mới** (`62c1aea6-d4cc-437a-8367-a2f6f831f143`). Tuy nhiên, do giao diện lấy nhầm UUID của **Trạm cũ** (`7a8d9016-1587-46e5-9a8e-4b96d821c454`), tham số `p_station_id` không khớp với `v_assigned_station_id` (`IS DISTINCT FROM`), hàm SQL văng mã lỗi `FORBIDDEN_STATION` -> `callRpc` dịch thành chuỗi thông báo lỗi trên.

---

## MỤC 4: KIỂM TRA DỮ LIỆU ĐỐI CHIẾU TRẠM & NHÂN SỰ

### 4.1. Hàm `staff_login` Lưu và Trả `assigned_station_id` Thế Nào? (`supabase/migrations/080_auth_sessions.sql`, Dòng 263 - 279)
```sql
    IF v_matched_staff.assigned_station_id IS NOT NULL THEN
        SELECT jsonb_build_object('id', id, 'name', name) INTO v_assigned_station
        FROM stations WHERE id = v_matched_staff.assigned_station_id;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'token', v_raw_token,
        'expires_at', v_expires_at,
        'staff', jsonb_build_object(
            'id', v_matched_staff.id,
            'name', v_matched_staff.name,
            'role', v_matched_staff.role
        ),
        'assigned_team', v_assigned_team,
        'assigned_station', v_assigned_station
    );
```
> **Nhận xét quan trọng:** `staff_login` trả về `assigned_station: { id: ..., name: ... }` chứ không đặt `assigned_station_id` bên trong object `staff`.

---

### 4.2. Frontend Nhận và Lưu `assigned_station_id` Thế Nào? (`src/contexts/SessionContext.tsx`, Dòng 142 - 171)
```tsx
  // Đăng nhập bằng mã PIN
  const login = async (pin: string): Promise<{ success: boolean; role?: StaffRole; error?: string }> => {
    setIsVerifying(true);
    try {
      const res = await callRpc<any>('staff_login', { p_pin: pin.trim() });
      const staffInfo = res?.staff || res?.user;
      const token = res?.token;

      if (res?.success && token && staffInfo) {
        const normalizedRole = normalizeRole(staffInfo.role || staffInfo.staff_role, staffInfo.station_assigned);
        const assignedStation = res.assigned_station || (staffInfo.station_assigned ? { id: staffInfo.station_assigned, name: staffInfo.station_assigned } : null);
        const assignedTeam = res.assigned_team || null;

        const authUser: AuthUser = {
          id: staffInfo.id || staffInfo.staff_id,
          name: staffInfo.name || staffInfo.staff_name,
          role: normalizedRole,
          assigned_team_id: staffInfo.assigned_team_id || assignedTeam?.id || null,
          assigned_team: assignedTeam,
          assigned_station_id: staffInfo.assigned_station_id || assignedStation?.id || null,
          assigned_station: assignedStation,
          token: token,
          expires_at: res.expires_at,
        };

        localStorage.setItem(TOKEN_STORAGE_KEY, token);
        setToken(token);
        setUser(authUser);
        setIsVerifying(false);
        return { success: true, role: normalizedRole };
      }
```
> **Kết luận:** Tại `SessionContext`, `authUser.assigned_station_id` nhận giá trị từ `assignedStation?.id` (tức là UUID lấy từ database `staff.assigned_station_id`).

---

### 4.3. Bảng Đối Chiếu 2 Bộ Trạm Trong Database và Migration `104b` (`supabase/migrations/104b_staff_station_mapping.sql`)

| Tên Trạm | Bộ Cũ (Bị Soft Delete `deleted_at = now()`) | Bộ Mới (Được Gán Cho Quản Trò & Support) | Quản Trò Phụ Trách (`staff.id`) |
| :--- | :--- | :--- | :--- |
| **Trạm 1: Cổng Sương Mù** | `7a8d9016-1587-46e5-9a8e-4b96d821c454` | `62c1aea6-d4cc-437a-8367-a2f6f831f143` | `f7e14023-f66b-4b9e-b74e-9c32686df32f` |
| **Trạm 2: Đền Cổ Lumen / Rừng Thì Thầm** | `8e1a6eb0-eed3-424c-a437-a75c845b1e4a` | `e24d72fa-d0f7-4cb3-b766-9f791e996c6e` | `9fb23580-6d6a-4dc9-ba09-d68177fb7e16` |
| **Trạm 3: Rừng Bóng Tối / Đầm Lầy Ảo Ảnh** | `f78844f3-38f4-4326-9c3e-798652ad3ff2` | `a8089f77-4358-49f8-ab5a-9290ee66cba9` | `048bc38a-2182-4d27-a92e-ab74004aa883` |
| **Trạm 4: Hồ Gương / Hang Pha Lê** | `1dd43ca4-ab24-4bac-a093-ce0a1543f569` | `00ebfdd9-ab16-4cb4-a8e0-6ba9d2836e78` | `05d48f1c-1f66-4229-a880-f84e0d13bc94` |
| **Trạm 5: Đỉnh Tháp / Đỉnh Thiên Giới** | `b6ed2a2b-e790-4fc3-9d9b-a8a1c0243e65` | `3283b49e-4e1d-47a5-9ef6-a31a15159a4e` | `a1892371-e756-4a1f-aba4-590651e4d949` |

---

### 4.4. Điểm Gãy Dữ Liệu Thực Tế Khiến Lỗi 2 và Lỗi 3 Xuất Hiện:

#### Tại `src/contexts/GameContext.tsx` (Dòng 271 & Dòng 322 - 331):
```tsx
// 1. Tải toàn bộ trạm không lọc deleted_at:
supabase.from('stations').select('*').order('order_index', { ascending: true })
```
```tsx
// 2. Lọc loại bỏ trùng lặp theo order_index:
const uniqueStations: Station[] = [];
const seenOrder = new Set<number>();
normalizedStations.forEach((st: Station) => {
  if (!seenOrder.has(st.order_index)) {
    seenOrder.add(st.order_index);
    uniqueStations.push(st);
  }
});
setStations(uniqueStations.length > 0 ? uniqueStations : normalizedStations);
```

#### Hệ Quả:
1. Vì câu truy vấn `supabase.from('stations').select('*').order('order_index', { ascending: true })` **KHÔNG** có điều kiện `.is('deleted_at', null)`, cả 10 bản ghi trạm (5 trạm cũ đã xóa mềm và 5 trạm mới) đều được trả về.
2. Bản ghi trạm cũ được tạo trước (`created_at` lúc 16:38:29) nằm trước trong kết quả trả về so với trạm mới (`created_at` lúc 16:42:32).
3. Thuật toán `seenOrder.add(st.order_index)` giữ lại phần tử **đầu tiên** gặp phải có `order_index = 1` -> chính là **Trạm cũ đã bị soft-delete (`7a8d9016...`)**, đồng thời **loại bỏ Trạm mới (`62c1aea6...`)**!
4. State `stations` trong toàn bộ Frontend bị gán danh sách gồm 5 trạm cũ đã bị xóa mềm!
5. **Gây ra Lỗi 2 tại `/support`:** Form gửi ID trạm cũ (`7a8d9016...`). SQL tìm `WHERE id = p_station_id AND deleted_at IS NULL` thì trả về `NOT FOUND` -> Báo lỗi: *"Không tìm thấy trạm thử thách hoặc trạm đã đóng."*
6. **Gây ra Lỗi 3 tại `/station`:** Quản Trò Trạm 1 có `user.assigned_station_id = '62c1aea6...'` (Trạm mới). Khi `StationPage.tsx` tìm `stations.find(s => s.id === user.assigned_station_id)`, không tìm thấy vì `stations` chỉ chứa các trạm cũ! `StationPage` rơi vào khối fallback khớp theo tên và lấy trạm cũ `order_index = 1` (`7a8d9016...`). Khi bấm cộng điểm, frontend gửi ID trạm cũ `7a8d9016...` lên server, server so sánh với `staff.assigned_station_id` (`62c1aea6...`) thấy lệch nhau -> Báo lỗi: *"Bạn không được phân công phụ trách trạm này."*
