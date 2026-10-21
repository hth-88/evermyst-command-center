// ============================================================================
// STAFF MODAL (StaffModal.tsx)
// File: src/components/admin/StaffModal.tsx
// Modal quản lý nhân sự BTC: gán đội/trạm, đặt lại mã PIN, phân quyền theo role
// ============================================================================
import React, { useState } from 'react';
import { callRpc } from '@/lib/rpc';
import type { StaffRole } from '@/lib/types';
import { X, CheckCircle2, AlertCircle, Users, KeyRound, ShieldAlert } from 'lucide-react';

interface StaffModalProps {
  staff?: any | null; // null nếu tạo mới
  teams: Array<{ id: string; name: string }>;
  stations: Array<{ id: string; name: string }>;
  onClose: () => void;
  onSuccess: () => void;
}

export const StaffModal: React.FC<StaffModalProps> = ({
  staff,
  teams,
  stations,
  onClose,
  onSuccess,
}) => {
  const isEditing = Boolean(staff?.id);

  const [name, setName] = useState(staff?.name || '');
  const [role, setRole] = useState<StaffRole>(staff?.role || 'team_support');
  const [assignedTeamId, setAssignedTeamId] = useState<string>(
    staff?.assigned_team_id || (teams[0]?.id ?? '')
  );
  const [assignedStationId, setAssignedStationId] = useState<string>(
    staff?.assigned_station_id || (stations[0]?.id ?? '')
  );
  const [newPin, setNewPin] = useState('');
  const [isActive, setIsActive] = useState<boolean>(staff?.is_active ?? true);

  const [isSubmitting, setIsSubmitting] = useState(false);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!name.trim()) {
      setErrorMsg('Vui lòng nhập họ tên nhân sự.');
      return;
    }

    if (!isEditing && !newPin.trim()) {
      setErrorMsg('Khi tạo mới nhân sự, bắt buộc phải thiết lập mã PIN ban đầu.');
      return;
    }

    if (newPin && newPin.length < 4) {
      setErrorMsg('Mã PIN bảo mật phải có ít nhất 4 ký tự.');
      return;
    }

    if (role === 'team_support' && !assignedTeamId) {
      setErrorMsg('Nhân sự Team Support bắt buộc phải được gán cho 1 đội chơi.');
      return;
    }

    if (role === 'station_master' && !assignedStationId) {
      setErrorMsg('Nhân sự Station Master bắt buộc phải được gán cho 1 trạm thử thách.');
      return;
    }

    setIsSubmitting(true);
    setErrorMsg(null);

    try {
      const res = await callRpc('admin_upsert_staff', {
        p_id: staff?.id,
        p_name: name.trim(),
        p_role: role,
        p_pin: newPin.trim() || undefined,
        p_assigned_team_id: role === 'team_support' ? assignedTeamId : null,
        p_assigned_station_id: role === 'station_master' ? assignedStationId : null,
        p_is_active: isActive,
      });

      if (res.success) {
        onSuccess();
        onClose();
      } else {
        setErrorMsg(res.error || res.message || 'Không thể lưu thông tin nhân sự.');
      }
    } catch (err: any) {
      setErrorMsg(err.message || 'Lỗi hệ thống khi lưu nhân sự.');
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
            <div className="w-9 h-9 rounded-xl bg-lumen/15 border border-lumen/30 flex items-center justify-center text-lumen">
              <Users className="w-5 h-5" />
            </div>
            <div>
              <h3 className="text-sm font-black text-evermyst-text">
                {isEditing ? `Chỉnh Sửa Nhân Sự: ${staff?.name}` : 'Thêm Nhân Sự Mới'}
              </h3>
              <p className="text-[11px] text-evermyst-text-dim">
                Phân quyền truy cập & mã PIN bảo mật
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
          {/* Tên & Vai trò */}
          <div className="space-y-1">
            <label className="block text-[11px] font-bold text-evermyst-text-dim uppercase tracking-wider">
              Họ Và Tên Nhân Sự *
            </label>
            <input
              type="text"
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="Ví dụ: Nguyễn Văn A"
              className="w-full h-10 rounded-xl bg-evermyst-surface border border-evermyst-border px-3 text-xs text-evermyst-text font-semibold focus:outline-none focus:border-lumen"
              required
            />
          </div>

          <div className="space-y-1">
            <label className="block text-[11px] font-bold text-evermyst-text-dim uppercase tracking-wider">
              Vai Trò (Role) *
            </label>
            <select
              value={role}
              onChange={(e) => setRole(e.target.value as StaffRole)}
              className="w-full h-10 rounded-xl bg-evermyst-surface border border-evermyst-border px-3 text-xs text-evermyst-text font-bold focus:outline-none focus:border-lumen"
            >
              <option value="team_support">Team Support (Hỗ trợ đội chơi)</option>
              <option value="station_master">Station Master (Quản trò trạm)</option>
              <option value="admin">Admin (Ban Quản Trị Tối Cao)</option>
            </select>
          </div>

          {/* Phân bổ theo Role */}
          {role === 'team_support' && (
            <div className="space-y-1 p-3 rounded-2xl bg-evermyst-surface/60 border border-evermyst-border">
              <label className="block text-[11px] font-bold text-evermyst-text-dim uppercase tracking-wider">
                Gán Đội Chơi Phụ Trách *
              </label>
              <select
                value={assignedTeamId}
                onChange={(e) => setAssignedTeamId(e.target.value)}
                className="w-full h-10 rounded-xl bg-evermyst-card border border-evermyst-border px-3 text-xs text-evermyst-text font-semibold focus:outline-none focus:border-lumen"
                required
              >
                {teams.map((t) => (
                  <option key={t.id} value={t.id}>
                    {t.name}
                  </option>
                ))}
              </select>
            </div>
          )}

          {role === 'station_master' && (
            <div className="space-y-1 p-3 rounded-2xl bg-evermyst-surface/60 border border-evermyst-border">
              <label className="block text-[11px] font-bold text-evermyst-text-dim uppercase tracking-wider">
                Gán Trạm Thử Thách Phụ Trách *
              </label>
              <select
                value={assignedStationId}
                onChange={(e) => setAssignedStationId(e.target.value)}
                className="w-full h-10 rounded-xl bg-evermyst-card border border-evermyst-border px-3 text-xs text-evermyst-text font-semibold focus:outline-none focus:border-lumen"
                required
              >
                {stations.map((s) => (
                  <option key={s.id} value={s.id}>
                    {s.name}
                  </option>
                ))}
              </select>
            </div>
          )}

          {/* Thiết lập / Đặt lại PIN */}
          <div className="space-y-1.5 p-3 rounded-2xl bg-evermyst-surface/40 border border-evermyst-border">
            <div className="flex items-center gap-1.5 text-lumen font-bold text-[11px] uppercase tracking-wider">
              <KeyRound className="w-3.5 h-3.5" />
              {isEditing ? 'Đặt Lại Mã PIN (Bỏ trống nếu không đổi)' : 'Thiết Lập Mã PIN Đăng Nhập *'}
            </div>
            <input
              type="password"
              value={newPin}
              onChange={(e) => setNewPin(e.target.value)}
              placeholder={isEditing ? 'Nhập mã PIN mới nếu muốn đổi...' : 'Mã PIN (VD: 123456)'}
              className="w-full h-10 rounded-xl bg-evermyst-card border border-evermyst-border px-3 font-mono font-bold text-evermyst-text text-sm focus:outline-none focus:border-lumen"
              maxLength={12}
            />
            <p className="text-[10px] text-evermyst-text-dim">
              * Mã PIN dùng để đăng nhập vào hệ thống tại trang chủ.
            </p>
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
              <span className="font-bold text-evermyst-text">Tài Khoản Đang Hoạt Động</span>
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
                  Lưu Nhân Sự
                </>
              )}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
};
