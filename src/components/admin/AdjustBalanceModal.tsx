// ============================================================================
// ADJUST BALANCE MODAL (AdjustBalanceModal.tsx)
// File: src/components/admin/AdjustBalanceModal.tsx
// Modal cộng/trừ Lumen cho đội chơi, BẮT BUỘC nhập lý do theo Phase 7 spec.
// ============================================================================
import React, { useState } from 'react';
import { callRpc } from '@/lib/rpc';
import { X, CheckCircle2, AlertCircle, Plus, Minus, Sparkles } from 'lucide-react';

interface AdjustBalanceModalProps {
  team: { id: string; name: string; light_balance: number };
  onClose: () => void;
  onSuccess: () => void;
}

const QUICK_ADJUST_REASONS = [
  'Thưởng mini-game phụ',
  'Phạt vi phạm nội quy',
  'Bù trừ sự cố kỹ thuật trạm',
  'Hỗ trợ đạo cụ sự kiện',
  'Điều chỉnh cân bằng game',
];

export const AdjustBalanceModal: React.FC<AdjustBalanceModalProps> = ({
  team,
  onClose,
  onSuccess,
}) => {
  const [amountStr, setAmountStr] = useState<string>('10');
  const [isPositive, setIsPositive] = useState<boolean>(true);
  const [reason, setReason] = useState<string>('');
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    const parsedAmount = parseInt(amountStr);
    if (isNaN(parsedAmount) || parsedAmount <= 0) {
      setErrorMsg('Vui lòng nhập số lượng Lumen hợp lệ (> 0).');
      return;
    }

    if (!reason.trim()) {
      setErrorMsg('BẮT BUỘC phải nhập lý do điều chỉnh để ghi sổ kiểm toán.');
      return;
    }

    const finalAmount = isPositive ? parsedAmount : -parsedAmount;

    // Kiểm tra không để số dư âm
    if (finalAmount < 0 && team.light_balance + finalAmount < 0) {
      setErrorMsg(`Không thể trừ vượt quá số dư hiện tại (${team.light_balance}✦).`);
      return;
    }

    setIsSubmitting(true);
    setErrorMsg(null);

    try {
      const res = await callRpc('admin_adjust_balance', {
        p_team_id: team.id,
        p_amount: finalAmount,
        p_description: reason.trim(),
      });

      if (res.success) {
        onSuccess();
        onClose();
      } else {
        setErrorMsg(res.error || res.message || 'Không thể điều chỉnh số dư.');
      }
    } catch (err: any) {
      setErrorMsg(err.message || 'Lỗi hệ thống khi điều chỉnh số dư.');
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 bg-black/80 backdrop-blur-sm flex items-center justify-center p-4 animate-fadeIn">
      <div className="bg-evermyst-card border border-evermyst-border rounded-3xl w-full max-w-md flex flex-col shadow-2xl overflow-hidden">
        {/* Header */}
        <div className="p-4 border-b border-evermyst-border flex items-center justify-between bg-evermyst-surface">
          <div className="flex items-center gap-2.5">
            <div className="w-9 h-9 rounded-xl bg-lumen/15 border border-lumen/30 flex items-center justify-center text-lumen font-black text-sm">
              ±✦
            </div>
            <div>
              <h3 className="text-sm font-black text-evermyst-text">
                Điều Chỉnh Lumen Thủ Công
              </h3>
              <p className="text-[11px] text-evermyst-text-dim">
                Đội chơi: <strong className="text-white">{team.name}</strong> • Hiện có:{' '}
                <span className="text-lumen font-mono font-bold">{team.light_balance}✦</span>
              </p>
            </div>
          </div>
          <button
            onClick={onClose}
            className="p-1.5 rounded-lg text-evermyst-text-dim hover:text-white hover:bg-evermyst-card"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* Form Body */}
        <form onSubmit={handleSubmit} className="p-5 space-y-4 text-xs">
          {/* Toggle Cộng / Trừ & Nhập số lượng */}
          <div className="space-y-1.5">
            <label className="block text-[11px] font-bold text-evermyst-text-dim uppercase tracking-wider">
              Chọn Thao Tác & Số Lượng Lumen
            </label>
            <div className="flex items-center gap-2">
              <button
                type="button"
                onClick={() => setIsPositive(true)}
                className={`h-11 px-4 rounded-xl font-black text-xs flex items-center gap-1 border transition-all ${
                  isPositive
                    ? 'bg-success text-evermyst-bg border-success shadow-md shadow-success/20'
                    : 'bg-evermyst-surface text-evermyst-text-dim border-evermyst-border'
                }`}
              >
                <Plus className="w-4 h-4" /> Cộng
              </button>

              <button
                type="button"
                onClick={() => setIsPositive(false)}
                className={`h-11 px-4 rounded-xl font-black text-xs flex items-center gap-1 border transition-all ${
                  !isPositive
                    ? 'bg-danger text-white border-danger shadow-md shadow-danger/20'
                    : 'bg-evermyst-surface text-evermyst-text-dim border-evermyst-border'
                }`}
              >
                <Minus className="w-4 h-4" /> Trừ
              </button>

              <div className="relative flex-1">
                <input
                  type="number"
                  min={1}
                  value={amountStr}
                  onChange={(e) => setAmountStr(e.target.value)}
                  className="w-full h-11 rounded-xl bg-evermyst-surface border border-evermyst-border px-3 font-mono font-black text-base text-evermyst-text focus:outline-none focus:border-lumen"
                  required
                />
                <span className="absolute right-3 top-3 text-xs font-mono font-bold text-evermyst-text-dim">
                  Lumen
                </span>
              </div>
            </div>
          </div>

          {/* Lý do điều chỉnh (Bắt buộc) */}
          <div className="space-y-2">
            <div className="flex items-center justify-between">
              <label className="block text-[11px] font-black text-lumen uppercase tracking-wider">
                Lý Do Điều Chỉnh (Bắt buộc) *
              </label>
            </div>

            {/* Chip lý do nhanh */}
            <div className="flex flex-wrap gap-1.5">
              {QUICK_ADJUST_REASONS.map((chip: string) => (
                <button
                  key={chip}
                  type="button"
                  onClick={() => {
                    setReason(chip);
                    setErrorMsg(null);
                  }}
                  className={`px-2.5 py-1 rounded-lg text-[10px] font-semibold border transition-all ${
                    reason === chip
                      ? 'bg-lumen text-evermyst-bg border-lumen font-bold'
                      : 'bg-evermyst-surface text-evermyst-text-dim border-evermyst-border hover:border-lumen/40'
                  }`}
                >
                  {chip}
                </button>
              ))}
            </div>

            <textarea
              rows={2}
              value={reason}
              onChange={(e) => {
                setReason(e.target.value);
                setErrorMsg(null);
              }}
              placeholder="Nhập lý do chi tiết để lưu vào Audit Log..."
              className="w-full rounded-xl bg-evermyst-surface border border-evermyst-border p-2.5 text-xs text-evermyst-text focus:outline-none focus:border-lumen resize-none"
              required
            />
          </div>

          {/* Dự kiến số dư sau điều chỉnh */}
          <div className="p-3 rounded-2xl bg-evermyst-surface/50 border border-evermyst-border flex items-center justify-between text-xs">
            <span className="text-evermyst-text-dim font-bold">Số dư sau điều chỉnh:</span>
            <span className="font-mono font-black text-sm text-evermyst-text">
              {team.light_balance}✦{' '}
              <span className={isPositive ? 'text-success' : 'text-danger'}>
                {isPositive ? '+' : '-'}{parseInt(amountStr) || 0}✦
              </span>{' '}
              ={' '}
              <span className="text-lumen font-black">
                {team.light_balance + (isPositive ? (parseInt(amountStr) || 0) : -(parseInt(amountStr) || 0))}✦
              </span>
            </span>
          </div>

          {errorMsg && (
            <div className="p-3 rounded-xl bg-danger/20 border border-danger/40 text-danger text-xs font-bold flex items-center gap-2">
              <AlertCircle className="w-4 h-4 shrink-0" />
              {errorMsg}
            </div>
          )}

          <div className="grid grid-cols-2 gap-2 pt-1">
            <button
              type="button"
              onClick={onClose}
              className="h-11 rounded-xl bg-evermyst-surface border border-evermyst-border text-xs font-bold text-evermyst-text-dim hover:text-white"
            >
              Hủy Bỏ
            </button>
            <button
              type="submit"
              disabled={isSubmitting}
              className="h-11 rounded-xl bg-lumen text-evermyst-bg text-xs font-black uppercase hover:bg-lumen/90 transition-all shadow-md shadow-lumen/20 flex items-center justify-center gap-1.5"
            >
              {isSubmitting ? (
                <div className="w-4 h-4 border-2 border-evermyst-bg border-t-transparent rounded-full animate-spin" />
              ) : (
                <>
                  <CheckCircle2 className="w-4 h-4" />
                  Xác Nhận Thay Đổi
                </>
              )}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
};
