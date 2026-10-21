// ============================================================================
// EVERMYST TYPES - Toàn bộ TypeScript types cho hệ thống (V2 Architecture)
// ============================================================================

// ---------------------------------------------------------------------------
// Roles & Assignments (ADR-2)
// ---------------------------------------------------------------------------
export type StaffRole = 'admin' | 'team_support' | 'station_master';

export interface AssignedTeamRef {
  id: string;
  name: string;
}

export interface AssignedStationRef {
  id: string;
  name: string;
}

export interface Staff {
  id: string;
  name: string;
  role: StaffRole;
  pin?: string;
  assigned_team_id?: string | null;
  team_name?: string | null;
  assigned_station_id?: string | null;
  station_name?: string | null;
  is_active: boolean;
  created_at?: string;
}

export interface AuthUser {
  id: string;
  name: string;
  role: StaffRole;
  assigned_team_id?: string | null;
  assigned_team?: AssignedTeamRef | null;
  assigned_station_id?: string | null;
  assigned_station?: AssignedStationRef | null;
  station_assigned?: string | null;
  token: string;
  expires_at?: string;
}

// ---------------------------------------------------------------------------
// Database Row Types
// ---------------------------------------------------------------------------

export interface Team {
  id: string;
  name: string;
  qr_code: string;
  light_balance: number;
  shield_until: string | null;
  unlocked_stations: string[];
  is_active: boolean;
  created_at: string;
}

export type ScoringType = 'tier' | 'fixed' | 'time_attack';

export interface Station {
  id: string;
  name: string;
  description: string;
  order_index: number;
  is_active: boolean;
  scoring_type: ScoringType;
  scoring_config: Record<string, any>;
  min_score: number;
  max_score: number;
  allow_multiple_attempts: boolean;
  created_at: string;
  deleted_at?: string | null;
}

export type HintTier = 'bronze' | 'silver' | 'gold' | 'custom';

export interface Hint {
  id: string;
  station_id?: string | null;
  title: string;
  content: string;
  tier: HintTier;
  price?: number;
  order_index: number;
  is_active: boolean;
  created_at: string;
  deleted_at?: string | null;
  station_name?: string;
}

export interface TeamHint {
  id: string;
  team_id: string;
  hint_id: string;
  unlocked_at: string;
  unlocked_by: string;
  purchase_tx_id?: string | null;
}

export type ItemEffectType = 'shield' | 'spy' | 'spyglass' | 'key' | 'master_key' | 'custom';

export interface Item {
  id: string;
  item_code?: string;
  name: string;
  description: string;
  price: number;
  effect_type: ItemEffectType;
  effect_value?: number;
  duration_minutes: number;
  is_active: boolean;
  created_at: string;
  deleted_at?: string | null;
}

export interface TeamItem {
  id: string;
  team_id: string;
  item_id: string;
  item_code?: string;
  quantity: number;
  used_count: number;
  created_at: string;
  updated_at: string;
  item?: Item;
}

export type TransactionType =
  | 'station_clear'
  | 'buy_hint'
  | 'hint_purchase'
  | 'buy_item'
  | 'shop_item'
  | 'pvp_steal'
  | 'pvp_backlash'
  | 'admin_adjust'
  | 'reversal'
  | 'initial_grant'
  | 'migration_correction';

export type TransactionStatus = 'approved' | 'pending' | 'rejected';

export interface Transaction {
  id: string;
  client_request_id?: string | null;
  team_id: string;
  amount: number;
  type: TransactionType;
  description: string;
  created_by: string;
  actor_staff_id?: string | null;
  actor_role?: string | null;
  status: TransactionStatus;
  reviewed_by?: string | null;
  reviewed_at?: string | null;
  is_reversed: boolean;
  reverses_tx_id?: string | null;
  claim_id?: string | null;
  metadata?: Record<string, any>;
  created_at: string;
  // Computed on server
  can_reverse?: boolean;
  reverse_blocked_reason?: string | null;
  team_name?: string;
}

export type ClaimStatus =
  | 'draft'
  | 'pending_station'
  | 'pending_admin'
  | 'approved'
  | 'rejected'
  | 'cancelled';

