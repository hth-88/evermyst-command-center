# BẢNG TỪ ĐIỂN MÃ LỖI NGHIỆP VỤ HỆ THỐNG EVERMYST V2 (ERROR CODES)

Tài liệu chuẩn hóa toàn bộ các mã lỗi nghiệp vụ (Standard Error Codes) trả về từ Database RPC (Security Definer) lên Frontend.
Frontend dựa trên các mã ổn định này để hiển thị thông báo tiếng Việt tương ứng cho người dùng.

---

## 1. Xác thực & Quản lý Phiên (Authentication & Sessions)

| Mã Lỗi | Mô tả Kỹ thuật | Thông báo hiển thị Tiếng Việt (Frontend) |
| :--- | :--- | :--- |
| `UNAUTHENTICATED` | Session token rỗng, không tìm thấy hash trong DB, hoặc đã hết hạn 24h | Phiên làm việc đã hết hạn hoặc không hợp lệ. Vui lòng đăng nhập lại. |
| `INVALID_PIN` | Mã PIN rỗng, sai định dạng hoặc chứa ký tự không hợp lệ | Mã PIN không được để trống và phải đúng định dạng số. |
| `INVALID_CREDENTIALS` | Mã PIN không khớp với bất kỳ nhân sự active nào | Mã PIN không chính xác hoặc tài khoản nhân sự đã bị khóa. |
| `LOGIN_LOCKED` | IP bị rate-limit do nhập sai mã PIN quá 5 lần trong vòng 5 phút (khóa 10 phút) | IP của bạn tạm thời bị khóa 10 phút do nhập sai mã PIN quá 5 lần. Vui lòng thử lại sau. |
| `PIN_NOT_UNIQUE` | Mã PIN bị trùng với nhân sự đang hoạt động khác khi tạo/đổi PIN | Mã PIN này đã được sử dụng bởi nhân sự khác. Vui lòng chọn mã PIN khác. |
| `STAFF_DEACTIVATED` | Tài khoản nhân sự có cờ `is_active = false` | Tài khoản nhân sự này đã bị vô hiệu hóa bởi Ban Quản Trị. |
| `FORBIDDEN_ROLE` | Vai trò nhân sự (`role`) không nằm trong danh sách cho phép của hành động | Vai trò của bạn không được phép thực hiện chức năng này. |
| `FORBIDDEN_STATION` | `station_master` cố gắng thao tác trạm khác trạm được phân công | Bạn không được phân công phụ trách trạm này. |
| `FORBIDDEN_TEAM` | `team_support` cố gắng thao tác cho đội khác đội được phân công | Bạn chỉ được phép hỗ trợ đội chơi mà bạn được phân công. |

---

## 2. Trạm Thử Thách & Claim Trạm (Stations & Claims)

| Mã Lỗi | Mô tả Kỹ thuật | Thông báo hiển thị Tiếng Việt (Frontend) |
| :--- | :--- | :--- |
| `INVALID_SCORING_INPUT` | Input chấm điểm sai (tier không tồn tại, units vượt trần, thiếu tham số) | Thông số chấm điểm không hợp lệ đối với cấu hình trạm này. |
| `STATION_NOT_FOUND` | Trạm không tồn tại hoặc đã bị vô hiệu hóa (`is_active = false`, `deleted_at IS NOT NULL`) | Không tìm thấy trạm thử thách hoặc trạm đã đóng. |
| `CLAIM_ALREADY_EXISTS` | Đội đã có claim đang xử lý hoặc đã duyệt trên trạm này (Partial Unique Violation) | Đội này đã hoàn thành hoặc đang có yêu cầu chấm điểm tại trạm này. |
| `CLAIM_NOT_FOUND` | Bản ghi `station_claims` không tìm thấy theo ID | Không tìm thấy yêu cầu chấm điểm trạm. |
| `CLAIM_STATUS_INVALID` | Thao tác không hợp lệ đối với trạng thái claim hiện tại (ví dụ: duyệt claim đã duyệt) | Trạng thái yêu cầu không phù hợp để thực hiện thao tác này. |
| `NOTE_REQUIRED_ON_REJECT` | Từ chối claim nhưng không nhập lý do bắt buộc | Bắt buộc phải nhập lý do khi từ chối yêu cầu claim trạm. |
| `OVERRIDE_REQUIRES_NOTE` | Sửa đổi input/điểm của đội nhưng không nhập lý do bắt buộc | Bắt buộc phải nhập lý do điều chỉnh khi thay đổi điểm số của đội. |
| `INVALID_ACTION` | Hành động thẩm định không hợp lệ (chỉ chấp nhận `approve` hoặc `reject`) | Thao tác thẩm định không hợp lệ. |
| `STATION_ORDER_INVALID` | Trạm chưa được mở theo đúng tiến trình/thứ tự yêu cầu | Đội chưa vượt qua trạm trước đó để mở khóa trạm này. |

