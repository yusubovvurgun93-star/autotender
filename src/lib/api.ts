import { buyerDb, sellerDb, type Db } from '@/lib/supabase';
import type {
  AdminBidRow,
  AdminBillingStats,
  AdminReport,
  ReportInput,
  AdminOrder,
  AdminRequestRow,
  AdminStats,
  AdminStore,
  AppNotification,
  AppTexts,
  BillingOverview,
  BuyerRequest,
  CarBrand,
  ClosedFeedItem,
  CoinLedgerItem,
  CreatedOrder,
  Insights,
  CreateRequestInput,
  CreateServiceRequestInput,
  ProviderProfileInput,
  SubmitServiceBidInput,
  DealContact,
  MyBid,
  MyRole,
  MyStore,
  SellerFeedItem,
  StoreProfileInput,
  SubmitBidInput,
} from '@/lib/types';

/* ------------------------------------------------------------------ */
/* Ümumi köməkçilər                                                    */
/* ------------------------------------------------------------------ */

export function friendlyError(message: string | undefined | null): string {
  const m = message || '';
  if (/permission denied|row-level security|not authorized/i.test(m)) {
    return 'Bu əməliyyat üçün icazəniz yoxdur.';
  }
  if (/failed to fetch|networkerror|load failed/i.test(m)) {
    return 'İnternet bağlantısını yoxlayın və yenidən cəhd edin.';
  }
  if (/jwt expired|invalid jwt/i.test(m)) {
    return 'Sessiya bitib. Səhifəni yeniləyin.';
  }
  return m || 'Naməlum xəta baş verdi.';
}

async function rpc<T>(db: Db, fn: string, args?: Record<string, unknown>): Promise<T> {
  const { data, error } = await db.rpc(fn, args);
  if (error) throw new Error(friendlyError(error.message));
  return data as T;
}

function must<T>(res: { data: T | null; error: { message: string } | null }): T {
  if (res.error) throw new Error(friendlyError(res.error.message));
  return (res.data ?? ([] as unknown)) as T;
}

/* ------------------------------------------------------------------ */
/* Ümumi                                                               */
/* ------------------------------------------------------------------ */

export async function fetchBrands(): Promise<CarBrand[]> {
  const res = await buyerDb.from('car_brands').select('id,name').order('name');
  return must<CarBrand[]>(res as never);
}

/** Vaxtı bitmiş sorğuları bağlayır və mağazalara coin qaytarır (təkrar çağırmaq təhlükəsizdir) */
export async function expireRequests(db: Db): Promise<void> {
  await db.rpc('expire_requests');
}

/* ------------------------------------------------------------------ */
/* Bildirişlər                                                         */
/* ------------------------------------------------------------------ */

export async function fetchNotifications(db: Db): Promise<AppNotification[]> {
  const res = await db
    .from('in_app_notifications')
    .select('id,user_id,kind,title,body,request_id,is_read,created_at')
    .order('created_at', { ascending: false })
    .limit(30);
  return must<AppNotification[]>(res as never);
}

export async function markNotificationsRead(db: Db, userId: string): Promise<void> {
  await db.from('in_app_notifications').update({ is_read: true }).eq('user_id', userId).eq('is_read', false);
}

/* ------------------------------------------------------------------ */
/* Alıcı                                                               */
/* ------------------------------------------------------------------ */

const REQUEST_SELECT =
  'id,request_type,city,area,on_site,provider_pref,' +
  'buyer_tag,brand,model,year,vin,part_name,part_images,category,urgency,budget_azn,status,deal_status,sealed,' +
  'accepted_bid_id,expires_at,created_at,' +
  'bids(id,request_id,store_id,price_azn,price_type,eta_hours,images,condition,warranty,note,status,deal_status,created_at,' +
  'store:stores(id,name,grade,rating,review_count,verified,provider_type,mobile_service)),' +
  'store_reviews(stars)';

export async function fetchMyRequests(): Promise<BuyerRequest[]> {
  const res = await buyerDb
    .from('requests')
    .select(REQUEST_SELECT)
    .order('created_at', { ascending: false })
    .limit(100);
  const rows = must<BuyerRequest[]>(res as never);
  return rows.map((r) => ({ ...r, bids: Array.isArray(r.bids) ? r.bids : [] }));
}

export async function createRequest(input: CreateRequestInput): Promise<string> {
  return rpc<string>(buyerDb, 'create_request', {
    p_brand: input.brand,
    p_model: input.model,
    p_year: input.year,
    p_vin: input.vin,
    p_part_name: input.partName,
    p_category: input.category,
    p_urgency: input.urgency,
    p_budget: input.budget,
    p_images: input.images,
  });
}

export async function createServiceRequest(input: CreateServiceRequestInput): Promise<string> {
  return rpc<string>(buyerDb, 'create_service_request', {
    p_category: input.category,
    p_title: input.title,
    p_brand: input.brand,
    p_model: input.model,
    p_year: input.year,
    p_city: input.city,
    p_area: input.area || null,
    p_on_site: input.onSite,
    p_provider_pref: input.providerPref,
    p_urgency: input.urgency,
    p_budget: input.budget,
    p_images: input.images,
  });
}

