// ============================================================================
// SHOP TAB - Cửa hàng & Kho Đồ Chiến Thuật (ShopTab.tsx)
// Hiển thị 3 Khu vực: 1. Kho đồ (trên cùng), 2. Cửa hàng Đạo cụ, 3. Mua Manh mối
// Đồng bộ Realtime, Hỗ trợ RPC Atomic Transactions + Resilient Client Fallback
// ============================================================================
import React, { useState, useMemo, useEffect } from 'react';
import { useGame } from '@/contexts/GameContext';
import { DEFAULT_HINTS } from '@/lib/constants';
import {
  Shield,
  Eye,
  Key,
  ShoppingBag,
  Package,
  Scroll,
  Sparkles,
  Lock,
  Unlock,
  CheckCircle2,
  X,
  Loader2,
  AlertTriangle,
  ChevronRight,
  Info,
} from 'lucide-react';
import { getShieldRemaining, getTierInfo } from '@/lib/utils';
import type { Team, Hint, Item } from '@/lib/types';

interface ShopTabProps {
  selectedTeam: Team | null;
}

export default function ShopTab({ selectedTeam }: ShopTabProps) {
  const {
    teams,
    hints,
    items,
    teamHints,
    teamItems,
    stations,
    teamStationKeys,
    buyHint,
    fetchTeamHints,
    buyItem,
    useItem,
  } = useGame();

  // Đảm bảo luôn có đội active kể cả khi selectedTeam ban đầu là null
  const currentTeam = useMemo(() => {
    if (selectedTeam) return selectedTeam;
    return teams.length > 0 ? teams[0] : null;
  }, [selectedTeam, teams]);

  const [isProcessing, setIsProcessing] = useState<boolean>(false);
  const [revealedHint, setRevealedHint] = useState<{
    title: string;
    content: string;
    tier: string;
  } | null>(null);

  // Modal State cho Kính Vọng Tầm (Spyglass)
  const [isSpyModalOpen, setIsSpyModalOpen] = useState(false);
  const [selectedOpponentId, setSelectedOpponentId] = useState<string>('');
  const [spyResult, setSpyResult] = useState<{
    target_team_name: string;
    balance: number;
    has_active_shield: boolean;
    shield_until?: string | null;
  } | null>(null);

  // Modal State cho Chìa Khóa Vạn Năng (Master Key)
  const [isKeyModalOpen, setIsKeyModalOpen] = useState(false);
  const [selectedStationId, setSelectedStationId] = useState<string>('');

  // Re-render mỗi giây để TopBar & Shield Badge đếm ngược realtime
  const [, setTick] = useState(0);
  useEffect(() => {
    const timer = setInterval(() => setTick((t) => t + 1), 1000);
    return () => clearInterval(timer);
  }, []);

  // 1. Trạng thái Khiên hiện tại của đội
  const currentShield = useMemo(() => {
    return getShieldRemaining(currentTeam?.shield_until ?? null);
  }, [currentTeam?.shield_until]);

  // 2. Số lượng từng đạo cụ trong kho đồ đội
  const inventoryCounts = useMemo(() => {
    if (!currentTeam) return { shield: 0, spyglass: 0, master_key: 0 };
    const counts = { shield: 0, spyglass: 0, master_key: 0 };

    teamItems
      .filter((ti) => ti.team_id === currentTeam.id)
      .forEach((ti) => {
        const code = (ti.item_code || ti.item?.item_code || '').toLowerCase();
        const effect = (ti.item?.effect_type || '').toLowerCase();
        const name = (ti.item?.name || '').toLowerCase();

        if (code === 'shield' || effect === 'shield' || name.includes('khiên')) {
          counts.shield += ti.quantity;
        } else if (
          code === 'spyglass' ||
          code === 'spy' ||
          effect === 'spy' ||
          effect === 'spyglass' ||
          name.includes('vọng tầm') ||
          name.includes('cú vọ')
        ) {
          counts.spyglass += ti.quantity;
        } else if (
          code === 'master_key' ||
          code === 'key' ||
          effect === 'key' ||
          effect === 'master_key' ||
          name.includes('chìa khóa')
        ) {
          counts.master_key += ti.quantity;
        }
      });

    return counts;
  }, [teamItems, currentTeam]);

  // 3. Set hint_id mà đội đã mở khóa
  const ownedHintIds = useMemo(() => {
    if (!currentTeam) return new Set<string>();
    return new Set(
      teamHints.filter((th) => th.team_id === currentTeam.id).map((th) => th.hint_id)
    );
  }, [teamHints, currentTeam]);

  // 4. Danh sách các trạm đã cắm Chìa Khóa Vạn Năng
  const activeKeyStationIds = useMemo(() => {
    if (!currentTeam) return [];
    return teamStationKeys[currentTeam.id] || [];
  }, [teamStationKeys, currentTeam]);

  // 5. Đối thủ hợp lệ để do thám (5 đội còn lại)
  const opponentTeams = useMemo(() => {
    if (!currentTeam) return [];
    return teams.filter((t) => t.id !== currentTeam.id && t.is_active);
  }, [teams, currentTeam]);

  // 6. Danh sách 5 trạm chính thức
  const activeStations = useMemo(() => {
    const list: typeof stations = [];
    const seen = new Set<number>();
    stations.forEach((s) => {
      if (!seen.has(s.order_index) && s.is_active) {
        seen.add(s.order_index);
        list.push(s);
      }
    });
    return list.sort((a, b) => a.order_index - b.order_index);
  }, [stations]);

  // ---------------------------------------------------------------------------
  // HANDLERS: SỬ DỤNG ĐẠO CỤ (KHO ĐỒ)
  // ---------------------------------------------------------------------------
  const handleUseShield = async () => {
    if (!currentTeam || isProcessing || inventoryCounts.shield <= 0) return;
    setIsProcessing(true);
    await useItem(currentTeam.id, 'shield');
    setIsProcessing(false);
  };

  const handleOpenSpyModal = () => {
    if (inventoryCounts.spyglass <= 0) return;
    setSpyResult(null);
    if (opponentTeams.length > 0 && !selectedOpponentId) {
      setSelectedOpponentId(opponentTeams[0].id);
    }
    setIsSpyModalOpen(true);
  };

  const handleExecuteSpy = async () => {
    if (!currentTeam || !selectedOpponentId || isProcessing) return;
    setIsProcessing(true);

    const res = await useItem(currentTeam.id, 'spyglass', selectedOpponentId);
    if (res.success) {
      setSpyResult({
        target_team_name: (res as any).target_team_name || 'Đội đối thủ',
        balance: (res as any).balance ?? 0,
        has_active_shield: !!(res as any).has_active_shield,
        shield_until: (res as any).shield_until ?? null,
      });
    }
    setIsProcessing(false);
  };

  const handleOpenKeyModal = () => {
    if (inventoryCounts.master_key <= 0) return;
    if (activeStations.length > 0 && !selectedStationId) {
      setSelectedStationId(activeStations[0].id);
    }
    setIsKeyModalOpen(true);
  };

  const handleExecuteKey = async () => {
    if (!currentTeam || !selectedStationId || isProcessing) return;
    setIsProcessing(true);

    const res = await useItem(currentTeam.id, 'master_key', undefined, selectedStationId);
    if (res.success) {
      setIsKeyModalOpen(false);
    }
    setIsProcessing(false);
  };

  // ---------------------------------------------------------------------------
  // HANDLERS: MUA ĐẠO CỤ
  // ---------------------------------------------------------------------------
  const handleBuyItemAction = async (itemCode: string) => {
    if (!currentTeam || isProcessing) return;
    setIsProcessing(true);
    await buyItem(currentTeam.id, itemCode);
    setIsProcessing(false);
  };

  // ---------------------------------------------------------------------------
  // HANDLERS: MUA & XEM MANH MỐI
  // ---------------------------------------------------------------------------
  const handleBuyHintAction = async (hint: Hint) => {
    if (!currentTeam || isProcessing) return;
    setIsProcessing(true);

    const res = await buyHint(currentTeam.id, hint.id);
    if (res.success) {
      const content = res.secret_content || res.hint_content || hint.content;
      if (content) {
        setRevealedHint({
          title: res.hint_title || hint.title,
          content,
          tier: hint.tier,
        });
      }
    }
    setIsProcessing(false);
  };

  const handleViewHintAction = async (hint: Hint) => {
    if (!currentTeam) return;
    setIsProcessing(true);
    const unlocked = await fetchTeamHints(currentTeam.id);
    const found = unlocked.find((u) => u.hint_id === hint.id);
    setIsProcessing(false);

    const secret =
      (found as any)?.secret_content ||
      (found as any)?.content ||
      hint.content ||
      'Nội dung mật thư đã được giải mã cho đội của bạn.';

    setRevealedHint({
      title: hint.title,
      content: secret,
      tier: hint.tier,
    });
  };

  // Dữ liệu 3 Đạo cụ chuẩn
  const shopItemDefs = [
    {
      code: 'shield',
      name: 'Khiên Màn Sương',
      price: 30,
      icon: <Shield className="w-5 h-5 text-props" />,
      tag: 'Bảo vệ 20 phút',
      desc: 'Kích hoạt bảo vệ đội khỏi tấn công PvP trong 20 phút. Nếu bị đánh lén, kẻ địch bị phạt phản phệ 10 Lumen.',
      qty: inventoryCounts.shield,
    },
    {
      code: 'spyglass',
      name: 'Kính Vọng Tầm',
      price: 20,
      icon: <Eye className="w-5 h-5 text-cyan-400" />,
      tag: 'Do thám đối thủ',
      desc: 'Soi ngay số dư Lumen hiện tại và trạng thái Khiên bảo vệ của 1 đội đối thủ bất kỳ.',
      qty: inventoryCounts.spyglass,
    },
    {
      code: 'master_key',
      name: 'Chìa Khóa Vạn Năng',
      price: 60,
      icon: <Key className="w-5 h-5 text-amber-400" />,
      tag: 'Vượt trạm',
      desc: 'Kích hoạt huy hiệu Chìa Khóa tại trạm mục tiêu, giúp đội vượt qua câu đố khó hoặc mở lối tắt.',
      qty: inventoryCounts.master_key,
    },
  ];

  // 3 Bậc Hint
  const hintTiers = [
    { tier: 'bronze', label: 'Đồng (Bronze)', defaultPrice: 20 },
    { tier: 'silver', label: 'Bạc (Silver)', defaultPrice: 50 },
    { tier: 'gold', label: 'Vàng (Gold)', defaultPrice: 100 },
  ];

  const currentBalance = currentTeam?.light_balance ?? 0;

  return (
    <div className="p-4 space-y-6 pb-28 animate-fadeIn">
      {/* Team Balance Summary Bar */}
      <div className="bg-evermyst-card border border-evermyst-border rounded-2xl p-3.5 flex items-center justify-between shadow-lg">
        <div className="flex items-center gap-2.5">
          <div className="w-10 h-10 rounded-xl bg-lumen/10 border border-lumen/30 flex items-center justify-center text-lumen font-black text-base">
            ✦
          </div>
          <div>
            <div className="text-[10px] font-bold uppercase tracking-wider text-evermyst-text-dim">
              Số Dư Hiện Tại
            </div>
            <div className="text-lg font-black text-white truncate max-w-[170px]">
              {currentTeam?.name || 'Đội chơi'}
            </div>
          </div>
        </div>

        <div className="text-right">
          <div className="text-2xl font-black font-mono text-lumen leading-none">
            {currentBalance}✦
          </div>
          <div className="text-[10px] text-evermyst-text-dim font-bold mt-1">LUMEN KHẢ DỤNG</div>
        </div>
      </div>

      {/* ===================================================================== */}
      {/* KHU VỰC 1: KHO ĐỒ CỦA ĐỘI (INVENTORY) Ở TRÊN CÙNG                    */}
      {/* ===================================================================== */}
      <section className="space-y-3">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2">
            <div className="p-1.5 rounded-lg bg-props/15 text-props border border-props/30">
              <Package className="w-4 h-4" />
            </div>
            <h2 className="text-sm font-black text-white uppercase tracking-wider">
              1. Kho Đồ Của Đội (Inventory)
            </h2>
          </div>
          <span className="text-[11px] font-bold text-props px-2 py-0.5 rounded-full bg-props/10 border border-props/20">
            {inventoryCounts.shield + inventoryCounts.spyglass + inventoryCounts.master_key} vật phẩm
          </span>
        </div>

        <div className="grid grid-cols-1 gap-2.5">
          {/* Card 1: Khiên Màn Sương */}
          <div className="bg-evermyst-card border border-evermyst-border rounded-2xl p-3.5 flex items-center justify-between gap-3 shadow-md">
            <div className="flex items-center gap-3">
              <div className="w-11 h-11 rounded-xl bg-purple-500/15 border border-purple-500/30 flex items-center justify-center shrink-0">
                <Shield className="w-6 h-6 text-purple-400" />
              </div>
              <div className="space-y-0.5">
                <div className="flex items-center gap-2">
                  <h3 className="text-sm font-bold text-white">Khiên Màn Sương</h3>
                  <span
                    className={`text-xs font-black px-2 py-0.5 rounded-lg font-mono ${
                      inventoryCounts.shield > 0
                        ? 'bg-purple-500/20 text-purple-300 border border-purple-500/40'
                        : 'bg-evermyst-surface text-evermyst-text-dim'
                    }`}
                  >
                    x{inventoryCounts.shield}
                  </span>
                </div>
                <div className="text-xs text-evermyst-text-dim">
                  {currentShield.active ? (
                    <span className="text-purple-300 font-bold flex items-center gap-1">
                      <span className="w-1.5 h-1.5 rounded-full bg-purple-400 animate-pulse" />
                      Đang bật: còn {currentShield.label}
                    </span>
                  ) : (
                    <span>Bảo vệ đội khỏi cướp PvP (20 phút)</span>
                  )}
                </div>
              </div>
            </div>

            <button
              onClick={handleUseShield}
              disabled={inventoryCounts.shield <= 0 || isProcessing}
              className={`shrink-0 px-3.5 py-2.5 rounded-xl font-bold text-xs flex items-center gap-1.5 transition-all ${
                inventoryCounts.shield > 0
                  ? 'bg-gradient-to-r from-purple-600 to-indigo-600 text-white shadow-lg shadow-purple-500/20 active:scale-95 hover:brightness-110'
                  : 'bg-evermyst-surface text-evermyst-text-dim border border-evermyst-border cursor-not-allowed'
              }`}
            >
              {isProcessing ? (
                <Loader2 className="w-3.5 h-3.5 animate-spin" />
              ) : (
                <Shield className="w-3.5 h-3.5" />
              )}
              {inventoryCounts.shield > 0 ? 'KÍCH HOẠT (+20P)' : 'Chưa có'}
            </button>
          </div>

          {/* Card 2: Kính Vọng Tầm */}
          <div className="bg-evermyst-card border border-evermyst-border rounded-2xl p-3.5 flex items-center justify-between gap-3 shadow-md">
            <div className="flex items-center gap-3">
              <div className="w-11 h-11 rounded-xl bg-cyan-500/15 border border-cyan-500/30 flex items-center justify-center shrink-0">
                <Eye className="w-6 h-6 text-cyan-400" />
              </div>
              <div className="space-y-0.5">
                <div className="flex items-center gap-2">
                  <h3 className="text-sm font-bold text-white">Kính Vọng Tầm</h3>
                  <span
                    className={`text-xs font-black px-2 py-0.5 rounded-lg font-mono ${
                      inventoryCounts.spyglass > 0
                        ? 'bg-cyan-500/20 text-cyan-300 border border-cyan-500/40'
                        : 'bg-evermyst-surface text-evermyst-text-dim'
                    }`}
                  >
                    x{inventoryCounts.spyglass}
                  </span>
                </div>
                <div className="text-xs text-evermyst-text-dim">
                  Soi số dư & trạng thái khiên 1 đối thủ
                </div>
              </div>
            </div>

            <button
              onClick={handleOpenSpyModal}
              disabled={inventoryCounts.spyglass <= 0 || isProcessing}
              className={`shrink-0 px-3.5 py-2.5 rounded-xl font-bold text-xs flex items-center gap-1.5 transition-all ${
                inventoryCounts.spyglass > 0
                  ? 'bg-gradient-to-r from-cyan-600 to-blue-600 text-white shadow-lg shadow-cyan-500/20 active:scale-95 hover:brightness-110'
                  : 'bg-evermyst-surface text-evermyst-text-dim border border-evermyst-border cursor-not-allowed'
              }`}
            >
              <Eye className="w-3.5 h-3.5" />
              {inventoryCounts.spyglass > 0 ? 'SOI ĐỐI THỦ' : 'Chưa có'}
            </button>
          </div>

          {/* Card 3: Chìa Khóa Vạn Năng */}
          <div className="bg-evermyst-card border border-evermyst-border rounded-2xl p-3.5 flex items-center justify-between gap-3 shadow-md">
            <div className="flex items-center gap-3">
              <div className="w-11 h-11 rounded-xl bg-amber-500/15 border border-amber-500/30 flex items-center justify-center shrink-0">
                <Key className="w-6 h-6 text-amber-400" />
              </div>
              <div className="space-y-0.5">
                <div className="flex items-center gap-2">
                  <h3 className="text-sm font-bold text-white">Chìa Khóa Vạn Năng</h3>
                  <span
                    className={`text-xs font-black px-2 py-0.5 rounded-lg font-mono ${
                      inventoryCounts.master_key > 0
                        ? 'bg-amber-500/20 text-amber-300 border border-amber-500/40'
                        : 'bg-evermyst-surface text-evermyst-text-dim'
                    }`}
                  >
                    x{inventoryCounts.master_key}
                  </span>
                </div>
                <div className="text-xs text-evermyst-text-dim">
                  {activeKeyStationIds.length > 0 ? (
                    <span className="text-amber-300 font-bold">
                      Đã cắm tại {activeKeyStationIds.length} trạm
                    </span>
                  ) : (
                    <span>Cắm vào trạm mục tiêu để vượt trạm</span>
                  )}
                </div>
              </div>
            </div>

            <button
              onClick={handleOpenKeyModal}
              disabled={inventoryCounts.master_key <= 0 || isProcessing}
              className={`shrink-0 px-3.5 py-2.5 rounded-xl font-bold text-xs flex items-center gap-1.5 transition-all ${
                inventoryCounts.master_key > 0
                  ? 'bg-gradient-to-r from-amber-500 to-yellow-500 text-evermyst-bg font-black shadow-lg shadow-amber-500/20 active:scale-95 hover:brightness-110'
                  : 'bg-evermyst-surface text-evermyst-text-dim border border-evermyst-border cursor-not-allowed'
              }`}
            >
              <Key className="w-3.5 h-3.5" />
              {inventoryCounts.master_key > 0 ? 'GẮN VÀO TRẠM' : 'Chưa có'}
            </button>
          </div>
        </div>
      </section>

      {/* ===================================================================== */}
      {/* KHU VỰC 2: MUA ĐẠO CỤ (SHOP ITEMS)                                    */}
      {/* ===================================================================== */}
      <section className="space-y-3">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2">
            <div className="p-1.5 rounded-lg bg-lumen/15 text-lumen border border-lumen/30">
              <ShoppingBag className="w-4 h-4" />
            </div>
            <h2 className="text-sm font-black text-white uppercase tracking-wider">
              2. Cửa Hàng Đạo Cụ (Shop Items)
            </h2>
          </div>
          <span className="text-[11px] text-evermyst-text-dim">Trừ Lumen tự động</span>
        </div>

        <div className="space-y-3">
          {shopItemDefs.map((item) => {
            const canAfford = currentBalance >= item.price;
            const shortage = item.price - currentBalance;

            return (
              <div
                key={item.code}
                className="bg-evermyst-card border border-evermyst-border rounded-2xl p-4 shadow-md space-y-3 hover:border-evermyst-border-light transition-all"
              >
                <div className="flex items-start justify-between gap-3">
                  <div className="flex items-center gap-3">
                    <div className="w-10 h-10 rounded-xl bg-evermyst-surface border border-evermyst-border flex items-center justify-center shrink-0">
                      {item.icon}
                    </div>
                    <div>
                      <div className="flex items-center gap-2">
                        <h3 className="text-sm font-bold text-white">{item.name}</h3>
                        <span className="text-[10px] font-bold px-2 py-0.5 rounded-full bg-evermyst-surface text-evermyst-text-muted border border-evermyst-border">
                          {item.tag}
                        </span>
                      </div>
                      <div className="text-xs text-lumen font-mono font-bold mt-0.5">
                        Giá: {item.price}✦ Lumen
                      </div>
                    </div>
                  </div>

                  <span className="text-xs font-mono font-semibold text-evermyst-text-dim">
                    Kho: {item.qty}
                  </span>
                </div>

                <p className="text-xs text-evermyst-text-muted leading-relaxed">
                  {item.desc}
                </p>

                <div className="pt-1 flex items-center justify-end">
                  <button
                    onClick={() => handleBuyItemAction(item.code)}
                    disabled={!canAfford || isProcessing}
                    className={`w-full sm:w-auto min-w-[140px] py-2.5 px-4 rounded-xl font-bold text-xs flex items-center justify-center gap-1.5 transition-all ${
                      canAfford
                        ? 'bg-lumen hover:bg-lumen-light text-evermyst-bg font-black active:scale-95 shadow-md shadow-lumen/20'
                        : 'bg-evermyst-surface border border-evermyst-border text-danger font-semibold cursor-not-allowed opacity-80'
                    }`}
                  >
                    {isProcessing ? (
                      <Loader2 className="w-3.5 h-3.5 animate-spin" />
                    ) : canAfford ? (
                      <ShoppingBag className="w-3.5 h-3.5" />
                    ) : (
                      <AlertTriangle className="w-3.5 h-3.5" />
                    )}
                    {canAfford ? `MUA NGAY (${item.price}✦)` : `Thiếu ${shortage}✦ Lumen`}
                  </button>
                </div>
              </div>
            );
          })}
        </div>
      </section>

      {/* ===================================================================== */}
      {/* KHU VỰC 3: MUA MANH MỐI BÍ MẬT (HINTS - ĐỒNG / BẠC / VÀNG)            */}
      {/* ===================================================================== */}
      <section className="space-y-3">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2">
            <div className="p-1.5 rounded-lg bg-amber-500/15 text-amber-400 border border-amber-500/30">
              <Scroll className="w-4 h-4" />
            </div>
            <h2 className="text-sm font-black text-white uppercase tracking-wider">
              3. Manh Mối Mật Thư (Hints)
            </h2>
          </div>
          <span className="text-[11px] text-amber-400 font-bold">
            Đã mở {ownedHintIds.size}/3
          </span>
        </div>

        <div className="space-y-3">
          {hintTiers.map((tierConfig) => {
            const hint: Hint =
              hints.find((h) => h.tier === tierConfig.tier) ||
              hints.find((h) => h.tier.toLowerCase() === tierConfig.tier) ||
              DEFAULT_HINTS.find((dh) => dh.tier === tierConfig.tier) ||
              DEFAULT_HINTS[0];

            const isOwned = ownedHintIds.has(hint.id);
            const tierInfo = getTierInfo(tierConfig.tier);
            const price = tierConfig.defaultPrice;
            const canAfford = currentBalance >= price;
            const shortage = price - currentBalance;

            return (
              <div
                key={tierConfig.tier}
                className={`bg-evermyst-card rounded-2xl p-4 border transition-all ${
                  isOwned
                    ? 'border-emerald-500/40 bg-emerald-500/5'
                    : 'border-evermyst-border hover:border-evermyst-border-light'
                }`}
              >
                <div className="flex items-start justify-between gap-3">
                  <div className="space-y-1 flex-1">
                    <div className="flex items-center gap-2 flex-wrap">
                      <span
                        className={`text-[10px] font-black uppercase px-2 py-0.5 rounded-full border ${tierInfo.bgColor} ${tierInfo.color}`}
                      >
                        Bậc {tierInfo.label}
                      </span>
                      <h3 className="text-sm font-bold text-white">{hint.title}</h3>
                    </div>

                    <div className="text-xs text-evermyst-text-dim">
                      {isOwned ? (
                        <span className="text-emerald-400 font-bold flex items-center gap-1">
                          <CheckCircle2 className="w-3.5 h-3.5" /> Đã mở khóa thành công
                        </span>
                      ) : (
                        <span>Giá mở khóa: <b className="text-lumen font-mono">{price}✦ Lumen</b></span>
                      )}
                    </div>
                  </div>

                  <div className="shrink-0">
                    {isOwned ? (
                      <button
                        onClick={() => handleViewHintAction(hint)}
                        className="px-3 py-1.5 rounded-xl bg-emerald-500/15 border border-emerald-500/30 text-emerald-300 font-bold text-xs hover:bg-emerald-500/25 transition-all flex items-center gap-1"
                      >
                        <Scroll className="w-3.5 h-3.5" /> Xem lại
                      </button>
                    ) : (
                      <button
                        onClick={() => handleBuyHintAction(hint)}
                        disabled={!canAfford || isProcessing}
                        className={`px-3.5 py-2 rounded-xl font-bold text-xs flex items-center gap-1.5 transition-all ${
                          canAfford
                            ? 'bg-amber-500 hover:bg-amber-400 text-evermyst-bg font-black active:scale-95 shadow-md shadow-amber-500/20'
                            : 'bg-evermyst-surface border border-evermyst-border text-danger font-semibold cursor-not-allowed'
                        }`}
                      >
                        {isProcessing ? (
                          <Loader2 className="w-3.5 h-3.5 animate-spin" />
                        ) : canAfford ? (
                          <Unlock className="w-3.5 h-3.5" />
                        ) : (
                          <Lock className="w-3.5 h-3.5" />
                        )}
                        {canAfford ? `MUA MẬT THƯ (${price}✦)` : `Thiếu ${shortage}✦`}
                      </button>
                    )}
                  </div>
                </div>

                {/* Khung nội dung mật thư nếu đã mở khóa */}
                {isOwned && hint.content && (
                  <div className="mt-3 p-3 rounded-xl bg-amber-500/10 border border-amber-500/30 text-amber-200 text-xs leading-relaxed animate-fadeIn">
                    <div className="text-[10px] uppercase font-black tracking-wider text-amber-400 mb-1 flex items-center gap-1">
                      <Scroll className="w-3 h-3" /> NỘI DUNG MẬT THƯ ĐÃ GIẢI MÃ:
                    </div>
                    <div className="font-medium italic select-text">
                      "{hint.content}"
                    </div>
                  </div>
                )}
              </div>
            );
          })}
        </div>
      </section>

      {/* ===================================================================== */}
      {/* MODAL 1: KÍNH VỌNG TẦM (SPYGLASS MODAL)                              */}
      {/* ===================================================================== */}
      {isSpyModalOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/80 backdrop-blur-sm animate-fadeIn">
          <div className="bg-evermyst-surface border border-cyan-500/40 rounded-3xl p-5 w-full max-w-sm shadow-2xl space-y-4">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2">
                <div className="p-2 rounded-xl bg-cyan-500/20 text-cyan-400 border border-cyan-500/30">
                  <Eye className="w-5 h-5" />
                </div>
                <div>
                  <h3 className="text-base font-black text-white">Kính Vọng Tầm</h3>
                  <p className="text-[11px] text-evermyst-text-dim">Do thám số dư & khiên đối thủ</p>
                </div>
              </div>
              <button
                onClick={() => setIsSpyModalOpen(false)}
                className="p-1 rounded-lg text-evermyst-text-dim hover:text-white"
              >
                <X className="w-5 h-5" />
              </button>
            </div>

            {!spyResult ? (
              <div className="space-y-3">
                <label className="text-xs font-bold text-evermyst-text-muted uppercase tracking-wider">
                  Chọn 1 đội đối thủ để soi:
                </label>

                <div className="space-y-2 max-h-56 overflow-y-auto pr-1">
                  {opponentTeams.map((opp) => (
                    <button
                      key={opp.id}
                      onClick={() => setSelectedOpponentId(opp.id)}
                      className={`w-full flex items-center justify-between p-3 rounded-xl border text-left transition-all ${
                        selectedOpponentId === opp.id
                          ? 'bg-cyan-500/15 border-cyan-500 text-white font-bold'
                          : 'bg-evermyst-card border-evermyst-border text-evermyst-text-dim hover:border-evermyst-border-light'
                      }`}
                    >
                      <span className="text-xs truncate">{opp.name}</span>
                      <span className="text-xs font-mono font-bold text-cyan-400">
                        {opp.qr_code}
                      </span>
                    </button>
                  ))}
                </div>

                <button
                  onClick={handleExecuteSpy}
                  disabled={!selectedOpponentId || isProcessing}
                  className="w-full py-3 rounded-xl bg-gradient-to-r from-cyan-500 to-blue-500 text-white font-black text-sm flex items-center justify-center gap-2 shadow-lg shadow-cyan-500/20 active:scale-95 transition-all"
                >
                  {isProcessing ? (
                    <Loader2 className="w-4 h-4 animate-spin" />
                  ) : (
                    <Eye className="w-4 h-4" />
                  )}
                  SOI NGAY
                </button>
              </div>
            ) : (
              /* Kết quả do thám */
              <div className="space-y-4 animate-scaleUp">
                <div className="p-4 rounded-2xl bg-cyan-500/10 border border-cyan-500/30 text-center space-y-2">
                  <div className="text-xs font-bold text-cyan-300 uppercase tracking-wider">
                    Kết Quả Do Thám
                  </div>
                  <h4 className="text-lg font-black text-white">{spyResult.target_team_name}</h4>

                  <div className="py-2">
                    <div className="text-[10px] text-evermyst-text-dim font-bold">SỐ DƯ HIỆN TẠI</div>
                    <div className="text-3xl font-black font-mono text-lumen">
                      {spyResult.balance}✦
                    </div>
                  </div>

                  <div className="pt-2 border-t border-cyan-500/20">
                    <div className="text-[10px] text-evermyst-text-dim font-bold mb-1">TRẠNG THÁI KHIÊN</div>
                    {spyResult.has_active_shield ? (
                      <div className="inline-flex items-center gap-1 px-3 py-1 rounded-xl bg-purple-500/20 text-purple-300 border border-purple-500/40 font-bold text-xs">
                        <Shield className="w-3.5 h-3.5" />
                        Đang bảo vệ (Có Khiên Màn Sương)
                      </div>
                    ) : (
                      <div className="inline-flex items-center gap-1 px-3 py-1 rounded-xl bg-emerald-500/15 text-emerald-300 border border-emerald-500/30 font-bold text-xs">
                        Không có khiên (Có thể tấn công PvP)
                      </div>
                    )}
                  </div>
                </div>

                <button
                  onClick={() => setIsSpyModalOpen(false)}
                  className="w-full py-2.5 rounded-xl bg-evermyst-card border border-evermyst-border text-white font-bold text-xs hover:bg-evermyst-card-hover transition-colors"
                >
                  Đóng Báo Cáo
                </button>
              </div>
            )}
          </div>
        </div>
      )}

      {/* ===================================================================== */}
      {/* MODAL 2: CHÌA KHÓA VẠN NĂNG (MASTER KEY MODAL)                       */}
      {/* ===================================================================== */}
      {isKeyModalOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/80 backdrop-blur-sm animate-fadeIn">
          <div className="bg-evermyst-surface border border-amber-500/40 rounded-3xl p-5 w-full max-w-sm shadow-2xl space-y-4">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2">
                <div className="p-2 rounded-xl bg-amber-500/20 text-amber-400 border border-amber-500/30">
                  <Key className="w-5 h-5" />
                </div>
                <div>
                  <h3 className="text-base font-black text-white">Chìa Khóa Vạn Năng</h3>
                  <p className="text-[11px] text-evermyst-text-dim">Cắm vào trạm để mở lối tắt</p>
                </div>
              </div>
              <button
                onClick={() => setIsKeyModalOpen(false)}
                className="p-1 rounded-lg text-evermyst-text-dim hover:text-white"
              >
                <X className="w-5 h-5" />
              </button>
            </div>

            <div className="space-y-3">
              <label className="text-xs font-bold text-evermyst-text-muted uppercase tracking-wider">
                Chọn trạm mục tiêu (1 đến 5):
              </label>

              <div className="space-y-2 max-h-56 overflow-y-auto pr-1">
                {activeStations.map((st) => {
                  const alreadyHasKey = activeKeyStationIds.includes(st.id);
                  return (
                    <button
                      key={st.id}
                      onClick={() => setSelectedStationId(st.id)}
                      className={`w-full flex items-center justify-between p-3 rounded-xl border text-left transition-all ${
                        selectedStationId === st.id
                          ? 'bg-amber-500/15 border-amber-500 text-white font-bold'
                          : 'bg-evermyst-card border-evermyst-border text-evermyst-text-dim hover:border-evermyst-border-light'
                      }`}
                    >
                      <div className="flex items-center gap-2">
                        <span className="w-5 h-5 rounded-md bg-evermyst-surface text-amber-400 font-mono text-xs font-bold flex items-center justify-center">
                          {st.order_index}
                        </span>
                        <span className="text-xs truncate">{st.name}</span>
                      </div>

                      {alreadyHasKey && (
                        <span className="text-[10px] font-bold text-amber-400 flex items-center gap-0.5">
                          <CheckCircle2 className="w-3 h-3" /> Đã cắm
                        </span>
                      )}
                    </button>
                  );
                })}
              </div>

              <button
                onClick={handleExecuteKey}
                disabled={!selectedStationId || isProcessing}
                className="w-full py-3 rounded-xl bg-gradient-to-r from-amber-500 to-yellow-500 text-evermyst-bg font-black text-sm flex items-center justify-center gap-2 shadow-lg shadow-amber-500/20 active:scale-95 transition-all"
              >
                {isProcessing ? (
                  <Loader2 className="w-4 h-4 animate-spin" />
                ) : (
                  <Key className="w-4 h-4" />
                )}
                KÍCH HOẠT TẠI TRẠM NÀY
              </button>
            </div>
          </div>
        </div>
      )}

      {/* ===================================================================== */}
      {/* MODAL 3: XEM NỘI DUNG MẬT THƯ (PARCHMENT MODAL)                       */}
      {/* ===================================================================== */}
      {revealedHint && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/80 backdrop-blur-sm animate-fadeIn">
          <div className="bg-[#1A1813] border-2 border-amber-500/50 rounded-3xl p-6 w-full max-w-sm shadow-2xl space-y-4 text-center relative overflow-hidden">
            <div className="absolute top-0 left-0 right-0 h-1 bg-gradient-to-r from-transparent via-amber-400 to-transparent" />

            <div className="w-12 h-12 rounded-2xl bg-amber-500/20 border border-amber-500/40 text-amber-400 flex items-center justify-center mx-auto shadow-lg shadow-amber-500/20">
              <Scroll className="w-6 h-6" />
            </div>

            <div>
              <div className="text-[10px] uppercase font-black tracking-widest text-amber-400/80">
                MẬT THƯ CỔ TỰ BÍ TRUYỀN
              </div>
              <h3 className="text-lg font-black text-white mt-1">{revealedHint.title}</h3>
            </div>

            <div className="p-4 rounded-2xl bg-amber-950/40 border border-amber-500/30 text-amber-100 text-sm leading-relaxed font-serif italic shadow-inner select-text">
              "{revealedHint.content}"
            </div>

            <button
              onClick={() => setRevealedHint(null)}
              className="w-full py-2.5 rounded-xl bg-amber-500 hover:bg-amber-400 text-evermyst-bg font-black text-xs active:scale-95 transition-all shadow-md shadow-amber-500/20"
            >
              ĐÃ GHI NHỚ MẬT MÃ
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
