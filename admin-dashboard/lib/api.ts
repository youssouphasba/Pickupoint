import axios from "axios";

const baseURL =
  process.env.NEXT_PUBLIC_API_URL ||
  "https://api.denkma.com";

const TOKEN_KEY = "denkma_admin_token";

export function getToken(): string | null {
  if (typeof window === "undefined") return null;
  return localStorage.getItem(TOKEN_KEY);
}

export function setToken(token: string) {
  localStorage.setItem(TOKEN_KEY, token);
}

export function clearToken() {
  localStorage.removeItem(TOKEN_KEY);
}

export const api = axios.create({
  baseURL,
  timeout: 20_000,
});

// Attach token to every request
api.interceptors.request.use((config) => {
  const token = getToken();
  if (token) {
    config.headers.Authorization = `Bearer ${token}`;
  }
  return config;
});

api.interceptors.response.use(
  (res) => res,
  (err) => {
    if (typeof window !== "undefined" && err?.response?.status === 401) {
      clearToken();
      if (window.location.pathname !== "/login") {
        window.location.href = "/login";
      }
    }
    return Promise.reject(err);
  }
);

export type AdminMe = {
  id: string;
  email: string | null;
  full_name: string | null;
  role: string;
  avatar_url?: string | null;
};

export async function fetchMe(): Promise<AdminMe> {
  const { data } = await api.get("/api/admin/auth/me");
  return data as AdminMe;
}

export async function login(email: string, password: string) {
  const { data } = await api.post("/api/admin/auth/login", { email, password });
  // Store token from response
  if (data.token) {
    setToken(data.token);
  }
  return data;
}

export async function logout() {
  await api.post("/api/admin/auth/logout").catch(() => {});
  clearToken();
}

// ───────────────────────── Users ─────────────────────────

export type AdminUser = {
  user_id: string;
  phone: string;
  name?: string | null;
  email?: string | null;
  full_name?: string | null;
  role: string;
  is_active: boolean;
  is_banned?: boolean;
  is_phone_verified?: boolean;
  kyc_status?: string | null;
  relay_point_id?: string | null;
  profile_picture_url?: string | null;
  profile_picture_status?: string | null;
  profile_picture_rejected_reason?: string | null;
  created_at?: string;
  deliveries_completed?: number;
  average_rating?: number;
  total_earned?: number;
  loyalty_points?: number;
  referral_code?: string | null;
};

export async function fetchUsers(params: {
  role?: string;
  skip?: number;
  limit?: number;
}) {
  const { data } = await api.get<{ users: AdminUser[]; total: number }>(
    "/api/admin/users",
    { params }
  );
  return data;
}

export async function changeUserRole(userId: string, role: string) {
  const { data } = await api.put(`/api/users/${userId}/role`, null, {
    params: { role },
  });
  return data;
}

export async function banUser(userId: string, reason: string) {
  const { data } = await api.post(`/api/admin/users/${userId}/ban`, { reason });
  return data;
}

export async function unbanUser(userId: string, reason: string) {
  const { data } = await api.post(`/api/admin/users/${userId}/unban`, {
    reason,
  });
  return data;
}

export async function moderateProfilePhoto(
  userId: string,
  status: "approved" | "rejected" | "pending",
  reason?: string
) {
  const { data } = await api.patch(`/api/admin/users/${userId}/profile-photo`, {
    status,
    reason,
  });
  return data;
}

// ───────────────────────── Parcels ─────────────────────────

export type AdminParcel = {
  parcel_id: string;
  tracking_code: string;
  status: string;
  delivery_mode: string;
  sender_user_id?: string;
  sender_name?: string | null;
  recipient_phone?: string;
  recipient_name?: string | null;
  origin_relay_id?: string | null;
  destination_relay_id?: string | null;
  quoted_price?: number;
  paid_price?: number | null;
  payment_status?: string;
  created_at?: string;
  updated_at?: string;
};

export async function fetchParcels(params: {
  status?: string;
  scope?: string;
  created_today?: boolean;
  payment_blocked?: boolean;
  from_date?: string;
  to_date?: string;
  skip?: number;
  limit?: number;
}) {
  const { data } = await api.get<{ parcels: AdminParcel[]; total: number }>(
    "/api/admin/parcels",
    { params }
  );
  return data;
}

// ───────────────────────── Payouts ─────────────────────────

export type AdminPayout = {
  payout_id: string;
  user_id: string;
  amount: number;
  method: string;
  destination?: string | null;
  status: string;
  created_at?: string;
};

export async function fetchPendingPayouts(params?: {
  from_date?: string;
  to_date?: string;
}) {
  const { data } = await api.get<{ payouts: AdminPayout[] }>(
    "/api/admin/wallets/payouts",
    { params }
  );
  return data;
}

