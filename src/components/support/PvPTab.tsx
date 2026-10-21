// ============================================================================
// PVP TAB - Trọng tài PvP: Giải quyết chiến đấu cướp điểm giữa 2 đội
// Khóa đội theo Support, Xác thực Điều kiện Mở Combat (QR/Ảnh vs Mua lượt -20✦)
// ============================================================================
import React, { useState, useMemo, useEffect } from 'react';
import { useGame } from '@/contexts/GameContext';
import { useSession } from '@/contexts/SessionContext';
import {
  Swords,
  Shield,
  ShieldAlert,
  Timer,
  Loader2,
  AlertTriangle,
  ChevronDown,
  Sparkles,
  Zap,
  Image as ImageIcon,
  CheckCircle2,
  QrCode,
  X,
} from 'lucide-react';
import { getShieldRemaining, getCooldownRemaining } from '@/lib/utils';
import type { Team, PvPResponse } from '@/lib/types';

interface PvPTabProps {
  selectedTeam?: Team | null;
}

// Declare selector subcomponent outside render to satisfy React Compiler
interface TeamSelectBoxProps {
  label: string;
  value: string;
  onChange: (id: string) => void;
  showList: boolean;
  setShowList: (v: boolean) => void;
  excludeId: string;
  teams: Team[];
  icon: React.ReactNode;
}

function TeamSelectBox({
  label,
  value,
  onChange,
  showList,
  setShowList,
  excludeId,
  teams,
  icon,
}: TeamSelectBoxProps) {
  const selected = teams.find((t) => t.id === value);
  const available = teams.filter((t) => t.id !== excludeId);

  return (
    <div className="relative">
      <label className="flex items-center gap-1.5 text-xs font-bold text-evermyst-text-muted uppercase tracking-wider mb-1.5">
        {icon}
        {label}
      </label>

      <button
        type="button"
        onClick={() => setShowList(!showList)}
        className="w-full min-h-[52px] flex items-center justify-between px-3.5 py-2.5 bg-evermyst-card border border-evermyst-border rounded-xl hover:border-evermyst-border-light active:scale-[0.98] transition-all"
      >
        <span className={`text-sm font-bold truncate pr-2 ${selected ? 'text-evermyst-text' : 'text-evermyst-text-dim'}`}>
          {selected ? selected.name : 'Bấm chọn đội...'}
        </span>
        <div className="flex items-center gap-2 shrink-0">
          {selected && (
            <span className="text-xs font-mono font-bold text-lumen">
              {selected.light_balance}✦
            </span>
          )}
          <ChevronDown
            className={`w-4 h-4 text-evermyst-text-dim transition-transform ${showList ? 'rotate-180' : ''}`}
          />
        </div>
      </button>

      {showList && (
        <>
          <div className="fixed inset-0 z-30" onClick={() => setShowList(false)} />
          <div className="absolute top-full left-0 right-0 mt-1.5 bg-evermyst-card border border-evermyst-border rounded-xl shadow-2xl z-40 max-h-56 overflow-y-auto animate-slideDown divide-y divide-evermyst-border/40">
            {available.map((team) => (
              <button
                key={team.id}
                type="button"
                onClick={() => {
                  onChange(team.id);
                  setShowList(false);
                }}
                className={`w-full flex items-center justify-between px-3.5 py-3 text-left hover:bg-evermyst-card-hover transition-colors ${
                  value === team.id ? 'bg-lumen/10 font-bold' : ''
                }`}
              >
                <span className="text-sm text-evermyst-text truncate">{team.name}</span>
                <span className="text-xs text-lumen font-mono font-bold">
                  {team.light_balance}✦
                </span>
              </button>
            ))}
          </div>
        </>
      )}
    </div>
  );
}

