// ============================================================================
// VIETNAMESE ERROR CODES DICTIONARY (errors.vi.ts)
// File: src/lib/errors.vi.ts
// Ánh xạ toàn bộ mã lỗi từ Database RPC (ADR-1, ADR-4) sang thông báo Tiếng Việt
// ============================================================================

export const ERROR_MESSAGES_VI: Record<string, string> = {
  // 1. Xác thực & Quản lý Phiên (Authentication & Sessions)
  UNAUTHENTICATED: 'Phiên làm việc đã hết hạn hoặc không hợp lệ. Vui lòng đăng nhập lại.',
  INVALID_TOKEN: 'Mã phiên (token) không hợp lệ hoặc đã bị thu hồi.',
  INVALID_PIN: 'Mã PIN không được để trống và phải đúng định dạng số.',
  INVALID_CREDENTIALS: 'Mã PIN không chính xác hoặc tài khoản nhân sự đã bị khóa.',
  LOGIN_LOCKED: 'IP của bạn tạm thời bị khóa 10 phút do nhập sai mã PIN quá 5 lần. Vui lòng thử lại sau.',
  PIN_NOT_UNIQUE: 'Mã PIN này đã được sử dụng bởi nhân sự khác đang hoạt động. Vui lòng chọn mã PIN khác.',
  STAFF_DEACTIVATED: 'Tài khoản nhân sự này đã bị vô hiệu hóa bởi Ban Quản Trị.',
  FORBIDDEN: 'Bạn không có quyền thực hiện hành động này.',
  FORBIDDEN_ROLE: 'Vai trò của bạn không được phép thực hiện chức năng này.',
  FORBIDDEN_STATION: 'Bạn không được phân công phụ trách trạm này.',
  FORBIDDEN_TEAM: 'Bạn chỉ được phép hỗ trợ đội chơi mà bạn được phân công.',

  // 2. Trạm Thử Thách & Claim Trạm (Stations & Claims)
  INVALID_SCORING_INPUT: 'Thông số chấm điểm không hợp lệ đối với cấu hình trạm này.',
  STATION_NOT_FOUND: 'Không tìm thấy trạm thử thách hoặc trạm đã đóng.',
  CLAIM_ALREADY_EXISTS: 'Đội này đã hoàn thành hoặc đang có yêu cầu chấm điểm tại trạm này.',
  CLAIM_NOT_FOUND: 'Không tìm thấy yêu cầu chấm điểm trạm.',
  CLAIM_STATUS_INVALID: 'Trạng thái yêu cầu không phù hợp để thực hiện thao tác này.',
  NOTE_REQUIRED_ON_REJECT: 'Bắt buộc phải nhập lý do khi từ chối yêu cầu claim trạm.',
  OVERRIDE_REQUIRES_NOTE: 'Bắt buộc phải nhập lý do điều chỉnh khi thay đổi điểm số của đội.',
  INVALID_ACTION: 'Thao tác thẩm định không hợp lệ (chỉ chấp nhận approve hoặc reject).',
  STATION_ORDER_INVALID: 'Đội chưa vượt qua trạm trước đó để mở khóa trạm này.',

  // 3. Tài Chính, Số Dư & Ledger Bất Biến (Ledger Integrity)
  TEAM_NOT_FOUND: 'Không tìm thấy thông tin đội chơi.',
  INVALID_AMOUNT: 'Số lượng hoặc số điểm không hợp lệ (phải lớn hơn 0).',
  INSUFFICIENT_FUNDS: 'Số dư Lumen của đội không đủ để thực hiện giao dịch này.',
  INSUFFICIENT_BALANCE: 'Số dư Lumen của đội không đủ để thực hiện giao dịch này.',
  LEDGER_IMMUTABLE: 'Sổ cái tài chính là bất biến, không thể sửa đổi hoặc xóa trực tiếp!',
  BALANCE_INTEGRITY_FAIL: 'Phát hiện sai lệch số dư so với lịch sử sổ cái. Giao dịch bị tạm ngưng.',

  // 4. Cửa Hàng, Đạo Cụ & Chìa Khóa (Shop, Items & Keys)
  ITEM_NOT_FOUND: 'Không tìm thấy đạo cụ yêu cầu trong cửa hàng.',
  ITEM_NOT_OWNED: 'Đội không còn vật phẩm này trong kho đồ để sử dụng.',
  NOT_OWNED: 'Đội không sở hữu vật phẩm này trong kho đồ.',
  KEY_ALREADY_EXISTS: 'Đội đã có chìa khóa sẵn sàng cho trạm này.',
  KEY_ALREADY_CONSUMED: 'Chìa khóa trạm này đã được sử dụng.',
  STATION_REQUIRED: 'Vui lòng chọn trạm cần trang bị chìa khóa lối tắt.',
  STATION_ALREADY_CLEARED: 'Đội đã hoàn thành trạm độc quyền này trước đó, không cần dùng chìa khóa.',
  TARGET_SAME_TEAM: 'Không thể chọn chính đội của mình làm mục tiêu do thám.',
  HINT_ALREADY_PURCHASED: 'Đội đã sở hữu manh mối này từ trước. Vui lòng xem lại không tốn phí.',
  ALREADY_OWNED: 'Đội đã sở hữu manh mối này từ trước.',
  PRICE_CHANGED: 'Giá vật phẩm đã thay đổi. Vui lòng tải lại trang.',
  LIMIT_REACHED: 'Đã đạt giới hạn số lượng cho phép.',

  // 5. Chiến Đấu PvP (PvP Combat)
  PVP_SAME_TEAM: 'Không thể tự tấn công chính đội của mình!',
  COOLDOWN_ACTIVE: 'Hai đội vừa giao đấu. Cooldown 2 chiều còn hiệu lực! Vui lòng thử lại sau.',
  NOTHING_TO_STEAL: 'Đội phòng thủ không còn Lumen để cướp.',
  DEFENDER_SHIELDED: '🛡️ Đội phòng thủ đang có Khiên Màn Sương! Bạn đã bị phạt phản phệ.',

  // 6. Hoàn Tác Giao Dịch & Điều Chỉnh Quản Trị (Reversals & Admin Adjustments)
  NOT_FOUND: 'Dữ liệu yêu cầu không tồn tại trên hệ thống.',
  TX_NOT_FOUND: 'Không tìm thấy thông tin giao dịch cần hoàn tác.',
  ALREADY_REVERSED: 'Giao dịch này đã được hoàn tác trước đó.',
  CANNOT_REVERSE_REVERSAL: 'Không thể hoàn tác một giao dịch đối ứng bù đắp!',
  NOT_REVERSIBLE: 'Chỉ có thể hoàn tác giao dịch đã được phê duyệt.',
  UNDO_WINDOW_EXPIRED: 'Đã hết thời hạn tự hoàn tác (5 phút). Vui lòng liên hệ Admin!',
  INSUFFICIENT_BALANCE_FOR_REVERT: 'Không thể hoàn tác! Đội đã sử dụng số Lumen này. Báo Admin dùng force-revert!',
  REASON_REQUIRED: 'Bắt buộc phải nhập lý do khi thực hiện thao tác này.',

  // 7. Quản Trị & Cấu Hình Hệ Thống (Admin CRUD & Settings)
  NAME_REQUIRED: 'Tên không được để trống.',
  TITLE_REQUIRED: 'Tiêu đề manh mối không được để trống.',
  CONTENT_REQUIRED: 'Nội dung manh mối không được để trống.',
  KEY_REQUIRED: 'Mã cài đặt không được để trống.',
  INVALID_SCORE_RANGE: 'Khoảng điểm không hợp lệ (min >= 0 và min <= max).',
  INVALID_SCORING_TYPE: 'Kiểu chấm điểm trạm không hợp lệ (tier, fixed, time_attack).',
  INVALID_SCORING_CONFIG: 'Cấu hình chấm điểm trạm không hợp lệ đối với kiểu đã chọn.',
  INVALID_TIER: 'Phân hạng manh mối không hợp lệ.',
  INVALID_EFFECT_TYPE: 'Loại hiệu ứng đạo cụ không hợp lệ.',
  INVALID_DURATION: 'Thời lượng bảo vệ của Khiên (duration_minutes) bắt buộc phải lớn hơn 0.',
  INVALID_STAFF_ASSIGNMENT: 'Phân công vai trò không hợp lệ (team_support cần đội; station_master cần trạm; admin không gán đội/trạm).',
  LAST_ADMIN_PROTECTED: 'Không thể tự vô hiệu hóa hoặc đổi vai trò của Admin cuối cùng trong hệ thống!',
};

/**
 * Tra cứu thông báo lỗi Tiếng Việt thân thiện theo mã lỗi ổn định
 */
export function getErrorMessage(code?: string | null, fallback?: string): string {
  if (!code) return fallback || 'Đã có lỗi xảy ra. Vui lòng thử lại.';
  return ERROR_MESSAGES_VI[code] || fallback || `Lỗi nghiệp vụ [${code}]. Vui lòng thử lại.`;
}
