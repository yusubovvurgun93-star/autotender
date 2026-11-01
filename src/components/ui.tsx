import { useEffect, useState, type ReactNode } from 'react';
import { Camera, ShieldCheck, Star, X } from 'lucide-react';
import { GRADE_COLORS, providerTypeLabel, type Db } from '@/lib/supabase';
import { uploadPartImage } from '@/lib/api';
import { useCountdown } from '@/lib/utils';
import type { PublicStore } from '@/lib/types';

/** Hər saniyə yox, verilən aralıqla yenidən çəkmək üçün (vaxtı bitən sorğuları siyahıdan çıxarmaq) */
export function useTick(ms = 30000) {
  const [, setN] = useState(0);
  useEffect(() => {
    const id = setInterval(() => setN((n) => n + 1), ms);
    return () => clearInterval(id);
  }, [ms]);
}

export function Countdown({ expiresAt }: { expiresAt: string }) {
  const c = useCountdown(expiresAt);
  return <span className={c.total > 0 && c.total < 10 * 60000 ? 'text-red-500 font-bold' : ''}>{c.label}</span>;
}

/** Kartın üstündə qalan vaxtı göstərən zolaq (yaşıl → sarı → qırmızı). Valideyn `relative overflow-hidden` olmalıdır. */
export function TimeBar({ createdAt, expiresAt }: { createdAt: string; expiresAt: string }) {
  const total = new Date(expiresAt).getTime() - new Date(createdAt).getTime();
  const left = new Date(expiresAt).getTime() - Date.now();
  const pct = total > 0 ? Math.max(0, Math.min(1, left / total)) : 0;
  const color = pct > 0.5 ? '#1E9E5A' : pct > 0.2 ? '#FFC61A' : '#D93A2B';
  return (
    <div className="absolute inset-x-0 top-0 h-1.5 bg-[#EAF0EB]" aria-hidden="true">
      <div className="h-full rounded-r-full transition-[width] duration-1000" style={{ width: `${Math.round(pct * 100)}%`, background: color }} />
    </div>
  );
}

export function Stars({
  value,
  onChange,
  size = 'md',
}: {
  value: number;
  onChange?: (v: number) => void;
  size?: 'sm' | 'md' | 'lg';
}) {
  const cls = size === 'lg' ? 'w-8 h-8' : size === 'md' ? 'w-5 h-5' : 'w-3.5 h-3.5';
  return (
    <div className="flex items-center gap-0.5">
      {[1, 2, 3, 4, 5].map((n) => {
        const icon = (
          <Star className={`${cls} ${n <= Math.round(value) ? 'fill-amber-400 text-amber-400' : 'text-slate-300'}`} />
        );
        return onChange ? (
          <button key={n} type="button" onClick={() => onChange(n)} aria-label={`${n} ulduz`} className="p-0.5">
            {icon}
          </button>
        ) : (
          <span key={n}>{icon}</span>
        );
      })}
    </div>
  );
}

/** Mağaza adı + etibar göstəriciləri: təsdiq, reytinq (və ya "Yeni"), dərəcə */
export function StoreBadge({ store }: { store: PublicStore | null; tone?: 'green' | 'orange' }) {
  if (!store) return <span className="text-sm font-bold text-slate-800">Partnyor mağaza</span>;
  const rated = store.review_count > 0 || Number(store.rating) < 5;
  return (
    <div className="min-w-0">
      <div className="flex items-center gap-1.5">
        <span className="text-sm font-bold text-slate-900 truncate">{store.name}</span>
        {store.verified && <ShieldCheck className="w-4 h-4 flex-shrink-0 text-[#13694f]" aria-label="Təsdiqlənib" />}
      </div>
      <div className="flex items-center gap-1.5 text-[11px] text-slate-500 mt-1 flex-wrap">
        {store.provider_type && store.provider_type !== 'shop' && (
          <span className="tag-blue">
            {providerTypeLabel(store.provider_type)}
            {store.mobile_service ? ', yerinə gəlir' : ''}
          </span>
        )}
        {rated ? (
          <span className="tag-amber">
            {Number(store.rating).toFixed(1)} ulduz
            {store.review_count > 0 ? ` (${store.review_count})` : ''}
          </span>
        ) : (
          <span className="tag">Yeni mağaza</span>
        )}
        <span className={`font-bold ${GRADE_COLORS[store.grade] ?? 'text-slate-500'}`}>{store.grade}</span>
      </div>
    </div>
  );
}

export function PhotoStrip({ urls, alt = 'Şəkil' }: { urls: string[] | null | undefined; alt?: string }) {
  if (!urls || urls.length === 0) return null;
  return (
    <div className="flex flex-wrap gap-1.5 mt-2">
      {urls.map((u) => (
        <a key={u} href={u} target="_blank" rel="noreferrer" className="block">
          <img
            src={u}
            alt={alt}
            loading="lazy"
            className="w-16 h-16 rounded-xl object-cover bg-slate-100"
          />
        </a>
      ))}
    </div>
  );
}

