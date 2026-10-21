// ============================================================================
// APP - Root router and Toast container for Evermyst Command Center (Phase 6)
// ============================================================================
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import { SessionProvider } from '@/contexts/SessionContext';
import { GameProvider, useGame } from '@/contexts/GameContext';
import { RoleRoute } from '@/components/guards/RoleRoute';
import LoginPage from '@/pages/LoginPage';
import SupportPage from '@/pages/SupportPage';
import StationPage from '@/pages/StationPage';
import AdminPage from '@/pages/AdminPage';
import { CheckCircle2, AlertTriangle, AlertCircle, Info, X } from 'lucide-react';

function ToastContainer() {
  const { toasts, removeToast } = useGame();

  if (toasts.length === 0) return null;

  return (
    <div className="fixed top-3 right-3 left-3 sm:left-auto sm:w-96 z-50 space-y-2 pointer-events-none">
      {toasts.map((toast) => (
        <div
          key={toast.id}
          className={`pointer-events-auto p-3.5 rounded-2xl border shadow-xl flex items-start gap-3 backdrop-blur-md animate-slideDown ${
            toast.type === 'success'
              ? 'bg-success/20 border-success/40 text-success-light'
              : toast.type === 'error'
              ? 'bg-danger/20 border-danger/40 text-danger-light'
              : toast.type === 'warning'
              ? 'bg-warning/20 border-warning/40 text-warning'
              : 'bg-evermyst-card border-evermyst-border text-evermyst-text'
          }`}
        >
          <div className="shrink-0 mt-0.5">
            {toast.type === 'success' && <CheckCircle2 className="w-4 h-4" />}
            {toast.type === 'error' && <AlertCircle className="w-4 h-4" />}
            {toast.type === 'warning' && <AlertTriangle className="w-4 h-4" />}
            {toast.type === 'info' && <Info className="w-4 h-4 text-lumen" />}
          </div>

          <div className="flex-1 text-xs font-semibold leading-relaxed">
            {toast.message}
          </div>

          <button
            onClick={() => removeToast(toast.id)}
            className="text-evermyst-text-dim hover:text-white shrink-0 p-0.5"
          >
            <X className="w-3.5 h-3.5" />
          </button>
        </div>
      ))}
    </div>
  );
}

export default function App() {
  return (
    <BrowserRouter>
      <SessionProvider>
        <GameProvider>
          <Routes>
            {/* Route /: Trang đăng nhập PIN bảo mật, tự chuyển theo role khi đã đăng nhập */}
            <Route path="/" element={<LoginPage />} />
            <Route path="/login" element={<Navigate to="/" replace />} />

            {/* Route /support: Chỉ dành cho team_support */}
            <Route
              path="/support"
              element={
                <RoleRoute allowedRoles={['team_support']}>
                  <SupportPage />
                </RoleRoute>
              }
            />

            {/* Route /station: Chỉ dành cho station_master */}
            <Route
              path="/station"
              element={
                <RoleRoute allowedRoles={['station_master']}>
                  <StationPage />
                </RoleRoute>
              }
            />

            {/* Route /admin: Chỉ dành cho admin */}
            <Route
              path="/admin"
              element={
                <RoleRoute allowedRoles={['admin']}>
                  <AdminPage />
                </RoleRoute>
              }
            />

            {/* Catch-all: đưa về trang chủ */}
            <Route path="*" element={<Navigate to="/" replace />} />
          </Routes>
          <ToastContainer />
        </GameProvider>
      </SessionProvider>
    </BrowserRouter>
  );
}