export const cancelRequest = (requestId: string) =>
  rpc<void>(buyerDb, 'cancel_request', { p_request_id: requestId });

export const acceptBid = (bidId: string) => rpc<DealContact>(buyerDb, 'accept_bid', { p_bid_id: bidId });

export const getDealContact = (requestId: string) =>
  rpc<DealContact>(buyerDb, 'get_deal_contact', { p_request_id: requestId });

export const reportDealFailed = (requestId: string) =>
  rpc<void>(buyerDb, 'report_deal_failed', { p_request_id: requestId });

export const confirmDeal = (requestId: string, stars: number | null, comment: string | null) =>
  rpc<void>(buyerDb, 'confirm_deal', { p_request_id: requestId, p_stars: stars, p_comment: comment });

/** Şəkli kiçildir (maks. 1280px, JPEG) ki, mobil internetdə tez yüklənsin */
async function compressImage(file: File, maxDim = 1280, quality = 0.8): Promise<Blob> {
  try {
    const bitmap = await createImageBitmap(file);
    const scale = Math.min(1, maxDim / Math.max(bitmap.width, bitmap.height));
    const w = Math.round(bitmap.width * scale);
    const h = Math.round(bitmap.height * scale);
    const canvas = document.createElement('canvas');
    canvas.width = w;
    canvas.height = h;
    const ctx = canvas.getContext('2d');
    if (!ctx) return file;
    ctx.drawImage(bitmap, 0, 0, w, h);
    const blob = await new Promise<Blob | null>((resolve) => canvas.toBlob(resolve, 'image/jpeg', quality));
    return blob ?? file;
  } catch {
    return file;
  }
}

