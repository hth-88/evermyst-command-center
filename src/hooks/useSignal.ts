// ============================================================================
// REALTIME SIGNAL HOOK (useSignal.ts)
// File: src/hooks/useSignal.ts
// Đăng ký kênh ADR-3, debounce 300ms, tự reconnect, fallback polling 10s khi offline
// ============================================================================
import { useEffect, useRef, useState, useCallback } from 'react';
import { supabase } from '@/lib/supabase';
import type { ConnectionStatus, RealtimeSignal } from '@/lib/types';

export interface UseSignalOptions {
  enabled?: boolean;
  debounceMs?: number;
  pollingIntervalMs?: number;
}

export function useSignal(
  topic: string,
  onSignal: (signal?: Partial<RealtimeSignal>) => void | Promise<void>,
  options: UseSignalOptions = {}
) {
  const {
    enabled = true,
    debounceMs = 300,
    pollingIntervalMs = 10000,
  } = options;

  const [status, setStatus] = useState<ConnectionStatus>('connecting');
  const [lastSignalAt, setLastSignalAt] = useState<string | null>(null);

  const debounceTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const pollingTimerRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const callbackRef = useRef(onSignal);

  // Giữ callback luôn mới nhất mà không gây re-subscription
  useEffect(() => {
    callbackRef.current = onSignal;
  }, [onSignal]);

  // Hàm kích hoạt refetch có debounce 300ms
  const triggerDebouncedSignal = useCallback((payload?: any) => {
    if (debounceTimerRef.current) {
      clearTimeout(debounceTimerRef.current);
    }

    debounceTimerRef.current = setTimeout(() => {
      setLastSignalAt(new Date().toISOString());
      callbackRef.current(payload);
    }, debounceMs);
  }, [debounceMs]);

  // Thiết lập kênh Realtime và fallback Polling
  useEffect(() => {
    if (!enabled) return;

    let isSubscribed = true;

    // 1. Khởi tạo Supabase Realtime Channel
    const channelName = `realtime_signals_${topic.replace(/[^a-zA-Z0-9_-]/g, '_')}`;
    const channel = supabase.channel(channelName, {
      config: {
        broadcast: { ack: false },
      },
    });

    // Lắng nghe Broadcast messages
    channel
      .on('broadcast', { event: topic }, (response: any) => {
        triggerDebouncedSignal(response.payload);
      })
      .on('broadcast', { event: '*' }, (response: any) => {
        if (topic === '*' || response?.payload?.topic === topic) {
          triggerDebouncedSignal(response.payload);
        }
      });

    // Theo dõi trạng thái kết nối của Realtime WebSocket
    channel.subscribe((subscriptionStatus) => {
      if (!isSubscribed) return;

      if (subscriptionStatus === 'SUBSCRIBED') {
        setStatus('connected');
        // Dừng polling khi đã kết nối WebSocket thành công
        if (pollingTimerRef.current) {
          clearInterval(pollingTimerRef.current);
          pollingTimerRef.current = null;
        }
      } else if (
        subscriptionStatus === 'CLOSED' ||
        subscriptionStatus === 'CHANNEL_ERROR' ||
        subscriptionStatus === 'TIMED_OUT'
      ) {
        setStatus('disconnected');
        startPollingFallback();
      }
    });

    // 2. Hàm kích hoạt Polling 10s khi mất kết nối WebSocket
    function startPollingFallback() {
      if (pollingTimerRef.current) return;
      setStatus('polling');

      pollingTimerRef.current = setInterval(() => {
        if (!isSubscribed) return;
        triggerDebouncedSignal({ topic, isFallback: true });
      }, pollingIntervalMs);
    }

    // 3. Lắng nghe trạng thái mạng thiết bị (online/offline)
    const handleOnline = () => {
      setStatus('connecting');
      channel.subscribe();
      triggerDebouncedSignal();
    };

    const handleOffline = () => {
      setStatus('disconnected');
      startPollingFallback();
    };

    window.addEventListener('online', handleOnline);
    window.addEventListener('offline', handleOffline);

    // Dọn dẹp khi unmount
    return () => {
      isSubscribed = false;
      if (debounceTimerRef.current) clearTimeout(debounceTimerRef.current);
      if (pollingTimerRef.current) clearInterval(pollingTimerRef.current);
      window.removeEventListener('online', handleOnline);
      window.removeEventListener('offline', handleOffline);
      supabase.removeChannel(channel);
    };
  }, [topic, enabled, debounceMs, pollingIntervalMs, triggerDebouncedSignal]);

  return {
    status,
    isConnected: status === 'connected',
    isPolling: status === 'polling',
    lastSignalAt,
    refetchNow: () => triggerDebouncedSignal(),
  };
}
