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
    <div className="absolute inset-x-0 top-0 h-1 bg-slate-100" aria-hidden="true">
      <div className="h-full transition-[width] duration-1000" style={{ width: `${Math.round(pct * 100)}%`, background: color }} />
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
export function StoreBadge({ store, tone = 'green' }: { store: PublicStore | null; tone?: 'green' | 'orange' }) {
  if (!store) return <span className="text-xs font-bold text-slate-800">Partnyor mağaza</span>;
  const accent = tone === 'green' ? 'text-[#0B4635]' : 'text-[#9A5B00]';
  return (
    <div className="min-w-0">
      <div className="flex items-center gap-1">
        <span className="text-xs font-bold text-slate-800 truncate">{store.name}</span>
        {store.verified && <ShieldCheck className={`w-3.5 h-3.5 flex-shrink-0 ${accent}`} />}
      </div>
      <div className="flex items-center gap-1.5 text-[10px] text-slate-500 mt-0.5 flex-wrap">
        {store.provider_type && store.provider_type !== 'shop' && (
          <span className="px-1.5 py-0.5 rounded bg-indigo-50 text-indigo-700 font-semibold">
            {providerTypeLabel(store.provider_type)}
            {store.mobile_service ? ' · yerinə gəlir' : ''}
          </span>
        )}
        {store.review_count > 0 || Number(store.rating) < 5 ? (
          <>
            <Star className="w-3 h-3 fill-amber-400 text-amber-400" />
            <span className="font-semibold text-slate-700">{Number(store.rating).toFixed(1)}</span>
            <span>({store.review_count})</span>
          </>
        ) : (
          <span className="px-1.5 py-0.5 rounded bg-slate-100 text-slate-500 font-semibold">Yeni mağaza</span>
        )}
        <span className={`font-bold ${GRADE_COLORS[store.grade] ?? 'text-slate-500'}`}>{store.grade}</span>
      </div>
    </div>
  );
}

export function PhotoStrip({ urls, alt = 'Şəkil' }: { urls: string[] | null | undefined; alt?: string }) {
  if (!urls || urls.length === 0) return null;
  return (
    <div className="flex gap-1.5 mt-2">
      {urls.map((u) => (
        <a key={u} href={u} target="_blank" rel="noreferrer" className="block">
          <img
            src={u}
            alt={alt}
            loading="lazy"
            className="w-16 h-16 rounded-lg object-cover border border-slate-200 bg-slate-100"
          />
        </a>
      ))}
    </div>
  );
}

export function EmptyState({ title, text }: { title: string; text?: string }) {
  return (
    <div className="rounded-3xl bg-white/70 border border-dashed border-slate-300 p-7 text-center">
      <h3 className="font-display text-sm font-bold text-slate-800">{title}</h3>
      {text && <p className="text-xs text-slate-500 mt-1 max-w-[16rem] mx-auto">{text}</p>}
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
  const on = tone === 'green' ? 'bg-[#0B4635] border-[#0B4635] text-white' : 'bg-[#FFC61A] border-[#FFC61A] text-[#1B1B12]';
  return (
    <button
      type="button"
      onClick={onClick}
      className={`px-3 py-1.5 rounded-xl border text-xs font-semibold whitespace-nowrap transition-all ${
        active ? on : 'bg-white border-slate-200 text-slate-600'
      }`}
    >
      {children}
    </button>
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
      {hint && <p className="text-[11px] text-slate-500 mb-1 font-medium">{hint}</p>}
      <div className="flex items-center gap-2 flex-wrap">
        {urls.map((u) => (
          <div key={u} className="relative">
            <img src={u} alt="" className="w-16 h-16 rounded-lg object-cover border border-slate-200" />
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
          <label className="w-16 h-16 rounded-lg border-2 border-dashed border-slate-300 flex flex-col items-center justify-center text-slate-400 cursor-pointer hover:border-[#0B4635] hover:text-[#0B4635]">
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
      {err && <p className="text-[10px] text-rose-600 mt-1">{err}</p>}
    </div>
  );
}
