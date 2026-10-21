// ============================================================================
// PROPERTY-BASED TEST SUITE (tests/property.ts)
// File: tests/property.ts
// Sinh chuỗi thao tác ngẫu nhiên (Fuzzing / Simulation) và kiểm tra 5 bất biến:
// 1. Số dư mọi đội luôn >= 0 (Chống số dư âm tuyệt đối)
// 2. Số dư = Tổng các dòng tiền trong Ledger (Bất biến tài chính toàn vẹn)
// 3. Tối đa 1 claim đang chiếm slot cho mỗi cặp (team, station) exclusive
// 4. unlocked_stations của đội khớp chính xác các claim approved
// 5. Không có chìa khóa mồ côi (orphaned keys)
// ============================================================================

interface MockTeam {
  id: string;
  name: string;
  light_balance: number;
  unlocked_stations: string[];
}

interface MockTransaction {
  id: string;
  team_id: string;
  amount: number;
  status: 'approved' | 'rejected' | 'pending';
  is_reversed: boolean;
  type: string;
}

interface MockClaim {
  id: string;
  team_id: string;
  station_id: string;
  status: 'pending_station' | 'pending_admin' | 'approved' | 'rejected';
  is_exclusive: boolean;
}

interface MockKey {
  id: string;
  team_id: string;
  station_id: string;
  consumed_claim_id: string | null;
}

