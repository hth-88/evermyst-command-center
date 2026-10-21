// ============================================================================
// HISTORY TAB (src/components/support/HistoryTab.tsx)
// File: src/components/support/HistoryTab.tsx
// Hiển thị lịch sử giao dịch và nút hoàn tác: chỉ hiển thị nút khi can_reverse = true
// Ràng buộc: Mọi cờ can_* lấy trực tiếp từ RPC get_history, không tự tính ở client
// ============================================================================
import React, { useState, useMemo, useEffect, useCallback } from 'react';
import { useGame } from '@/contexts/GameContext';
import { callRpc } from '@/lib/rpc';
import {
  RotateCcw,
  Clock,
  Loader2,
  AlertCircle,
  HelpCircle,
} from 'lucide-react';
import {
  formatTime,
  formatLumen,
  getTransactionLabel,
} from '@/lib/utils';
import type { Team, Transaction } from '@/lib/types';

interface HistoryTabProps {
  selectedTeam: Team | null;
}

export default function HistoryTab({ selectedTeam }: HistoryTabProps) {
  const { teams, user, transactions, reverseTransaction } = useGame();
  const [historyLogs, setHistoryLogs] = useState<Transaction[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [filterMode, setFilterMode] = useState<'team' | 'my' | 'all'>('team');
  const [isProcessing, setIsProcessing] = useState(false);
  const [reversalModal, setReversalModal] = useState<Transaction | null>(null);
  const [reversalReason, setReversalReason] = useState('');

  // Tải lịch sử kèm cờ can_reverse và reverse_blocked_reason từ RPC get_history
  const fetchHistory = useCallback(async () => {
    try {
      const res = await callRpc<any>('get_history', {
        p_team_id: selectedTeam?.id || null,
        p_limit: 100,
      });

      if (res.success && Array.isArray(res.transactions)) {
        setHistoryLogs(res.transactions);
      } else {
        const teamTxs = transactions.filter((t) => !selectedTeam || t.team_id === selectedTeam.id);
        setHistoryLogs(teamTxs);
      }
    } catch (err) {
      console.error('Lỗi tải lịch sử:', err);
      const teamTxs = transactions.filter((t) => !selectedTeam || t.team_id === selectedTeam.id);
      setHistoryLogs(teamTxs);
    } finally {
      setIsLoading(false);
    }
  }, [selectedTeam?.id, transactions]);

  useEffect(() => {
    fetchHistory();
  }, [fetchHistory]);

  const teamMap = useMemo(() => {
    const map = new Map<string, string>();
    teams.forEach((t) => map.set(t.id, t.name));
    return map;
  }, [teams]);

  const filteredTransactions = useMemo(() => {
    return historyLogs.filter((tx) => {
      if (filterMode === 'team') {
        if (!selectedTeam) return true;
        return tx.team_id === selectedTeam.id;
      }
      if (filterMode === 'my') {
        return tx.created_by === user?.name;
      }
      return true;
    });
  }, [historyLogs, filterMode, selectedTeam, user?.name]);

  const handleConfirmReversal = async () => {
    if (!reversalModal || isProcessing) return;
    setIsProcessing(true);

    const res = await reverseTransaction(reversalModal.id, reversalReason);

    setIsProcessing(false);
    if (res.success) {
      setReversalModal(null);
      setReversalReason('');
      await fetchHistory();
    }
  };

  return (
    <div className="p-4 space-y-4 pb-28 animate-fadeIn">
      {/* Filter Tabs */}
      <div className="flex bg-evermyst-surface p-1 rounded-xl border border-evermyst-border">
        <button
          onClick={() => setFilterMode('team')}
          className={`flex-1 py-2 text-xs font-bold rounded-lg transition-all ${
            filterMode === 'team'
              ? 'bg-lumen text-evermyst-bg shadow'
              : 'text-evermyst-text-muted hover:text-evermyst-text'
          }`}
        >
          {selectedTeam ? `Đội: ${selectedTeam.name}` : 'Theo Đội'}
        </button>
        <button
          onClick={() => setFilterMode('my')}
          className={`flex-1 py-2 text-xs font-bold rounded-lg transition-all ${
            filterMode === 'my'
              ? 'bg-lumen text-evermyst-bg shadow'
              : 'text-evermyst-text-muted hover:text-evermyst-text'
          }`}
        >
          Do Tôi Tạo
        </button>
        <button
          onClick={() => setFilterMode('all')}
          className={`flex-1 py-2 text-xs font-bold rounded-lg transition-all ${
            filterMode === 'all'
              ? 'bg-lumen text-evermyst-bg shadow'
              : 'text-evermyst-text-muted hover:text-evermyst-text'
          }`}
        >
          Toàn Bộ
        </button>
      </div>

      {/* Transaction List */}
      <div className="space-y-3">
        {isLoading ? (
          <div className="text-center py-12 text-evermyst-text-muted text-xs">
            Đang tải sổ cái giao dịch...
          </div>
        ) : filteredTransactions.length === 0 ? (
          <div className="text-center py-12 text-evermyst-text-muted text-xs">
            Chưa có giao dịch nào được ghi nhận
          </div>
        ) : (
          filteredTransactions.map((tx) => {
            const teamName = tx.team_name || teamMap.get(tx.team_id) || 'Đội chơi';
            // Cờ can_reverse và lý do chặn lấy 100% từ RPC get_history
            const canUndo = Boolean(tx.can_reverse);
            const blockedReason = tx.reverse_blocked_reason;

            return (
              <div
                key={tx.id}
                className={`p-3.5 rounded-2xl border transition-all ${
                  tx.is_reversed
                    ? 'bg-evermyst-surface/40 border-evermyst-border/40 opacity-60'
                    : 'bg-evermyst-card border-evermyst-border'
                }`}
              >
                <div className="flex items-start justify-between gap-2">
                  <div className="space-y-1">
                    <div className="flex items-center gap-1.5 flex-wrap">
                      <span className="text-xs font-bold text-evermyst-text">
                        {teamName}
                      </span>
                      <span className="text-[10px] px-1.5 py-0.5 rounded bg-evermyst-surface border border-evermyst-border text-evermyst-text-dim">
                        {getTransactionLabel(tx.type)}
                      </span>
                      {tx.status === 'pending' && (
                        <span className="text-[10px] px-1.5 py-0.5 rounded bg-warning/20 text-warning font-bold">
                          CHỜ DUYỆT
                        </span>
                      )}
                      {tx.is_reversed && (
                        <span className="text-[10px] px-1.5 py-0.5 rounded bg-danger/20 text-danger font-bold">
                          ĐÃ HOÀN TÁC
                        </span>
                      )}
                    </div>

                    <p className="text-xs text-evermyst-text-muted leading-relaxed">
                      {tx.description}
                    </p>

                    <div className="flex items-center gap-2 text-[10px] text-evermyst-text-dim pt-0.5">
                      <span>{formatTime(tx.created_at)}</span>
                      <span>•</span>
                      <span>Tạo bởi: {tx.created_by}</span>
                    </div>
                  </div>

                  <div className="text-right shrink-0">
                    <div
                      className={`text-base font-black font-mono ${
                        tx.amount >= 0 ? 'text-success' : 'text-danger'
                      }`}
                    >
                      {formatLumen(tx.amount)}✦
                    </div>
                  </div>
                </div>

                {/* Reversal Row: Chỉ hiện nút Hoàn Tác khi can_reverse = true, ngược lại hiện lý do */}
                <div className="mt-3 pt-2.5 border-t border-evermyst-border/50 flex items-center justify-between text-xs">
                  {canUndo ? (
                    <>
                      <span className="text-[11px] text-success font-semibold flex items-center gap-1">
                        <Clock className="w-3 h-3 text-warning" />
                        Có thể hoàn tác
                      </span>
                      <button
                        onClick={() => {
                          setReversalModal(tx);
                          setReversalReason('');
                        }}
                        className="h-8 px-3 rounded-xl bg-danger/15 hover:bg-danger/25 text-danger border border-danger/30 text-xs font-bold flex items-center gap-1 active:scale-95 transition-all shadow-sm"
                      >
                        <RotateCcw className="w-3 h-3" />
                        Hoàn Tác
                      </button>
                    </>
                  ) : (
                    blockedReason && (
                      <span className="text-[10px] text-evermyst-text-dim flex items-center gap-1 italic">
                        <HelpCircle className="w-3 h-3 text-evermyst-text-muted shrink-0" />
                        {blockedReason}
                      </span>
                    )
                  )}
                </div>
              </div>
            );
          })
        )}
      </div>

      {/* Confirmation Modal */}
      {reversalModal && (
        <div className="fixed inset-0 z-50 bg-black/85 flex items-center justify-center p-4 animate-fadeIn">
          <div className="w-full max-w-sm bg-evermyst-surface border border-evermyst-border rounded-2xl p-5 shadow-2xl space-y-4 animate-scaleUp">
            <div className="text-center">
              <div className="w-12 h-12 rounded-full bg-danger/15 text-danger border border-danger/30 flex items-center justify-center mx-auto mb-2">
                <RotateCcw className="w-6 h-6" />
              </div>
              <h3 className="text-base font-black text-evermyst-text">
                Xác nhận Hoàn tác Giao dịch
              </h3>
              <p className="text-xs text-evermyst-text-muted mt-1">
                Tạo giao dịch đảo ngược (
                <strong className={reversalModal.amount >= 0 ? 'text-danger' : 'text-success'}>
                  {formatLumen(-reversalModal.amount)} Lumen
                </strong>
                ) để bù trừ số dư theo ADR-4.
              </p>
            </div>

            <div className="p-3 bg-evermyst-card rounded-xl border border-evermyst-border text-xs space-y-1">
              <div className="text-evermyst-text font-bold">
                {teamMap.get(reversalModal.team_id)} • {reversalModal.description}
              </div>
              <div className="text-evermyst-text-dim font-mono">
                Số tiền gốc: {formatLumen(reversalModal.amount)} Lumen
              </div>
            </div>

            <div className="space-y-1.5">
              <label className="text-xs font-semibold text-evermyst-text-muted">
                Lý do hoàn tác (bắt buộc ghi nhận audit):
              </label>
              <input
                type="text"
                value={reversalReason}
                onChange={(e) => setReversalReason(e.target.value)}
                placeholder="Ví dụ: Bấm nhầm điểm trạm..."
                className="w-full h-11 px-3 bg-evermyst-bg border border-evermyst-border rounded-xl text-xs text-evermyst-text focus:outline-none focus:border-danger"
              />
            </div>

            <div className="flex gap-2">
              <button
                onClick={() => setReversalModal(null)}
                className="flex-1 h-12 rounded-xl bg-evermyst-card border border-evermyst-border text-xs font-bold text-evermyst-text-muted hover:text-white"
              >
                Hủy
              </button>
              <button
                onClick={handleConfirmReversal}
                disabled={isProcessing || !reversalReason.trim()}
                className="flex-1 h-12 rounded-xl bg-danger hover:bg-danger-dark text-white text-xs font-bold flex items-center justify-center gap-1.5 shadow active:scale-95 disabled:opacity-40 transition-all"
              >
                {isProcessing ? (
                  <Loader2 className="w-4 h-4 animate-spin" />
                ) : (
                  'Xác nhận Hoàn tác'
                )}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