---

## 3. Tài Chính, Số Dư & Ledger Bất Biến (Ledger Integrity)

| Mã Lỗi | Mô tả Kỹ thuật | Thông báo hiển thị Tiếng Việt (Frontend) |
| :--- | :--- | :--- |
| `TEAM_NOT_FOUND` | Đội chơi không tồn tại hoặc bị vô hiệu hóa | Không tìm thấy thông tin đội chơi. |
| `INVALID_AMOUNT` | Số lượng hoặc số điểm không hợp lệ (<= 0 hoặc vượt trần) | Số lượng hoặc số điểm không hợp lệ (phải lớn hơn 0). |
| `INSUFFICIENT_FUNDS` | Số dư Lumen của đội không đủ để thanh toán | Số dư Lumen của đội không đủ để thực hiện giao dịch này. |
| `INSUFFICIENT_BALANCE` | Bí danh chuẩn hóa của INSUFFICIENT_FUNDS | Số dư Lumen của đội không đủ để thực hiện giao dịch này. |
| `LEDGER_IMMUTABLE` | Vi phạm tính bất biến của sổ cái (Cố tình DELETE hoặc sửa đổi số liệu transactions) | Sổ cái tài chính là bất biến, không thể sửa đổi hoặc xóa trực tiếp! |
| `BALANCE_INTEGRITY_FAIL`| Số dư đội bị âm hoặc không khớp với tổng dòng tiền Ledger | Phát hiện sai lệch số dư so với lịch sử sổ cái. Giao dịch bị tạm ngưng. |

---

## 4. Cửa Hàng, Đạo Cụ & Chìa Khóa (Shop, Items & Keys)

| Mã Lỗi | Mô tả Kỹ thuật | Thông báo hiển thị Tiếng Việt (Frontend) |
| :--- | :--- | :--- |
| `ITEM_NOT_FOUND` | Đạo cụ không tồn tại hoặc đã bị ngừng bán | Không tìm thấy đạo cụ yêu cầu trong cửa hàng. |
| `ITEM_NOT_OWNED` | Đội không còn vật phẩm này trong kho đồ để sử dụng | Đội không còn vật phẩm này trong kho đồ. |
| `NOT_OWNED` | Bí danh của ITEM_NOT_OWNED | Đội không sở hữu vật phẩm này trong kho đồ. |
| `KEY_ALREADY_EXISTS` | Đội đã có chìa khóa sẵn sàng chưa dùng cho trạm này | Đội đã có chìa khóa sẵn sàng cho trạm này. |
| `KEY_ALREADY_CONSUMED` | Chìa khóa trạm đã được tiêu thụ cho một claim trước đó | Chìa khóa trạm này đã được sử dụng. |
| `STATION_REQUIRED` | Dùng chìa khóa trạm nhưng không cung cấp ID trạm | Vui lòng chọn trạm cần trang bị chìa khóa lối tắt. |
| `STATION_ALREADY_CLEARED` | Trạm độc quyền đã được đội vượt qua trước đó | Đội đã hoàn thành trạm độc quyền này trước đó, không cần dùng chìa khóa. |
| `TARGET_SAME_TEAM` | Chọn mục tiêu đạo cụ (do thám) là chính đội mình | Không thể chọn chính đội của mình làm mục tiêu do thám. |
| `HINT_ALREADY_PURCHASED` | Chặn mua trùng manh mối đã mở khóa | Đội đã sở hữu manh mối này từ trước. Vui lòng xem lại không tốn phí. |
| `ALREADY_OWNED` | Bí danh của HINT_ALREADY_PURCHASED | Đội đã sở hữu manh mối này từ trước. |

---

## 5. Chiến Đấu PvP (PvP Combat)

