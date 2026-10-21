// ============================================================================
// ROLE ROUTE GUARD (RoleRoute.tsx)
// File: src/components/guards/RoleRoute.tsx
// Phân quyền UX theo role: sai role thì tự redirect về trang chủ của role đó
// ============================================================================
import React from 'react';
import { Navigate } from 'react-router-dom';
import { useSession } from '@/contexts/SessionContext';
import type { StaffRole } from '@/lib/types';

interface RoleRouteProps {
  allowedRoles: StaffRole[];
  children: React.ReactNode;
}

export const getRoleHomePath = (role?: StaffRole | string | null): string => {
  switch (role) {
    case 'admin':
      return '/admin';
    case 'station_master':
      return '/station';
    case 'team_support':
    case 'support':
      return '/support';
    default:
      return '/';
  }
};

export const RoleRoute: React.FC<RoleRouteProps> = ({ allowedRoles, children }) => {
  const { user, isVerifying } = useSession();

  // Khi đang xác thực phiên, SessionProvider đã chặn hiển thị. Nhưng phòng hờ:
  if (isVerifying) {
    return null;
  }

  // 1. Chưa đăng nhập -> Đưa về trang đăng nhập PIN (/)
  if (!user) {
    return <Navigate to="/" replace />;
  }

  // 2. Sai role -> Redirect về trang chủ của role đó (Acceptance requirement)
  const normalizedUserRole = user.role === ('support' as any) ? 'team_support' : user.role;
  if (!allowedRoles.includes(user.role) && !allowedRoles.includes(normalizedUserRole)) {
    const homePath = getRoleHomePath(user.role);
    return <Navigate to={homePath} replace />;
  }

  // 3. Đúng role -> Render nội dung trang
  return <>{children}</>;
};
