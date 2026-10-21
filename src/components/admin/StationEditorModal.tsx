// ============================================================================
// STATION EDITOR MODAL (StationEditorModal.tsx)
// File: src/components/admin/StationEditorModal.tsx
// Modal tạo mới hoặc chỉnh sửa trạm thi đấu, hỗ trợ chọn dynamic scoring_type,
// hiển thị form cấu hình động tương ứng, validate trước khi lưu qua RPC.
// ============================================================================
import React, { useState } from 'react';
import { callRpc } from '@/lib/rpc';
import type { ScoringType } from '@/scoring/types';
import {
  X,
  Layers,
  CheckCircle2,
  AlertCircle,
  Plus,
  Trash2,
  Clock,
  Settings2,
  Sliders,
} from 'lucide-react';

interface StationEditorModalProps {
  station?: any | null; // null nếu tạo mới
  onClose: () => void;
  onSuccess: () => void;
}

export const StationEditorModal: React.FC<StationEditorModalProps> = ({
  station,
  onClose,
  onSuccess,
}) => {
  const isEditing = Boolean(station?.id);

  // Thông tin cơ bản của trạm
  const [name, setName] = useState(station?.name || '');
  const [description, setDescription] = useState(station?.description || '');
  const [orderIndex, setOrderIndex] = useState<number>(station?.order_index ?? 1);
  const [isActive, setIsActive] = useState<boolean>(station?.is_active ?? true);
  const [allowMultipleAttempts, setAllowMultipleAttempts] = useState<boolean>(
    station?.allow_multiple_attempts ?? false
  );
  const [minScore, setMinScore] = useState<number>(station?.min_score ?? 0);
  const [maxScore, setMaxScore] = useState<number>(station?.max_score ?? 100);

  // Loại chấm điểm & Cấu hình động
  const [scoringType, setScoringType] = useState<ScoringType>(
    station?.scoring_type || 'tier'
  );

  // Config: TIER
  const [tiers, setTiers] = useState<Array<{ tier: string; label: string; points: number }>>(
    () => {
      if (station?.scoring_type === 'tier' && station?.scoring_config?.tiers) {
        return station.scoring_config.tiers;
      }
      return [
        { tier: 'tier_1', label: 'Giải mã hoàn hảo', points: 50 },
        { tier: 'tier_2', label: 'Hoàn thành tiêu chuẩn', points: 30 },
        { tier: 'tier_3', label: 'Hoàn thành trễ hạn', points: 15 },
      ];
    }
  );

  // Config: FIXED
  const [fixedBasePoints, setFixedBasePoints] = useState<number>(
    station?.scoring_type === 'fixed' ? (station?.scoring_config?.base_points ?? 40) : 40
  );
  const [fixedOptions, setFixedOptions] = useState<Array<{ key: string; label: string; points: number }>>(
    () => {
      if (station?.scoring_type === 'fixed' && station?.scoring_config?.options) {
        return station.scoring_config.options;
      }
      return [{ key: 'bonus_speed', label: 'Tốc độ kỷ lục', points: 10 }];
    }
  );

  // Config: TIME ATTACK
  const [timeBasePoints, setTimeBasePoints] = useState<number>(
    station?.scoring_type === 'time_attack' ? (station?.scoring_config?.base_points ?? 10) : 10
  );
  const [pointsPerUnit, setPointsPerUnit] = useState<number>(
    station?.scoring_type === 'time_attack' ? (station?.scoring_config?.points_per_unit ?? 5) : 5
  );
  const [maxUnits, setMaxUnits] = useState<number>(
    station?.scoring_type === 'time_attack' ? (station?.scoring_config?.max_units ?? 10) : 10
  );
  const [unitLabel, setUnitLabel] = useState<string>(
    station?.scoring_type === 'time_attack' ? (station?.scoring_config?.unit_label ?? 'mục tiêu') : 'mục tiêu'
  );

  // Trạng thái lưu
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);

  // Validate form trước khi lưu
  const validateForm = (): string | null => {
    if (!name.trim()) return 'Tên trạm không được để trống.';
    if (minScore > maxScore) return 'Điểm tối thiểu (Min) không được lớn hơn điểm tối đa (Max).';

    if (scoringType === 'tier') {
      if (tiers.length === 0) return 'Mô hình Tier phải có ít nhất 1 mức điểm.';
      for (const t of tiers) {
        if (!t.tier.trim() || !t.label.trim()) return 'Vui lòng nhập đầy đủ mã và nhãn cho mọi Tier.';
        if (t.points < 0) return 'Điểm số của mỗi Tier không được âm.';
      }
    } else if (scoringType === 'fixed') {
      if (fixedBasePoints < 0) return 'Điểm gốc (Base Points) không được âm.';
    } else if (scoringType === 'time_attack') {
      if (maxUnits <= 0) return 'Số đơn vị tối đa (Max Units) phải lớn hơn 0.';
      if (pointsPerUnit < 0) return 'Điểm cho mỗi đơn vị không được âm.';
    }

    return null;
  };

  // Đóng gói cấu hình động theo scoring_type
  const buildScoringConfig = (): Record<string, any> => {
    if (scoringType === 'tier') {
      return { tiers };
    }
    if (scoringType === 'fixed') {
      return {
        base_points: fixedBasePoints,
        options: fixedOptions,
      };
    }
    if (scoringType === 'time_attack') {
      return {
        base_points: timeBasePoints,
        points_per_unit: pointsPerUnit,
        max_units: maxUnits,
        unit_label: unitLabel.trim() || 'đơn vị',
      };
    }
    return {};
  };

  // Submit lưu trạm
  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    const validationError = validateForm();
    if (validationError) {
      setErrorMsg(validationError);
      return;
    }

    setIsSubmitting(true);
    setErrorMsg(null);

    const config = buildScoringConfig();

    try {
      const res = await callRpc('admin_upsert_station', {
        p_id: station?.id,
        p_name: name.trim(),
        p_description: description.trim(),
        p_scoring_type: scoringType,
        p_scoring_config: config,
        p_min_score: minScore,
        p_max_score: maxScore,
        p_order_index: orderIndex,
        p_allow_multiple_attempts: allowMultipleAttempts,
        p_is_active: isActive,
      });

      if (res.success) {
        onSuccess();
        onClose();
      } else {
        setErrorMsg(res.error || res.message || 'Không thể lưu thông tin trạm.');
      }
    } catch (err: any) {
      setErrorMsg(err.message || 'Lỗi kết nối khi lưu trạm.');
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 bg-black/80 backdrop-blur-sm flex items-center justify-center p-4 animate-fadeIn">
      <div className="bg-evermyst-card border border-evermyst-border rounded-3xl w-full max-w-xl max-h-[90vh] flex flex-col shadow-2xl overflow-hidden">
        {/* Header */}
        <div className="p-4 border-b border-evermyst-border flex items-center justify-between bg-evermyst-surface">
          <div className="flex items-center gap-2.5">
            <div className="w-9 h-9 rounded-xl bg-lumen/15 border border-lumen/30 flex items-center justify-center text-lumen">
              <Settings2 className="w-5 h-5" />
            </div>
            <div>
              <h3 className="text-sm font-black text-evermyst-text">
                {isEditing ? `Chỉnh Sửa Trạm: ${station?.name}` : 'Tạo Trạm Thử Thách Mới'}
              </h3>
              <p className="text-[11px] text-evermyst-text-dim">
                Cấu hình luật chấm điểm & hạn mức điểm
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
        <form onSubmit={handleSubmit} className="flex-1 overflow-y-auto p-5 space-y-4 text-xs">
          {/* Tên & Thứ tự */}
          <div className="grid grid-cols-3 gap-3">
            <div className="col-span-2 space-y-1">
              <label className="block text-[11px] font-bold text-evermyst-text-dim uppercase tracking-wider">
                Tên Trạm Thử Thách *
              </label>
              <input
                type="text"
                value={name}
                onChange={(e) => setName(e.target.value)}
                placeholder="Ví dụ: Mê Cung Gương, Rừng Ảo Ảnh..."
                className="w-full h-10 rounded-xl bg-evermyst-surface border border-evermyst-border px-3 text-xs text-evermyst-text font-semibold focus:outline-none focus:border-lumen"
                required
              />
            </div>
            <div className="space-y-1">
              <label className="block text-[11px] font-bold text-evermyst-text-dim uppercase tracking-wider">
                Thứ Tự (Order)
              </label>
              <input
                type="number"
                min={1}
                value={orderIndex}
                onChange={(e) => setOrderIndex(parseInt(e.target.value) || 1)}
                className="w-full h-10 rounded-xl bg-evermyst-surface border border-evermyst-border px-3 text-xs text-evermyst-text font-mono font-bold focus:outline-none focus:border-lumen"
              />
            </div>
          </div>

          {/* Mô tả */}
          <div className="space-y-1">
            <label className="block text-[11px] font-bold text-evermyst-text-dim uppercase tracking-wider">
              Mô Tả Nhiệm Vụ
            </label>
            <textarea
              rows={2}
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              placeholder="Mô tả thử thách của trạm..."
              className="w-full rounded-xl bg-evermyst-surface border border-evermyst-border p-2.5 text-xs text-evermyst-text focus:outline-none focus:border-lumen resize-none"
            />
          </div>

          {/* Min & Max Score */}
          <div className="grid grid-cols-2 gap-3 p-3 rounded-2xl bg-evermyst-surface/50 border border-evermyst-border">
            <div className="space-y-1">
              <label className="block text-[11px] font-bold text-evermyst-text-dim uppercase tracking-wider">
                Điểm Tối Thiểu (Min Score)
              </label>
              <input
                type="number"
                value={minScore}
                onChange={(e) => setMinScore(parseInt(e.target.value) || 0)}
                className="w-full h-9 rounded-xl bg-evermyst-card border border-evermyst-border px-3 font-mono font-bold text-evermyst-text"
              />
            </div>
            <div className="space-y-1">
              <label className="block text-[11px] font-bold text-evermyst-text-dim uppercase tracking-wider">
                Điểm Tối Đa (Max Score)
              </label>
              <input
                type="number"
                value={maxScore}
                onChange={(e) => setMaxScore(parseInt(e.target.value) || 100)}
                className="w-full h-9 rounded-xl bg-evermyst-card border border-evermyst-border px-3 font-mono font-bold text-evermyst-text"
              />
            </div>
          </div>

          {/* Cài đặt Bổ sung: Active & Multi attempts */}
          <div className="flex items-center gap-6 p-3 rounded-2xl bg-evermyst-surface/30 border border-evermyst-border">
            <label className="flex items-center gap-2 cursor-pointer">
              <input
                type="checkbox"
                checked={isActive}
                onChange={(e) => setIsActive(e.target.checked)}
                className="w-4 h-4 rounded text-lumen"
              />
              <span className="font-bold text-evermyst-text">Đang Kích Hoạt</span>
            </label>

            <label className="flex items-center gap-2 cursor-pointer">
              <input
                type="checkbox"
                checked={allowMultipleAttempts}
                onChange={(e) => setAllowMultipleAttempts(e.target.checked)}
                className="w-4 h-4 rounded text-lumen"
              />
              <span className="font-bold text-evermyst-text">Cho Phép Thi Lại Nhiều Lần</span>
            </label>
          </div>

          {/* CHỌN SCORING_TYPE */}
          <div className="space-y-2 pt-2">
            <label className="block text-[11px] font-black text-lumen uppercase tracking-wider">
              Chọn Mô Hình Chấm Điểm (Scoring Type)
            </label>
            <div className="grid grid-cols-3 gap-2">
              <button
                type="button"
                onClick={() => setScoringType('tier')}
                className={`p-3 rounded-2xl border text-center transition-all ${
                  scoringType === 'tier'
                    ? 'bg-lumen/15 border-lumen text-lumen shadow-sm'
                    : 'bg-evermyst-surface border-evermyst-border text-evermyst-text-dim hover:text-white'
                }`}
              >
                <Layers className="w-5 h-5 mx-auto mb-1" />
                <div className="font-bold text-xs">Theo Mức (Tier)</div>
                <div className="text-[10px] opacity-70">Bậc hạng định sẵn</div>
              </button>

              <button
                type="button"
                onClick={() => setScoringType('fixed')}
                className={`p-3 rounded-2xl border text-center transition-all ${
                  scoringType === 'fixed'
                    ? 'bg-lumen/15 border-lumen text-lumen shadow-sm'
                    : 'bg-evermyst-surface border-evermyst-border text-evermyst-text-dim hover:text-white'
                }`}
              >
                <CheckCircle2 className="w-5 h-5 mx-auto mb-1" />
                <div className="font-bold text-xs">Cố Định (Fixed)</div>
                <div className="text-[10px] opacity-70">Pass / Fail + Bonus</div>
              </button>

              <button
                type="button"
                onClick={() => setScoringType('time_attack')}
                className={`p-3 rounded-2xl border text-center transition-all ${
                  scoringType === 'time_attack'
                    ? 'bg-lumen/15 border-lumen text-lumen shadow-sm'
                    : 'bg-evermyst-surface border-evermyst-border text-evermyst-text-dim hover:text-white'
                }`}
              >
                <Clock className="w-5 h-5 mx-auto mb-1" />
                <div className="font-bold text-xs">Thời Gian / Số Lượng</div>
                <div className="text-[10px] opacity-70">Điểm x Đơn vị</div>
              </button>
            </div>
          </div>

          {/* DYNAMIC FORM CẤU HÌNH TƯƠNG ỨNG */}
          <div className="p-4 rounded-2xl bg-evermyst-surface border border-evermyst-border space-y-3">
            {/* 1. MODEL TIER */}
            {scoringType === 'tier' && (
              <div className="space-y-3">
                <div className="flex items-center justify-between">
                  <span className="text-[11px] font-bold text-evermyst-text uppercase">
                    Danh Sách Các Mức Tier
                  </span>
                  <button
                    type="button"
                    onClick={() =>
                      setTiers([
                        ...tiers,
                        {
                          tier: `tier_${tiers.length + 1}`,
                          label: `Mức ${tiers.length + 1}`,
                          points: 20,
                        },
                      ])
                    }
                    className="px-2.5 py-1 rounded-lg bg-lumen/15 border border-lumen/30 text-lumen text-[11px] font-bold flex items-center gap-1 hover:bg-lumen/25"
                  >
                    <Plus className="w-3.5 h-3.5" /> Thêm Mức
                  </button>
                </div>

                <div className="space-y-2">
                  {tiers.map((t, idx) => (
                    <div
                      key={idx}
                      className="grid grid-cols-12 gap-2 items-center bg-evermyst-card p-2 rounded-xl border border-evermyst-border"
                    >
                      <input
                        type="text"
                        value={t.tier}
                        onChange={(e) => {
                          const updated = [...tiers];
                          updated[idx].tier = e.target.value;
                          setTiers(updated);
                        }}
                        placeholder="Mã (tier_1)"
                        className="col-span-3 h-8 rounded-lg bg-evermyst-surface px-2 text-xs font-mono font-bold text-evermyst-text"
                      />
                      <input
                        type="text"
                        value={t.label}
                        onChange={(e) => {
                          const updated = [...tiers];
                          updated[idx].label = e.target.value;
                          setTiers(updated);
                        }}
                        placeholder="Nhãn hiển thị (VD: Vàng)"
                        className="col-span-5 h-8 rounded-lg bg-evermyst-surface px-2 text-xs font-semibold text-evermyst-text"
                      />
                      <input
                        type="number"
                        value={t.points}
                        onChange={(e) => {
                          const updated = [...tiers];
                          updated[idx].points = parseInt(e.target.value) || 0;
                          setTiers(updated);
                        }}
                        placeholder="Điểm"
                        className="col-span-3 h-8 rounded-lg bg-evermyst-surface px-2 text-xs font-mono font-bold text-success text-right"
                      />
                      <button
                        type="button"
                        onClick={() => setTiers(tiers.filter((_, i) => i !== idx))}
                        disabled={tiers.length <= 1}
                        className="col-span-1 text-evermyst-text-dim hover:text-danger flex justify-center disabled:opacity-30"
                      >
                        <Trash2 className="w-3.5 h-3.5" />
                      </button>
                    </div>
                  ))}
                </div>
              </div>
            )}

            {/* 2. MODEL FIXED */}
            {scoringType === 'fixed' && (
              <div className="space-y-3">
                <div className="space-y-1">
                  <label className="block text-[11px] font-bold text-evermyst-text-dim uppercase tracking-wider">
                    Điểm Hoàn Thành Cơ Bản (Base Points)
                  </label>
                  <input
                    type="number"
                    value={fixedBasePoints}
                    onChange={(e) => setFixedBasePoints(parseInt(e.target.value) || 0)}
                    className="w-full h-10 rounded-xl bg-evermyst-card border border-evermyst-border px-3 font-mono font-bold text-success"
                  />
                </div>

                <div className="pt-2 border-t border-evermyst-border space-y-2">
                  <div className="flex items-center justify-between">
                    <span className="text-[11px] font-bold text-evermyst-text uppercase">
                      Tiêu Chí Thưởng Phụ (Tùy chọn)
                    </span>
                    <button
                      type="button"
                      onClick={() =>
                        setFixedOptions([
                          ...fixedOptions,
                          {
                            key: `bonus_${fixedOptions.length + 1}`,
                            label: `Thưởng phụ ${fixedOptions.length + 1}`,
                            points: 5,
                          },
                        ])
                      }
                      className="px-2.5 py-1 rounded-lg bg-lumen/15 border border-lumen/30 text-lumen text-[11px] font-bold flex items-center gap-1 hover:bg-lumen/25"
                    >
                      <Plus className="w-3.5 h-3.5" /> Thêm Option
                    </button>
                  </div>

                  {fixedOptions.map((opt, idx) => (
                    <div
                      key={idx}
                      className="grid grid-cols-12 gap-2 items-center bg-evermyst-card p-2 rounded-xl border border-evermyst-border"
                    >
                      <input
                        type="text"
                        value={opt.key}
                        onChange={(e) => {
                          const updated = [...fixedOptions];
                          updated[idx].key = e.target.value;
                          setFixedOptions(updated);
                        }}
                        placeholder="Mã option"
                        className="col-span-3 h-8 rounded-lg bg-evermyst-surface px-2 text-xs font-mono font-bold text-evermyst-text"
                      />
                      <input
                        type="text"
                        value={opt.label}
                        onChange={(e) => {
                          const updated = [...fixedOptions];
                          updated[idx].label = e.target.value;
                          setFixedOptions(updated);
                        }}
                        placeholder="Nhãn thưởng"
                        className="col-span-5 h-8 rounded-lg bg-evermyst-surface px-2 text-xs font-semibold text-evermyst-text"
                      />
                      <input
                        type="number"
                        value={opt.points}
                        onChange={(e) => {
                          const updated = [...fixedOptions];
                          updated[idx].points = parseInt(e.target.value) || 0;
                          setFixedOptions(updated);
                        }}
                        placeholder="Điểm"
                        className="col-span-3 h-8 rounded-lg bg-evermyst-surface px-2 text-xs font-mono font-bold text-success text-right"
                      />
                      <button
                        type="button"
                        onClick={() => setFixedOptions(fixedOptions.filter((_, i) => i !== idx))}
                        className="col-span-1 text-evermyst-text-dim hover:text-danger flex justify-center"
                      >
                        <Trash2 className="w-3.5 h-3.5" />
                      </button>
                    </div>
                  ))}
                </div>
              </div>
            )}

            {/* 3. MODEL TIME ATTACK */}
            {scoringType === 'time_attack' && (
              <div className="space-y-3">
                <div className="grid grid-cols-2 gap-3">
                  <div className="space-y-1">
                    <label className="block text-[11px] font-bold text-evermyst-text-dim uppercase tracking-wider">
                      Điểm Khởi Điểm (Base)
                    </label>
                    <input
                      type="number"
                      value={timeBasePoints}
                      onChange={(e) => setTimeBasePoints(parseInt(e.target.value) || 0)}
                      className="w-full h-9 rounded-xl bg-evermyst-card border border-evermyst-border px-3 font-mono font-bold text-evermyst-text"
                    />
                  </div>

                  <div className="space-y-1">
                    <label className="block text-[11px] font-bold text-evermyst-text-dim uppercase tracking-wider">
                      Điểm Cho Mỗi Đơn Vị
                    </label>
                    <input
                      type="number"
                      value={pointsPerUnit}
                      onChange={(e) => setPointsPerUnit(parseInt(e.target.value) || 0)}
                      className="w-full h-9 rounded-xl bg-evermyst-card border border-evermyst-border px-3 font-mono font-bold text-success"
                    />
                  </div>
                </div>

                <div className="grid grid-cols-2 gap-3">
                  <div className="space-y-1">
                    <label className="block text-[11px] font-bold text-evermyst-text-dim uppercase tracking-wider">
                      Đơn Vị Tối Đa (Max Units)
                    </label>
                    <input
                      type="number"
                      min={1}
                      value={maxUnits}
                      onChange={(e) => setMaxUnits(parseInt(e.target.value) || 1)}
                      className="w-full h-9 rounded-xl bg-evermyst-card border border-evermyst-border px-3 font-mono font-bold text-evermyst-text"
                    />
                  </div>

                  <div className="space-y-1">
                    <label className="block text-[11px] font-bold text-evermyst-text-dim uppercase tracking-wider">
                      Tên Đơn Vị Đo
                    </label>
                    <input
                      type="text"
                      value={unitLabel}
                      onChange={(e) => setUnitLabel(e.target.value)}
                      placeholder="VD: lượt, bóng, giây..."
                      className="w-full h-9 rounded-xl bg-evermyst-card border border-evermyst-border px-3 font-semibold text-evermyst-text"
                    />
                  </div>
                </div>
              </div>
            )}
          </div>

          {/* Lỗi nếu có */}
          {errorMsg && (
            <div className="p-3 rounded-xl bg-danger/20 border border-danger/40 text-danger text-xs font-bold flex items-center gap-2">
              <AlertCircle className="w-4 h-4 shrink-0" />
              {errorMsg}
            </div>
          )}

          {/* Nút hành động */}
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
              className="h-11 rounded-xl bg-lumen text-evermyst-bg text-xs font-black uppercase tracking-wider hover:bg-lumen/90 transition-all shadow-md shadow-lumen/20 flex items-center justify-center gap-1.5"
            >
              {isSubmitting ? (
                <div className="w-4 h-4 border-2 border-evermyst-bg border-t-transparent rounded-full animate-spin" />
              ) : (
                <>
                  <CheckCircle2 className="w-4 h-4" />
                  Lưu Trạm Thử Thách
                </>
              )}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
};
