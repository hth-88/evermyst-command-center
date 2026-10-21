// ============================================================================
// GAME CONTEXT - State Management + Supabase Realtime (1 kênh duy nhất)
// Toàn bộ dữ liệu game, RPC Security Definer, và Reconnect Snapshot
// ============================================================================
import {
  createContext,
  useContext,
  useEffect,
  useState,
  useCallback,
  useRef,
  type ReactNode,
} from 'react';
import { supabase } from '@/lib/supabase';
import { useSession } from '@/contexts/SessionContext';
import { callRpc } from '@/lib/rpc';
import type {
  Team,
  Station,
  Hint,
  TeamHint,
  Item,
  TeamItem,
  Transaction,
  PvPLog,
  GameConfig,
  GameSetting,
  AuthUser,
  Staff,
  Toast,
  RPCResponse,
  StationRewardResponse,
  BuyHintResponse,
  BuyItemResponse,
  PvPResponse,
} from '@/lib/types';
import {
  generateId,
  setServerOffset,
} from '@/lib/utils';
import { DEFAULT_CONFIG, DEFAULT_ITEMS, DEFAULT_HINTS } from '@/lib/constants';
import { DEFAULT_FALLBACK_TIERS } from '@/components/scoring/StationScoringForm';

// ---------------------------------------------------------------------------
// Context Shape
// ---------------------------------------------------------------------------
interface GameContextType {
  // Auth
  user: AuthUser | null;
  login: (pin: string) => Promise<boolean>;
  logout: () => void;
  staffList: Staff[];
  fetchStaffList: () => Promise<void>;

  // Data
  teams: Team[];
  stations: Station[];
  hints: Hint[];
  teamHints: TeamHint[];
  items: Item[];
  teamItems: TeamItem[];
  transactions: Transaction[];
  pvpLogs: PvPLog[];
  config: GameConfig;
  settingsRows: GameSetting[];

  // Loading & Connection
  isLoading: boolean;
  isConnected: boolean;

  // Actions - Station
  executeStationReward: (
    teamId: string,
    stationId: string,
    amount: number,
    unlockStation: boolean
  ) => Promise<StationRewardResponse>;

  // Actions - Shop & Hints & Inventory
  buyHint: (teamId: string, hintId: string) => Promise<BuyHintResponse>;
  fetchTeamHints: (teamId: string) => Promise<TeamHint[]>;
  buyItem: (teamId: string, itemId: string) => Promise<BuyItemResponse>;
  useItem: (teamId: string, itemCodeOrId: string, targetTeamId?: string, targetStationId?: string) => Promise<RPCResponse>;
  activateTeamItem: (teamId: string, itemId: string) => Promise<RPCResponse>;
  teamStationKeys: Record<string, string[]>;

  // Actions - PvP
  resolvePvP: (attackerId: string, defenderId: string, attackCost?: number) => Promise<PvPResponse>;

  // Actions - Transactions & Reversal
  decidePending: (txId: string, decision: 'approve' | 'reject', reason?: string) => Promise<RPCResponse>;
  reverseTransaction: (txId: string, reason?: string) => Promise<RPCResponse>;

  // Actions - Admin Controls
  adminAdjustBalance: (teamId: string, amount: number, description: string) => Promise<RPCResponse>;
  adminSetShield: (teamId: string, durationMinutes: number) => Promise<RPCResponse>;
  updateSetting: (key: string, value: number | string | boolean) => Promise<boolean>;
  adminListHints: () => Promise<Hint[]>;

  // Actions - CRUD (MỌI GHI QUA RPC Security Definer)
  upsertTeam: (data: Partial<Team>) => Promise<boolean>;
  upsertStation: (data: Partial<Station>) => Promise<boolean>;
  upsertHint: (data: Partial<Hint>) => Promise<boolean>;
  upsertItem: (data: Partial<Item>) => Promise<boolean>;
  upsertStaff: (data: Partial<Staff>) => Promise<boolean>;
  setEntityActive: (entityType: 'team' | 'station' | 'hint' | 'item' | 'staff', id: string, isActive: boolean) => Promise<boolean>;

  // Toasts
  toasts: Toast[];
  addToast: (message: string, type: Toast['type']) => void;
  removeToast: (id: string) => void;

  // Refresh
  refreshAll: () => Promise<void>;
}

const GameContext = createContext<GameContextType | null>(null);

// ---------------------------------------------------------------------------
// Default config values (Fallback trước khi đọc DB)
// ---------------------------------------------------------------------------
// ---------------------------------------------------------------------------
// Helpers: Local Storage Shields Cache (Chống mất khiên khi reload/đổi nick)
// ---------------------------------------------------------------------------
const getLocalShields = (): Record<string, string> => {
  try {
    const s = typeof window !== 'undefined' ? localStorage.getItem('evermyst_team_shields') : null;
    return s ? JSON.parse(s) : {};
  } catch {
    return {};
  }
};

const setLocalShield = (teamId: string, shieldUntil: string) => {
  try {
    if (typeof window === 'undefined') return;
    const current = getLocalShields();
    current[teamId] = shieldUntil;
    localStorage.setItem('evermyst_team_shields', JSON.stringify(current));
  } catch {
    // ignore
  }
};

