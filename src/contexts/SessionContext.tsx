// ============================================================================
// SESSION CONTEXT & SESSION PROVIDER (SessionContext.tsx)
// File: src/contexts/SessionContext.tsx
// Quản lý phiên token, gọi auth_verify_session khi load trang, chặn render khi chưa verify
// ============================================================================
import React, { createContext, useContext, useState, useEffect, useCallback } from 'react';
import { callRpc, TOKEN_STORAGE_KEY } from '@/lib/rpc';
import type { AuthUser, StaffRole, LoginResponse } from '@/lib/types';
import { Shield } from 'lucide-react';

interface SessionContextType {
  user: AuthUser | null;
  token: string | null;
  isVerifying: boolean;
  login: (pin: string) => Promise<{ success: boolean; role?: StaffRole; error?: string }>;
  logout: () => Promise<void>;
  refreshSession: () => Promise<void>;
}

const SessionContext = createContext<SessionContextType | null>(null);

function normalizeRole(rawRole?: string, stationAssigned?: string | null): StaffRole {
  if (rawRole === 'admin') return 'admin';
  if (rawRole === 'station_master') return 'station_master';
  if (rawRole === 'team_support') return 'team_support';
  if (rawRole === 'support') {
    return stationAssigned ? 'station_master' : 'team_support';
  }
  return 'team_support';
}