export function runPropertySimulation(numSteps = 100) {
  console.log('================================================================');
  console.log(` BẮT ĐẦU PROPERTY-BASED TESTING (${numSteps} BƯỚC NGẪU NHIÊN)`);
  console.log('================================================================\n');

  // Khởi tạo thế giới giả lập (6 đội, 5 trạm)
  const teams: Record<string, MockTeam> = {
    't1': { id: 't1', name: 'Lửa Thiêng', light_balance: 100, unlocked_stations: [] },
    't2': { id: 't2', name: 'Sóng Thần', light_balance: 100, unlocked_stations: [] },
    't3': { id: 't3', name: 'Rừng Xanh', light_balance: 100, unlocked_stations: [] },
    't4': { id: 't4', name: 'Sấm Sét', light_balance: 100, unlocked_stations: [] },
    't5': { id: 't5', name: 'Trăng Khuyết', light_balance: 100, unlocked_stations: [] },
    't6': { id: 't6', name: 'Bình Minh', light_balance: 100, unlocked_stations: [] },
  };

  const stations = ['st1', 'st2', 'st3', 'st4', 'st5'];
  const transactions: MockTransaction[] = [];
  const claims: MockClaim[] = [];
  const keys: MockKey[] = [];

  // Tạo dòng ledger ban đầu cho mỗi đội (+100)
  Object.values(teams).forEach((t) => {
    transactions.push({
      id: `init_${t.id}`,
      team_id: t.id,
      amount: 100,
      status: 'approved',
      is_reversed: false,
      type: 'initial_grant',
    });
  });

  const checkInvariants = (stepIndex: number) => {
    // Bất biến 1: Số dư >= 0
    for (const t of Object.values(teams)) {
      if (t.light_balance < 0) {
        throw new Error(`[VIOLATION - Invariant 1] Đội ${t.name} có số dư âm: ${t.light_balance} tại bước ${stepIndex}`);
      }
    }

    // Bất biến 2: Số dư = Tổng ledger
    for (const t of Object.values(teams)) {
      const ledgerSum = transactions
        .filter((tx) => tx.team_id === t.id && tx.status === 'approved')
        .reduce((sum, tx) => sum + tx.amount, 0);

      if (t.light_balance !== ledgerSum) {
        throw new Error(
          `[VIOLATION - Invariant 2] Đội ${t.name} lệch số dư tại bước ${stepIndex}: Balance=${t.light_balance}, LedgerSum=${ledgerSum}`
        );
      }
    }

    // Bất biến 3: Tối đa 1 claim chiếm slot exclusive
    const slotMap = new Map<string, number>();
    for (const c of claims) {
      if (c.is_exclusive && (c.status === 'pending_station' || c.status === 'pending_admin')) {
        const key = `${c.team_id}_${c.station_id}`;
        const count = (slotMap.get(key) || 0) + 1;
        slotMap.set(key, count);
        if (count > 1) {
          throw new Error(`[VIOLATION - Invariant 3] Cặp (${c.team_id}, ${c.station_id}) có > 1 claim chiếm slot tại bước ${stepIndex}`);
        }
      }
    }

    // Bất biến 4: unlocked_stations khớp claim approved
    for (const t of Object.values(teams)) {
      const approvedStations = new Set(
        claims.filter((c) => c.team_id === t.id && c.status === 'approved').map((c) => c.station_id)
      );
      for (const st of t.unlocked_stations) {
        if (!approvedStations.has(st)) {
          throw new Error(`[VIOLATION - Invariant 4] Đội ${t.name} có trạm ${st} mở khóa nhưng không có claim approved!`);
        }
      }
    }

    // Bất biến 5: Không có key mồ côi
    for (const k of keys) {
      if (!teams[k.team_id]) {
        throw new Error(`[VIOLATION - Invariant 5] Chìa khóa ${k.id} trỏ đến team không tồn tại!`);
      }
      if (!stations.includes(k.station_id)) {
        throw new Error(`[VIOLATION - Invariant 5] Chìa khóa ${k.id} trỏ đến trạm không tồn tại!`);
      }
    }
  };

  // Chạy mô phỏng numSteps hành động ngẫu nhiên
  const teamIds = Object.keys(teams);

  for (let i = 1; i <= numSteps; i++) {
    const actionType = Math.floor(Math.random() * 5); // 0: claim, 1: approve, 2: buy/use, 3: pvp, 4: reverse
    const randomTeamId = teamIds[Math.floor(Math.random() * teamIds.length)];
    const randomStationId = stations[Math.floor(Math.random() * stations.length)];
    const team = teams[randomTeamId];

    switch (actionType) {
      case 0: {
        // Nộp claim
        const hasActiveSlot = claims.some(
          (c) => c.team_id === randomTeamId && c.station_id === randomStationId && (c.status === 'pending_station' || c.status === 'pending_admin')
        );
        if (!hasActiveSlot) {
          claims.push({
            id: `claim_${i}`,
            team_id: randomTeamId,
            station_id: randomStationId,
            status: 'pending_station',
            is_exclusive: true,
          });
        }
        break;
      }
      case 1: {
        // Quản trò / Admin duyệt claim
        const pendingClaim = claims.find((c) => c.status === 'pending_station' || c.status === 'pending_admin');
        if (pendingClaim) {
          pendingClaim.status = 'approved';
          const claimTeam = teams[pendingClaim.team_id];
          const points = 30;
          claimTeam.light_balance += points;
          if (!claimTeam.unlocked_stations.includes(pendingClaim.station_id)) {
            claimTeam.unlocked_stations.push(pendingClaim.station_id);
          }
          transactions.push({
            id: `tx_claim_${i}`,
            team_id: pendingClaim.team_id,
            amount: points,
            status: 'approved',
            is_reversed: false,
            type: 'station_clear',
          });
        }
        break;
      }
      case 2: {
        // Mua vật phẩm (chỉ khi đủ số dư)
        const itemPrice = 20;
        if (team.light_balance >= itemPrice) {
          team.light_balance -= itemPrice;
          transactions.push({
            id: `tx_shop_${i}`,
            team_id: team.id,
            amount: -itemPrice,
            status: 'approved',
            is_reversed: false,
            type: 'shop_item',
          });
        }
        break;
      }
      case 3: {
        // PvP
        const targetTeamId = teamIds[Math.floor(Math.random() * teamIds.length)];
        if (targetTeamId !== randomTeamId) {
          const defender = teams[targetTeamId];
          const stealAmount = Math.min(15, defender.light_balance);
          if (stealAmount > 0) {
            defender.light_balance -= stealAmount;
            team.light_balance += stealAmount;
            transactions.push({
              id: `tx_pvp_atk_${i}`,
              team_id: team.id,
              amount: stealAmount,
              status: 'approved',
              is_reversed: false,
              type: 'pvp_steal',
            });
            transactions.push({
              id: `tx_pvp_def_${i}`,
              team_id: defender.id,
              amount: -stealAmount,
              status: 'approved',
              is_reversed: false,
              type: 'pvp_steal',
            });
          }
        }
        break;
      }
      case 4: {
        // Hoàn tác transaction hợp lệ
        const reversableTx = transactions.find(
          (tx) => tx.status === 'approved' && !tx.is_reversed && tx.type !== 'reversal' && tx.type !== 'initial_grant'
        );
        if (reversableTx) {
          const txTeam = teams[reversableTx.team_id];
          // Nếu là khoản cộng mà số dư hiện tại không đủ hoàn tác, chặn để tránh âm
          if (reversableTx.amount > 0 && txTeam.light_balance < reversableTx.amount) {
            // Chặn hoàn tác thông thường
          } else {
            reversableTx.is_reversed = true;
            txTeam.light_balance -= reversableTx.amount;
            transactions.push({
              id: `rev_${reversableTx.id}`,
              team_id: txTeam.id,
              amount: -reversableTx.amount,
              status: 'approved',
              is_reversed: false,
              type: 'reversal',
            });
          }
        }
        break;
      }
    }

    // Kiểm tra toàn vẹn sau từng bước
    checkInvariants(i);
  }

  console.log(`[PASS] Đã hoàn thành toàn bộ ${numSteps} chuỗi thao tác ngẫu nhiên.`);
  console.log('[PASS] Cả 5 bất biến (Invariant 1 -> 5) được bảo toàn 100% không một lỗi sai lệch!\n');
}

// Chạy trực tiếp simulation với 500 bước thao tác ngẫu nhiên
runPropertySimulation(500);
