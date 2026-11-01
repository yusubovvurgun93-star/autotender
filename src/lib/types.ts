// Baza ilə razılaşdırılmış tiplər (supabase/migrations/20261029120000_secure_rewrite.sql)

export type RequestStatus = 'active' | 'completed' | 'expired' | 'cancelled';
export type BidStatus = 'pending' | 'accepted' | 'rejected' | 'expired';
export type Condition = 'original' | 'analog' | 'used';
export type RequestType = 'part' | 'service';
export type ProviderType = 'shop' | 'service_center' | 'master';
export type ProviderPref = 'any' | 'service_center' | 'master';
export type PriceType = 'fixed' | 'from';
export type Urgency = 'express' | 'standard' | 'wide';
export type PlanKey = 'free' | 'plus' | 'pro';

/** Mağazanın hamıya açıq sahələri (telefon, VÖEN, coin gizlidir) */
export type PublicStore = {
  id: string;
  name: string;
  grade: string;
  rating: number;
  review_count: number;
  verified: boolean;
  provider_type?: ProviderType;
  mobile_service?: boolean;
};

/** Satıcının öz mağazası (get_my_store) */
export type MyStore = PublicStore & {
  owner_id: string | null;
  voen: string | null;
  phone: string;
  address: string | null;
  supported_brands: string[];
  categories: string[];
  coin_balance: number;
  failed_deals: number;
  plan: PlanKey;
  plan_until: string | null;
  suspended: boolean;
  suspended_reason: string | null;
  offerings: string[];
  service_categories: string[];
  cities: string[];
  created_at: string;
};

export type CarBrand = { id: string; name: string };

export type BuyerBid = {
  id: string;
  request_id: string;
  store_id: string;
  price_azn: number;
  condition: Condition | string;
  warranty: string;
  note: string | null;
  status: BidStatus;
  deal_status: string | null;
  created_at: string;
  price_type?: PriceType;
  eta_hours?: number | null;
  images?: string[] | null;
  store: PublicStore | null;
};

export type BuyerRequest = {
  id: string;
  request_type: RequestType;
  city: string | null;
  area: string | null;
  on_site: boolean;
  provider_pref: ProviderPref;
  buyer_tag: string;
  brand: string;
  model: string | null;
  year: number | null;
  vin: string | null;
  part_name: string;
  part_images: string[] | null;
  category: string | null;
  urgency: Urgency | string;
  budget_azn: number | null;
  status: RequestStatus;
  deal_status: string | null;
  accepted_bid_id: string | null;
  expires_at: string;
  created_at: string;
  bids: BuyerBid[];
  // request_id UNIQUE olduğu üçün PostgREST obyekt qaytarır (massiv yox)
  store_reviews: { stars: number }[] | { stars: number } | null;
};

export type DealContact = {
  store_name: string;
  phone: string;
  price: number;
  deal_status?: string | null;
  reviewed?: boolean;
};

export type CreateRequestInput = {
  brand: string;
  model: string;
  year: number | null;
  vin: string | null;
  partName: string;
  category: string | null;
  urgency: Urgency;
  budget: number | null;
  images: string[];
};

export type CreateServiceRequestInput = {
  category: string;
  title: string;
  brand: string;
  model: string;
  year: number | null;
  city: string;
  area: string;
  onSite: boolean;
  providerPref: ProviderPref;
  urgency: Urgency;
  budget: number | null;
  images: string[];
};

export type ProviderProfileInput = {
  providerType: ProviderType;
  offerings: string[];
  serviceCategories: string[];
  cities: string[];
  mobile: boolean;
};

export type SubmitServiceBidInput = {
  requestId: string;
  price: number;
  priceType: PriceType;
  etaHours: number;
  warranty: string;
  note: string;
  images: string[];
};

export type SellerFeedItem = {
  id: string;
  request_type: RequestType;
  city: string | null;
  area: string | null;
  on_site: boolean;
  provider_pref: ProviderPref;
  buyer_tag: string;
  brand: string;
  model: string | null;
  year: number | null;
  vin: string | null;
  part_name: string;
  part_images: string[] | null;
  category: string | null;
  urgency: string;
  budget_azn: number | null;
  expires_at: string;
  created_at: string;
  bid_count: number;
  slots_full: boolean;
  my_bid_id: string | null;
};

export type ClosedFeedItem = {
  id: string;
  request_type: RequestType;
  city: string | null;
  brand: string;
  model: string | null;
  year: number | null;
  part_name: string;
  category: string | null;
  urgency: string;
  budget_azn: number | null;
  status: RequestStatus;
  created_at: string;
  expires_at: string;
  bid_count: number;
  i_bid: boolean;
  accepted_price: number | null;
};

export type MyBid = {
  bid_id: string;
  request_id: string;
  request_type: RequestType;
  price_type: PriceType;
  eta_hours: number | null;
  city: string | null;
  price_azn: number;
  condition: string;
  warranty: string;
  note: string | null;
  bid_status: BidStatus;
  deal_status: string | null;
  bid_created_at: string;
  brand: string;
  model: string | null;
  year: number | null;
  part_name: string;
  category: string | null;
  request_status: RequestStatus;
  request_expires_at: string;
  winning_price: number | null;
  winning_warranty: string | null;
  price_difference: number | null;
};

