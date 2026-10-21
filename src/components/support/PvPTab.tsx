// ============================================================================
// PVP TAB - Trọng tài PvP: Giải quyết chiến đấu cướp điểm giữa 2 đội
// Deadlock-free, kiểm tra Khiên Màn Sương và Cooldown chuẩn giờ Server
// ============================================================================
import { useState, useMemo, useEffect } from 'react';
import { useGame } from '@/contexts/GameContext';
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
} from 'lucide-react';
import { getShieldRemaining, getCooldownRemaining } from '@/lib/utils';
import type { Team, PvPResponse } from '@/lib/types';

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

export default function PvPTab() {
  const { teams, pvpLogs, config, resolvePvP } = useGame();
  const [attackerId, setAttackerId] = useState('');
  const [defenderId, setDefenderId] = useState('');
  const [isProcessing, setIsProcessing] = useState(false);
  const [lastResult, setLastResult] = useState<PvPResponse | null>(null);
  const [showAttackerList, setShowAttackerList] = useState(false);
  const [showDefenderList, setShowDefenderList] = useState(false);
  const [, setTick] = useState(0);

  // Force re-render every second for real-time cooldown & shield calculation
  useEffect(() => {
    const timer = setInterval(() => setTick((t) => t + 1), 1000);
    return () => clearInterval(timer);
  }, []);

  const activeTeams = useMemo(() => teams.filter((t) => t.is_active), [teams]);
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

  const canFight =
    attackerId &&
    defenderId &&
    attackerId !== defenderId &&
    !pairCooldown.active &&
    !isProcessing;

  const handleFight = async () => {
    if (!canFight) return;
    setIsProcessing(true);
    setLastResult(null);

    const res = await resolvePvP(attackerId, defenderId);
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

        <div className="flex justify-center -my-1">
          <div className="w-7 h-7 rounded-full bg-evermyst-surface border border-evermyst-border flex items-center justify-center text-[11px] font-black text-evermyst-text-dim z-10 shadow">
            VS
          </div>
        </div>

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
            XÁC NHẬN CHIẾN ĐẤU PVP
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

          {lastResult.result === 'success' && (
            <div className="grid grid-cols-2 gap-2 text-center text-xs pt-1">
              <div className="p-2 rounded-xl bg-evermyst-bg/60 border border-evermyst-border">
                <div className="text-[10px] text-evermyst-text-dim">Đội Tấn Công</div>
                <div className="text-sm font-black text-success font-mono">
                  +{lastResult.stolen_amount}✦
                </div>
              </div>
              <div className="p-2 rounded-xl bg-evermyst-bg/60 border border-evermyst-border">
                <div className="text-[10px] text-evermyst-text-dim">Đội Bị Cướp</div>
                <div className="text-sm font-black text-danger font-mono">
                  -{lastResult.stolen_amount}✦
                </div>
              </div>
            </div>
          )}

          {lastResult.result === 'backlash' && (
            <div className="p-2 rounded-xl bg-evermyst-bg/60 border border-evermyst-border text-center text-xs">
              <div className="text-[10px] text-evermyst-text-dim">Phạt Phản Phệ Đội Tấn Công</div>
              <div className="text-sm font-black text-props font-mono">
                -{lastResult.backlash_amount}✦
              </div>
            </div>
          )}
        </div>
      )}
    </div>
  );
}
