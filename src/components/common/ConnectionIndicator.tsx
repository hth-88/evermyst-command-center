// ============================================================================
// CONNECTION INDICATOR COMPONENT (ConnectionIndicator.tsx)
// File: src/components/common/ConnectionIndicator.tsx
// Hiển thị trạng thái kết nối Realtime / Fallback Polling theo chuẩn 1 tay ngoài trời
// ============================================================================
import React from 'react';
import { Wifi, WifiOff, RefreshCw } from 'lucide-react';
import type { ConnectionStatus } from '@/lib/types';

interface ConnectionIndicatorProps {
  status: ConnectionStatus;
  onRefresh?: () => void;
  className?: string;
  compact?: boolean;
}

export const ConnectionIndicator: React.FC<ConnectionIndicatorProps> = ({
  status,
  onRefresh,
  className = '',
  compact = false,
}) => {
  const isConnected = status === 'connected';
  const isPolling = status === 'polling';
  const isConnecting = status === 'connecting';

  return (
    <div
      className={`inline-flex items-center gap-1.5 px-2 py-0.5 rounded-full border text-[11px] font-semibold transition-all ${
        isConnected
          ? 'bg-success/10 border-success/30 text-success'
          : isPolling
          ? 'bg-warning/15 border-warning/40 text-warning animate-pulse'
          : isConnecting
          ? 'bg-lumen/15 border-lumen/40 text-lumen'
          : 'bg-danger/15 border-danger/40 text-danger'
      } ${className}`}
    >
      {isConnected ? (
        <>
          <Wifi className="w-3 h-3 text-success shrink-0" />
          {!compact && <span>Trực tuyến</span>}
        </>
      ) : isPolling ? (
        <>
          <WifiOff className="w-3 h-3 text-warning shrink-0" />
          {!compact && <span>Mất kết nối • Polling 10s</span>}
        </>
      ) : isConnecting ? (
        <>
          <RefreshCw className="w-3 h-3 text-lumen animate-spin shrink-0" />
          {!compact && <span>Đang kết nối...</span>}
        </>
      ) : (
        <>
          <WifiOff className="w-3 h-3 text-danger shrink-0" />
          {!compact && <span>Ngoại tuyến</span>}
        </>
      )}

      {onRefresh && (
        <button
          onClick={(e) => {
            e.stopPropagation();
            onRefresh();
          }}
          title="Tải lại ngay"
          className="ml-0.5 hover:opacity-80 active:scale-95 transition-transform"
        >
          <RefreshCw className="w-2.5 h-2.5" />
        </button>
      )}
    </div>
  );
};
