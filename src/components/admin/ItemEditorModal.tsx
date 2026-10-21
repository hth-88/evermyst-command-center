// ============================================================================
// ITEM EDITOR MODAL (ItemEditorModal.tsx)
// File: src/components/admin/ItemEditorModal.tsx
// Modal tạo/sửa vật phẩm shop theo Phase 5: name, description, price, effect_type,
// effect_value, duration_minutes (bắt buộc > 0 với shield), is_active
// ============================================================================
import React, { useState } from 'react';
import { callRpc } from '@/lib/rpc';
import type { ItemEffectType } from '@/lib/types';
import { X, CheckCircle2, AlertCircle, Package, Shield, Eye, Key, Flame } from 'lucide-react';

interface ItemEditorModalProps {
  item?: any | null;
  onClose: () => void;
  onSuccess: () => void;
}

export const ItemEditorModal: React.FC<ItemEditorModalProps> = ({
  item,
  onClose,
  onSuccess,
}) => {
  const isEditing = Boolean(item?.id);

  const [name, setName] = useState(item?.name || '');
  const [description, setDescription] = useState(item?.description || '');
  const [price, setPrice] = useState<number>(item?.price ?? 20);
  const [effectType, setEffectType] = useState<ItemEffectType>(
    item?.effect_type || 'shield'
  );
  const [effectValue, setEffectValue] = useState<number>(item?.effect_value ?? 0);
  const [durationMinutes, setDurationMinutes] = useState<number>(
    item?.duration_minutes ?? (item?.effect_type === 'shield' ? 15 : 0)
  );
  const [isActive, setIsActive] = useState<boolean>(item?.is_active ?? true);

  const [isSubmitting, setIsSubmitting] = useState(false);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!name.trim()) {
      setErrorMsg('Vui lòng nhập tên đạo cụ.');
      return;
    }
    if (price < 0) {
      setErrorMsg('Giá bán đạo cụ không được âm.');
      return;
    }
    if (effectType === 'shield' && durationMinutes <= 0) {
      setErrorMsg('Thời lượng bảo vệ của Khiên bắt buộc phải lớn hơn 0 phút.');
      return;
    }

    setIsSubmitting(true);
    setErrorMsg(null);

    try {
      const res = await callRpc('admin_upsert_item', {
        p_id: item?.id,
        p_name: name.trim(),
        p_description: description.trim(),
        p_price: price,
        p_effect_type: effectType,
        p_effect_value: effectValue,
        p_duration_minutes: durationMinutes,
        p_is_active: isActive,
      });

      if (res.success) {
        onSuccess();
        onClose();
      } else {
        setErrorMsg(res.error || res.message || 'Không thể lưu đạo cụ.');
      }
    } catch (err: any) {
      setErrorMsg(err.message || 'Lỗi hệ thống khi lưu đạo cụ.');
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
              <Package className="w-5 h-5" />
            </div>
            <div>
              <h3 className="text-sm font-black text-evermyst-text">
                {isEditing ? 'Chỉnh Sửa Đạo Cụ' : 'Tạo Đạo Cụ Phép Thuật Mới'}
              </h3>
              <p className="text-[11px] text-evermyst-text-dim">
                Thiết lập hiệu ứng và giá bán trong Shop
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
          {/* Tên & Giá */}
          <div className="grid grid-cols-3 gap-3">
            <div className="col-span-2 space-y-1">
              <label className="block text-[11px] font-bold text-evermyst-text-dim uppercase tracking-wider">
                Tên Đạo Cụ *
              </label>
              <input
                type="text"
                value={name}
                onChange={(e) => setName(e.target.value)}
                placeholder="Ví dụ: Khiên Hộ Vệ, Kính Viễn Vọng..."
                className="w-full h-10 rounded-xl bg-evermyst-surface border border-evermyst-border px-3 text-xs text-evermyst-text font-semibold focus:outline-none focus:border-lumen"
                required
              />
            </div>
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
          </div>

          {/* Mô tả */}
          <div className="space-y-1">
            <label className="block text-[11px] font-bold text-evermyst-text-dim uppercase tracking-wider">
              Mô Tả Hiệu Ứng
            </label>
            <textarea
              rows={2}
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              placeholder="Mô tả công dụng khi kích hoạt..."
              className="w-full rounded-xl bg-evermyst-surface border border-evermyst-border p-2.5 text-xs text-evermyst-text focus:outline-none focus:border-lumen resize-none"
            />
          </div>

          {/* Loại hiệu ứng */}
          <div className="space-y-1.5">
            <label className="block text-[11px] font-bold text-evermyst-text-dim uppercase tracking-wider">
              Loại Hiệu Ứng (Effect Type) *
            </label>
            <div className="grid grid-cols-4 gap-2">
              <button
                type="button"
                onClick={() => {
                  setEffectType('shield');
                  if (durationMinutes <= 0) setDurationMinutes(15);
                }}
                className={`p-2.5 rounded-xl border text-center transition-all ${
                  effectType === 'shield'
                    ? 'bg-props/20 border-props text-props font-bold'
                    : 'bg-evermyst-surface border-evermyst-border text-evermyst-text-dim'
                }`}
              >
                <Shield className="w-4 h-4 mx-auto mb-1" />
                Khiên
              </button>

              <button
                type="button"
                onClick={() => setEffectType('spy')}
                className={`p-2.5 rounded-xl border text-center transition-all ${
                  effectType === 'spy'
                    ? 'bg-purple-500/20 border-purple-500 text-purple-400 font-bold'
                    : 'bg-evermyst-surface border-evermyst-border text-evermyst-text-dim'
                }`}
              >
                <Eye className="w-4 h-4 mx-auto mb-1" />
                Do Thám
              </button>

              <button
                type="button"
                onClick={() => setEffectType('key')}
                className={`p-2.5 rounded-xl border text-center transition-all ${
                  effectType === 'key'
                    ? 'bg-lumen/20 border-lumen text-lumen font-bold'
                    : 'bg-evermyst-surface border-evermyst-border text-evermyst-text-dim'
                }`}
              >
                <Key className="w-4 h-4 mx-auto mb-1" />
                Chìa Khóa
              </button>

              <button
                type="button"
                onClick={() => setEffectType('custom')}
                className={`p-2.5 rounded-xl border text-center transition-all ${
                  effectType === 'custom'
                    ? 'bg-danger/20 border-danger text-danger font-bold'
                    : 'bg-evermyst-surface border-evermyst-border text-evermyst-text-dim'
                }`}
              >
                <Flame className="w-4 h-4 mx-auto mb-1" />
                Đặc Biệt
              </button>
            </div>
          </div>

          {/* Chi tiết thông số theo hiệu ứng */}
          <div className="grid grid-cols-2 gap-3 p-3 rounded-2xl bg-evermyst-surface/50 border border-evermyst-border">
            <div className="space-y-1">
              <label className="block text-[11px] font-bold text-evermyst-text-dim uppercase tracking-wider">
                Thời Lượng (Phút) {effectType === 'shield' ? '*' : ''}
              </label>
              <input
                type="number"
                min={0}
                value={durationMinutes}
                onChange={(e) => setDurationMinutes(parseInt(e.target.value) || 0)}
                placeholder="0"
                className="w-full h-9 rounded-xl bg-evermyst-card border border-evermyst-border px-3 font-mono font-bold text-evermyst-text"
              />
              {effectType === 'shield' && (
                <p className="text-[10px] text-props">Bắt buộc &gt; 0 cho Khiên</p>
              )}
            </div>

            <div className="space-y-1">
              <label className="block text-[11px] font-bold text-evermyst-text-dim uppercase tracking-wider">
                Giá Trị Bổ Sung (Value)
              </label>
              <input
                type="number"
                value={effectValue}
                onChange={(e) => setEffectValue(parseInt(e.target.value) || 0)}
                placeholder="0"
                className="w-full h-9 rounded-xl bg-evermyst-card border border-evermyst-border px-3 font-mono font-bold text-evermyst-text"
              />
              <p className="text-[10px] text-evermyst-text-dim">Mức cướp hoặc bonus nếu có</p>
            </div>
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
              <span className="font-bold text-evermyst-text">Đang Kích Hoạt Mở Bán Trong Shop</span>
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
                  Lưu Đạo Cụ
                </>
              )}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
};
