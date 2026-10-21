// ============================================================================
// FORCE REVERT MODAL (ForceRevertModal.tsx)
// File: src/components/admin/ForceRevertModal.tsx
// Hộp thoại xác nhận hoàn tác bắt buộc (Force Revert) với p_force: true
// Vượt qua kiểm tra thời gian 5 phút hoặc quyền thông thường theo Phase 7 spec.
// ============================================================================
import React, { useState } from 'react';
import { callRpc } from '@/lib/rpc';
import {
  X,
  AlertTriangle,
  RotateCcw,
  AlertCircle,
  CheckCircle2,
  ShieldAlert,
} from 'lucide-react';

interface ForceRevertModalProps {
  transaction: any;
  onClose: () => void;
  onSuccess: () => void;
}

export const ForceRevertModal: React.FC<ForceRevertModalProps> = ({
  transaction,
  onClose,
  onSuccess,
}) => {
  const [reason, setReason] = useState('');
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);

  const handleConfirmForceRevert = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!reason.trim()) {
      setErrorMsg('BẮT BUỘC phải nhập lý do giải trình khi thực hiện Hoàn tác Bắt buộc.');
      return;
    }

    setIsSubmitting(true);
    setErrorMsg(null);

    try {
      const res = await callRpc('reverse_transaction', {
        p_tx_id: transaction.id,
        p_force: true,
        p_reason: reason.trim(),
      });

      if (res.success) {
        onSuccess();
        onClose();
      } else {
        setErrorMsg(res.error || res.message || 'Không thể thực hiện hoàn tác bắt buộc.');
      }
    } catch (err: any) {
      setErrorMsg(err.message || 'Lỗi hệ thống khi hoàn tác bắt buộc.');
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 bg-black/85 backdrop-blur-md flex items-center justify-center p-4 animate-fadeIn">
      <div className="bg-evermyst-card border-2 border-danger/60 rounded-3xl w-full max-w-md flex flex-col shadow-2xl overflow-hidden">
        {/* Header Cảnh Báo Nguy Hiểm */}
        <div className="p-4 border-b border-danger/30 flex items-center justify-between bg-danger/10">
          <div className="flex items-center gap-2.5 text-danger">
            <div className="w-10 h-10 rounded-xl bg-danger/20 border border-danger/40 flex items-center justify-center">
              <ShieldAlert className="w-6 h-6 text-danger" />
            </div>
            <div>
              <h3 className="text-sm font-black text-danger tracking-wide uppercase">
                Xác Nhận Force Revert
              </h3>
              <p className="text-[11px] text-danger/80 font-bold">
                Hoàn tác can thiệp cấp cao của Admin
              </p>
            </div>
          </div>
          <button
            onClick={onClose}
            className="p-1.5 rounded-lg text-evermyst-text-dim hover:text-white"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* Nội dung cảnh báo & chi tiết giao dịch */}
        <form onSubmit={handleConfirmForceRevert} className="p-5 space-y-4 text-xs">
          <div className="p-3 rounded-2xl bg-danger/10 border border-danger/30 text-danger text-xs space-y-1.5">
            <div className="font-bold flex items-center gap-1.5">
              <AlertTriangle className="w-4 h-4 shrink-0" />
              Lý do không đủ điều kiện thông thường:
            </div>
            <p className="text-[11px] font-semibold text-evermyst-text">
              {transaction.reverse_blocked_reason || 'Đã quá thời gian hoàn tác tiêu chuẩn (5 phút).'}
            </p>
          </div>

          {/* Chi tiết transaction */}
          <div className="p-3.5 rounded-2xl bg-evermyst-surface border border-evermyst-border space-y-2">
            <div className="flex items-center justify-between text-xs">
              <span className="text-evermyst-text-dim">Mã Giao Dịch:</span>
              <span className="font-mono text-evermyst-text font-bold truncate max-w-[160px]">
                {transaction.id}
              </span>
            </div>
            <div className="flex items-center justify-between text-xs">
              <span className="text-evermyst-text-dim">Đội Chơi:</span>
              <span className="font-bold text-white">{transaction.team_name}</span>
            </div>
            <div className="flex items-center justify-between text-xs">
              <span className="text-evermyst-text-dim">Số Lượng Lumen:</span>
              <span className="font-mono font-black text-danger text-sm">
                {transaction.amount > 0 ? `+${transaction.amount}` : transaction.amount}✦
              </span>
            </div>
            <div className="flex items-center justify-between text-xs">
              <span className="text-evermyst-text-dim">Diễn Giải:</span>
              <span className="text-evermyst-text-muted truncate max-w-[200px]">
                {transaction.description}
              </span>
            </div>
          </div>

          {/* Nhập lý do bắt buộc */}
          <div className="space-y-1.5">
            <label className="block text-[11px] font-black text-danger uppercase tracking-wider">
              Lý Do Ép Buộc Hoàn Tác (Bắt buộc) *
            </label>
            <textarea
              rows={3}
              value={reason}
              onChange={(e) => {
                setReason(e.target.value);
                setErrorMsg(null);
              }}
              placeholder="Giải trình lý do Admin can thiệp hoàn tác bắt buộc..."
              className="w-full rounded-xl bg-evermyst-surface border border-danger/50 p-3 text-xs text-evermyst-text focus:outline-none focus:border-danger resize-none"
              required
            />
            <p className="text-[10px] text-evermyst-text-dim">
              * Hành động này sẽ tạo dòng ledger đối ứng loại reversal và lưu nhật ký kiểm toán.
            </p>
          </div>

          {errorMsg && (
            <div className="p-3 rounded-xl bg-danger/20 border border-danger/40 text-danger text-xs font-bold flex items-center gap-2">
              <AlertCircle className="w-4 h-4 shrink-0" />
              {errorMsg}
            </div>
          )}

          <div className="grid grid-cols-2 gap-2 pt-2">
            <button
              type="button"
              onClick={onClose}
              className="h-12 rounded-xl bg-evermyst-surface border border-evermyst-border text-xs font-bold text-evermyst-text-dim hover:text-white"
            >
              Hủy Bỏ
            </button>
            <button
              type="submit"
              disabled={isSubmitting}
              className="h-12 rounded-xl bg-danger text-white text-xs font-black uppercase hover:bg-danger/90 transition-all shadow-lg shadow-danger/25 flex items-center justify-center gap-1.5"
            >
              {isSubmitting ? (
                <div className="w-4 h-4 border-2 border-white border-t-transparent rounded-full animate-spin" />
              ) : (
                <>
                  <RotateCcw className="w-4 h-4" />
                  Xác Nhận Force Revert
                </>
              )}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
};