export interface StationClaim {
  id: string;
  team_id: string;
  team_name?: string;
  station_id: string;
  station_name?: string;
  status: ClaimStatus;
  input: Record<string, any>;
  original_input?: Record<string, any>;
  scoring_snapshot: Record<string, any>;
  computed_points: number;
  final_points: number;
  is_exclusive: boolean;
  requires_admin_review: boolean;
  key_used: boolean;
  submitted_by?: string | null;
  submitted_by_role?: string | null;
  station_verified_by?: string | null;
  station_verified_at?: string | null;
  admin_verified_by?: string | null;
  admin_verified_at?: string | null;
  reject_reason?: string | null;
  correction_note?: string | null;
  client_request_id?: string | null;
  tx_id?: string | null;
  created_at: string;
  updated_at: string;
}

export interface PvPLog {
  id: string;
  client_request_id?: string | null;
  attacker_team_id: string;
  defender_team_id: string;
  amount_stolen: number;
  result: 'success' | 'backlash' | 'cooldown_blocked';
  created_by: string;
  created_at: string;
  attacker_name?: string;
  defender_name?: string;
}

export interface GameSetting {
  key: string;
  value: { v: number | string | boolean };
  label: string;
  description: string;
  category: 'economy' | 'station' | 'shop' | 'pvp' | 'system' | 'general';
  is_public: boolean;
  updated_at: string;
  updated_by: string;
}

export interface GameSettingHistory {
  id: string;
  key: string;
  old_value: { v: number | string | boolean } | null;
  new_value: { v: number | string | boolean };
  changed_by: string;
  created_at: string;
}

export interface AdminAuditLog {
  id: string;
  staff_id: string | null;
  staff_name?: string;
  action: 'CREATE' | 'UPDATE' | 'DELETE' | 'SOFT_DELETE';
  entity: 'stations' | 'hints' | 'items' | 'staff' | 'game_settings';
  entity_id: string | null;
  before: Record<string, any> | null;
  after: Record<string, any> | null;
  created_at: string;
}

export interface GameConfig {
  starting_balance: number;
  station_reward_low: number;
  station_reward_mid: number;
  station_reward_high: number;
  pending_threshold: number;
  hint_price_bronze: number;
  hint_price_silver: number;
  hint_price_gold: number;
  pvp_cooldown_minutes: number;
  pvp_steal_percent: number;
  pvp_backlash_amount: number;
  shield_duration_minutes: number;
  undo_window_minutes: number;
  [key: string]: number;
}

// ---------------------------------------------------------------------------
// Standard RPC Responses
// ---------------------------------------------------------------------------

export interface RPCResponse<T = any> {
  success: boolean;
  code?: string;
  message?: string;
  error?: string;
  idempotent?: boolean;
  data?: T;
  [key: string]: any;
}

export interface LoginResponse extends RPCResponse {
  token?: string;
  expires_at?: string;
  staff?: {
    id: string;
    name: string;
    role: StaffRole;
  };
  assigned_team?: AssignedTeamRef | null;
  assigned_station?: AssignedStationRef | null;
}

export type StandardErrorCode = string;

export type StationRewardResponse = RPCResponse<{
  claim_id?: string;
  status?: ClaimStatus;
  computed_points?: number;
  is_exclusive?: boolean;
}>;

export type BuyHintResponse = RPCResponse<{
  hint_id?: string;
  hint_title?: string;
  hint_content?: string;
  secret_content?: string;
  already_owned?: boolean;
  tier?: string;
  price?: number;
  new_balance?: number;
  tx_id?: string;
}>;

export type BuyItemResponse = RPCResponse<{
  item_id?: string;
  item_code?: string;
  item_name?: string;
  price?: number;
  new_balance?: number;
  tx_id?: string;
  quantity?: number;
  new_quantity?: number;
  shield_until?: string;
}>;

export type PvPResponse = RPCResponse<{
  result?: 'success' | 'backlash';
  amount_stolen?: number;
  attacker_balance?: number;
  defender_balance?: number;
  tx_id?: string;
  cooldown_until?: string;
}>;

// ---------------------------------------------------------------------------
// UI & Signal Types
// ---------------------------------------------------------------------------

export type SupportTab = 'station' | 'shop' | 'pvp' | 'history';

export interface Toast {
  id: string;
  message: string;
  type: 'success' | 'error' | 'warning' | 'info';
  duration?: number;
}

export type ConnectionStatus = 'connected' | 'connecting' | 'disconnected' | 'polling';

export interface RealtimeSignal {
  topic: string;
  payload: Record<string, any>;
  emitted_at: string;
}

// ---------------------------------------------------------------------------
// Strongly Typed RPC Parameter & Response Definitions (Phase 6)
// ---------------------------------------------------------------------------

export interface StaffLoginParams {
  p_pin: string;
}

