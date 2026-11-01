import { createClient } from '@supabase/supabase-js';

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL as string;
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY as string;

const authBase = { persistSession: true, autoRefreshToken: true, detectSessionInUrl: false };

/**
 * İKİ AYRI SESSİYA:
 * - buyerDb: alıcı. Qeydiyyatsız (anonim giriş), hər cihaza bir daimi "gizli" kimlik.
 * - sellerDb: satıcı / admin. E-poçt + parol.
 * Ayrı storageKey sayəsində satıcı hesabı ilə girmək alıcı tarixçəsini silmir.
 */
export const buyerDb = createClient(supabaseUrl, supabaseAnonKey, {
  auth: { ...authBase, storageKey: 'autotender-buyer-auth' },
});

export const sellerDb = createClient(supabaseUrl, supabaseAnonKey, {
  auth: { ...authBase, storageKey: 'autotender-seller-auth' },
});

export type Db = typeof buyerDb;

export const BRAND_ALL = 'Bütün markalar';

export const URGENCY_CONFIG: Record<
  string,
  { label: string; shortLabel: string; hours: number }
> = {
  express: { label: '1 saat (ekspres)', shortLabel: '1 saat', hours: 1 },
  standard: { label: '6 saat (bu gün)', shortLabel: '6 saat', hours: 6 },
  wide: { label: '24 saat (geniş axtarış)', shortLabel: '24 saat', hours: 24 },
};

export const CONDITION_LABELS: Record<string, string> = {
  original: 'Orijinal (yeni)',
  analog: 'Keyfiyyətli analoq',
  used: 'İşlənmiş / ölüxana',
  service: 'Xidmət',
};

export const WARRANTY_OPTIONS = ['Zəmanətsiz', '1 ay', '3 ay', '6 ay', '1 il'];

export const GRADE_COLORS: Record<string, string> = {
  'A+': 'text-emerald-600',
  A: 'text-amber-600',
  B: 'text-slate-500',
};

export const CATEGORIES = [
  { key: 'oil', label: 'Yağdəyişmə və filtrlər', short: 'Yağ' },
  { key: 'aggregate', label: 'Aqreqat (mühərrik, karopka)', short: 'Aqreqat' },
  { key: 'body', label: 'Kuzov / işıqlandırma', short: 'Kuzov' },
  { key: 'electrical', label: 'Elektrik / sensor', short: 'Elektrik' },
  { key: 'wheel', label: 'Təkər / əyləc / asqı', short: 'Təkər' },
  { key: 'accessory', label: 'Aksesuar / qulluq', short: 'Aksesuar' },
] as const;

/** Usta / servis xidmət növləri (server: valid_service_categories) */
export const SERVICE_CATEGORIES = [
  { key: 'diagnostics', label: 'Diaqnostika / kompüter', short: 'Diaqnostika' },
  { key: 'engine', label: 'Mühərrik / karopka təmiri', short: 'Mühərrik' },
  { key: 'chassis', label: 'Ayaq hissəsi (asqı) / əyləc / sükan', short: 'Asqı' },
  { key: 'electrical', label: 'Avto elektrik', short: 'Elektrik' },
  { key: 'body', label: 'Kuzov / boya / rixtovka', short: 'Kuzov' },
  { key: 'ac', label: 'Kondisioner / soyuducu', short: 'Kondisioner' },
  { key: 'tires', label: 'Təkər / balans / montaj', short: 'Təkər' },
  { key: 'maintenance', label: 'Yağ / texniki baxış', short: 'Texniki' },
  { key: 'detailing', label: 'Yuyulma / polirovka / kimyəvi', short: 'Detailing' },
  { key: 'towing', label: 'Evakuator / yol yardımı', short: 'Evakuator' },
] as const;

export const CITIES = ['Bakı', 'Sumqayıt', 'Gəncə', 'Mingəçevir', 'Lənkəran', 'Şəki', 'Naxçıvan', 'Digər'] as const;

export const PROVIDER_TYPES = [
  { key: 'shop', label: 'Mağaza' },
  { key: 'service_center', label: 'Servis' },
  { key: 'master', label: 'Usta' },
] as const;

export const PROVIDER_PREFS = [
  { key: 'any', label: 'Fərqi yoxdur' },
  { key: 'service_center', label: 'Servis' },
  { key: 'master', label: 'Fərdi usta' },
] as const;

export function providerTypeLabel(t: string | null | undefined): string {
  return PROVIDER_TYPES.find((p) => p.key === t)?.label ?? 'Mağaza';
}

export function serviceCategoryLabel(key: string | null | undefined): string {
  return SERVICE_CATEGORIES.find((c) => c.key === key)?.label ?? 'Xidmət';
}

/** Sorğunun kateqoriya etiketi (hissə və ya xidmət) */
export function requestCategoryLabel(r: { request_type?: string | null; category: string | null }): string {
  return r.request_type === 'service' ? serviceCategoryLabel(r.category) : categoryLabel(r.category);
}

/** Köhnə mətn kateqoriyalarını (məs. "Aqreqat (Mühərrik / Karopka)") açar sözə çevirir */
export function categoryKey(raw: string | null | undefined): string | null {
  if (!raw) return null;
  const v = raw.toLowerCase();
  if (CATEGORIES.some((c) => c.key === v)) return v;
  if (v.startsWith('yağ')) return 'oil';
  if (v.startsWith('aqreqat')) return 'aggregate';
  if (v.startsWith('kuzov')) return 'body';
  if (v.startsWith('elektrik')) return 'electrical';
  if (v.startsWith('təkər')) return 'wheel';
  if (v.startsWith('aksesuar')) return 'accessory';
  return null;
}

export function categoryLabel(raw: string | null | undefined): string {
  const key = categoryKey(raw);
  return CATEGORIES.find((c) => c.key === key)?.label ?? 'Detal';
}
