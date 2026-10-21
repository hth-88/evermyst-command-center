// ============================================================================
// PENDING ADMIN QUEUE (PendingAdminQueue.tsx)
// File: src/components/admin/PendingAdminQueue.tsx
// Hàng chờ duyệt dành riêng cho Admin (pending_admin):
// So sánh side-by-side input gốc vs input đã chỉnh, badge chìa khóa, duyệt / từ chối
// ============================================================================
import React, { useState } from 'react';
import { callRpc } from '@/lib/rpc';
import { formatScoringInput } from '@/scoring/format';
import {
  CheckCircle2,
  XCircle,
  AlertCircle,
  Key,
  Clock,
  ArrowRight,
  ShieldAlert,
  MessageSquare,
} from 'lucide-react';

interface PendingAdminQueueProps {
  claims: any[];
  onRefresh: () => void;
}

export const PendingAdminQueue: React.FC<PendingAdminQueueProps> = ({
  claims,
  onRefresh,
}) => {
  const [actionLoadingId, setActionLoadingId] = useState<string | null>(null);

  // Modal Từ chối của Admin
  const [rejectClaim, setRejectClaim] = useState<any | null>(null);
  const [rejectReason, setRejectReason] = useState('');
  const [errorMsg, setErrorMsg] = useState<string | null>(null);

  const handleApprove = async (claim: any) => {
    const claimId = claim.claim_id || claim.id;
    setActionLoadingId(claimId);
    try {
      const res = await callRpc('verify_station_claim', {
        p_claim_id: claimId,
        p_action: 'approve',
      });

      if (res.success) {
        onRefresh();
      } else {
        alert(res.error || res.message || 'Không thể phê duyệt claim.');
      }
    } finally {
      setActionLoadingId(null);
    }
  };

  const handleConfirmReject = async () => {
    if (!rejectClaim) return;
    if (!rejectReason.trim()) {
      setErrorMsg('Vui lòng nhập lý do từ chối claim.');
      return;
    }

    const claimId = rejectClaim.claim_id || rejectClaim.id;
    setActionLoadingId(claimId);
    try {
      const res = await callRpc('verify_station_claim', {
        p_claim_id: claimId,
        p_action: 'reject',
        p_note: rejectReason.trim(),
      });

      if (res.success) {
        setRejectClaim(null);
        setRejectReason('');
        onRefresh();
      } else {
        setErrorMsg(res.error || res.message || 'Không thể từ chối claim.');
      }
    } finally {
      setActionLoadingId(null);
    }
  };

  if (claims.length === 0) {
    return (
      <div className="p-12 text-center rounded-3xl bg-evermyst-card/40 border border-evermyst-border space-y-2">
        <CheckCircle2 className="w-10 h-10 text-success/60 mx-auto" />
        <p className="text-sm font-bold text-evermyst-text">Không có yêu cầu chờ BTC duyệt</p>
        <p className="text-xs text-evermyst-text-dim">
          Mọi kết quả thi đấu đã được xử lý hoàn tất hoặc tự động phê duyệt.
        </p>
      </div>
    );
  }

  return (
    <div className="space-y-4">
      {claims.map((claim) => {
        const claimId = claim.claim_id || claim.id;
        const isModified = Boolean(
          claim.original_input &&
          JSON.stringify(claim.original_input) !== JSON.stringify(claim.input)
        );

        return (
          <div
            key={claimId}
            className="p-4 rounded-3xl bg-evermyst-card border-2 border-warning/50 space-y-3.5 shadow-xl shadow-warning/5"
          >
            {/* Header: Đội chơi & Trạm & Điểm */}
            <div className="flex items-start justify-between">
              <div>
                <div className="flex items-center gap-2">
                  <span className="text-base font-black text-evermyst-text">
                    {claim.team_name}
                  </span>
                  <span className="px-2 py-0.5 rounded-md bg-warning/20 text-warning text-[10px] font-black uppercase">
                    Chờ BTC Duyệt
                  </span>
                </div>
                <div className="text-xs font-semibold text-evermyst-text-dim mt-0.5">
                  Tại trạm: <span className="text-white font-bold">{claim.station_name}</span>
                </div>
              </div>

              <div className="text-right">
                <div className="text-[10px] text-evermyst-text-dim">Điểm chốt</div>
                <div className="text-lg font-black font-mono text-warning">
                  +{claim.final_points ?? claim.computed_points}✦
                </div>
              </div>
            </div>

            {/* Badge Chìa Khóa nếu có */}
            {claim.key_used && (
              <div className="inline-flex items-center gap-1.5 px-3 py-1 rounded-xl bg-lumen/15 border border-lumen/40 text-xs font-black text-lumen">
                <Key className="w-3.5 h-3.5" />
                🗝️ ĐÃ DÙNG CHÌA KHÓA CỔ TÍCH
              </div>
            )}

            {/* SO SÁNH INPUT GỐC VS INPUT ĐÃ CHỈNH */}
            <div className="rounded-2xl bg-evermyst-surface border border-evermyst-border p-3.5 space-y-2">
              <div className="text-[11px] font-black uppercase text-evermyst-text-dim tracking-wider">
                So sánh dữ liệu nộp:
              </div>

              {isModified ? (
                <div className="grid grid-cols-2 gap-3 text-xs">
                  {/* Cột Trái: Input gốc */}
                  <div className="p-3 rounded-xl bg-evermyst-card/60 border border-evermyst-border space-y-1">
                    <span className="text-[10px] font-bold text-evermyst-text-dim uppercase">
                      1. Gốc (Support nộp):
                    </span>
                    <pre className="font-mono text-[11px] text-evermyst-text break-all whitespace-pre-wrap">
                      {JSON.stringify(claim.original_input || claim.input, null, 2)}
                    </pre>
                  </div>

                  {/* Cột Phải: Input đã chỉnh */}
                  <div className="p-3 rounded-xl bg-amber-500/10 border border-amber-500/30 space-y-1">
                    <span className="text-[10px] font-bold text-amber-400 uppercase flex items-center gap-1">
                      <ArrowRight className="w-3 h-3" /> 2. Đã chỉnh (Quản trò):
                    </span>
                    <pre className="font-mono text-[11px] text-amber-200 break-all whitespace-pre-wrap">
                      {JSON.stringify(claim.input, null, 2)}
                    </pre>
                  </div>
                </div>
              ) : (
                <div className="p-2.5 rounded-xl bg-evermyst-card/60 border border-evermyst-border">
                  <div className="text-[10px] text-evermyst-text-dim mb-1 font-bold">
                    Thông số nộp trực tiếp:
                  </div>
                  <pre className="font-mono text-[11px] text-evermyst-text break-all whitespace-pre-wrap">
                    {JSON.stringify(claim.input, null, 2)}
                  </pre>
                </div>
              )}

              {/* Ghi chú của Quản trò */}
              {claim.correction_note && (
                <div className="p-2.5 rounded-xl bg-amber-500/15 border border-amber-500/30 flex items-start gap-2 text-xs text-amber-200">
                  <MessageSquare className="w-4 h-4 shrink-0 mt-0.5 text-amber-400" />
                  <div>
                    <span className="font-bold text-amber-400">Ghi chú điều chỉnh: </span>
                    {claim.correction_note}
                  </div>
                </div>
              )}
            </div>

            {/* Nút hành động */}
            <div className="grid grid-cols-2 gap-2 pt-1">
              <button
                disabled={actionLoadingId === claimId}
                onClick={() => setRejectClaim(claim)}
                className="h-11 rounded-xl bg-danger/15 hover:bg-danger/25 text-danger border border-danger/30 text-xs font-bold flex items-center justify-center gap-1.5 active:scale-98 transition-all"
              >
                <XCircle className="w-4 h-4" />
                Từ Chối Claim
              </button>

              <button
                disabled={actionLoadingId === claimId}
                onClick={() => handleApprove(claim)}
                className="h-11 rounded-xl bg-gradient-to-r from-success to-emerald-600 text-evermyst-bg text-xs font-black uppercase flex items-center justify-center gap-1.5 active:scale-98 transition-all shadow-md shadow-success/20"
              >
                <CheckCircle2 className="w-4 h-4" />
                Phê Duyệt (+{claim.final_points ?? claim.computed_points}✦)
              </button>
            </div>
          </div>
        );
      })}

      {/* Modal Từ Chối Claim của Admin */}
      {rejectClaim && (
        <div className="fixed inset-0 z-50 bg-black/80 backdrop-blur-sm flex items-center justify-center p-4 animate-fadeIn">
          <div className="bg-evermyst-card border border-evermyst-border rounded-3xl p-5 w-full max-w-sm space-y-4 shadow-2xl">
            <div className="flex items-center gap-2 text-danger">
              <AlertCircle className="w-5 h-5 shrink-0" />
              <h3 className="text-sm font-black text-evermyst-text">
                Từ Chối Kết Quả Của Đội {rejectClaim.team_name}
              </h3>
            </div>

            <p className="text-xs text-evermyst-text-dim">
              Vui lòng nhập lý do từ chối để ghi vào lịch sử đội chơi:
            </p>

            <textarea
              rows={3}
              value={rejectReason}
              onChange={(e) => {
                setRejectReason(e.target.value);
                setErrorMsg(null);
              }}
              placeholder="Nhập lý do từ chối..."
              className="w-full rounded-xl bg-evermyst-surface border border-evermyst-border p-3 text-xs text-evermyst-text focus:outline-none focus:border-danger resize-none"
            />

            {errorMsg && (
              <div className="text-[11px] text-danger font-semibold flex items-center gap-1">
                <AlertCircle className="w-3.5 h-3.5 shrink-0" />
                {errorMsg}
              </div>
            )}

            <div className="grid grid-cols-2 gap-2 pt-1">
              <button
                onClick={() => setRejectClaim(null)}
                className="h-11 rounded-xl bg-evermyst-surface border border-evermyst-border text-xs font-bold text-evermyst-text-dim hover:text-white"
              >
                Hủy
              </button>
              <button
                onClick={handleConfirmReject}
                className="h-11 rounded-xl bg-danger text-white text-xs font-black uppercase hover:bg-danger/90 transition-all"
              >
                Xác Nhận Từ Chối
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};