export interface AuthVerifySessionParams {
  p_token?: string;
}

export interface StaffLogoutParams {
  p_token?: string;
}

export interface AdminRevokeSessionsParams {
  p_token?: string;
  p_staff_id: string;
}

export interface SubmitStationClaimParams {
  p_token?: string;
  p_station_id: string;
  p_input: Record<string, any>;
  p_client_request_id?: string;
  p_team_id?: string | null;
}

export interface VerifyStationClaimParams {
  p_token?: string;
  p_claim_id: string;
  p_action: 'approve' | 'reject';
  p_note?: string;
  p_client_request_id?: string;
}

export interface CancelStationClaimParams {
  p_token?: string;
  p_claim_id: string;
  p_reason?: string;
}

export interface GetStationQueueParams {
  p_token?: string;
  p_station_id?: string | null;
}

export interface GetTeamStationStatusParams {
  p_token?: string;
  p_station_id?: string | null;
}

export interface AdminListClaimsParams {
  p_token?: string;
  p_status?: string;
  p_limit?: number;
  p_offset?: number;
}

export interface PurchaseHintParams {
  p_token?: string;
  p_hint_id: string;
  p_client_request_id?: string;
}

export interface PurchaseItemParams {
  p_token?: string;
  p_item_id: string;
  p_client_request_id?: string;
}

export interface UseTeamItemParams {
  p_token?: string;
  p_item_id: string;
  p_target_team_id?: string | null;
  p_target_station_id?: string | null;
}

export interface ResolvePvPParams {
  p_token?: string;
  p_target_team_id: string;
  p_client_request_id?: string;
}

export interface ReverseTransactionParams {
  p_token?: string;
  p_tx_id: string;
  p_force?: boolean;
  p_reason?: string;
  p_client_request_id?: string;
}

export interface AdminAdjustBalanceParams {
  p_token?: string;
  p_team_id: string;
  p_amount: number;
  p_description: string;
  p_client_request_id?: string;
}

export interface GetHistoryParams {
  p_token?: string;
  p_limit?: number;
  p_offset?: number;
}

export interface GetTeamDashboardParams {
  p_token?: string;
}

export interface AdminGetAuditLogParams {
  p_token?: string;
  p_limit?: number;
  p_offset?: number;
}

export interface AdminGetLeaderboardParams {
  p_token?: string;
}

export interface AdminUpsertStationParams {
  p_token?: string;
  p_id?: string;
  p_name: string;
  p_description?: string;
  p_scoring_type: ScoringType;
  p_scoring_config: Record<string, any>;
  p_min_score: number;
  p_max_score: number;
  p_order_index?: number;
  p_allow_multiple_attempts?: boolean;
  p_is_active?: boolean;
}

export interface AdminDeleteStationParams {
  p_token?: string;
  p_id: string;
}

export interface AdminUpsertHintParams {
  p_token?: string;
  p_id?: string;
  p_station_id?: string | null;
  p_title: string;
  p_content: string;
  p_tier: HintTier;
  p_price: number;
  p_order_index?: number;
  p_is_active?: boolean;
}

export interface AdminDeleteHintParams {
  p_token?: string;
  p_id: string;
}

export interface AdminUpsertItemParams {
  p_token?: string;
  p_id?: string;
  p_name: string;
  p_description?: string;
  p_price: number;
  p_effect_type: ItemEffectType;
  p_effect_value?: number;
  p_duration_minutes?: number;
  p_is_active?: boolean;
}

export interface AdminDeleteItemParams {
  p_token?: string;
  p_id: string;
}

export interface AdminListStaffParams {
  p_token?: string;
}

export interface AdminUpsertStaffParams {
  p_token?: string;
  p_id?: string;
  p_name: string;
  p_role: StaffRole;
  p_pin?: string;
  p_assigned_team_id?: string | null;
  p_assigned_station_id?: string | null;
  p_is_active?: boolean;
}

export interface AdminUpdateGameSettingsParams {
  p_token?: string;
  p_settings: Record<string, any>;
}

export interface UpdateSettingParams {
  p_token?: string;
  p_key: string;
  p_value: Record<string, any>;
}

export interface AdminGetAdminAuditLogParams {
  p_token?: string;
  p_limit?: number;
  p_offset?: number;
}

// ---------------------------------------------------------------------------
// Master RPC Type Map
// ---------------------------------------------------------------------------

