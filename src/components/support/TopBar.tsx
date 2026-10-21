// ============================================================================
// SUPPORT TOP BAR - Thanh Header cố định (TopBar.tsx)
// File: src/components/support/TopBar.tsx
// Hiển thị trực tiếp Đội được phân công từ Token (ADR-2, Phase 6)
// Xóa hoàn toàn bộ chọn đội (dropdown, quét QR đổi đội)
// ============================================================================
import React, { useState, useEffect } from 'react';
import { useSession } from '@/contexts/SessionContext';
import { Shield, LogOut } from 'lucide-react';
import { getShieldRemaining } from '@/lib/utils';
import { ConnectionIndicator } from '@/components/common/ConnectionIndicator';
import type { Team, ConnectionStatus } from '@/lib/types';

interface TopBarProps {
  assignedTeam: Team | null;
  connectionStatus?: ConnectionStatus;
  onRefresh?: () => void;
}

export default function TopBar({
  assignedTeam,
  connectionStatus = 'connected',
  onRefresh,
}: TopBarProps) {
  const { user, logout } = useSession();
  const [shieldState, setShieldState] = useState(() =>
    getShieldRemaining(assignedTeam?.shield_until ?? null)
  );

  // Đếm ngược Khiên bảo vệ thời gian thực
  useEffect(() => {
    const update = () => {
      setShieldState(getShieldRemaining(assignedTeam?.shield_until ?? null));
    };
    update();
    const interval = setInterval(update, 1000);
    return () => clearInterval(interval);
  }, [assignedTeam?.shield_until]);

  return (
    <header className="sticky top-0 z-40 bg-evermyst-surface/95 backdrop-blur-md border-b border-evermyst-border shadow-md">
      {/* Hàng 1: Thông tin Nhân sự & Trạng thái kết nối */}
      <div className="flex items-center justify-between px-3.5 py-1.5 border-b border-evermyst-border/40 text-xs">
        <div className="flex items-center gap-2">
          <span className="font-semibold text-evermyst-text">{user?.name}</span>
          <span className="px-1.5 py-0.5 rounded bg-lumen/15 text-lumen text-[10px] font-bold">
            Team Support
          </span>
          <ConnectionIndicator status={connectionStatus} onRefresh={onRefresh} compact />
        </div>

        <button
          onClick={logout}
          className="text-evermyst-text-dim hover:text-danger flex items-center gap-1 text-[11px] font-semibold transition-colors"
        >
          <LogOut className="w-3.5 h-3.5" /> Thoát
        </button>
      </div>

      {/* Hàng 2: Đội Được Phân Công Cố Định (KHÔNG có dropdown / QR Switcher) */}
      <div className="flex items-center justify-between px-3.5 py-2.5 bg-evermyst-card/60">
        <div className="truncate pr-2">
          <div className="text-[10px] uppercase tracking-wider font-bold text-evermyst-text-dim">
            Đội Phụ Trách
          </div>
          <div className="text-base font-black text-evermyst-text truncate">
            {assignedTeam?.name || user?.assigned_team?.name || 'Đội chưa xác định'}
          </div>
        </div>

        {/* Số dư & Khiên */}
        <div className="flex items-center gap-2.5 shrink-0">
          {shieldState.active && (
            <div className="flex items-center gap-1 px-2.5 py-1 rounded-xl bg-props/15 border border-props/30 text-props text-xs font-bold animate-pulse">
              <Shield className="w-3.5 h-3.5" />
              <span>{shieldState.label}</span>
            </div>
          )}

          <div className="px-3 py-1 rounded-xl bg-lumen/10 border border-lumen/25 text-right">
            <div className="text-[9px] text-evermyst-text-dim font-bold">LUMEN</div>
            <div className="text-base font-black text-lumen font-mono leading-none">
              {assignedTeam?.light_balance ?? 0}✦
            </div>
          </div>
        </div>
      </div>
    </header>
  );
}
