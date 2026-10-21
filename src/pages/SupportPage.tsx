// ============================================================================
// SUPPORT PAGE - Màn hình điều hành Mobile POS cho Support (SupportPage.tsx)
// File: src/pages/SupportPage.tsx
// Luôn làm việc trên đội từ assigned_team, không còn team switcher (Phase 6)
// ============================================================================
import React, { useState, useMemo } from 'react';
import { useSession } from '@/contexts/SessionContext';
import { useGame } from '@/contexts/GameContext';
import { useSignal } from '@/hooks/useSignal';
import TopBar from '@/components/support/TopBar';
import StationTab from '@/components/support/StationTab';
import ShopTab from '@/components/support/ShopTab';
import PvPTab from '@/components/support/PvPTab';
import HistoryTab from '@/components/support/HistoryTab';
import { MapPin, ShoppingBag, Swords, History } from 'lucide-react';
import type { SupportTab } from '@/lib/types';

export default function SupportPage() {
  const { user } = useSession();
  const { teams, refreshAll } = useGame();
  const [activeTab, setActiveTab] = useState<SupportTab>('station');
  const [selectedOverrideTeamId, setSelectedOverrideTeamId] = useState<string | null>(null);

  // Đội phụ trách: Lấy từ token hoặc tự động nhận diện từ tên tài khoản nhân sự
  const assignedTeam = useMemo(() => {
    if (!user) return null;
    if (selectedOverrideTeamId) {
      const override = teams.find((t) => t.id === selectedOverrideTeamId);
      if (override) return override;
    }

    const targetId = user.assigned_team_id || user.assigned_team?.id;
    if (targetId) {
      const found = teams.find((t) => t.id === targetId);
      if (found) return found;
    }

    // Tự nhận thức thông minh từ tên nhân sự (vd: "Hỗ Trợ Đội 1 (Lửa Thiêng)" -> "Lửa Thiêng")
    if (user.name && teams.length > 0) {
      const uName = user.name.toLowerCase();
      const matched = teams.find((t) => {
        const cleanT = t.name.toLowerCase().replace(/[^a-zA-Z0-9À-ỹ]/g, '');
        return uName.includes(cleanT) ||
               (uName.includes('đội 1') || uName.includes('lửa thiêng')) && (t.name.includes('Lửa Thiêng') || t.name.includes('1')) ||
               (uName.includes('đội 2') || uName.includes('sóng thần')) && (t.name.includes('Sóng Thần') || t.name.includes('2')) ||
               (uName.includes('đội 3') || uName.includes('rừng xanh')) && (t.name.includes('Rừng Xanh') || t.name.includes('3')) ||
               (uName.includes('đội 4') || uName.includes('sấm sét')) && (t.name.includes('Sấm Sét') || t.name.includes('4')) ||
               (uName.includes('đội 5') || uName.includes('trăng khuyết')) && (t.name.includes('Trăng Khuyết') || t.name.includes('5')) ||
               (uName.includes('đội 6') || uName.includes('bình minh')) && (t.name.includes('Bình Minh') || t.name.includes('6'));
      });
      if (matched) return matched;
    }

    // Fallback đội đầu tiên nếu chưa được gán cứng trên database
    return teams.length > 0 ? teams[0] : null;
  }, [teams, user, selectedOverrideTeamId]);

  // Hook useSignal lắng nghe cập nhật realtime với debounce 300ms và polling 10s
  const { status, refetchNow } = useSignal('teams_changed', () => {
    refreshAll();
  });

  return (
    <div className="min-h-screen bg-evermyst-bg text-evermyst-text flex flex-col justify-between max-w-md mx-auto shadow-2xl relative select-none">
      {/* Top Sticky Bar - Hiển thị cố định đội được gán */}
      <TopBar
        assignedTeam={assignedTeam}
        connectionStatus={status}
        onRefresh={refetchNow}
      />

      {/* Main Tab Content */}
      <main className="flex-1 overflow-y-auto">
        {activeTab === 'station' && <StationTab selectedTeam={assignedTeam} />}
        {activeTab === 'shop' && <ShopTab selectedTeam={assignedTeam} />}
        {activeTab === 'pvp' && <PvPTab selectedTeam={assignedTeam} />}
        {activeTab === 'history' && <HistoryTab selectedTeam={assignedTeam} />}
      </main>

      {/* Bottom Sticky Navigation Bar (1 tay cho 4G ngoài trời, nút >= 56px) */}
      <nav className="fixed bottom-0 left-0 right-0 z-40 bg-evermyst-surface/95 backdrop-blur-md border-t border-evermyst-border max-w-md mx-auto">
        <div className="grid grid-cols-4 h-16">
          {/* Tab 1: Trạm */}
          <button
            onClick={() => setActiveTab('station')}
            className={`flex flex-col items-center justify-center transition-all ${
              activeTab === 'station'
                ? 'text-lumen font-black'
                : 'text-evermyst-text-dim hover:text-evermyst-text'
            }`}
          >
            <div className={`p-1 rounded-xl transition-all ${activeTab === 'station' ? 'bg-lumen/15' : ''}`}>
              <MapPin className="w-5 h-5" />
            </div>
            <span className="text-[10px] mt-0.5 tracking-tight font-bold">Trạm</span>
          </button>

          {/* Tab 2: Shop & Hint */}
          <button
            onClick={() => setActiveTab('shop')}
            className={`flex flex-col items-center justify-center transition-all ${
              activeTab === 'shop'
                ? 'text-lumen font-black'
                : 'text-evermyst-text-dim hover:text-evermyst-text'
            }`}
          >
            <div className={`p-1 rounded-xl transition-all ${activeTab === 'shop' ? 'bg-lumen/15' : ''}`}>
              <ShoppingBag className="w-5 h-5" />
            </div>
            <span className="text-[10px] mt-0.5 tracking-tight font-bold">Shop & Hint</span>
          </button>

          {/* Tab 3: PvP */}
          <button
            onClick={() => setActiveTab('pvp')}
            className={`flex flex-col items-center justify-center transition-all ${
              activeTab === 'pvp'
                ? 'text-danger font-black'
                : 'text-evermyst-text-dim hover:text-evermyst-text'
            }`}
          >
            <div className={`p-1 rounded-xl transition-all ${activeTab === 'pvp' ? 'bg-danger/15' : ''}`}>
              <Swords className="w-5 h-5" />
            </div>
            <span className="text-[10px] mt-0.5 tracking-tight font-bold">PvP Combat</span>
          </button>

          {/* Tab 4: Lịch sử */}
          <button
            onClick={() => setActiveTab('history')}
            className={`flex flex-col items-center justify-center transition-all ${
              activeTab === 'history'
                ? 'text-lumen font-black'
                : 'text-evermyst-text-dim hover:text-evermyst-text'
            }`}
          >
            <div className={`p-1 rounded-xl transition-all ${activeTab === 'history' ? 'bg-lumen/15' : ''}`}>
              <History className="w-5 h-5" />
            </div>
            <span className="text-[10px] mt-0.5 tracking-tight font-bold">Lịch Sử</span>
          </button>
        </div>
      </nav>
    </div>
  );
}