export async function uploadPartImage(file: File, userId: string, db: Db = buyerDb): Promise<string> {
  if (!/^image\//.test(file.type)) throw new Error('Yalnız şəkil faylı yükləmək olar.');
  const blob = await compressImage(file);
  if (blob.size > 3 * 1024 * 1024) throw new Error('Şəkil çox böyükdür (maks. 3 MB).');
  const path = `${userId}/${crypto.randomUUID()}.jpg`;
  const { error } = await db.storage
    .from('part-images')
    .upload(path, blob, { contentType: 'image/jpeg', upsert: false });
  if (error) throw new Error(friendlyError(error.message));
  return db.storage.from('part-images').getPublicUrl(path).data.publicUrl;
}

/* ------------------------------------------------------------------ */
/* Satıcı                                                              */
/* ------------------------------------------------------------------ */

export const getMyRole = () => rpc<MyRole>(sellerDb, 'get_my_role');

export async function getMyStore(): Promise<MyStore | null> {
  const rows = await rpc<MyStore[] | null>(sellerDb, 'get_my_store');
  return rows && rows.length > 0 ? rows[0] : null;
}

export const updateProviderProfile = (p: ProviderProfileInput) =>
  rpc<void>(sellerDb, 'update_provider_profile', {
    p_provider_type: p.providerType,
    p_offerings: p.offerings,
    p_service_categories: p.serviceCategories,
    p_cities: p.cities,
    p_mobile: p.mobile,
  });

export async function registerStore(p: StoreProfileInput): Promise<string> {
  const id = await rpc<string>(sellerDb, 'register_store', {
    p_name: p.name,
    p_voen: p.voen || null,
    p_phone: p.phone,
    p_address: p.address || null,
    p_brands: p.brands,
    p_categories: p.categories,
  });
  // Usta/servis sahələri ayrı çağırışla yazılır; mağaza artıq açılıb, ona görə uğursuzluq qeydiyyatı ləğv etmir
  if (p.provider) {
    try {
      await updateProviderProfile(p.provider);
    } catch {
      /* istifadəçi profildən təkrar seçə bilər */
    }
  }
  return id;
}

export const updateMyStore = (p: { name: string; address: string; brands: string[]; categories: string[] }) =>
  rpc<void>(sellerDb, 'update_my_store', {
    p_name: p.name,
    p_address: p.address,
    p_brands: p.brands,
    p_categories: p.categories,
  });

export const sellerFeed = () => rpc<SellerFeedItem[]>(sellerDb, 'seller_feed');
export const sellerClosedFeed = () => rpc<ClosedFeedItem[]>(sellerDb, 'seller_closed_feed');
export const sellerMyBids = () => rpc<MyBid[]>(sellerDb, 'seller_my_bids');

export const submitBid = (b: SubmitBidInput) =>
  rpc<string>(sellerDb, 'submit_bid', {
    p_request_id: b.requestId,
    p_price: b.price,
    p_condition: b.condition,
    p_warranty: b.warranty,
    p_note: b.note || null,
    p_images: b.images,
  });

export const submitServiceBid = (b: SubmitServiceBidInput) =>
  rpc<string>(sellerDb, 'submit_service_bid', {
    p_request_id: b.requestId,
    p_price: b.price,
    p_price_type: b.priceType,
    p_eta_hours: b.etaHours,
    p_warranty: b.warranty,
    p_note: b.note || null,
    p_images: b.images,
  });

export async function fetchCoinLedger(): Promise<CoinLedgerItem[]> {
  const res = await sellerDb
    .from('coin_ledger')
    .select('id,amount,type,note,created_at')
    .order('created_at', { ascending: false })
    .limit(30);
  return must<CoinLedgerItem[]>(res as never);
}

/* ------------------------------------------------------------------ */
/* Admin                                                               */
/* ------------------------------------------------------------------ */

export const adminDashboard = () => rpc<AdminStats>(sellerDb, 'admin_dashboard');
export const adminListStores = () => rpc<AdminStore[]>(sellerDb, 'admin_list_stores');

export const adminListOrders = (status: string | null = null) =>
  rpc<AdminOrder[]>(sellerDb, 'admin_list_orders', { p_status: status });
export const adminConfirmOrder = (id: string) => rpc<void>(sellerDb, 'admin_confirm_order', { p_order: id });
export const adminCancelOrder = (id: string) => rpc<void>(sellerDb, 'admin_cancel_order', { p_order: id });
export const adminSetPlan = (storeId: string, plan: string, days = 30) =>
  rpc<void>(sellerDb, 'admin_set_plan', { p_store: storeId, p_plan: plan, p_days: days });
export const adminSetText = (key: string, value: string) =>
  rpc<void>(sellerDb, 'admin_set_text', { p_key: key, p_value: value });
export const adminSetCatalogPrice = (key: string, price: number) =>
  rpc<void>(sellerDb, 'admin_set_catalog_price', { p_key: key, p_price: price });
export const adminBillingStats = () => rpc<AdminBillingStats>(sellerDb, 'admin_billing_stats');

export const adminAdjustCoins = (storeId: string, delta: number, note?: string) =>
  rpc<number>(sellerDb, 'admin_adjust_coins', { p_store: storeId, p_delta: delta, p_note: note ?? null });

export const adminSetVerified = (storeId: string, verified: boolean) =>
  rpc<void>(sellerDb, 'admin_set_verified', { p_store: storeId, p_verified: verified });

export async function adminRecentRequests(): Promise<AdminRequestRow[]> {
  const res = await sellerDb
    .from('requests')
    .select('id,brand,model,part_name,status,created_at')
    .order('created_at', { ascending: false })
    .limit(20);
  return must<AdminRequestRow[]>(res as never);
}

export async function adminRecentBids(): Promise<AdminBidRow[]> {
  const res = await sellerDb
    .from('bids')
    .select('id,price_azn,condition,status,created_at,store:stores(name)')
    .order('created_at', { ascending: false })
    .limit(20);
  return must<AdminBidRow[]>(res as never);
}

/* ------------------------------------------------------------------ */
/* Hesab, plan, analiz, Telegram                                        */
/* ------------------------------------------------------------------ */

export const getAppTexts = () => rpc<AppTexts>(sellerDb, 'get_app_texts');
export const billingOverview = () => rpc<BillingOverview>(sellerDb, 'billing_overview');
export const createPaymentOrder = (itemKey: string) =>
  rpc<CreatedOrder>(sellerDb, 'create_payment_order', { p_item: itemKey });
export const cancelPaymentOrder = (id: string) => rpc<void>(sellerDb, 'cancel_payment_order', { p_order: id });
export const sellerInsights = () => rpc<Insights>(sellerDb, 'seller_insights');

export const telegramStatus = () => rpc<{ linked: boolean }>(sellerDb, 'telegram_status');
export const telegramCreateCode = () => rpc<string>(sellerDb, 'telegram_create_code');
export const telegramUnlink = () => rpc<void>(sellerDb, 'telegram_unlink');

/* ------------------------------------------------------------------ */
/* Şikayət, məlumat ixracı, hesabın silinməsi                           */
/* ------------------------------------------------------------------ */

export const submitReport = (db: Db, r: ReportInput) =>
  rpc<void>(db, 'submit_report', {
    p_kind: r.kind,
    p_store: r.storeId ?? null,
    p_request: r.requestId ?? null,
    p_reason: r.reason,
    p_details: r.details?.trim() || null,
  });

export const exportMyData = (db: Db) => rpc<Record<string, unknown>>(db, 'export_my_data');
export const deleteMyAccount = (db: Db) => rpc<void>(db, 'delete_my_account');

export const adminListReports = (status: string | null = 'open') =>
  rpc<AdminReport[]>(sellerDb, 'admin_list_reports', { p_status: status });
export const adminResolveReport = (id: string, status: 'resolved' | 'dismissed', note?: string) =>
  rpc<void>(sellerDb, 'admin_resolve_report', { p_report: id, p_status: status, p_note: note ?? null });
export const adminSetSuspended = (storeId: string, suspended: boolean, reason?: string) =>
  rpc<void>(sellerDb, 'admin_set_suspended', { p_store: storeId, p_suspended: suspended, p_reason: reason ?? null });
export const adminCancelRequest = (id: string) => rpc<void>(sellerDb, 'admin_cancel_request', { p_request: id });
