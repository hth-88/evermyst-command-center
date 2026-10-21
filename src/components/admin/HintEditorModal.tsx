// ============================================================================
// HINT EDITOR MODAL (HintEditorModal.tsx)
// File: src/components/admin/HintEditorModal.tsx
// Modal tạo/sửa gợi ý mật theo Phase 5: title, tier, price, content, station_id, is_active
// ============================================================================
import React, { useState } from 'react';
import { callRpc } from '@/lib/rpc';
import type { HintTier } from '@/lib/types';
import { X, CheckCircle2, AlertCircle, HelpCircle } from 'lucide-react';

interface HintEditorModalProps {
  hint?: any | null;
  stations: Array<{ id: string; name: string }>;
  onClose: () => void;
  onSuccess: () => void;
}

export const HintEditorModal: React.FC<HintEditorModalProps> = ({
  hint,
  stations,
  onClose,
  onSuccess,
}) => {
  const isEditing = Boolean(hint?.id);

  const [title, setTitle] = useState(hint?.title || '');
  const [tier, setTier] = useState<HintTier>(hint?.tier || 'bronze');
  const [price, setPrice] = useState<number>(hint?.price ?? 10);
  const [content, setContent] = useState(hint?.content || '');
  const [stationId, setStationId] = useState<string>(hint?.station_id || '');
  const [isActive, setIsActive] = useState<boolean>(hint?.is_active ?? true);

  const [isSubmitting, setIsSubmitting] = useState(false);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!title.trim()) {
      setErrorMsg('Vui lòng nhập tiêu đề gợi ý.');
      return;
    }
    if (!content.trim()) {
      setErrorMsg('Vui lòng nhập nội dung gợi ý mật.');
      return;
    }
    if (price < 0) {
      setErrorMsg('Giá mở gợi ý không được nhỏ hơn 0.');
      return;
    }

    setIsSubmitting(true);
    setErrorMsg(null);

    try {
      const res = await callRpc('admin_upsert_hint', {
        p_id: hint?.id,
        p_title: title.trim(),
        p_content: content.trim(),
        p_tier: tier,
        p_price: price,
        p_station_id: stationId ? stationId : null,
        p_is_active: isActive,
      });

      if (res.success) {
        onSuccess();
        onClose();
      } else {
        setErrorMsg(res.error || res.message || 'Không thể lưu manh mối.');
      }
    } catch (err: any) {
      setErrorMsg(err.message || 'Lỗi hệ thống khi lưu manh mối.');
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 bg-black/80 backdrop-blur-sm flex items-center justify-center p-4 animate-fadeIn">
      <div className="bg-evermyst-card border border-evermyst-border rounded-3xl w-full max-w-lg flex flex-col shadow-2xl overflow-hidden">
        {/* Header */}
        <div className="p-4 border-b border-evermyst-border flex items-center justify-between bg-evermyst-surface">
          <div className="flex items-center gap-2.5">
            <div className="w-9 h-9 rounded-xl bg-lumen/15 border border-lumen/30 flex items-center justify-center text-lumen">
              <HelpCircle className="w-5 h-5" />
            </div>
            <div>
              <h3 className="text-sm font-black text-evermyst-text">
                {isEditing ? 'Chỉnh Sửa Manh Mối' : 'Tạo Manh Mối Mật Mới'}
              </h3>
              <p className="text-[11px] text-evermyst-text-dim">
                Cung cấp gợi ý giải đố cho các đội chơi
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
          {/* Tiêu đề & Cấp độ */}
          <div className="grid grid-cols-3 gap-3">
            <div className="col-span-2 space-y-1">
              <label className="block text-[11px] font-bold text-evermyst-text-dim uppercase tracking-wider">
                Tiêu Đề Manh Mối *
              </label>
              <input
                type="text"
                value={title}
                onChange={(e) => setTitle(e.target.value)}
                placeholder="Ví dụ: Lời nguyền tháp cổ..."
                className="w-full h-10 rounded-xl bg-evermyst-surface border border-evermyst-border px-3 text-xs text-evermyst-text font-semibold focus:outline-none focus:border-lumen"
                required
              />
            </div>
            <div className="space-y-1">
              <label className="block text-[11px] font-bold text-evermyst-text-dim uppercase tracking-wider">
                Cấp Độ (Tier)
              </label>
              <select
                value={tier}
                onChange={(e) => setTier(e.target.value as HintTier)}
                className="w-full h-10 rounded-xl bg-evermyst-surface border border-evermyst-border px-3 text-xs text-evermyst-text font-bold focus:outline-none focus:border-lumen"
              >
                <option value="bronze">Đồng (Bronze)</option>
                <option value="silver">Bạc (Silver)</option>
                <option value="gold">Vàng (Gold)</option>
                <option value="custom">Đặc Biệt (Custom)</option>
              </select>
            </div>
          </div>

          {/* Giá bán & Trạm liên kết */}
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1">
              <label className="block text-[11px] font-bold text-evermyst-text-dim uppercase tracking-wider">
                Giá Bán (Lumen) *
              </label>
              <input
                type="number"
                min={0}
                value={price}
                onChange={(e) => setPrice(parseInt(e.target.value) || 0)}
                className="w-full h-10 rounded-xl bg-evermyst-surface border border-evermyst-border px-3 font-mono font-bold text-lumen focus:outline-none focus:border-lumen"
                required
              />
            </div>
            <div className="space-y-1">
              <label className="block text-[11px] font-bold text-evermyst-text-dim uppercase tracking-wider">
                Trạm Liên Kết (Tùy chọn)
              </label>
              <select
                value={stationId}
                onChange={(e) => setStationId(e.target.value)}
                className="w-full h-10 rounded-xl bg-evermyst-surface border border-evermyst-border px-3 text-xs text-evermyst-text font-semibold focus:outline-none focus:border-lumen"
              >
                <option value="">-- Dùng chung toàn game --</option>
                {stations.map((st) => (
                  <option key={st.id} value={st.id}>
                    {st.name}
                  </option>
                ))}
              </select>
            </div>
          </div>

          {/* Nội dung manh mối */}
          <div className="space-y-1">
            <label className="block text-[11px] font-bold text-evermyst-text-dim uppercase tracking-wider">
              Nội Dung Gợi Ý Mật (Mở sau khi mua) *
            </label>
            <textarea
              rows={4}
              value={content}
              onChange={(e) => setContent(e.target.value)}
              placeholder="Nhập nội dung bí mật, câu đố hoặc tọa độ giải cứu..."
              className="w-full rounded-xl bg-evermyst-surface border border-evermyst-border p-3 text-xs text-evermyst-text focus:outline-none focus:border-lumen resize-none"
              required
            />
          </div>

          {/* Kích hoạt */}
          <div className="p-3 rounded-2xl bg-evermyst-surface/40 border border-evermyst-border">
            <label className="flex items-center gap-2 cursor-pointer">
              <input
                type="checkbox"
                checked={isActive}
                onChange={(e) => setIsActive(e.target.checked)}
                className="w-4 h-4 rounded text-lumen"
              />
              <span className="font-bold text-evermyst-text">Đang Kích Hoạt Mở Bán</span>
            </label>
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
                  Lưu Manh Mối
                </>
              )}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
};