export async function approvePayout(payoutId: string, note?: string) {
  const { data } = await api.put(
    `/api/admin/wallets/payouts/${payoutId}/approve`,
    note ? { note } : {}
  );
  return data;
}

export async function rejectPayout(payoutId: string, reason: string) {
  const { data } = await api.put(
    `/api/admin/wallets/payouts/${payoutId}/reject`,
    { reason }
  );
  return data;
}

// ------------------------- WhatsApp support -------------------------

export type WhatsAppSupportParcel = {
  parcel_id: string;
  tracking_code: string;
  status: string;
  recipient_name?: string | null;
  recipient_phone?: string | null;
  sender_user_id?: string | null;
  assigned_driver_id?: string | null;
  payment_status?: string | null;
  updated_at?: string | null;
};

export type WhatsAppSupportUser = {
  user_id: string;
  name?: string | null;
  phone?: string | null;
  email?: string | null;
  role?: string | null;
  profile_picture_url?: string | null;
  is_active?: boolean;
  is_banned?: boolean;
  kyc_status?: string | null;
};

export type WhatsAppSupportConversation = {
  conversation_id: string;
  phone: string;
  source: "whatsapp";
  status: "open" | "pending" | "resolved";
  matched_user_id?: string | null;
  matched_user?: WhatsAppSupportUser | null;
  matched_parcel_id?: string | null;
  matched_parcel?: WhatsAppSupportParcel | null;
  related_parcels?: WhatsAppSupportParcel[];
  last_message_text?: string | null;
  last_message_at?: string | null;
  last_inbound_at?: string | null;
  created_at?: string | null;
  updated_at?: string | null;
};

export type WhatsAppSupportMessage = {
  message_id: string;
  conversation_id: string;
  whatsapp_message_id?: string | null;
  direction: "inbound" | "outbound";
  phone: string;
  message_type: string;
  text?: string | null;
  media?: {
    media_id?: string | null;
    mime_type?: string | null;
    file_size?: number | null;
    download_url?: string | null;
  } | null;
  matched_user_id?: string | null;
  matched_parcel_id?: string | null;
  matched_tracking_code?: string | null;
  created_at?: string | null;
};

export async function fetchWhatsappSupportConversations(params?: {
  status?: string;
  q?: string;
  limit?: number;
}) {
  const { data } = await api.get<{ conversations: WhatsAppSupportConversation[] }>(
    "/api/admin/support/whatsapp/conversations",
    { params }
  );
  return data;
}

export async function fetchWhatsappSupportConversation(conversationId: string) {
  const { data } = await api.get<{
    conversation: WhatsAppSupportConversation;
    messages: WhatsAppSupportMessage[];
  }>(`/api/admin/support/whatsapp/conversations/${conversationId}`);
  return data;
}

export async function updateWhatsappSupportConversationStatus(
  conversationId: string,
  status: "open" | "pending" | "resolved"
) {
  const { data } = await api.patch(
    `/api/admin/support/whatsapp/conversations/${conversationId}/status`,
    { status }
  );
  return data;
}

export async function sendWhatsappSupportTextReply(
  conversationId: string,
  text: string
) {
  const { data } = await api.post(
    `/api/admin/support/whatsapp/conversations/${conversationId}/reply`,
    { text }
  );
  return data;
}

export async function sendWhatsappSupportVoiceReply(
  conversationId: string,
  blob: Blob
) {
  const formData = new FormData();
  const extension = blob.type.includes("ogg") ? "ogg" : "webm";
  formData.append("file", blob, `note-vocale.${extension}`);
  const { data } = await api.post(
    `/api/admin/support/whatsapp/conversations/${conversationId}/voice`,
    formData,
    { headers: { "Content-Type": "multipart/form-data" } }
  );
  return data;
}

// ───────────────────────── Relay Points ─────────────────────────

export type AdminRelay = {
  relay_id: string;
  name: string;
  city?: string;
  address?: string | { label?: string; city?: string; geopin?: { lat: number; lng: number } };
  latitude?: number;
  longitude?: number;
  is_active: boolean;
  is_verified?: boolean;
  max_capacity?: number;
  current_load?: number;
  agent_user_id?: string | null;
  created_at?: string;
};

export async function fetchRelays(params?: { active?: boolean }) {
  const { data } = await api.get<{ relay_points: AdminRelay[]; total: number }>(
    "/api/admin/relay-points",
    { params: { limit: 500, ...params } }
  );
  return data;
}

export async function verifyRelay(relayId: string) {
  const { data } = await api.put(`/api/admin/relay-points/${relayId}/verify`);
  return data;
}

// ───────────────────────── Drivers ─────────────────────────

export async function fetchDrivers(params?: { active?: boolean }) {
  const { data } = await api.get<{ drivers: (AdminUser & { missions_count?: number })[] }>(
    "/api/admin/drivers",
    { params }
  );
  return data;
}

