// =====================================================================
// scripts/race_104.mjs
// Kịch bản kiểm thử Race Condition & Idempotency đồng thời cho RPC 104
//
// Cách chạy:
//   node scripts/race_104.mjs
// =====================================================================

import { createClient } from '@supabase/supabase-js';
import * as fs from 'fs';
import * as path from 'path';

// 1. Đọc cấu hình từ .env
const envPath = path.join(process.cwd(), '.env');
let supabaseUrl = process.env.VITE_SUPABASE_URL;
let supabaseAnonKey = process.env.VITE_SUPABASE_ANON_KEY;

if (fs.existsSync(envPath)) {
  const envContent = fs.readFileSync(envPath, 'utf8');
  for (const line of envContent.split('\n')) {
    const trimmed = line.trim();
    if (trimmed.startsWith('VITE_SUPABASE_URL=')) {
      supabaseUrl = trimmed.split('=')[1].trim();
    } else if (trimmed.startsWith('VITE_SUPABASE_ANON_KEY=')) {
      supabaseAnonKey = trimmed.split('=')[1].trim();
    }
  }
}

if (!supabaseUrl || !supabaseAnonKey) {
  console.error('❌ Thiếu VITE_SUPABASE_URL hoặc VITE_SUPABASE_ANON_KEY trong .env');
  process.exit(1);
}

const supabase = createClient(supabaseUrl, supabaseAnonKey);