export const SessionProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [token, setToken] = useState<string | null>(() => {
    return typeof window !== 'undefined' ? localStorage.getItem(TOKEN_STORAGE_KEY) : null;
  });
  const [user, setUser] = useState<AuthUser | null>(null);
  const [isVerifying, setIsVerifying] = useState<boolean>(true);

  // Hàm xác thực token với database RPC
  const verifySession = useCallback(async () => {
    const storedToken = localStorage.getItem(TOKEN_STORAGE_KEY);
    if (!storedToken) {
      setUser(null);
      setToken(null);
      setIsVerifying(false);
      return;
    }

    try {
      const res = await callRpc<any>('auth_verify_session', {
        p_token: storedToken,
      });

      let staffData: any = null;
      let assignedTeam: any = null;
      let assignedStation: any = null;
      let expiresAt: string | undefined = undefined;

      // Hỗ trợ cả định dạng V1 (array) và V2 (object)
      if (Array.isArray(res) && res.length > 0) {
        const row = res[0];
        staffData = {
          id: row.staff_id || row.id,
          name: row.staff_name || row.name,
          role: normalizeRole(row.staff_role || row.role, row.station_assigned),
          station_assigned: row.station_assigned,
        };
        if (row.station_assigned) {
          assignedStation = { id: row.station_assigned, name: row.station_assigned };
        }
      } else if (res && Array.isArray(res.data) && res.data.length > 0) {
        const row = res.data[0];
        staffData = {
          id: row.staff_id || row.id,
          name: row.staff_name || row.name,
          role: normalizeRole(row.staff_role || row.role, row.station_assigned),
          station_assigned: row.station_assigned,
        };
        if (row.station_assigned) {
          assignedStation = { id: row.station_assigned, name: row.station_assigned };
        }
      } else if (res && (res.staff || res.user)) {
        const s = res.staff || res.user;
        staffData = {
          id: s.id || s.staff_id,
          name: s.name || s.staff_name,
          role: normalizeRole(s.role || s.staff_role, s.station_assigned),
          assigned_team_id: s.assigned_team_id,
          assigned_station_id: s.assigned_station_id || s.station_assigned,
        };
        assignedTeam = res.assigned_team || null;
        assignedStation = res.assigned_station || (s.station_assigned ? { id: s.station_assigned, name: s.station_assigned } : null);
        expiresAt = res.expires_at;
      }

      if (staffData && staffData.id) {
        setUser({
          id: staffData.id,
          name: staffData.name,
          role: staffData.role,
          assigned_team_id: staffData.assigned_team_id || assignedTeam?.id || null,
          assigned_team: assignedTeam,
          assigned_station_id: staffData.assigned_station_id || assignedStation?.id || null,
          assigned_station: assignedStation,
          token: storedToken,
          expires_at: expiresAt,
        });
        setToken(storedToken);
      } else {
        // Token không hợp lệ hoặc đã hết hạn
        localStorage.removeItem(TOKEN_STORAGE_KEY);
        setUser(null);
        setToken(null);
      }
    } catch {
      localStorage.removeItem(TOKEN_STORAGE_KEY);
      setUser(null);
      setToken(null);
    } finally {
      setIsVerifying(false);
    }
  }, []);

  // Xác thực phiên khi tải trang lần đầu
  useEffect(() => {
    verifySession();

    // Lắng nghe tín hiệu unauthenticated tự động từ rpc interceptor
    const handleUnauthenticated = () => {
      setUser(null);
      setToken(null);
      localStorage.removeItem(TOKEN_STORAGE_KEY);
    };

    window.addEventListener('evermyst:unauthenticated', handleUnauthenticated);
    return () => {
      window.removeEventListener('evermyst:unauthenticated', handleUnauthenticated);
    };
  }, [verifySession]);

  // Đăng nhập bằng mã PIN
  const login = async (pin: string): Promise<{ success: boolean; role?: StaffRole; error?: string }> => {
    setIsVerifying(true);
    try {
      const res = await callRpc<any>('staff_login', { p_pin: pin.trim() });
      const staffInfo = res?.staff || res?.user;
      const token = res?.token;

      if (res?.success && token && staffInfo) {
        const normalizedRole = normalizeRole(staffInfo.role || staffInfo.staff_role, staffInfo.station_assigned);
        const assignedStation = res.assigned_station || (staffInfo.station_assigned ? { id: staffInfo.station_assigned, name: staffInfo.station_assigned } : null);
        const assignedTeam = res.assigned_team || null;

        const authUser: AuthUser = {
          id: staffInfo.id || staffInfo.staff_id,
          name: staffInfo.name || staffInfo.staff_name,
          role: normalizedRole,
          assigned_team_id: staffInfo.assigned_team_id || assignedTeam?.id || null,
          assigned_team: assignedTeam,
          assigned_station_id: staffInfo.assigned_station_id || assignedStation?.id || null,
          assigned_station: assignedStation,
          token: token,
          expires_at: res.expires_at,
        };

        localStorage.setItem(TOKEN_STORAGE_KEY, token);
        setToken(token);
        setUser(authUser);
        setIsVerifying(false);
        return { success: true, role: normalizedRole };
      }

      setIsVerifying(false);
      return { success: false, error: res?.error || res?.message || 'Mã PIN không chính xác hoặc tài khoản đã bị khóa.' };
    } catch (err: any) {
      setIsVerifying(false);
      return { success: false, error: err?.message || 'Lỗi mạng khi kết nối máy chủ.' };
    }
  };

  // Đăng xuất và dọn dẹp
  const logout = async () => {
    const currentToken = token || localStorage.getItem(TOKEN_STORAGE_KEY);
    if (currentToken) {
      try {
        await callRpc('staff_logout', { p_token: currentToken });
      } catch {
        // bỏ qua lỗi khi mạng yếu
      }
    }

    localStorage.removeItem(TOKEN_STORAGE_KEY);
    setUser(null);
    setToken(null);
    window.location.href = '/';
  };

  // 1. CHƯA VERIFY XONG: Chỉ hiện màn hình chờ, không render nội dung trang
  if (isVerifying) {
    return (
      <div className="min-h-screen bg-evermyst-bg flex flex-col items-center justify-center text-evermyst-text select-none relative overflow-hidden">
        <div className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-96 h-96 bg-lumen/5 rounded-full blur-3xl pointer-events-none" />
        <div className="relative z-10 flex flex-col items-center space-y-4">
          <div className="inline-flex items-center justify-center w-16 h-16 rounded-2xl bg-gradient-to-br from-lumen to-lumen-dark shadow-xl shadow-lumen/25 animate-pulse">
            <Shield className="w-9 h-9 text-evermyst-bg" />
          </div>
          <div className="text-center space-y-1">
            <h2 className="text-base font-black tracking-widest text-evermyst-text uppercase">EVERMYST</h2>
            <p className="text-xs text-evermyst-text-dim font-medium">Đang xác thực phiên nhân sự...</p>
          </div>
          <div className="w-8 h-8 border-3 border-lumen border-t-transparent rounded-full animate-spin mt-2" />
        </div>
      </div>
    );
  }

  return (
    <SessionContext.Provider
      value={{
        user,
        token,
        isVerifying,
        login,
        logout,
        refreshSession: verifySession,
      }}
    >
      {children}
    </SessionContext.Provider>
  );
};

export const useSession = () => {
  const context = useContext(SessionContext);
  if (!context) {
    throw new Error('useSession phải được sử dụng bên trong SessionProvider');
  }
  return context;
};