export function EmptyState({
  title,
  text,
  action,
}: {
  title: string;
  text?: string;
  action?: { label: string; onClick: () => void };
}) {
  return (
    <div className="rounded-3xl bg-white/60 border-2 border-dashed border-[#0B4635]/15 p-7 text-center">
      <h3 className="font-display text-base font-extrabold text-slate-800">{title}</h3>
      {text && <p className="text-[13px] text-slate-500 mt-1 max-w-[17rem] mx-auto">{text}</p>}
      {action && (
        <button type="button" onClick={action.onClick} className="btn-cta mt-4 px-6">
          {action.label}
        </button>
      )}
    </div>
  );
}

export function Chip({
  active,
  onClick,
  children,
  tone = 'green',
}: {
  active: boolean;
  onClick: () => void;
  children: ReactNode;
  tone?: 'green' | 'orange';
}) {
  const on =
    tone === 'green'
      ? 'bg-[#0B4635] text-white shadow-[0_6px_14px_-6px_rgba(11,70,53,0.7)]'
      : 'bg-[#FFC61A] text-[#0F2A21] shadow-[0_6px_14px_-6px_rgba(255,198,26,0.9)]';
  return (
    <button
      type="button"
      onClick={onClick}
      aria-pressed={active}
      className={`px-3.5 py-2 rounded-full text-[13px] font-semibold transition active:scale-95 ${
        active ? on : 'bg-white text-slate-600 shadow-[0_0_0_1px_rgba(15,42,33,0.09)]'
      }`}
    >
      {children}
    </button>
  );
}

/** Aşağıdan açılan şüşə pəncərə: ödəniş təlimatı, təsdiqlər və s. üçün */
export function Sheet({ title, onClose, children }: { title: string; onClose: () => void; children: ReactNode }) {
  useEffect(() => {
    const prev = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    return () => {
      document.body.style.overflow = prev;
    };
  }, []);
  return (
    <div className="fixed inset-0 z-[60] flex items-end justify-center">
      <div className="fixed inset-0 bg-[#0B2A20]/50 backdrop-blur-[2px]" onClick={onClose} />
      <div
        role="dialog"
        aria-label={title}
        className="glass sheet-up relative w-full max-w-md max-h-[88vh] overflow-y-auto rounded-t-[32px] p-5 pb-8 bg-white/90"
        style={{ paddingBottom: 'max(32px, env(safe-area-inset-bottom))' }}
      >
        <div className="flex items-center justify-between mb-4">
          <h3 className="font-display text-lg font-extrabold text-slate-900">{title}</h3>
          <button onClick={onClose} aria-label="Bağla" className="h-9 w-9 rounded-full bg-black/5 text-slate-600 flex items-center justify-center">
            <X className="w-4 h-4" />
          </button>
        </div>
        {children}
      </div>
    </div>
  );
}

/** Şəkil seçici: sıxır, `part-images` bucket-inə öz qovluğuna yükləyir (maks. `max` ədəd) */
export function ImagePicker({
  db,
  userId,
  urls,
  onChange,
  onBusy,
  max = 3,
  hint,
}: {
  db: Db;
  userId: string | null;
  urls: string[];
  onChange: (urls: string[]) => void;
  onBusy?: (busy: boolean) => void;
  max?: number;
  hint?: string;
}) {
  const [uploading, setUploading] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  const pick = async (files: FileList | null) => {
    if (!files || !userId) return;
    const room = max - urls.length;
    if (room <= 0) return;
    setUploading(true);
    onBusy?.(true);
    setErr(null);
    let next = urls;
    try {
      for (const file of Array.from(files).slice(0, room)) {
        const url = await uploadPartImage(file, userId, db);
        next = [...next, url].slice(0, max);
        onChange(next);
      }
    } catch (e) {
      setErr(e instanceof Error ? e.message : 'Şəkil yüklənmədi.');
    } finally {
      setUploading(false);
      onBusy?.(false);
    }
  };

  return (
    <div>
      {hint && <p className="label">{hint}</p>}
      <div className="flex items-center gap-2 flex-wrap">
        {urls.map((u) => (
          <div key={u} className="relative">
            <img src={u} alt="" className="w-16 h-16 rounded-xl object-cover" />
            <button
              type="button"
              onClick={() => onChange(urls.filter((x) => x !== u))}
              className="absolute -top-1.5 -right-1.5 w-5 h-5 rounded-full bg-slate-800 text-white flex items-center justify-center"
              aria-label="Şəkli sil"
            >
              <X className="w-3 h-3" />
            </button>
          </div>
        ))}
        {urls.length < max && (
          <label className="w-16 h-16 rounded-xl border-2 border-dashed border-[#0B4635]/25 bg-[#F4F7F4] flex flex-col items-center justify-center text-slate-500 cursor-pointer hover:border-[#0B4635] hover:text-[#0B4635]">
            <Camera className="w-5 h-5" />
            <span className="text-[9px] mt-0.5">{uploading ? 'Yüklənir…' : 'Əlavə et'}</span>
            <input
              type="file"
              accept="image/*"
              multiple
              className="hidden"
              disabled={uploading}
              onChange={(e) => {
                void pick(e.target.files);
                e.target.value = '';
              }}
            />
          </label>
        )}
      </div>
      {err && <p className="text-xs text-rose-600 mt-1">{err}</p>}
    </div>
  );
}
