// ============================================================================
// RAVEN EYE SNAPSHOT MODAL (src/components/support/RavenEyeModal.tsx)
// File: src/components/support/RavenEyeModal.tsx
// Hiển thị hồ sơ tình báo do thám được (5 thông số: Số dư, Khiên, Trạm, Hint, Giờ)
// ============================================================================
import React from 'react';
import { Eye, Shield, Coins, MapPin, Search, Clock, X } from 'lucide-react';
import { getShieldRemaining, formatTime } from '@/lib/utils';

interface RavenEyeModalProps {
  isOpen: boolean;
  onClose: () => void;
  snapshot: {
    team_name?: string;
    light_balance?: number;
    shield_until?: string | null;
    unlocked_stations_count?: number;
    hints_unlocked_count?: number;
    spied_at?: string;
  } | null;
}

export const RavenEyeModal: React.FC<RavenEyeModalProps> = ({
  isOpen,
  onClose,
  snapshot,
}) => {
  if (!isOpen || !snapshot) return null;

  const shieldInfo = getShieldRemaining(snapshot.shield_until ?? null);

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/85 backdrop-blur-md animate-fadeIn">
      <div className="bg-evermyst-card border border-info/40 rounded-3xl w-full max-w-sm overflow-hidden shadow-2xl shadow-info/20 space-y-4 p-5 animate-scaleUp">
        {/* Header */}
        <div className="flex items-center justify-between border-b border-evermyst-border pb-3">
          <div className="flex items-center gap-2.5">
            <div className="w-10 h-10 rounded-2xl bg-info/20 text-info flex items-center justify-center shadow-lg shadow-info/25">
              <Eye className="w-6 h-6 animate-pulse" />
            </div>
            <div>
              <div className="text-[10px] text-info uppercase font-black tracking-widest">
                TÌNH BÁO QUẠ ĐEN
              </div>
              <h3 className="text-lg font-black text-white leading-tight">
                {snapshot.team_name || 'Đội Đối Thủ'}
              </h3>
            </div>
          </div>

          <button
            onClick={onClose}
            className="p-1.5 rounded-xl hover:bg-evermyst-surface text-evermyst-text-dim hover:text-white"
          >
            <X className="w-4 h-4" />
          </button>
        </div>

        {/* 5 Thông Số Tình Báo */}
        <div className="grid grid-cols-2 gap-2.5">
          {/* Thông số 1: Số dư Lumen */}
          <div className="p-3.5 rounded-2xl bg-evermyst-surface border border-evermyst-border flex flex-col justify-between">
            <div className="flex items-center gap-1.5 text-xs text-evermyst-text-dim font-bold">
              <Coins className="w-3.5 h-3.5 text-lumen" />
              <span>SỐ DƯ</span>
            </div>
            <div className="text-xl font-black text-lumen font-mono mt-1">
              {snapshot.light_balance ?? 0}✦
            </div>
          </div>

          {/* Thông số 2: Trạng thái Khiên */}
          <div className="p-3.5 rounded-2xl bg-evermyst-surface border border-evermyst-border flex flex-col justify-between">
            <div className="flex items-center gap-1.5 text-xs text-evermyst-text-dim font-bold">
              <Shield className="w-3.5 h-3.5 text-props" />
              <span>KHIÊN</span>
            </div>
            <div className={`text-xs font-black mt-1 ${shieldInfo.active ? 'text-props animate-pulse' : 'text-evermyst-text-muted'}`}>
              {shieldInfo.active ? shieldInfo.label : 'Không bật'}
            </div>
          </div>

          {/* Thông số 3: Trạm Đã Vượt */}
          <div className="p-3.5 rounded-2xl bg-evermyst-surface border border-evermyst-border flex flex-col justify-between">
            <div className="flex items-center gap-1.5 text-xs text-evermyst-text-dim font-bold">
              <MapPin className="w-3.5 h-3.5 text-success" />
              <span>TRẠM ĐÃ VƯỢT</span>
            </div>
            <div className="text-xl font-black text-success font-mono mt-1">
              {snapshot.unlocked_stations_count ?? 0}/5
            </div>
          </div>

          {/* Thông số 4: Hint Đã Mua */}
          <div className="p-3.5 rounded-2xl bg-evermyst-surface border border-evermyst-border flex flex-col justify-between">
            <div className="flex items-center gap-1.5 text-xs text-evermyst-text-dim font-bold">
              <Search className="w-3.5 h-3.5 text-amber-400" />
              <span>HINT ĐÃ MỞ</span>
            </div>
            <div className="text-xl font-black text-amber-400 font-mono mt-1">
              {snapshot.hints_unlocked_count ?? 0}
            </div>
          </div>
        </div>

        {/* Thông số 5: Thời điểm do thám */}
        <div className="p-2.5 rounded-xl bg-evermyst-surface/60 border border-evermyst-border/50 text-[11px] text-evermyst-text-muted flex items-center justify-between">
          <span className="flex items-center gap-1.5">
            <Clock className="w-3.5 h-3.5 text-info" />
            Thời điểm trinh sát:
          </span>
          <span className="font-mono text-evermyst-text font-semibold">
            {snapshot.spied_at ? formatTime(snapshot.spied_at) : 'Vừa xong'}
          </span>
        </div>

        {/* Nút Đóng */}
        <button
          type="button"
          onClick={onClose}
          className="w-full h-12 rounded-xl bg-evermyst-surface border border-evermyst-border hover:bg-evermyst-border text-white text-xs font-bold transition-all"
        >
          Đóng tình báo
        </button>
      </div>
    </div>
  );
};
