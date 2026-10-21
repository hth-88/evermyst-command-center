// ============================================================================
// CENTRAL RPC CALLER & ERROR INTERCEPTOR (rpc.ts)
// File: src/lib/rpc.ts
// Tự gắn p_token, sinh client_request_id cho RPC ghi, dịch mã lỗi sang Tiếng Việt
// ============================================================================
import { supabase } from '@/lib/supabase';
import { getErrorMessage } from '@/lib/errors.vi';
import type { RPCResponse, RpcMap } from '@/lib/types';

export const TOKEN_STORAGE_KEY = 'evermyst_token';

// Danh sách các RPC ghi nhận thay đổi số dư hoặc dữ liệu (Mutations)
const MUTATION_RPCS = new Set([
  'submit_station_claim',
  'verify_station_claim',
  'cancel_station_claim',
  'purchase_hint',
  'purchase_item',
  'use_team_item',
  'resolve_pvp',
  'reverse_transaction',
  'admin_adjust_balance',
  'admin_upsert_station',
  'admin_delete_station',
  'admin_upsert_hint',
  'admin_delete_hint',
  'admin_upsert_item',
  'admin_delete_item',
  'admin_upsert_staff',
  'admin_update_game_settings',
  'update_setting',
  'admin_revoke_sessions',
]);

// Danh sách các RPC nhận tham số p_client_request_id
const IDEMPOTENT_MUTATIONS = new Set([
  'submit_station_claim',
  'purchase_hint',
  'purchase_item',
  'resolve_pvp',
  'reverse_transaction',
  'admin_adjust_balance',
]);

export interface CallRpcOptions {
  clientRequestId?: string;
  isMutation?: boolean;
}

/**
 * Sinh UUID/ClientId chuẩn cho ý định người dùng
 */
export function generateClientRequestId(prefix = 'req'): string {
  return `${prefix}_${Date.now()}_${Math.random().toString(36).substring(2, 9)}`;
}

/**
 * Gọi Supabase RPC an toàn:
 * 1. Tự động đính kèm p_token từ localStorage.
 * 2. Sinh client_request_id duy nhất cho mỗi ý định ghi (giữ nguyên khi retry).
 * 3. Chuyển đổi mã lỗi sang Tiếng Việt từ errors.vi.ts.
 * 4. Tự động kích hoạt đăng xuất khi gặp lỗi UNAUTHENTICATED.
 * 5. TypeScript typings an toàn cho mọi RPC.
 */
export async function callRpc<K extends keyof RpcMap>(
  rpcName: K,
  args?: RpcMap[K]['args'],
  options?: CallRpcOptions
): Promise<RpcMap[K]['return']>;
export async function callRpc<T = any>(
  rpcName: string,
  args?: Record<string, any>,
  options?: CallRpcOptions
): Promise<RPCResponse<T>>;
export async function callRpc(
  rpcName: string,
  args: Record<string, any> = {},
  options: CallRpcOptions = {}
): Promise<RPCResponse<any>> {
  const token = localStorage.getItem(TOKEN_STORAGE_KEY) || '';

  const finalArgs: Record<string, any> = { ...args };

  // 1. Tự động gắn p_token nếu RPC yêu cầu và chưa được truyền tường minh
  if (!('p_token' in finalArgs) && rpcName !== 'staff_login') {
    finalArgs.p_token = token;
  }

  // 2. Tự động sinh hoặc giữ nguyên p_client_request_id cho RPC ghi
  const isMutation = options.isMutation ?? MUTATION_RPCS.has(rpcName);
  const needsIdempotency = IDEMPOTENT_MUTATIONS.has(rpcName);

  if (needsIdempotency && !finalArgs.p_client_request_id) {
    finalArgs.p_client_request_id = options.clientRequestId || generateClientRequestId();
  }

  try {
    const { data, error } = await supabase.rpc(rpcName, finalArgs);

    if (error) {
      const code = (error as any).code || 'RPC_ERROR';
      const viMessage = getErrorMessage(code, error.message);

      // Nếu session không hợp lệ hoặc hết hạn -> Kích hoạt đăng xuất
      if (code === 'UNAUTHENTICATED' || error.message.includes('UNAUTHENTICATED')) {
        handleUnauthenticated();
      }

      return {
        success: false,
        code,
        error: viMessage,
        message: viMessage,
      };
    }

    // Nếu RPC trả về JSON có cờ success = false
    if (data && typeof data === 'object') {
      const rpcData = data as RPCResponse;

      if (rpcData.success === false) {
        const code = rpcData.code || 'BUSINESS_ERROR';
        const viMessage = getErrorMessage(code, rpcData.error || rpcData.message);

        if (code === 'UNAUTHENTICATED') {
          handleUnauthenticated();
        }

        return {
          ...rpcData,
          code,
          error: viMessage,
          message: viMessage,
        };
      }

      return rpcData;
    }

    return {
      success: true,
      data: data,
    };
  } catch (err: any) {
    const viMessage = getErrorMessage('NETWORK_ERROR', err?.message || 'Lỗi kết nối máy chủ.');
    return {
      success: false,
      code: 'NETWORK_ERROR',
      error: viMessage,
      message: viMessage,
    };
  }
}

/**
 * Xử lý khi gặp lỗi UNAUTHENTICATED: Xóa token và phát sự kiện đăng xuất
 */
function handleUnauthenticated() {
  localStorage.removeItem(TOKEN_STORAGE_KEY);
  if (typeof window !== 'undefined') {
    window.dispatchEvent(new CustomEvent('evermyst:unauthenticated'));
  }
}