export interface RpcMap {
  staff_login: { args: StaffLoginParams; return: LoginResponse };
  auth_verify_session: { args: AuthVerifySessionParams; return: LoginResponse };
  staff_logout: { args: StaffLogoutParams; return: RPCResponse };
  admin_revoke_sessions: { args: AdminRevokeSessionsParams; return: RPCResponse<{ revoked_count: number }> };
  submit_station_claim: { args: SubmitStationClaimParams; return: RPCResponse<{ claim_id: string; status: ClaimStatus; computed_points: number; is_exclusive: boolean }> };
  verify_station_claim: { args: VerifyStationClaimParams; return: RPCResponse<{ claim_id: string; status: ClaimStatus; final_points?: number; tx_id?: string }> };
  cancel_station_claim: { args: CancelStationClaimParams; return: RPCResponse };
  get_station_queue: { args: GetStationQueueParams; return: RPCResponse<{ station_id: string; station?: any; teams?: Array<{ id: string; name: string }>; queue: StationClaim[]; recent_processed?: any[] }> };
  get_team_station_status: { args: GetTeamStationStatusParams; return: RPCResponse<{ claims: StationClaim[]; keys_count: number }> };
  admin_list_claims: { args: AdminListClaimsParams; return: RPCResponse<{ claims: StationClaim[]; total: number }> };
  purchase_hint: { args: PurchaseHintParams; return: RPCResponse<{ hint_id: string; hint_title: string; hint_content: string; price: number; new_balance: number; tx_id: string }> };
  purchase_item: { args: PurchaseItemParams; return: RPCResponse<{ item_id: string; item_name: string; price: number; new_balance: number; tx_id: string; new_quantity?: number; shield_until?: string }> };
  use_team_item: { args: UseTeamItemParams; return: RPCResponse<{ item_id: string; effect_type: string; remaining_quantity: number; shield_until?: string; spy_data?: any; key_granted?: boolean }> };
  resolve_pvp: { args: ResolvePvPParams; return: RPCResponse<{ result: 'success' | 'backlash'; amount_stolen: number; attacker_balance: number; defender_balance: number; tx_id?: string; cooldown_until: string }> };
  reverse_transaction: { args: ReverseTransactionParams; return: RPCResponse<{ reversed_tx_id: string; reversal_tx_id: string; team_id: string; new_balance: number; reversal_type: string }> };
  admin_adjust_balance: { args: AdminAdjustBalanceParams; return: RPCResponse<{ team_id: string; amount: number; new_balance: number; tx_id: string }> };
  get_history: { args: GetHistoryParams; return: RPCResponse<{ transactions: Transaction[]; total: number }> };
  get_team_dashboard: { args: GetTeamDashboardParams; return: RPCResponse<{ team: Team; hints: Hint[]; inventory: TeamItem[]; recent_transactions: Transaction[] }> };
  admin_get_audit_log: { args: AdminGetAuditLogParams; return: RPCResponse<{ logs: Transaction[]; total: number }> };
  admin_get_leaderboard: { args: AdminGetLeaderboardParams; return: RPCResponse<{ leaderboard: Array<{ id: string; name: string; light_balance: number; rank: number; stations_cleared: number; has_active_shield: boolean }> }> };
  admin_upsert_station: { args: AdminUpsertStationParams; return: RPCResponse<{ station: Station }> };
  admin_delete_station: { args: AdminDeleteStationParams; return: RPCResponse<{ action: string; station_id: string }> };
  admin_upsert_hint: { args: AdminUpsertHintParams; return: RPCResponse<{ hint: Hint }> };
  admin_delete_hint: { args: AdminDeleteHintParams; return: RPCResponse<{ action: string; hint_id: string }> };
  admin_upsert_item: { args: AdminUpsertItemParams; return: RPCResponse<{ item: Item }> };
  admin_delete_item: { args: AdminDeleteItemParams; return: RPCResponse<{ action: string; item_id: string }> };
  admin_list_staff: { args: AdminListStaffParams; return: RPCResponse<{ staff: Staff[] }> };
  admin_upsert_staff: { args: AdminUpsertStaffParams; return: RPCResponse<{ staff: Staff }> };
  admin_update_game_settings: { args: AdminUpdateGameSettingsParams; return: RPCResponse<{ updated_keys: string[] }> };
  update_setting: { args: UpdateSettingParams; return: RPCResponse<{ key: string; new_value: any }> };
  admin_get_admin_audit_log: { args: AdminGetAdminAuditLogParams; return: RPCResponse<{ audit_logs: AdminAuditLog[]; total: number }> };
}
