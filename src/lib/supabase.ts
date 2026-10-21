// ============================================================================
// SUPABASE CLIENT - Khởi tạo Supabase client cho Evermyst
// ============================================================================
import { createClient } from '@supabase/supabase-js';

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL || '';
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY || '';

if (!supabaseUrl || !supabaseAnonKey) {
  console.warn(
    '⚠️ EVERMYST: Chưa cấu hình Supabase!\n' +
    'Tạo file .env với:\n' +
    '  VITE_SUPABASE_URL=https://xxxxx.supabase.co\n' +
    '  VITE_SUPABASE_ANON_KEY=eyJhbGci...'
  );
}

export const supabase = createClient(supabaseUrl, supabaseAnonKey, {
  realtime: {
    params: {
      eventsPerSecond: 10,
    },
  },
});