async function main() {
  console.log('🚀 Bắt đầu kiểm thử Race Condition cho Migration 104...');
  console.log('📡 Supabase Endpoint:', supabaseUrl);

  // 2. Đăng nhập lấy token Admin thật
  console.log('\n--- BƯỚC 1: Đăng nhập lấy Token Admin ---');
  const { data: loginData, error: loginErr } = await supabase.rpc('staff_login', { p_pin: '0000' });
  if (loginErr || !loginData?.success) {
    console.error('❌ Đăng nhập Admin thất bại:', loginErr || loginData);
    process.exit(1);
  }

  const token = loginData.token;
  console.log('✅ Đăng nhập Admin thành công. Token:', token.substring(0, 12) + '...');

  // 3. Lấy thông tin 1 đội và 2 trạm
  console.log('\n--- BƯỚC 2: Chuẩn bị Đội và Trạm ---');
  const { data: teams } = await supabase.from('teams').select('id, name, light_balance').limit(1);
  const testTeam = teams[0];
  console.log(`Đội thử nghiệm: "${testTeam.name}" (ID: ${testTeam.id}), Số dư ban đầu: ${testTeam.light_balance} Lumen`);

  const { data: stations } = await supabase.from('stations').select('id, name, order_index').order('order_index');
  if (!stations || stations.length < 2) {
    console.error('❌ Không tìm đủ trạm.');
    process.exit(1);
  }

  // Chọn trạm 1 (nhiều lượt) và trạm 2 (1 lượt)
  const multiStation = stations[0]; // Cổng Sương Mù
  const singleStation = stations[1]; // Đền Cổ Lumen

  console.log(`Trạm nhiều lượt thử nghiệm: "${multiStation.name}" (ID: ${multiStation.id})`);
  console.log(`Trạm 1 lượt thử nghiệm: "${singleStation.name}" (ID: ${singleStation.id})`);

  // ===================================================================
  // TEST RACE 1: 10 REQUESTS ĐỒNG THỜI VÀO TRẠM NHIỀU LƯỢT (allow_multiple_attempts)
  // ===================================================================
  console.log('\n--- BƯỚC 3: Bắn 10 request đồng thời (Promise.all) vào Trạm Nhiều Lượt ---');
  const startTimeMulti = Date.now();
  const multiPromises = Array.from({ length: 10 }).map((_, i) => {
    const reqId = `race_multi_${Date.now()}_${i}_${Math.random().toString(36).substring(2, 7)}`;
    return supabase.rpc('award_station_direct_points', {
      p_token: token,
      p_team_id: testTeam.id,
      p_station_id: multiStation.id,
      p_points: 1, // mỗi lượt 1 điểm
      p_client_request_id: reqId,
      p_note: `Race test multi attempt #${i + 1}`
    });
  });

  const multiResults = await Promise.all(multiPromises);
  const durationMulti = Date.now() - startTimeMulti;
  console.log(`⏱️ Thời gian thực thi 10 requests đồng thời: ${durationMulti}ms`);

  let multiSuccessCount = 0;
  const playNumbers = new Set();

  multiResults.forEach((res, i) => {
    const data = res.data;
    if (data?.ok || data?.success) {
      multiSuccessCount++;
      playNumbers.add(data.data?.play_no);
    } else {
      console.log(`  Req #${i + 1} Error:`, data?.code, data?.message);
    }
  });

  console.log(`Kết quả: ${multiSuccessCount}/10 thành công.`);
  console.log(`Số thứ tự lượt (play_no) nhận được:`, Array.from(playNumbers).sort((a, b) => a - b));

  if (multiSuccessCount === 10 && playNumbers.size === 10) {
    console.log('✅ TEST RACE 1 ĐẠT: Không có xung đột, play_no được phân phối tuần tự chính xác 1..10.');
  } else {
    console.error('❌ TEST RACE 1 KHÔNG ĐẠT: Trùng lặp hoặc mất mát dữ liệu.');
  }

  // ===================================================================
  // TEST RACE 2: 5 REQUESTS ĐỒNG THỜI VÀO TRẠM 1 LƯỢT (CHẶN SPAM)
  // ===================================================================
  console.log('\n--- BƯỚC 4: Bắn 5 request đồng thời (Promise.all) vào Trạm 1 Lượt ---');
  const startTimeSingle = Date.now();
  const singlePromises = Array.from({ length: 5 }).map((_, i) => {
    const reqId = `race_single_${Date.now()}_${i}_${Math.random().toString(36).substring(2, 7)}`;
    return supabase.rpc('award_station_direct_points', {
      p_token: token,
      p_team_id: testTeam.id,
      p_station_id: singleStation.id,
      p_points: 2,
      p_client_request_id: reqId,
      p_note: `Race test single attempt #${i + 1}`
    });
  });

  const singleResults = await Promise.all(singlePromises);
  const durationSingle = Date.now() - startTimeSingle;
  console.log(`⏱️ Thời gian thực thi 5 requests đồng thời: ${durationSingle}ms`);

  let singleSuccessCount = 0;
  let singleBlockedCount = 0;

  singleResults.forEach((res, i) => {
    const data = res.data;
    if (data?.ok || data?.success) {
      singleSuccessCount++;
      console.log(`  Req #${i + 1}: ✅ Thành công (play_no: ${data.data?.play_no})`);
    } else if (data?.code === 'STATION_ALREADY_PLAYED') {
      singleBlockedCount++;
      console.log(`  Req #${i + 1}: 🛑 Bị chặn chính xác (${data.code}: ${data.message})`);
    } else {
      console.log(`  Req #${i + 1}: Lỗi khác (${data?.code}: ${data?.message})`);
    }
  });

  console.log(`Kết quả: ${singleSuccessCount} thành công, ${singleBlockedCount} bị chặn.`);

  if (singleSuccessCount === 1 && singleBlockedCount === 4) {
    console.log('✅ TEST RACE 2 ĐẠT: Đúng duy nhất 1 request lọt vào, 4 request song song bị chặn bởi khóa đội.');
  } else {
    console.error('❌ TEST RACE 2 KHÔNG ĐẠT: Cần kiểm tra lại cơ chế khóa FOR UPDATE.');
  }

  console.log('\n🎉 Hoàn thành kiểm thử Race Condition.');
}

main().catch(console.error);