export default function PvPTab({ selectedTeam }: PvPTabProps = {}) {
  const { teams, pvpLogs, config, resolvePvP } = useGame();
  const { user } = useSession();

  const isAdmin = user?.role === 'admin';
  const supportAssignedTeamId = selectedTeam?.id || user?.assigned_team_id || null;

  const [attackerId, setAttackerId] = useState('');
  const [defenderId, setDefenderId] = useState('');
  const [isProcessing, setIsProcessing] = useState(false);
  const [lastResult, setLastResult] = useState<PvPResponse | null>(null);
  const [lastAttackCost, setLastAttackCost] = useState<number>(0);
  const [showAttackerList, setShowAttackerList] = useState(false);
  const [showDefenderList, setShowDefenderList] = useState(false);
  const [, setTick] = useState(0);

  // Điều kiện mở giao tranh (Mode A: Minh chứng QR/Ảnh vs Mode B: Mua lượt)
  const [entryMode, setEntryMode] = useState<'proof' | 'buy_turn'>('proof');
  const [proofImage, setProofImage] = useState<string | null>(null);
  const [qrInput, setQrInput] = useState<string>('');

  // Force re-render every second for real-time cooldown & shield calculation
  useEffect(() => {
    const timer = setInterval(() => setTick((t) => t + 1), 1000);
    return () => clearInterval(timer);
  }, []);

  const activeTeams = useMemo(() => teams.filter((t) => t.is_active), [teams]);

  // NHIỆM VỤ 1: Khóa cứng attackerId theo đội của Support nếu không phải Admin
  useEffect(() => {
    if (!isAdmin && supportAssignedTeamId) {
      setAttackerId(supportAssignedTeamId);
    } else if (isAdmin && !attackerId && activeTeams.length > 0) {
      setAttackerId(activeTeams[0].id);
    }
  }, [isAdmin, supportAssignedTeamId, activeTeams, attackerId]);

  // Tự động chuyển defenderId sang đội hợp lệ khác attackerId nếu đang bị trùng
  useEffect(() => {
    if (attackerId) {
      if (!defenderId || defenderId === attackerId) {
        const other = activeTeams.find((t) => t.id !== attackerId);
        if (other) {
          setDefenderId(other.id);
        }
      }
    }
  }, [attackerId, defenderId, activeTeams]);

  const attacker = activeTeams.find((t) => t.id === attackerId);
  const defender = activeTeams.find((t) => t.id === defenderId);

  // Check Defender Shield Status
  const defenderShield = useMemo(() => {
    return getShieldRemaining(defender?.shield_until ?? null);
  }, [defender?.shield_until]);

  // Check Cooldown Status between Attacker & Defender
  const pairCooldown = useMemo(() => {
    if (!attackerId || !defenderId) return { active: false, label: '' };
    const lastCombat = pvpLogs.find(
      (log) =>
        log.attacker_team_id === attackerId &&
        log.defender_team_id === defenderId &&
        log.result !== 'cooldown_blocked'
    );
    if (!lastCombat) return { active: false, label: '' };

    const cooldownMin = config.pvp_cooldown_minutes || 30;
    const combatTime = new Date(lastCombat.created_at).getTime();
    const cooldownUntil = new Date(combatTime + cooldownMin * 60 * 1000).toISOString();
    return getCooldownRemaining(cooldownUntil);
  }, [attackerId, defenderId, pvpLogs, config.pvp_cooldown_minutes]);

  // NHIỆM VỤ 2: Tính toán điều kiện mở giao tranh
  const defaultTurnFee = config.pvp_attack_cost || 20;
  const attackCost = entryMode === 'buy_turn' ? defaultTurnFee : 0;

  const isQrMatched = Boolean(
    qrInput.trim() &&
    defender?.qr_code &&
    qrInput.trim().toLowerCase() === defender.qr_code.toLowerCase()
  );
  const isProofValid = Boolean(proofImage) || isQrMatched;
  const hasEnoughBalanceForTurn = (attacker?.light_balance ?? 0) >= attackCost;
  const isConditionMet = entryMode === 'proof' ? isProofValid : hasEnoughBalanceForTurn;

  const canFight =
    Boolean(attacker) &&
    Boolean(defender) &&
    attackerId !== defenderId &&
    !pairCooldown.active &&
    !isProcessing &&
    isConditionMet;

  const handleFight = async () => {
    if (!canFight) return;
    setIsProcessing(true);
    setLastResult(null);
    setLastAttackCost(attackCost);

    const res = await resolvePvP(attackerId, defenderId, attackCost);
    setLastResult(res);
    setIsProcessing(false);
  };

  return (
    <div className="p-4 space-y-4 pb-28 animate-fadeIn">
      {/* Header */}
      <div className="text-center py-1">
        <div className="inline-flex items-center justify-center w-12 h-12 rounded-2xl bg-danger/15 text-danger border border-danger/30 mb-1.5">
          <Swords className="w-6 h-6" />
        </div>
        <h2 className="text-base font-black text-evermyst-text tracking-wide uppercase">
          Trọng Tài Chiến Đấu PvP
        </h2>
        <p className="text-xs text-evermyst-text-dim">
          Cướp {config.pvp_steal_percent}% Lumen • Phạt phản phệ {config.pvp_backlash_amount} Lumen nếu gặp Khiên
        </p>
      </div>

      {/* Selectors */}
      <div className="space-y-3">
        {/* Đội Tấn Công: Khóa cứng nếu là Support, cho chọn nếu là Admin */}
        {isAdmin ? (
          <TeamSelectBox
            label="Đội Tấn Công (Kẻ Cướp)"
            value={attackerId}
            onChange={setAttackerId}
            showList={showAttackerList}
            setShowList={setShowAttackerList}
            excludeId={defenderId}
            teams={activeTeams}
            icon={<Swords className="w-3.5 h-3.5 text-danger" />}
          />
        ) : (
          <div className="relative">
            <label className="flex items-center gap-1.5 text-xs font-bold text-evermyst-text-muted uppercase tracking-wider mb-1.5">
              <Swords className="w-3.5 h-3.5 text-danger" />
              Đội Tấn Công (Kẻ Cướp)
            </label>
            <div className="w-full min-h-[52px] flex items-center justify-between px-3.5 py-2.5 bg-evermyst-card/70 border border-evermyst-border/80 rounded-xl select-none">
              <div className="flex items-center gap-2 truncate pr-2">
                <span className="text-sm font-bold text-evermyst-text truncate">
                  {attacker ? attacker.name : 'Đội của bạn'}
                </span>
                <span className="px-2 py-0.5 rounded-full bg-lumen/20 text-lumen text-[10px] font-bold shrink-0 border border-lumen/30 flex items-center gap-1">
                  <Sparkles className="w-2.5 h-2.5" /> Đội của bạn
                </span>
              </div>
              <div className="flex items-center gap-2 shrink-0">
                {attacker && (
                  <span className="text-xs font-mono font-bold text-lumen">
                    {attacker.light_balance}✦
                  </span>
                )}
              </div>
            </div>
          </div>
        )}

        <div className="flex justify-center -my-1">
          <div className="w-7 h-7 rounded-full bg-evermyst-surface border border-evermyst-border flex items-center justify-center text-[11px] font-black text-evermyst-text-dim z-10 shadow">
            VS
          </div>
        </div>

        {/* Đội Phòng Thủ: Loại trừ attackerId */}
        <TeamSelectBox
          label="Đội Phòng Thủ (Bị Quét)"
          value={defenderId}
          onChange={setDefenderId}
          showList={showDefenderList}
          setShowList={setShowDefenderList}
          excludeId={attackerId}
          teams={activeTeams}
          icon={<Shield className="w-3.5 h-3.5 text-props" />}
        />
      </div>

      {/* Warnings: Defender Shield Active */}
      {defender && defenderShield.active && (
        <div className="p-3.5 rounded-2xl bg-props/15 border border-props/40 space-y-1.5 animate-fadeIn">
          <div className="flex items-center gap-2 text-xs font-bold text-props">
            <ShieldAlert className="w-4 h-4 shrink-0" />
            <span>CẢNH BÁO: Đội phòng thủ đang có Khiên Màn Sương!</span>
          </div>
          <p className="text-xs text-props-light leading-relaxed">
            Nếu tấn công bây giờ, {attacker?.name || 'Đội tấn công'} sẽ bị <strong>phản phệ</strong> và bị phạt -{config.pvp_backlash_amount} Lumen!
          </p>
          <div className="text-[11px] font-mono text-props font-bold pt-0.5">
            {defenderShield.label}
          </div>
        </div>
      )}

      {/* Warnings: Cooldown Active */}
      {pairCooldown.active && (
        <div className="p-3 rounded-2xl bg-warning/15 border border-warning/40 flex items-center gap-2 text-xs text-warning animate-fadeIn">
          <Timer className="w-4 h-4 shrink-0" />
          <span>
            {attacker?.name} vừa tấn công {defender?.name}. {pairCooldown.label}
          </span>
        </div>
      )}

      {/* NHIỆM VỤ 2: Khối UI ĐIỀU KIỆN PHÁT ĐỘNG TẤN CÔNG */}
      <div className="p-3.5 rounded-2xl bg-evermyst-card border border-evermyst-border space-y-3">
        <div className="flex items-center justify-between">
          <label className="text-xs font-bold text-evermyst-text uppercase tracking-wider flex items-center gap-1.5">
            <Zap className="w-3.5 h-3.5 text-lumen" />
            Điều kiện phát động tấn công
          </label>
          <span className="text-[10px] font-bold font-mono text-evermyst-text-dim">
            {entryMode === 'proof' ? 'Miễn phí (0✦)' : `Phí: -${attackCost}✦`}
          </span>
        </div>

        {/* Tab Toggle Mode */}
        <div className="grid grid-cols-2 gap-2 p-1 bg-evermyst-surface rounded-xl border border-evermyst-border/60">
          <button
            type="button"
            onClick={() => setEntryMode('proof')}
            className={`py-2 px-2 rounded-lg text-xs font-bold transition-all flex items-center justify-center gap-1.5 ${
              entryMode === 'proof'
                ? 'bg-gradient-to-r from-lumen/20 to-lumen/10 text-lumen border border-lumen/40 shadow-sm'
                : 'text-evermyst-text-dim hover:text-white'
            }`}
          >
            <ImageIcon className="w-3.5 h-3.5" /> Minh chứng QR / Ảnh
          </button>
          <button
            type="button"
            onClick={() => setEntryMode('buy_turn')}
            className={`py-2 px-2 rounded-lg text-xs font-bold transition-all flex items-center justify-center gap-1.5 ${
              entryMode === 'buy_turn'
                ? 'bg-gradient-to-r from-danger/20 to-danger/10 text-danger-light border border-danger/40 shadow-sm'
                : 'text-evermyst-text-dim hover:text-white'
            }`}
          >
            🎟️ Mua lượt (-{defaultTurnFee}✦)
          </button>
        </div>

        {/* Mode A: Proof Image / QR Code */}
        {entryMode === 'proof' && (
          <div className="space-y-2.5 pt-1">
            <p className="text-[11px] text-evermyst-text-muted leading-relaxed">
              Tải ảnh chụp thẻ/mã QR của đối thủ hoặc nhập mã QR để mở giao tranh miễn phí:
            </p>

            <div className="flex items-center gap-2">
              <label className="flex-1 cursor-pointer">
                <input
                  type="file"
                  accept="image/*"
                  className="hidden"
                  onChange={(e) => {
                    const file = e.target.files?.[0];
                    if (file) {
                      const reader = new FileReader();
                      reader.onload = (event) => {
                        setProofImage(event.target?.result as string);
                      };
                      reader.readAsDataURL(file);
                    }
                  }}
                />
                <div className="w-full py-2.5 px-3 rounded-xl border border-dashed border-evermyst-border hover:border-lumen/50 bg-evermyst-surface/50 text-center text-xs font-semibold text-evermyst-text hover:text-white transition-all flex items-center justify-center gap-2">
                  <ImageIcon className="w-4 h-4 text-lumen" />
                  <span>{proofImage ? 'Đổi ảnh chụp khác' : 'Tải ảnh minh chứng QR/Thẻ'}</span>
                </div>
              </label>

              {proofImage && (
                <div className="relative group shrink-0">
                  <img
                    src={proofImage}
                    alt="Proof"
                    className="w-10 h-10 object-cover rounded-lg border border-success ring-2 ring-success/30"
                  />
                  <button
                    type="button"
                    onClick={() => setProofImage(null)}
                    className="absolute -top-1.5 -right-1.5 w-4 h-4 rounded-full bg-danger text-white text-[10px] flex items-center justify-center shadow"
                    title="Xóa ảnh"
                  >
                    <X className="w-3 h-3" />
                  </button>
                </div>
              )}
            </div>

            {/* QR Text input fallback */}
            <div className="relative">
              <input
                type="text"
                placeholder="Hoặc nhập mã QR đối thủ (VD: TEAM-02)..."
                value={qrInput}
                onChange={(e) => setQrInput(e.target.value)}
                className="w-full px-3 py-2 bg-evermyst-surface border border-evermyst-border rounded-xl text-xs text-white placeholder:text-evermyst-text-muted focus:outline-none focus:border-lumen pr-8"
              />
              <QrCode className="w-4 h-4 text-evermyst-text-dim absolute right-2.5 top-2.5 pointer-events-none" />
            </div>

            {/* Status Feedback */}
            {isProofValid ? (
              <div className="p-2 rounded-xl bg-success/15 border border-success/30 text-success text-[11px] font-bold flex items-center gap-1.5 animate-fadeIn">
                <CheckCircle2 className="w-3.5 h-3.5 shrink-0" />
                <span>✅ Đã xác thực minh chứng QR hợp lệ (0✦ phí lượt)</span>
              </div>
            ) : (
              <div className="text-[10px] text-amber-400 font-medium flex items-center gap-1">
                <span>⚠️ Cần tải ảnh chụp hoặc nhập đúng mã QR của {defender?.name || 'đối thủ'} để mở combat.</span>
              </div>
            )}
          </div>
        )}

        {/* Mode B: Buy Turn */}
        {entryMode === 'buy_turn' && (
          <div className="space-y-2 pt-1">
            <div className="flex items-center justify-between text-xs">
              <span className="text-evermyst-text-muted">Phí mua lượt tấn công:</span>
              <span className="font-mono font-bold text-danger">-{attackCost}✦ Lumen</span>
            </div>
            <div className="flex items-center justify-between text-xs">
              <span className="text-evermyst-text-muted">Số dư của {attacker?.name}:</span>
              <span className="font-mono font-bold text-lumen">{attacker?.light_balance ?? 0}✦ Lumen</span>
            </div>

            {!hasEnoughBalanceForTurn ? (
              <div className="p-2.5 rounded-xl bg-danger/15 border border-danger/30 text-danger-light text-xs font-bold animate-fadeIn">
                Đội tấn công không đủ Lumen để mua lượt PvP!
              </div>
            ) : (
              <div className="p-2 rounded-xl bg-lumen/10 border border-lumen/30 text-lumen text-[11px] font-bold flex items-center gap-1.5">
                <span>🎟️ Đủ điều kiện mua lượt PvP (-{attackCost}✦ sẽ trừ khi bấm tấn công)</span>
              </div>
            )}
          </div>
        )}
      </div>

      {/* Big Combat Execution Button (>56px) */}
      <button
        onClick={handleFight}
        disabled={!canFight}
        className="w-full min-h-[58px] rounded-2xl bg-gradient-to-r from-danger to-danger-dark hover:from-danger-light hover:to-danger text-white font-black text-sm uppercase tracking-wider disabled:opacity-30 disabled:cursor-not-allowed shadow-lg shadow-danger/25 active:scale-[0.98] transition-all flex items-center justify-center gap-2"
      >
        {isProcessing ? (
          <>
            <Loader2 className="w-5 h-5 animate-spin" />
            ĐANG TÍNH TOÁN COMBAT...
          </>
        ) : defenderShield.active ? (
          <>
            <ShieldAlert className="w-5 h-5" />
            VẪN TẤN CÔNG (SẼ BỊ PHẢN PHỆ)
          </>
        ) : (
          <>
            <Zap className="w-5 h-5 fill-current" />
            XÁC NHẬN CHIẾN ĐẤU PVP {attackCost > 0 ? `(-${attackCost}✦)` : '(0✦)'}
          </>
        )}
      </button>

      {/* Combat Result Card */}
      {lastResult && (
        <div
          className={`p-4 rounded-2xl border space-y-3 animate-slideUp ${
            lastResult.result === 'backlash'
              ? 'bg-props/15 border-props/50'
              : lastResult.result === 'success'
              ? 'bg-success/15 border-success/50'
              : 'bg-evermyst-card border-evermyst-border'
          }`}
        >
          <div className="flex items-center gap-2">
            {lastResult.result === 'backlash' ? (
              <ShieldAlert className="w-5 h-5 text-props shrink-0" />
            ) : lastResult.result === 'success' ? (
              <Sparkles className="w-5 h-5 text-success shrink-0" />
            ) : (
              <AlertTriangle className="w-5 h-5 text-warning shrink-0" />
            )}
            <h4 className="text-sm font-black text-evermyst-text">
              {lastResult.result === 'backlash'
                ? 'KẾT QUẢ: PHẢN PHỆ!'
                : lastResult.result === 'success'
                ? 'KẾT QUẢ: CƯỚP THÀNH CÔNG!'
                : 'THÔNG BÁO'}
            </h4>
          </div>

          <p className="text-xs text-evermyst-text leading-relaxed">
            {lastResult.message || lastResult.error}
          </p>

          {/* Chi tiết phí lượt / minh chứng */}
          <div className="pt-0.5">
            {lastAttackCost > 0 ? (
              <span className="text-[11px] font-mono text-danger font-bold">
                • Đã trừ -{lastAttackCost}✦ phí mua lượt giao tranh
              </span>
            ) : (
              <span className="text-[11px] font-mono text-success font-bold">
                • Sử dụng minh chứng QR hợp lệ (0✦ phí lượt)
              </span>
            )}
          </div>

          {lastResult.result === 'success' && (
            <div className="grid grid-cols-2 gap-2 text-center text-xs pt-1">
              <div className="p-2 rounded-xl bg-evermyst-bg/60 border border-evermyst-border">
                <div className="text-[10px] text-evermyst-text-dim">Đội Tấn Công</div>
                <div className="text-sm font-black text-success font-mono">
                  +{(lastResult.stolen_amount ?? lastResult.amount_stolen ?? 0)}✦
                </div>
              </div>
              <div className="p-2 rounded-xl bg-evermyst-bg/60 border border-evermyst-border">
                <div className="text-[10px] text-evermyst-text-dim">Đội Bị Cướp</div>
                <div className="text-sm font-black text-danger font-mono">
                  -{(lastResult.stolen_amount ?? lastResult.amount_stolen ?? 0)}✦
                </div>
              </div>
            </div>
          )}

          {lastResult.result === 'backlash' && (
            <div className="p-2 rounded-xl bg-evermyst-bg/60 border border-evermyst-border text-center text-xs">
              <div className="text-[10px] text-evermyst-text-dim">Phạt Phản Phệ Đội Tấn Công</div>
              <div className="text-sm font-black text-props font-mono">
                -{lastResult.backlash_amount || 10}✦
              </div>
            </div>
          )}
        </div>
      )}
    </div>
  );
}