| Mã Lỗi | Mô tả Kỹ thuật | Thông báo hiển thị Tiếng Việt (Frontend) |
| :--- | :--- | :--- |
| `PVP_SAME_TEAM` | Đội tấn công và đội phòng thủ trùng nhau | Không thể tự tấn công chính đội của mình! |
| `COOLDOWN_ACTIVE` | Cặp đấu đang trong thời gian giãn cách PvP 30 phút (tính 2 chiều Fix #6) | Hai đội vừa giao đấu. Cooldown 2 chiều còn hiệu lực! Vui lòng thử lại sau. |
| `NOTHING_TO_STEAL` | Đội phòng thủ có số dư <= 0, không có gì để cướp (không ghi log) | Đội phòng thủ không còn Lumen để cướp. |
| `DEFENDER_SHIELDED` | Đội phòng thủ có khiên, kích hoạt phản phệ phạt kẻ tấn công | 🛡️ Đội phòng thủ đang có Khiên Màn Sương! Bạn đã bị phạt phản phệ. |

---

## 6. Hoàn Tác Giao Dịch & Điều Chỉnh Quản Trị (Reversals & Admin Adjustments)

| Mã Lỗi | Mô tả Kỹ thuật | Thông báo hiển thị Tiếng Việt (Frontend) |
| :--- | :--- | :--- |
| `NOT_FOUND` / `TX_NOT_FOUND` | Giao dịch cần hoàn tác không tồn tại | Không tìm thấy thông tin giao dịch cần hoàn tác. |
| `ALREADY_REVERSED` | Giao dịch đã được hoàn tác trước đó (Chặn hoàn tác kép) | Giao dịch này đã được hoàn tác trước đó. |
| `CANNOT_REVERSE_REVERSAL` | Cố tình hoàn tác một dòng giao dịch đối ứng bù đắp (`type = 'reversal'`) | Không thể hoàn tác một giao dịch đối ứng bù đắp! |
| `NOT_REVERSIBLE` | Giao dịch ở trạng thái pending hoặc rejected | Chỉ có thể hoàn tác giao dịch đã được phê duyệt. |
| `UNDO_WINDOW_EXPIRED` | Đã quá cửa sổ hoàn tác 5 phút của nhân sự thường (`undo_window_minutes`) | Đã hết thời hạn tự hoàn tác (5 phút). Vui lòng liên hệ Admin! |
| `INSUFFICIENT_BALANCE_FOR_REVERT` | Hoàn tác khoản cộng nhưng đội đã tiêu mất số dư (chặn âm số dư) | Không thể hoàn tác! Đội đã sử dụng số Lumen này. Báo Admin dùng force-revert! |
| `REASON_REQUIRED` | Thiếu lý do bắt buộc khi điều chỉnh số dư hoặc hoàn tác đặc biệt | Bắt buộc phải nhập lý do khi thực hiện thao tác này. |

---

## 7. Quản Trị & Cấu Hình Hệ Thống (Admin CRUD & Settings)

| Mã Lỗi | Mô tả Kỹ thuật | Thông báo hiển thị Tiếng Việt (Frontend) |
| :--- | :--- | :--- |
| `NAME_REQUIRED` | Tên thực thể (trạm, đạo cụ, nhân sự) để trống | Tên không được để trống. |
| `TITLE_REQUIRED` | Tiêu đề manh mối để trống | Tiêu đề manh mối không được để trống. |
| `CONTENT_REQUIRED` | Nội dung bí mật của manh mối để trống | Nội dung manh mối không được để trống. |
| `KEY_REQUIRED` | Mã cài đặt hệ thống (`key`) để trống | Mã cài đặt không được để trống. |
| `INVALID_SCORE_RANGE` | `min_score < 0` hoặc `max_score < min_score` | Khoảng điểm không hợp lệ (min >= 0 và min <= max). |
| `INVALID_SCORING_TYPE` | Kiểu chấm điểm ngoài danh sách `('tier', 'fixed', 'time_attack')` | Kiểu chấm điểm trạm không hợp lệ. |
| `INVALID_SCORING_CONFIG` | Schema của `scoring_config` sai (thiếu tiers, điểm ngoài range, etc.) | Cấu hình chấm điểm trạm không hợp lệ đối với kiểu đã chọn. |
| `INVALID_TIER` | Tier manh mối ngoài `('bronze', 'silver', 'gold', 'custom')` | Phân hạng manh mối không hợp lệ. |
| `INVALID_EFFECT_TYPE` | Loại hiệu ứng ngoài `('shield', 'spy', 'key', 'custom')` | Loại hiệu ứng đạo cụ không hợp lệ. |
| `INVALID_DURATION` | Khiên bảo vệ nhưng `duration_minutes <= 0` | Thời lượng bảo vệ của Khiên (duration_minutes) bắt buộc phải lớn hơn 0. |
| `INVALID_STAFF_ASSIGNMENT` | Vi phạm ràng buộc phân công vai trò nhân sự (`chk_staff_role_assignment`) | Phân công vai trò không hợp lệ (team_support cần đội; station_master cần trạm; admin không được gán đội hay trạm). |
| `LAST_ADMIN_PROTECTED` | Cố tình tự vô hiệu hóa hoặc hạ quyền của Admin duy nhất còn lại | Không thể tự vô hiệu hóa hoặc đổi vai trò của Admin cuối cùng trong hệ thống! |