export type SubmitBidInput = {
  requestId: string;
  price: number;
  condition: Condition;
  warranty: string;
  note: string;
  images: string[];
};

export type StoreProfileInput = {
  name: string;
  voen: string;
  phone: string;
  address: string;
  brands: string[];
  categories: string[];
  provider?: ProviderProfileInput;
};

export type CoinLedgerItem = {
  id: string;
  amount: number;
  type: string;
  note: string | null;
  created_at: string;
};

export type AppNotification = {
  id: string;
  user_id: string;
  kind: string | null;
  title: string;
  body: string | null;
  request_id: string | null;
  is_read: boolean;
  created_at: string;
};

export type MyRole = {
  user_id: string | null;
  is_anonymous: boolean;
  is_admin: boolean;
  store_id: string | null;
};

export type AdminStats = {
  total_stores: number;
  verified_stores: number;
  total_requests: number;
  active_requests: number;
  completed_requests: number;
  expired_requests: number;
  requests_7d: number;
  total_bids: number;
  coins_spent: number;
  coins_refunded: number;
  bonus_coins_given: number;
  failed_deals: number;
};

export type AdminStore = MyStore;

export type AdminRequestRow = {
  id: string;
  brand: string;
  model: string | null;
  part_name: string;
  status: RequestStatus;
  created_at: string;
};

export type AdminBidRow = {
  id: string;
  price_azn: number;
  condition: string;
  status: BidStatus;
  created_at: string;
  store: { name: string } | null;
};

/* ------------------------------------------------------------------ */
/* Hesab, plan, ödəniş                                                  */
/* ------------------------------------------------------------------ */

export type CatalogItem = {
  key: string;
  kind: 'coins' | 'plan';
  title: string;
  price_azn: number;
  coins: number | null;
  plan: 'plus' | 'pro' | null;
  days: number | null;
};

export type PaymentOrder = {
  id: string;
  item_key: string;
  kind: 'coins' | 'plan';
  title: string;
  amount_azn: number;
  reference: string;
  status: 'pending' | 'paid' | 'cancelled';
  created_at: string;
  paid_at: string | null;
};

export type BillingOverview = {
  plan: PlanKey;
  plan_until: string | null;
  coin_balance: number;
  bid_fee: number;
  base_bid_fee: number;
  catalog: CatalogItem[];
  orders: PaymentOrder[];
};

export type CreatedOrder = { id: string; reference: string; amount_azn: number; title: string };

export type AppTexts = {
  payment_instructions?: string;
  support_whatsapp?: string;
  telegram_bot_username?: string;
};

export type MarketCategory = {
  category: string;
  requests: number;
  avg_bids: number | null;
  avg_win_price: number | null;
  no_bid_requests: number;
  my_bids: number;
  my_wins: number;
};

export type MarketBrand = { brand: string; requests: number; avg_win_price: number | null; my_bids: number };

export type ProInsights = {
  top_parts: { part: string; requests: number; avg_win_price: number | null; min_win_price: number | null; max_win_price: number | null }[];
  hourly: number[];
  price_position: { wins: number; losses: number; avg_gap_azn: number | null; avg_gap_pct: number | null };
  by_category_position: { category: string; wins: number; losses: number; avg_gap_pct: number | null }[];
  unanswered_7d: { brand: string; requests: number }[];
  response_speed: { my_median_min: number | null; winner_median_min: number | null };
};

export type Insights = {
  plan: PlanKey;
  level: 0 | 1 | 2;
  teaser: { requests_30d: number; completed_30d: number };
  market?: { by_category: MarketCategory[]; by_brand: MarketBrand[] };
  pro?: ProInsights;
};

export type AdminOrder = {
  id: string;
  reference: string;
  title: string;
  kind: 'coins' | 'plan';
  amount_azn: number;
  status: 'pending' | 'paid' | 'cancelled';
  created_at: string;
  paid_at: string | null;
  store_id: string;
  store_name: string;
  store_phone: string;
};

export type AdminBillingStats = {
  pending_orders: number;
  revenue_total: number;
  revenue_30d: number;
  active_plus: number;
  active_pro: number;
  catalog: { key: string; title: string; price_azn: number }[];
  texts: AppTexts;
};

/* ------------------------------------------------------------------ */
/* Şikayətlər                                                           */
/* ------------------------------------------------------------------ */

export type ReportReason = 'wrong_price' | 'bad_part' | 'no_response' | 'rude' | 'bypass' | 'spam' | 'fake' | 'other';

export type ReportInput = {
  kind: 'store' | 'request';
  storeId?: string | null;
  requestId?: string | null;
  reason: ReportReason;
  details?: string;
};

export type AdminReport = {
  id: string;
  kind: 'store' | 'request';
  reason: ReportReason;
  details: string | null;
  status: 'open' | 'resolved' | 'dismissed';
  admin_note: string | null;
  reporter_role: 'buyer' | 'seller';
  created_at: string;
  store_id: string | null;
  store_name: string | null;
  store_phone: string | null;
  store_suspended: boolean | null;
  store_total_reports: number | null;
  request_id: string | null;
  request_title: string | null;
  request_status: string | null;
};