// ───────────────────────── Analytics ─────────────────────────

export async function fetchStaleParcels() {
  const { data } = await api.get("/api/admin/analytics/stale-parcels");
  return data;
}

export async function fetchAnomalies() {
  const { data } = await api.get("/api/admin/analytics/anomaly-alerts");
  return data;
}

export async function fetchHeatmap() {
  const { data } = await api.get("/api/admin/analytics/heatmap");
  return data;
}

export async function fetchFleetLive() {
  const { data } = await api.get("/api/admin/fleet/live-rich");
  return data;
}

// ───────────────────────── Finance ─────────────────────────

export async function fetchFinanceReconciliation() {
  const { data } = await api.get("/api/admin/finance/reconciliation");
  return data;
}

export async function fetchFinanceMonthlySummary(period: string) {
  const { data } = await api.get("/api/admin/finance/monthly-summary", {
    params: { period },
  });
  return data;
}

export async function fetchCodMonitoring() {
  const { data } = await api.get("/api/admin/finance/cod-monitoring");
  return data;
}

// ───────────────────────── Audit log ─────────────────────────

export async function fetchAuditLog(params: {
  skip?: number;
  limit?: number;
  offset?: number;
  from_date?: string;
  to_date?: string;
}) {
  const { data } = await api.get("/api/admin/audit-log", { params });
  return data;
}

// ───────────────────────── Settings ─────────────────────────

export async function fetchSettings() {
  const { data } = await api.get("/api/admin/settings");
  return data;
}

export async function toggleExpress(enabled: boolean) {
  const { data } = await api.put("/api/admin/settings/express", {
    enabled,
  });
  return data;
}

export async function updateLogisticsSettings(body: {
  redirect_relay_max_distance_km: number;
}) {
  const { data } = await api.put("/api/admin/settings/logistics", body);
  return data;
}

export type OperationalSettingsPayload = {
  express_enabled: boolean;
  base_relay_to_relay: number;
  base_relay_to_home: number;
  base_home_to_relay: number;
  base_home_to_home: number;
  price_per_km: number;
  price_per_kg: number;
  free_weight_kg: number;
  min_price: number;
  express_multiplier: number;
  night_multiplier: number;
  default_distance_km: number;
  redirect_relay_max_distance_km: number;
};

export async function updateOperationalSettings(
  body: OperationalSettingsPayload
) {
  const { data } = await api.put("/api/admin/settings/operational", body);
  return data;
}

export async function fetchReferralStats() {
  const { data } = await api.get("/api/admin/settings/referral/stats");
  return data;
}

export async function updateReferralSettings(body: {
  client: ReferralRoleConfig;
  driver: ReferralRoleConfig;
  share_base_url?: string | null;
}) {
  const { data } = await api.put("/api/admin/settings/referral", body);
  return data;
}

export type ReferralRoleConfig = {
  enabled: boolean;
  sponsor_bonus_xof: number;
  referred_bonus_xof: number;
  apply_metric: string;
  apply_max_count: number;
  reward_metric: string;
  reward_count: number;
  max_referrals_per_sponsor: number;
};

// ───────────────────────── Parcel actions ─────────────────────────

export async function confirmPayment(parcelId: string) {
  const { data } = await api.post(
    `/api/admin/parcels/${parcelId}/confirm-payment`
  );
  return data;
}

export async function paymentOverride(parcelId: string, reason: string) {
  const { data } = await api.post(
    `/api/admin/parcels/${parcelId}/payment-override`,
    { reason }
  );
  return data;
}

export async function suspendParcel(parcelId: string) {
  const { data } = await api.post(
    `/api/admin/parcels/${parcelId}/suspend`
  );
  return data;
}

export async function unsuspendParcel(parcelId: string, toStatus: string) {
  const { data } = await api.post(
    `/api/admin/parcels/${parcelId}/unsuspend`,
    null,
    { params: { to_status: toStatus } }
  );
  return data;
}

export async function overrideParcelStatus(
  parcelId: string,
  newStatus: string,
  notes: string
) {
  const { data } = await api.post(
    `/api/admin/parcels/${parcelId}/override`,
    null,
    { params: { new_status: newStatus, notes } }
  );
  return data;
}

export async function fetchParcelAudit(parcelId: string) {
  const { data } = await api.get(
    `/api/admin/parcels/${parcelId}/audit-rich`
  );
  return data;
}

// ───────────────────────── Mission actions ─────────────────────────

export async function reassignMission(
  missionId: string,
  newDriverId: string,
  reason?: string
) {
  const { data } = await api.post(
    `/api/admin/missions/${missionId}/reassign`,
    { new_driver_id: newDriverId, reason }
  );
  return data;
}

// ───────────────────────── Incident resolution ─────────────────────────

