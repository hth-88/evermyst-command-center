// ============================================================================
// LOGIN PAGE - Đăng nhập nhân sự BTC Evermyst (LoginPage.tsx)
// File: src/pages/LoginPage.tsx
// Nhập mã PIN bảo mật, tự động chuyển hướng theo Role (ADR-2, Phase 6)
// ============================================================================
import React, { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { useSession } from '@/contexts/SessionContext';
import { getRoleHomePath } from '@/components/guards/RoleRoute';
import { Shield, Delete, AlertCircle } from 'lucide-react';

export default function LoginPage() {
  const { user, login } = useSession();
  const navigate = useNavigate();

  const [pin, setPin] = useState('');
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  // Nếu đã đăng nhập, tự động chuyển về trang chủ của Role
  useEffect(() => {
    if (user) {
      navigate(getRoleHomePath(user.role), { replace: true });
    }
  }, [user, navigate]);

  // Hỗ trợ nhập phím vật lý
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (isSubmitting) return;

      if (e.key >= '0' && e.key <= '9') {
        if (pin.length < 6) {
          handleKeypadPress(e.key);
        }
      } else if (e.key === 'Backspace') {
        handleDelete();
      } else if (e.key === 'Enter' && pin.length >= 4) {
        triggerLogin(pin);
      }
    };

    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [pin, isSubmitting]);

  const handleKeypadPress = (val: string) => {
    setErrorMessage(null);
    if (pin.length < 6) {
      const newPin = pin + val;
      setPin(newPin);
      if (newPin.length === 6) {
        triggerLogin(newPin);
      }
    }
  };

  const handleDelete = () => {
    setErrorMessage(null);
    setPin((prev) => prev.slice(0, -1));
  };

  const handleClear = () => {
    setErrorMessage(null);
    setPin('');
  };

  const triggerLogin = async (pinToSubmit: string) => {
    if (isSubmitting || !pinToSubmit.trim()) return;
    setIsSubmitting(true);
    setErrorMessage(null);

    const res = await login(pinToSubmit);
    setIsSubmitting(false);

    if (res.success && res.role) {
      navigate(getRoleHomePath(res.role), { replace: true });
    } else {
      setErrorMessage(res.error || 'Mã PIN không chính xác.');
      setPin('');
    }
  };

  return (
    <div className="min-h-screen flex flex-col justify-between p-4 bg-evermyst-bg text-evermyst-text relative select-none overflow-hidden">
      {/* Background Ambience */}
      <div className="absolute top-0 left-1/2 -translate-x-1/2 w-96 h-96 bg-lumen/5 rounded-full blur-3xl pointer-events-none" />
      <div className="absolute bottom-0 right-0 w-80 h-80 bg-props/5 rounded-full blur-3xl pointer-events-none" />

      {/* Top Header */}
      <header className="relative z-10 pt-6 flex flex-col items-center">
        <div className="inline-flex items-center justify-center w-14 h-14 rounded-2xl bg-gradient-to-br from-lumen to-lumen-dark shadow-lg shadow-lumen/20 mb-2">
          <Shield className="w-8 h-8 text-evermyst-bg" />
        </div>
        <h1 className="text-2xl font-black tracking-wider text-evermyst-text uppercase">
          EVERMYST
        </h1>
        <p className="text-xs text-evermyst-text-muted font-medium">
          Tactical Operator Command Center
        </p>
      </header>

      {/* Content Area */}
      <main className="relative z-10 w-full max-w-xs mx-auto my-auto py-2 space-y-4">
        {/* Hướng dẫn nhập PIN */}
        <div className="text-center space-y-1">
          <div className="text-xs font-semibold text-evermyst-text-dim">
            Nhập mã PIN cá nhân để đăng nhập
          </div>
          {errorMessage && (
            <div className="p-2.5 rounded-xl bg-danger/15 border border-danger/30 text-danger text-xs font-semibold flex items-center justify-center gap-1.5 animate-shake">
              <AlertCircle className="w-3.5 h-3.5 shrink-0" />
              <span>{errorMessage}</span>
            </div>
          )}
        </div>

        {/* Ô hiển thị 4-6 số PIN */}
        <div className="flex justify-center gap-3 py-2">
          {[0, 1, 2, 3, 4, 5].map((idx) => (
            <div
              key={idx}
              className={`w-4 h-4 rounded-full border transition-all duration-200 ${
                pin.length > idx
                  ? 'bg-lumen border-lumen shadow-sm shadow-lumen/50 scale-110'
                  : 'bg-evermyst-card border-evermyst-border'
              }`}
            />
          ))}
        </div>

        {/* Numeric Keypad Touch 1 tay ngoài trời (Nút >= 56px) */}
        <div className="grid grid-cols-3 gap-2.5 pt-2">
          {['1', '2', '3', '4', '5', '6', '7', '8', '9'].map((digit) => (
            <button
              key={digit}
              disabled={isSubmitting}
              onClick={() => handleKeypadPress(digit)}
              className="h-14 rounded-2xl bg-evermyst-card border border-evermyst-border hover:bg-evermyst-card-hover active:bg-lumen active:text-evermyst-bg text-xl font-bold font-mono transition-all flex items-center justify-center shadow-md active:scale-95 disabled:opacity-50"
            >
              {digit}
            </button>
          ))}

          {/* Hàng cuối: Clear / Submit, 0, Delete */}
          {pin.length >= 4 && pin.length < 6 ? (
            <button
              disabled={isSubmitting}
              onClick={() => triggerLogin(pin)}
              className="h-14 rounded-2xl bg-lumen text-evermyst-bg font-black text-sm transition-all flex items-center justify-center active:scale-95 shadow-lg shadow-lumen/40 animate-pulse"
            >
              VÀO →
            </button>
          ) : (
            <button
              disabled={isSubmitting || pin.length === 0}
              onClick={handleClear}
              className="h-14 rounded-2xl bg-evermyst-card border border-evermyst-border hover:bg-danger/20 text-xs font-bold text-evermyst-text-muted transition-all flex items-center justify-center active:scale-95 disabled:opacity-30"
            >
              XÓA
            </button>
          )}

          <button
            disabled={isSubmitting}
            onClick={() => handleKeypadPress('0')}
            className="h-14 rounded-2xl bg-evermyst-card border border-evermyst-border hover:bg-evermyst-card-hover active:bg-lumen active:text-evermyst-bg text-xl font-bold font-mono transition-all flex items-center justify-center shadow-md active:scale-95 disabled:opacity-50"
          >
            0
          </button>

          <button
            disabled={isSubmitting || pin.length === 0}
            onClick={handleDelete}
            className="h-14 rounded-2xl bg-evermyst-card border border-evermyst-border hover:bg-evermyst-card-hover active:bg-evermyst-surface text-evermyst-text-muted transition-all flex items-center justify-center active:scale-95 disabled:opacity-30"
          >
            <Delete className="w-5 h-5" />
          </button>
        </div>

        {isSubmitting && (
          <div className="flex items-center justify-center gap-2 pt-1 text-xs text-lumen font-semibold animate-pulse">
            <div className="w-3 h-3 border-2 border-lumen border-t-transparent rounded-full animate-spin" />
            Đang xác thực...
          </div>
        )}
      </main>

      {/* Footer */}
      <footer className="relative z-10 text-center py-2 text-[10px] text-evermyst-text-dim">
        BigGame D26 • Hệ thống điều hành chiến thuật bí mật
      </footer>
    </div>
  );
}