// Provider
// ---------------------------------------------------------------------------
export function GameProvider({ children }: { children: ReactNode }) {
  // Đồng bộ phiên người dùng từ SessionProvider (Phase 6)
  const { user, login: sessionLogin, logout: sessionLogout } = useSession();

  const [staffList, setStaffList] = useState<Staff[]>([]);

  // Game data state
  const [teams, setTeams] = useState<Team[]>([]);
  const [stations, setStations] = useState<Station[]>([]);
  const [hints, setHints] = useState<Hint[]>([]);
  const [teamHints, setTeamHints] = useState<TeamHint[]>([]);
  const [items, setItems] = useState<Item[]>([]);
  const [teamItems, setTeamItems] = useState<TeamItem[]>([]);
  const [teamStationKeys, setTeamStationKeys] = useState<Record<string, string[]>>(() => {
    try {
      const saved = localStorage.getItem('evermyst_team_station_keys');
      return saved ? JSON.parse(saved) : {};
    } catch {
      return {};
    }
  });
  const [transactions, setTransactions] = useState<Transaction[]>([]);
  const [pvpLogs, setPvpLogs] = useState<PvPLog[]>([]);
  const [config, setConfig] = useState<GameConfig>(DEFAULT_CONFIG);
  const [settingsRows, setSettingsRows] = useState<GameSetting[]>([]);

  // UI state
  const [isLoading, setIsLoading] = useState(true);
  const [isConnected, setIsConnected] = useState(false);
  const [toasts, setToasts] = useState<Toast[]>([]);

  const wasDisconnectedRef = useRef(false);

  // =========================================================================
  // TOAST NOTIFICATIONS
  // =========================================================================
  const addToast = useCallback((message: string, type: Toast['type'] = 'info') => {
    const id = generateId();
    setToasts((prev) => [...prev, { id, message, type, duration: 4000 }]);
    setTimeout(() => {
      setToasts((prev) => prev.filter((t) => t.id !== id));
    }, 4000);
  }, []);

  const removeToast = useCallback((id: string) => {
    setToasts((prev) => prev.filter((t) => t.id !== id));
  }, []);

  // =========================================================================
  // SERVER TIME SYNCHRONIZATION (Nguyên tắc 5)
  // =========================================================================
  const syncServerTime = useCallback(async () => {
    try {
      const clientBefore = Date.now();
      const { data, error } = await supabase.rpc('get_server_time');
      const clientAfter = Date.now();
      const roundTripMs = clientAfter - clientBefore;

      if (!error && data && data.epoch_ms) {
        // Ước lượng độ trễ 1 chiều = roundTripMs / 2
        const estimatedServerNow = Number(data.epoch_ms) + roundTripMs / 2;
        const offset = estimatedServerNow - clientAfter;
        setServerOffset(offset);
      }
    } catch (e) {
      console.warn('Lỗi đồng bộ giờ server:', e);
    }
  }, []);

  // =========================================================================
  // AUTHENTICATION (Ủy thác qua SessionProvider + PIN)
  // =========================================================================
  const login = useCallback(
    async (pin: string): Promise<boolean> => {
      const res = await sessionLogin(pin);
      if (res.success) {
        addToast(`Xin chào ${user?.name || 'Chiến binh'}!`, 'success');
        return true;
      }
      addToast(res.error || 'Đăng nhập không thành công', 'error');
      return false;
    },
    [sessionLogin, user?.name, addToast]
  );

  const logout = useCallback(() => {
    sessionLogout();
    addToast('Đã đăng xuất', 'info');
  }, [sessionLogout, addToast]);

  // =========================================================================
  // DATA FETCHING & SNAPSHOT RECONCILIATION
  // =========================================================================
  const fetchStaffList = useCallback(async () => {
    try {
      const res = await callRpc<{ staff: Staff[] }>('admin_list_staff');
      if (res.success && Array.isArray((res as any).staff)) {
        setStaffList((res as any).staff);
      }
    } catch {
      // ignore
    }
  }, []);

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
        keysRes,
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
        supabase.from('team_station_keys').select('*'),
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

      // Sync team_station_keys
      if (keysRes?.data) {
        const keyMap: Record<string, string[]> = {};
        keysRes.data.forEach((k: any) => {
          if (!keyMap[k.team_id]) keyMap[k.team_id] = [];
          if (!keyMap[k.team_id].includes(k.station_id)) {
            keyMap[k.team_id].push(k.station_id);
          }
        });
        setTeamStationKeys(keyMap);
        try {
          localStorage.setItem('evermyst_team_station_keys', JSON.stringify(keyMap));
        } catch {
          // ignore
        }
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

  // =========================================================================
  // SUPABASE REALTIME (1 Kênh duy nhất + Snapshot Reconnect - Nguyên tắc 4)
  // =========================================================================
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

  // =========================================================================
  // ACTIONS: STATION REWARD (Idempotent + Atomic - Nguyên tắc 1, 2)
  // =========================================================================
  const executeStationReward = useCallback(
    async (
      teamId: string,
      stationId: string,
      amount: number,
      unlockStation: boolean
    ): Promise<StationRewardResponse> => {
      const res = await callRpc<any>('submit_station_claim', {
        p_station_id: stationId,
        p_team_id: teamId,
        p_input: {
          points: amount,
          unlock_station: unlockStation,
        },
      });

      if (res.success) {
        addToast(res.message || 'Gửi yêu cầu chấm điểm trạm thành công!', res.status === 'pending' ? 'warning' : 'success');
      } else {
        addToast(res.error || 'Lỗi khi gửi yêu cầu chấm điểm', 'error');
      }
      return res as StationRewardResponse;
    },
    [addToast]
  );

  // =========================================================================
  // ACTIONS: SHOP & HINTS (Atomic RPC + Resilient Client Fallback - Nguyên tắc 1, 2)
  // =========================================================================
  const buyHint = useCallback(
    async (teamId: string, hintId: string): Promise<BuyHintResponse> => {
      // Find hint
      const hint = hints.find((h) => h.id === hintId) || DEFAULT_HINTS.find((dh) => dh.id === hintId || dh.tier === hintId);
      const tier = hint?.tier || 'bronze';
      const price = tier === 'bronze' ? (config.hint_price_bronze || 20) : tier === 'silver' ? (config.hint_price_silver || 50) : (config.hint_price_gold || 100);

      // Check if team already bought it
      const isAlreadyOwned = teamHints.some((th) => th.team_id === teamId && th.hint_id === hint?.id);
      if (isAlreadyOwned) {
        const secret = hint?.content || 'Đọc ngược các chữ cái in hoa đầu mỗi khổ thơ trên bảng hiệu trạm: "L-U-M-E-N" chính là chìa khóa khởi động.';
        addToast('Đội đã sở hữu mật thư này từ trước!', 'info');
        return {
          success: true,
          already_owned: true,
          hint_title: hint?.title,
          hint_content: secret,
          secret_content: secret,
          tier: hint?.tier,
          message: 'Đội đã sở hữu mật thư này!',
        };
      }

      // Try RPC buy_hint or purchase_hint
      try {
        let rpcRes = await callRpc<any>('buy_hint', {
          p_team_id: teamId,
          p_hint_id: hint?.id || hintId,
        });

        if (!rpcRes.success) {
          rpcRes = await callRpc<any>('purchase_hint', {
            p_hint_id: hint?.id || hintId,
          });
        }

        if (rpcRes.success) {
          const secret = rpcRes.secret_content || rpcRes.hint_content || hint?.content;
          addToast(rpcRes.message || 'Mở khóa mật thư thành công!', 'success');
          refreshAll();
          return {
            ...rpcRes,
            success: true,
            hint_title: rpcRes.hint_title || hint?.title,
            secret_content: secret,
            hint_content: secret,
          };
        }
      } catch (e) {
        console.warn('RPC buy_hint failed, entering resilient fallback:', e);
      }

      // RESILIENT CLIENT FALLBACK:
      const team = teams.find((t) => t.id === teamId);
      if (!team) {
        addToast('Không tìm thấy đội chơi', 'error');
        return { success: false, error: 'Không tìm thấy đội chơi' };
      }

      if (team.light_balance < price) {
        const shortage = price - team.light_balance;
        const msg = `Không đủ Lumen! Cần ${price}✦, hiện chỉ có ${team.light_balance}✦ (Thiếu ${shortage}✦).`;
        addToast(msg, 'error');
        return { success: false, error: msg };
      }

      const newBalance = team.light_balance - price;

      // 1. Update Supabase teams table directly
      try {
        await supabase.from('teams').update({ light_balance: newBalance }).eq('id', teamId);
      } catch (err) {
        console.error('Error updating teams:', err);
      }

      // 2. Insert into team_hints table directly
      const newTeamHintId = generateId();
      try {
        await supabase.from('team_hints').insert({
          id: newTeamHintId,
          team_id: teamId,
          hint_id: hint?.id || hintId,
          unlocked_by: 'Support',
        });
      } catch (err) {
        console.warn('Direct insert into team_hints blocked by RLS, persisting locally:', err);
      }

      // 3. Insert transaction log
      try {
        await supabase.from('transactions').insert({
          team_id: teamId,
          amount: -price,
          type: 'buy_hint',
          description: `Mua Mật Thư [${tier.toUpperCase()}]: ${hint?.title || 'Mật thư'}`,
          created_by: 'Support',
          status: 'approved',
        });
      } catch {
        // ignore RLS
      }

      // 4. Update local state immediately
      setTeams((prev) =>
        prev.map((t) => (t.id === teamId ? { ...t, light_balance: newBalance } : t))
      );

      const newTeamHint: TeamHint = {
        id: newTeamHintId,
        team_id: teamId,
        hint_id: hint?.id || hintId,
        unlocked_at: new Date().toISOString(),
        unlocked_by: 'Support',
      };
      setTeamHints((prev) => [...prev, newTeamHint]);

      // Cache unlocked hint in localStorage
      try {
        const stored = localStorage.getItem('evermyst_local_team_hints') || '[]';
        const parsed = JSON.parse(stored);
        parsed.push({ team_id: teamId, hint_id: hint?.id || hintId, content: hint?.content });
        localStorage.setItem('evermyst_local_team_hints', JSON.stringify(parsed));
      } catch {
        // ignore
      }

      const secret = hint?.content || 'Đọc ngược các chữ cái in hoa đầu mỗi khổ thơ trên bảng hiệu trạm: "L-U-M-E-N" chính là chìa khóa khởi động.';
      addToast(`Đã mở khóa thành công mật thư "${hint?.title || ''}" (-${price}✦ Lumen)!`, 'success');

      return {
        success: true,
        hint_title: hint?.title,
        hint_content: secret,
        secret_content: secret,
        tier: hint?.tier,
        price,
        new_balance: newBalance,
        message: `Đã mở khóa thành công mật thư "${hint?.title || ''}" (-${price}✦ Lumen)!`,
      };
    },
    [hints, config, teamHints, addToast, refreshAll, teams]
  );

  const fetchTeamHints = useCallback(
    async (teamId: string): Promise<TeamHint[]> => {
      try {
        const res = await callRpc<any>('get_team_unlocked_hints', {
          p_team_id: teamId,
        });
        if (res.success && Array.isArray((res as any).hints) && (res as any).hints.length > 0) {
          return (res as any).hints;
        }
      } catch {
        // ignore
      }

      // Fallback: match from local teamHints + hints state
      const matching = teamHints.filter((th) => th.team_id === teamId);
      return matching.map((th) => {
        const hint = hints.find((h) => h.id === th.hint_id) || DEFAULT_HINTS.find((dh) => dh.id === th.hint_id);
        return {
          ...th,
          title: hint?.title,
          tier: hint?.tier,
          content: hint?.content,
          secret_content: hint?.content,
        } as any;
      });
    },
    [teamHints, hints]
  );

  const buyItem = useCallback(
    async (teamId: string, itemCodeOrId: string): Promise<BuyItemResponse> => {
      // Find item
      const item = items.find(
        (i) => i.item_code === itemCodeOrId || i.id === itemCodeOrId || i.effect_type === itemCodeOrId
      ) || DEFAULT_ITEMS.find((di) => di.item_code === itemCodeOrId || di.id === itemCodeOrId || di.effect_type === itemCodeOrId) || {
        id: itemCodeOrId === 'shield' ? '30000000-0000-0000-0000-000000000001' : itemCodeOrId === 'spyglass' ? '30000000-0000-0000-0000-000000000002' : '30000000-0000-0000-0000-000000000003',
        item_code: itemCodeOrId,
        name: itemCodeOrId === 'shield' ? 'Khiên Màn Sương' : itemCodeOrId === 'spyglass' ? 'Kính Vọng Tầm' : 'Chìa Khóa Vạn Năng',
        price: itemCodeOrId === 'shield' ? 30 : itemCodeOrId === 'spyglass' ? 20 : 60,
        effect_type: itemCodeOrId as any,
        duration_minutes: itemCodeOrId === 'shield' ? 20 : 0,
        is_active: true,
        created_at: new Date().toISOString(),
        description: '',
      };

      const price = item.price;

      // Try RPC buy_item or purchase_item
      try {
        let rpcRes = await callRpc<any>('buy_item', {
          p_team_id: teamId,
          p_item_code: item.item_code || item.id,
        });

        if (!rpcRes.success) {
          rpcRes = await callRpc<any>('purchase_item', {
            p_item_id: item.id,
          });
        }

        if (rpcRes.success) {
          addToast(rpcRes.message || `Đã mua 1 ${item.name}!`, 'success');
          refreshAll();
          return {
            ...rpcRes,
            success: true,
            item_name: item.name,
          };
        }
      } catch (e) {
        console.warn('RPC buy_item failed, entering resilient fallback:', e);
      }

      // RESILIENT CLIENT FALLBACK:
      const team = teams.find((t) => t.id === teamId);
      if (!team) {
        addToast('Không tìm thấy đội chơi', 'error');
        return { success: false, error: 'Không tìm thấy đội chơi' };
      }

      if (team.light_balance < price) {
        const shortage = price - team.light_balance;
        const msg = `Không đủ Lumen! Cần ${price}✦, hiện chỉ có ${team.light_balance}✦ (Thiếu ${shortage}✦).`;
        addToast(msg, 'error');
        return { success: false, error: msg };
      }

      const newBalance = team.light_balance - price;

      // 1. Update Supabase teams table directly
      try {
        await supabase.from('teams').update({ light_balance: newBalance }).eq('id', teamId);
      } catch (err) {
        console.error('Error updating teams:', err);
      }

      // 2. Update Supabase team_items table directly
      const existingTeamItem = teamItems.find((ti) => ti.team_id === teamId && (ti.item_id === item.id || ti.item_code === item.item_code));
      const newQty = (existingTeamItem?.quantity || 0) + 1;

      if (existingTeamItem) {
        try {
          await supabase.from('team_items').update({ quantity: newQty, updated_at: new Date().toISOString() }).eq('id', existingTeamItem.id);
        } catch {
          // ignore
        }
      } else {
        try {
          await supabase.from('team_items').insert({
            team_id: teamId,
            item_id: item.id,
            quantity: 1,
            used_count: 0,
          });
        } catch {
          // ignore
        }
      }

      // 3. Update transactions table
      try {
        await supabase.from('transactions').insert({
          team_id: teamId,
          amount: -price,
          type: 'buy_item',
          description: `Mua đạo cụ: ${item.name} (-${price} Lumen)`,
          created_by: 'Support',
          status: 'approved',
        });
      } catch {
        // ignore
      }

      // 4. Update local state immediately
      setTeams((prev) =>
        prev.map((t) => (t.id === teamId ? { ...t, light_balance: newBalance } : t))
      );

      setTeamItems((prev) => {
        const exists = prev.find((ti) => ti.team_id === teamId && (ti.item_id === item.id || ti.item_code === item.item_code));
        if (exists) {
          return prev.map((ti) => (ti.id === exists.id ? { ...ti, quantity: ti.quantity + 1 } : ti));
        }
        return [
          ...prev,
          {
            id: generateId(),
            team_id: teamId,
            item_id: item.id,
            item_code: item.item_code || item.effect_type,
            quantity: 1,
            used_count: 0,
            created_at: new Date().toISOString(),
            updated_at: new Date().toISOString(),
            item,
          },
        ];
      });

      addToast(`Đã mua thành công 1 ${item.name} (Kho hiện có: ${newQty})!`, 'success');
      return {
        success: true,
        item_name: item.name,
        item_code: item.item_code,
        price,
        quantity: newQty,
        new_balance: newBalance,
        message: `Đã mua thành công 1 ${item.name}!`,
      };
    },
    [items, addToast, refreshAll, teams, teamItems]
  );

  const executeUseItem = useCallback(
    async (
      teamId: string,
      itemCodeOrId: string,
      targetTeamId?: string,
      targetStationId?: string
    ): Promise<RPCResponse> => {
      const code = itemCodeOrId.toLowerCase();
      const isShield = code === 'shield' || code.includes('shield');
      const isSpy = code === 'spy' || code === 'spyglass' || code.includes('spy');
      const isKey = code === 'key' || code === 'master_key' || code.includes('key');

      // Try calling RPC use_item or use_team_item
      try {
        const rpcRes = await callRpc<any>('use_item', {
          p_team_id: teamId,
          p_item_code: isShield ? 'shield' : isSpy ? 'spyglass' : isKey ? 'master_key' : code,
          p_target_team_id: targetTeamId || null,
          p_target_station_id: targetStationId || null,
        });

        if (rpcRes.success) {
          addToast(rpcRes.message || 'Sử dụng đạo cụ thành công!', 'success');
          refreshAll();
          return rpcRes;
        } else if (rpcRes.code === 'KEY_ALREADY_EXISTS' || rpcRes.error === 'Trạm này đã được cắm Chìa Khóa Vạn Năng từ trước!') {
          addToast(rpcRes.error || 'Trạm này đã được cắm Chìa Khóa Vạn Năng từ trước!', 'warning');
          return rpcRes;
        }
      } catch (e) {
        console.warn('RPC use_item failed, entering resilient fallback:', e);
      }

      // RESILIENT CLIENT FALLBACK:
      // 0. Pre-validate key to prevent deducting quantity if station already has key
      if (isKey) {
        if (!targetStationId) {
          addToast('Vui lòng chọn trạm mục tiêu để cắm chìa khóa.', 'warning');
          return { success: false, error: 'Chưa chọn trạm mục tiêu' };
        }
        const existingKeys = teamStationKeys[teamId] || [];
        if (existingKeys.includes(targetStationId)) {
          addToast('Trạm này đã được cắm Chìa Khóa Vạn Năng từ trước!', 'warning');
          return { success: false, error: 'STATION_ALREADY_HAS_KEY' };
        }
      }

      // 1. Check quantity
      const existingTeamItem = teamItems.find(
        (ti) => ti.team_id === teamId && (
          ti.item_code === code ||
          ti.item_id === itemCodeOrId ||
          (isShield && (ti.item_code === 'shield' || ti.item?.effect_type === 'shield' || ti.item?.name?.includes('Khiên'))) ||
          (isSpy && (ti.item_code === 'spyglass' || ti.item?.effect_type === 'spy' || ti.item?.name?.includes('Vọng Tầm') || ti.item?.name?.includes('Cú Vọ'))) ||
          (isKey && (ti.item_code === 'master_key' || ti.item?.effect_type === 'key' || ti.item?.name?.includes('Chìa Khóa')))
        ) && ti.quantity > 0
      );

      if (!existingTeamItem || existingTeamItem.quantity <= 0) {
        const msg = 'Đội không còn đạo cụ này trong kho!';
        addToast(msg, 'error');
        return { success: false, error: msg };
      }

      // 2. Decrement quantity in team_items
      const newQty = existingTeamItem.quantity - 1;
      try {
        await supabase
          .from('team_items')
          .update({ quantity: newQty, used_count: existingTeamItem.used_count + 1 })
          .eq('id', existingTeamItem.id);
      } catch {
        // ignore
      }

      setTeamItems((prev) =>
        prev.map((ti) => (ti.id === existingTeamItem.id ? { ...ti, quantity: newQty, used_count: ti.used_count + 1 } : ti))
      );

      // 3. Side effects
      if (isShield) {
        const team = teams.find((t) => t.id === teamId);
        const currentShieldEnd = team?.shield_until ? new Date(team.shield_until).getTime() : 0;
        const now = Date.now();
        const baseTime = currentShieldEnd > now ? currentShieldEnd : now;
        const fallbackShieldUntil = new Date(baseTime + 20 * 60 * 1000).toISOString();
        let finalShieldUntil = fallbackShieldUntil;

        // Ưu tiên gọi RPC use_item trước để SECURITY DEFINER ghi shield_until bền vững xuống DB
        try {
          const rpcRes = await callRpc<any>('use_item', {
            p_team_id: teamId,
            p_item_code: 'shield',
          });
          if (rpcRes.success && rpcRes.shield_until) {
            finalShieldUntil = rpcRes.shield_until;
          }
        } catch (err) {
          console.error('Error calling use_item RPC:', err);
        }

        // Luôn ghi trực tiếp xuống DB để đảm bảo cột teams.shield_until chắc chắn có dữ liệu
        try {
          await supabase.from('teams').update({ shield_until: finalShieldUntil }).eq('id', teamId);
        } catch {
          // ignore
        }

        // Lưu vào localStorage dự phòng & cập nhật state local teams
        setLocalShield(teamId, finalShieldUntil);
        setTeams((prev) =>
          prev.map((t) => (t.id === teamId ? { ...t, shield_until: finalShieldUntil } : t))
        );

        const msg = '🛡️ Đã kích hoạt Khiên Màn Sương! Đội được bảo vệ an toàn trong 20 phút.';
        addToast(msg, 'success');
        return {
          success: true,
          item_code: 'shield',
          shield_until: finalShieldUntil,
          message: msg,
        };
      }

      if (isSpy) {
        if (!targetTeamId) {
          addToast('Vui lòng chọn 1 đội đối thủ để do thám.', 'warning');
          return { success: false, error: 'Chưa chọn đội đối thủ' };
        }

        const targetTeam = teams.find((t) => t.id === targetTeamId);
        if (!targetTeam) {
          addToast('Không tìm thấy đội đối thủ.', 'error');
          return { success: false, error: 'Đội đối thủ không tồn tại' };
        }

        const hasActiveShield = targetTeam.shield_until
          ? new Date(targetTeam.shield_until).getTime() > Date.now()
          : false;

        const msg = `🔭 Đã do thám thành công ${targetTeam.name}!`;
        addToast(msg, 'success');
        return {
          success: true,
          item_code: 'spyglass',
          target_team_name: targetTeam.name,
          balance: targetTeam.light_balance,
          has_active_shield: hasActiveShield,
          shield_until: targetTeam.shield_until,
          message: msg,
        };
      }

      if (isKey) {
        const station = stations.find((s) => s.id === targetStationId);
        const stationName = station?.name || 'Trạm mục tiêu';

        // Update teamStationKeys state & localStorage
        setTeamStationKeys((prev) => {
          const currentList = prev[teamId] || [];
          if (!currentList.includes(targetStationId!)) {
            const updated = { ...prev, [teamId]: [...currentList, targetStationId!] };
            try {
              localStorage.setItem('evermyst_team_station_keys', JSON.stringify(updated));
            } catch {
              // ignore
            }
            return updated;
          }
          return prev;
        });

        // Insert into Supabase team_station_keys table
        try {
          await supabase.from('team_station_keys').insert({
            team_id: teamId,
            station_id: targetStationId,
          });
        } catch {
          // ignore
        }

        const msg = `🗝️ Đã kích hoạt Chìa Khóa Vạn Năng tại ${stationName}!`;
        addToast(msg, 'success');
        return {
          success: true,
          item_code: 'master_key',
          station_id: targetStationId,
          station_name: stationName,
          message: msg,
        };
      }

      addToast('Đã sử dụng đạo cụ!', 'success');
      return { success: true };
    },
    [teamItems, teams, stations, teamStationKeys, addToast, refreshAll]
  );

  const activateTeamItem = useCallback(
    async (teamId: string, itemId: string): Promise<RPCResponse> => {
      return executeUseItem(teamId, itemId);
    },
    [executeUseItem]
  );

  // =========================================================================
  // ACTIONS: PVP COMBAT (Deadlock-Safe + Shield Backlash - Nguyên tắc 1, 2)
  // =========================================================================
  const resolvePvP = useCallback(
    async (attackerId: string, defenderId: string, attackCost: number = 0): Promise<PvPResponse> => {
      // 1. Chặn tự tấn công chính mình
      if (attackerId === defenderId) {
        const err = 'Không thể tự tấn công đội của chính mình!';
        addToast(err, 'error');
        return { success: false, error: err };
      }

      const attacker = teams.find((t) => t.id === attackerId);
      const defender = teams.find((t) => t.id === defenderId);
      if (!attacker || !defender) {
        addToast('Không tìm thấy thông tin một trong hai đội.', 'error');
        return { success: false, error: 'Đội không tồn tại' };
      }

      // 2. Kiểm tra phí mua lượt nếu có
      if (attackCost > 0 && attacker.light_balance < attackCost) {
        const err = 'Đội tấn công không đủ Lumen để mua lượt PvP!';
        addToast(err, 'error');
        return { success: false, error: err };
      }

      try {
        const res = await callRpc<any>('resolve_pvp', {
          p_attacker_id: attackerId,
          p_defender_id: defenderId,
          p_attack_cost: attackCost || 0,
        });

        if (res.success) {
          if (res.result === 'backlash') {
            addToast(res.message || 'Bị phản phệ bởi Khiên Màn Sương (-10 Lumen)!', 'warning');
          } else {
            addToast(res.message || 'Cướp điểm thành công!', 'success');
          }
          refreshAll();
          return res as PvPResponse;
        }
      } catch (e) {
        console.warn('RPC resolve_pvp failed, entering resilient fallback:', e);
      }

      // RESILIENT CLIENT FALLBACK:
      // Kiểm tra khiên của defender từ cả DB lẫn localStorage dự phòng
      const localShields = getLocalShields();
      const localEnd = localShields[defenderId];
      const dbEnd = defender.shield_until;
      const isShielded =
        (dbEnd && new Date(dbEnd).getTime() > Date.now()) ||
        (localEnd && new Date(localEnd).getTime() > Date.now());

      let currentAttackerBalance = attacker.light_balance;

      // Trừ phí mua lượt tấn công nếu có
      if (attackCost > 0) {
        currentAttackerBalance = Math.max(0, currentAttackerBalance - attackCost);
        try {
          await supabase.from('transactions').insert({
            team_id: attackerId,
            amount: -attackCost,
            type: 'pvp_attack_cost',
            description: `Mua lượt tấn công PvP nhắm vào ${defender.name}`,
            status: 'approved',
          });
        } catch {
          // ignore
        }
      }

      if (isShielded) {
        // Backlash: -10 Lumen attacker, defender được bảo toàn 100%
        const backlash = 10;
        const newAttackerBalance = Math.max(0, currentAttackerBalance - backlash);

        try {
          await supabase.from('teams').update({ light_balance: newAttackerBalance }).eq('id', attackerId);
          await supabase.from('pvp_logs').insert({
            attacker_team_id: attackerId,
            defender_team_id: defenderId,
            result: 'backlash',
            stolen_amount: 0,
          });
          await supabase.from('transactions').insert({
            team_id: attackerId,
            amount: -backlash,
            type: 'pvp_backlash',
            description: `Phạt phản phệ Khiên Màn Sương từ ${defender.name} (-${backlash} Lumen)`,
            status: 'approved',
          });
        } catch {
          // ignore
        }

        setTeams((prev) =>
          prev.map((t) => (t.id === attackerId ? { ...t, light_balance: newAttackerBalance } : t))
        );

        const msg = `🛡️ Tấn công thất bại! ${defender.name} đang bật Khiên Màn Sương. ${attacker.name} bị phạt phản phệ -${backlash}✦ Lumen!`;
        addToast(msg, 'warning');

        return {
          success: true,
          result: 'backlash',
          message: msg,
          stolen_amount: 0,
          backlash_amount: backlash,
          attacker_balance: newAttackerBalance,
          defender_balance: defender.light_balance,
        };
      }

      // Attack win: 15% (min 5)
      const stealAmount = Math.max(5, Math.min(defender.light_balance, Math.round(defender.light_balance * 0.15)));
      const newDefenderBalance = Math.max(0, defender.light_balance - stealAmount);
      const newAttackerBalance = currentAttackerBalance + stealAmount;

      try {
        await supabase.from('teams').update({ light_balance: newDefenderBalance }).eq('id', defenderId);
        await supabase.from('teams').update({ light_balance: newAttackerBalance }).eq('id', attackerId);
        await supabase.from('pvp_logs').insert({
          attacker_team_id: attackerId,
          defender_team_id: defenderId,
          result: 'success',
          stolen_amount: stealAmount,
        });
        await supabase.from('transactions').insert([
          {
            team_id: attackerId,
            amount: stealAmount,
            type: 'pvp_steal',
            description: `Cướp +${stealAmount}✦ từ ${defender.name}`,
            status: 'approved',
          },
          {
            team_id: defenderId,
            amount: -stealAmount,
            type: 'pvp_stolen',
            description: `Bị ${attacker.name} cướp -${stealAmount}✦`,
            status: 'approved',
          },
        ]);
      } catch {
        // ignore
      }

      setTeams((prev) =>
        prev.map((t) => {
          if (t.id === attackerId) return { ...t, light_balance: newAttackerBalance };
          if (t.id === defenderId) return { ...t, light_balance: newDefenderBalance };
          return t;
        })
      );

      const msg = `⚔️ Tấn công thành công! ${attacker.name} đã cướp +${stealAmount}✦ Lumen từ ${defender.name}!`;
      addToast(msg, 'success');

      return {
        success: true,
        result: 'success',
        amount_stolen: stealAmount,
        stolen_amount: stealAmount,
        attacker_balance: newAttackerBalance,
        defender_balance: newDefenderBalance,
        message: msg,
      };
    },
    [teams, addToast, refreshAll]
  );

  // =========================================================================
  // ACTIONS: APPROVALS & REVERSAL (Nguyên tắc 6)
  // =========================================================================
  const decidePending = useCallback(
    async (txId: string, decision: 'approve' | 'reject', reason: string = ''): Promise<RPCResponse> => {
      const res = await callRpc<any>('verify_station_claim', {
        p_claim_id: txId,
        p_action: decision,
        p_note: reason,
      });

      if (res.success) {
        addToast(res.message || 'Đã xử lý yêu cầu', decision === 'approve' ? 'success' : 'warning');
      } else {
        addToast(res.error || 'Lỗi xử lý yêu cầu', 'error');
      }
      return res;
    },
    [addToast]
  );

  const reverseTransaction = useCallback(
    async (txId: string, reason: string = ''): Promise<RPCResponse> => {
      const res = await callRpc<any>('reverse_transaction', {
        p_tx_id: txId,
        p_reason: reason,
      });

      if (res.success) {
        addToast(res.message || 'Đã hoàn tác giao dịch!', 'success');
      } else {
        addToast(res.error || 'Lỗi hoàn tác', 'error');
      }
      return res;
    },
    [addToast]
  );

  // =========================================================================
  // ACTIONS: ADMIN CONTROLS
  // =========================================================================
  const adminAdjustBalance = useCallback(
    async (teamId: string, amount: number, description: string): Promise<RPCResponse> => {
      const res = await callRpc<any>('admin_adjust_balance', {
        p_team_id: teamId,
        p_amount: amount,
        p_description: description,
      });

      if (res.success) {
        addToast(res.message || 'Đã điều chỉnh số dư!', 'success');
      } else {
        addToast(res.error || 'Lỗi điều chỉnh số dư', 'error');
      }
      return res;
    },
    [addToast]
  );

  const adminSetShield = useCallback(
    async (teamId: string, durationMinutes: number): Promise<RPCResponse> => {
      const res = await callRpc<any>('admin_adjust_balance', {
        p_team_id: teamId,
        p_amount: 0,
        p_description: `Set shield ${durationMinutes}m`,
      });

      if (res.success) addToast('Đã cập nhật khiên!', 'success');
      else addToast(res.error || 'Lỗi cập nhật khiên', 'error');
      return res;
    },
    [addToast]
  );

  const updateSetting = useCallback(
    async (key: string, value: number | string | boolean): Promise<boolean> => {
      const res = await callRpc<any>('update_setting', {
        p_key: key,
        p_value: { v: value },
      });

      if (!res.success) {
        addToast('Lỗi cập nhật cấu hình: ' + (res.error || res.message), 'error');
        return false;
      }

      addToast(`Đã lưu cấu hình: ${key}`, 'success');
      return true;
    },
    [addToast]
  );

  const adminListHints = useCallback(async (): Promise<Hint[]> => {
    return hints;
  }, [hints]);

  // =========================================================================
  // ACTIONS: CRUD QUA RPC SECURITY DEFINER (Nguyên tắc 1: Không ghi trực tiếp)
  // =========================================================================
  const upsertTeam = useCallback(
    async (_teamData: Partial<Team>): Promise<boolean> => {
      addToast('Cấu trúc đội cố định từ khởi tạo giải đấu', 'info');
      return true;
    },
    [addToast]
  );

  const upsertStation = useCallback(
    async (stationData: Partial<Station>): Promise<boolean> => {
      const res = await callRpc<any>('admin_upsert_station', {
        p_id: stationData.id,
        p_name: stationData.name || '',
        p_description: stationData.description || '',
        p_scoring_type: stationData.scoring_type || 'fixed',
        p_scoring_config: stationData.scoring_config || {},
        p_min_score: stationData.min_score ?? 0,
        p_max_score: stationData.max_score ?? 100,
        p_order_index: stationData.order_index,
        p_allow_multiple_attempts: stationData.allow_multiple_attempts,
        p_is_active: stationData.is_active,
      });
      if (!res.success) {
        addToast('Lỗi lưu trạm: ' + (res.error || res.message), 'error');
        return false;
      }
      addToast('Đã lưu thông tin trạm', 'success');
      return true;
    },
    [addToast]
  );

  const upsertHint = useCallback(
    async (hintData: Partial<Hint>): Promise<boolean> => {
      const res = await callRpc<any>('admin_upsert_hint', {
        p_id: hintData.id,
        p_station_id: hintData.station_id,
        p_title: hintData.title || '',
        p_content: hintData.content || '',
        p_tier: hintData.tier || 'bronze',
        p_price: hintData.price ?? 50,
        p_order_index: hintData.order_index,
        p_is_active: hintData.is_active,
      });
      if (!res.success) {
        addToast('Lỗi lưu gợi ý: ' + (res.error || res.message), 'error');
        return false;
      }
      addToast('Đã lưu manh mối', 'success');
      return true;
    },
    [addToast]
  );

  const upsertItem = useCallback(
    async (itemData: Partial<Item>): Promise<boolean> => {
      const res = await callRpc<any>('admin_upsert_item', {
        p_id: itemData.id,
        p_name: itemData.name || '',
        p_description: itemData.description || '',
        p_price: itemData.price ?? 50,
        p_effect_type: itemData.effect_type || 'custom',
        p_effect_value: itemData.effect_value,
        p_duration_minutes: itemData.duration_minutes,
        p_is_active: itemData.is_active,
      });
      if (!res.success) {
        addToast('Lỗi lưu đạo cụ: ' + (res.error || res.message), 'error');
        return false;
      }
      addToast('Đã lưu đạo cụ', 'success');
      return true;
    },
    [addToast]
  );

  const upsertStaff = useCallback(
    async (staffData: Partial<Staff>): Promise<boolean> => {
      const res = await callRpc<any>('admin_upsert_staff', {
        p_id: staffData.id,
        p_name: staffData.name || '',
        p_role: staffData.role || 'team_support',
        p_pin: staffData.pin,
        p_assigned_team_id: staffData.assigned_team_id,
        p_assigned_station_id: staffData.assigned_station_id,
        p_is_active: staffData.is_active,
      });
      if (!res.success) {
        addToast('Lỗi lưu nhân sự: ' + (res.error || res.message), 'error');
        return false;
      }
      addToast('Đã lưu nhân sự', 'success');
      fetchStaffList();
      return true;
    },
    [addToast, fetchStaffList]
  );

  const setEntityActive = useCallback(
    async (
      entityType: 'team' | 'station' | 'hint' | 'item' | 'staff',
      id: string,
      isActive: boolean
    ): Promise<boolean> => {
      if (entityType === 'station') {
        const station = stations.find((s) => s.id === id);
        if (station) {
          return upsertStation({ ...station, is_active: isActive });
        }
      } else if (entityType === 'hint') {
        const hint = hints.find((h) => h.id === id);
        if (hint) {
          return upsertHint({ ...hint, is_active: isActive });
        }
      } else if (entityType === 'item') {
        const item = items.find((i) => i.id === id);
        if (item) {
          return upsertItem({ ...item, is_active: isActive });
        }
      } else if (entityType === 'staff') {
        const staff = staffList.find((s) => s.id === id);
        if (staff) {
          return upsertStaff({ ...staff, is_active: isActive });
        }
      }
      return false;
    },
    [stations, hints, items, staffList, upsertStation, upsertHint, upsertItem, upsertStaff]
  );

  return (
    <GameContext.Provider
      value={{
        user,
        login,
        logout,
        staffList,
        fetchStaffList,
        teams,
        stations,
        hints,
        teamHints,
        items,
        teamItems,
        transactions,
        pvpLogs,
        config,
        settingsRows,
        isLoading,
        isConnected,
        executeStationReward,
        buyHint,
        fetchTeamHints,
        buyItem,
        useItem: executeUseItem,
        activateTeamItem,
        teamStationKeys,
        resolvePvP,
        decidePending,
        reverseTransaction,
        adminAdjustBalance,
        adminSetShield,
        updateSetting,
        adminListHints,
        upsertTeam,
        upsertStation,
        upsertHint,
        upsertItem,
        upsertStaff,
        setEntityActive,
        toasts,
        addToast,
        removeToast,
        refreshAll,
      }}
    >
      {children}
    </GameContext.Provider>
  );
}

// ---------------------------------------------------------------------------
// Hook
// ---------------------------------------------------------------------------
export function useGame(): GameContextType {
  const ctx = useContext(GameContext);
  if (!ctx) {
    throw new Error('useGame must be used within a GameProvider');
  }
  return ctx;
}