export async function resolveIncident(
  parcelId: string,
  action: "reassign" | "return" | "cancel",
  notes?: string
) {
  const { data } = await api.post(
    `/api/admin/incidents/${parcelId}/resolve`,
    { action, notes }
  );
  return data;
}

// ───────────────────────── COD settlement ─────────────────────────

export async function settleCod(driverId: string, amount?: number) {
  const { data } = await api.post("/api/admin/finance/settle", null, {
    params: { driver_id: driverId, ...(amount != null ? { amount } : {}) },
  });
  return data;
}

// ───────────────────────── User detail ─────────────────────────

export async function fetchUserDetail(userId: string) {
  const { data } = await api.get(`/api/admin/users/${userId}/detail`);
  return data;
}

export async function fetchUserHistory(userId: string) {
  const { data } = await api.get(`/api/admin/users/${userId}/history`);
  return data;
}

export async function assignRelayPoint(userId: string, relayId: string) {
  const { data } = await api.put(`/api/users/${userId}/relay-point`, null, {
    params: { relay_id: relayId },
  });
  return data;
}

export async function setReferralAccess(
  userId: string,
  enabledOverride: boolean | null
) {
  const { data } = await api.put(
    `/api/admin/users/${userId}/referral-access`,
    { enabled_override: enabledOverride }
  );
  return data;
}

// ───────────────────────── Relay detail ─────────────────────────

export async function fetchRelayDetail(relayId: string) {
  const { data } = await api.get(
    `/api/admin/relay-points/${relayId}/detail`
  );
  return data;
}

// ───────────────────────── Legal ─────────────────────────

export async function fetchLegalDoc(docType: string) {
  const { data } = await api.get(`/api/legal/${docType}`);
  return data;
}

export async function updateLegalDoc(
  docType: string,
  body: { title?: string; content: string }
) {
  const { data } = await api.put(`/api/legal/${docType}`, body);
  return data;
}

// ───────────────────────── Rewards ─────────────────────────

export async function triggerMonthlyRewards(period: string) {
  const { data } = await api.post("/api/admin/recompenses/trigger-monthly", null, {
    params: { period },
  });
  return data;
}

export async function fetchDriverStats(period: string) {
  const { data } = await api.get("/api/admin/recompenses/driver-stats", {
    params: { period },
  });
  return data;
}

// ───────────────────────── Dashboard ─────────────────────────

export async function fetchDashboard() {
  const { data } = await api.get("/api/admin/dashboard");
  return data;
}

// ───────────────────── Action Center ─────────────────────

export type ActionUrgency = "normal" | "warning" | "critical";

export type ActionItem = {
  id: string;
  age_hours: number;
  urgency: ActionUrgency;
  href?: string;
  // Champs spécifiques selon la catégorie — typés côté consommateur.
  [key: string]: unknown;
};

export type ActionCategory = {
  label: string;
  href: string;
  count: number;
  urgent_count: number;
  warning_count: number;
  items: ActionItem[];
};

export type ActionCenter = {
  generated_at: string;
  total: number;
  total_urgent: number;
  total_warning: number;
  categories: {
    payouts: ActionCategory;
    applications: ActionCategory;
    incidents: ActionCategory;
    anomalies: ActionCategory;
    stale_parcels: ActionCategory;
    payment_blocked: ActionCategory;
    support: ActionCategory;
    disputes: ActionCategory;
  };
  sla: Record<string, { warning: number; critical: number }>;
};

export async function fetchActionCenter(): Promise<ActionCenter> {
  const { data } = await api.get("/api/admin/action-center");
  return data as ActionCenter;
}

// ───────────────────── Admin events (cloche) ─────────────────────

export type AdminEvent = {
  event_id: string;
  event_type: string;
  severity: "critical" | "warning" | "info";
  title: string;
  message: string;
  href: string | null;
  metadata: Record<string, unknown>;
  created_at: string;
  is_read: boolean;
};

export type AdminEventsFeed = {
  events: AdminEvent[];
  unread_count: number;
};

export async function fetchAdminEvents(params: {
  limit?: number;
  before?: string;
  from_date?: string;
  to_date?: string;
  unread_only?: boolean;
} = {}): Promise<AdminEventsFeed> {
  const { data } = await api.get("/api/admin/events", { params });
  return data as AdminEventsFeed;
}

export async function fetchAdminEventsUnreadCount(): Promise<number> {
  const { data } = await api.get<{ unread_count: number }>(
    "/api/admin/events/unread-count"
  );
  return data.unread_count;
}

export async function markAdminEventRead(eventId: string) {
  const { data } = await api.post(`/api/admin/events/${eventId}/read`);
  return data;
}

export async function markAllAdminEventsRead() {
  const { data } = await api.post(`/api/admin/events/read-all`);
  return data;
}
