import { useState, type FormEvent, type ReactNode } from 'react';
import { X } from 'lucide-react';
import { BRAND_ALL, CATEGORIES } from '@/lib/supabase';
import * as api from '@/lib/api';
import { useSeller } from '@/lib/auth';
import { normalizeAzPhone } from '@/lib/validate';
import { showToast } from '@/lib/utils';
import type { CarBrand, MyStore, ProviderProfileInput, StoreProfileInput } from '@/lib/types';
import { Chip } from '@/components/ui';
import { DEFAULT_PROVIDER, ProviderFields, validateProvider } from '@/components/Provider';

const inputCls =
  'w-full bg-slate-50 border border-slate-200 rounded-lg px-3 py-2.5 text-xs text-slate-800 focus:outline-none focus:border-[#0B4635]';

function Field({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div>
      <label className="text-[11px] text-slate-500 mb-0.5 block font-medium">{label}</label>
      {children}
    </div>
  );
}

function Sheet({ title, onClose, children }: { title: string; onClose: () => void; children: ReactNode }) {
  return (
    <div className="fixed inset-0 z-[60] flex items-end sm:items-center justify-center">
      <div className="fixed inset-0 bg-black/60" onClick={onClose} />
      <div className="relative w-full max-w-md max-h-[92vh] overflow-y-auto bg-white rounded-t-3xl sm:rounded-3xl p-5 shadow-2xl">
        <div className="flex items-center justify-between mb-3">
          <h3 className="text-sm font-bold text-slate-900">{title}</h3>
          <button onClick={onClose} className="p-1 rounded-lg bg-slate-100 text-slate-500" aria-label="Bağla">
            <X className="w-4 h-4" />
          </button>
        </div>
        {children}
      </div>
    </div>
  );
}

function toggle(list: string[], v: string): string[] {
  return list.includes(v) ? list.filter((x) => x !== v) : [...list, v];
}

function ChipPickers({
  brands,
  selBrands,
  setSelBrands,
  selCats,
  setSelCats,
  showCats = true,
}: {
  brands: CarBrand[];
  selBrands: string[];
  setSelBrands: (b: string[]) => void;
  selCats: string[];
  setSelCats: (c: string[]) => void;
  showCats?: boolean;
}) {
  const all = selBrands.includes(BRAND_ALL);
  return (
    <>
      <Field label="Hansı markalarla işləyirsiniz? *">
        <div className="flex flex-wrap gap-1.5">
          <Chip tone="orange" active={all} onClick={() => setSelBrands(all ? [] : [BRAND_ALL])}>
            {BRAND_ALL}
          </Chip>
          {!all &&
            brands.map((b) => (
              <Chip tone="orange" key={b.id} active={selBrands.includes(b.name)} onClick={() => setSelBrands(toggle(selBrands, b.name))}>
                {b.name}
              </Chip>
            ))}
        </div>
      </Field>
      {showCats && (
        <Field label="Hansı detal kateqoriyaları? *">
          <div className="flex flex-wrap gap-1.5">
            {CATEGORIES.map((c) => (
              <Chip tone="orange" key={c.key} active={selCats.includes(c.key)} onClick={() => setSelCats(toggle(selCats, c.key))}>
                {c.icon} {c.short}
              </Chip>
            ))}
          </div>
        </Field>
      )}
    </>
  );
}

function validateProfile(
  p: { name: string; phone?: string; brands: string[]; categories: string[]; provider?: ProviderProfileInput },
  needPhone: boolean
): string | null {
  if (p.name.trim().length < 2) return 'Mağaza adını yazın.';
  if (needPhone && !normalizeAzPhone(p.phone || '')) return 'Telefon nömrəsi düzgün deyil (məs: 050 123 45 67).';
  if (p.brands.length === 0) return 'Ən azı bir marka seçin.';
  if (p.provider) {
    const pv = validateProvider(p.provider);
    if (pv) return pv;
    if (p.provider.offerings.includes('parts') && p.categories.length === 0) return 'Ən azı bir detal kateqoriyası seçin.';
  } else if (p.categories.length === 0) {
    return 'Ən azı bir kateqoriya seçin.';
  }
  return null;
}

/* ====================================================================== */
/* Giriş / Qeydiyyat / Parol bərpası                                       */
/* ====================================================================== */

export function SellerAuthModal({
  brands,
  onClose,
  onSuccess,
}: {
  brands: CarBrand[];
  onClose: () => void;
  onSuccess: () => void;
}) {
  const seller = useSeller();
  const [mode, setMode] = useState<'login' | 'register' | 'reset'>('login');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [name, setName] = useState('');
  const [phone, setPhone] = useState('');
  const [voen, setVoen] = useState('');
  const [address, setAddress] = useState('');
  const [selBrands, setSelBrands] = useState<string[]>([BRAND_ALL]);
  const [selCats, setSelCats] = useState<string[]>(CATEGORIES.map((c) => c.key));
  const [provider, setProvider] = useState<ProviderProfileInput>(DEFAULT_PROVIDER);
  const [agreed, setAgreed] = useState(false);
  const termsUrl = import.meta.env.VITE_TERMS_URL as string | undefined;
  const privacyUrl = import.meta.env.VITE_PRIVACY_URL as string | undefined;
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [info, setInfo] = useState<string | null>(null);

  const submit = async (e: FormEvent) => {
    e.preventDefault();
    setError(null);
    setInfo(null);
    if (!/^\S+@\S+\.\S+$/.test(email.trim())) return setError('E-poçt ünvanını düzgün yazın.');

    setBusy(true);
    try {
      if (mode === 'reset') {
        await seller.resetPassword(email);
        setInfo('Parolu yeniləmək üçün link e-poçtunuza göndərildi.');
        return;
      }
      if (password.length < 6) return setError('Parol ən azı 6 simvol olmalıdır.');

      if (mode === 'login') {
        await seller.signIn(email, password);
        onSuccess();
        return;
      }

      if ((termsUrl || privacyUrl) && !agreed) return setError('Davam etmək üçün şərtlərlə razılaşın.');
      const profile: StoreProfileInput = {
        name: name.trim(),
        voen: voen.trim(),
        phone: normalizeAzPhone(phone) ?? phone,
        address: address.trim(),
        brands: selBrands,
        categories: selCats,
        provider,
      };
      const problem = validateProfile({ ...profile }, true);
      if (problem) return setError(problem);

      const result = await seller.signUp(email, password, profile);
      if (result === 'confirm_email') {
        setInfo('Hesab yaradıldı. E-poçtunuzu təsdiqləyin — ilk girişdən sonra mağazanız avtomatik açılacaq.');
        setMode('login');
        return;
      }
      showToast({ title: 'Mağazanız açıldı', body: '30 başlanğıc coin hesabınıza əlavə olundu.', type: 'success' });
      onSuccess();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Xəta baş verdi.');
    } finally {
      setBusy(false);
    }
  };

  return (
    <Sheet
      title={mode === 'login' ? 'Satıcı girişi' : mode === 'register' ? 'Mağaza qeydiyyatı' : 'Parolu bərpa et'}
      onClose={onClose}
    >
      <form onSubmit={submit} className="space-y-2.5">
        <Field label="E-poçt">
          <input
            type="email"
            autoComplete="email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            className={inputCls}
            placeholder="magaza@mail.az"
          />
        </Field>

        {mode !== 'reset' && (
          <Field label="Parol">
            <input
              type="password"
              autoComplete={mode === 'login' ? 'current-password' : 'new-password'}
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              className={inputCls}
              placeholder="Ən azı 6 simvol"
            />
          </Field>
        )}

        {mode === 'register' && (
          <>
            <Field label="Mağaza adı *">
              <input value={name} onChange={(e) => setName(e.target.value)} className={inputCls} placeholder="Məs: Sumqayıt Avto" />
            </Field>
            <Field label="WhatsApp / mobil nömrə * (alıcıya yalnız təklif seçiləndə açılır)">
              <input
                type="tel"
                value={phone}
                onChange={(e) => setPhone(e.target.value)}
                className={inputCls}
                placeholder="050 123 45 67"
              />
            </Field>
            <div className="grid grid-cols-2 gap-2">
              <Field label="VÖEN (könüllü)">
                <input value={voen} onChange={(e) => setVoen(e.target.value)} className={inputCls} inputMode="numeric" maxLength={10} />
              </Field>
              <Field label="Ünvan (könüllü)">
                <input value={address} onChange={(e) => setAddress(e.target.value)} className={inputCls} />
              </Field>
            </div>
            <ProviderFields value={provider} onChange={setProvider} />
            <ChipPickers
              brands={brands}
              selBrands={selBrands}
              setSelBrands={setSelBrands}
              selCats={selCats}
              setSelCats={setSelCats}
              showCats={provider.offerings.includes('parts')}
            />
            {(termsUrl || privacyUrl) && (
              <label className="flex items-start gap-2 text-[11px] text-slate-600 cursor-pointer">
                <input type="checkbox" checked={agreed} onChange={(e) => setAgreed(e.target.checked)} className="mt-0.5" />
                <span>
                  {termsUrl && (
                    <a href={termsUrl} target="_blank" rel="noreferrer" className="underline">
                      İstifadə şərtləri
                    </a>
                  )}
                  {termsUrl && privacyUrl ? ' və ' : ''}
                  {privacyUrl && (
                    <a href={privacyUrl} target="_blank" rel="noreferrer" className="underline">
                      məxfilik siyasəti
                    </a>
                  )}{' '}
                  ilə razıyam
                </span>
              </label>
            )}
            <p className="text-[10px] text-slate-400">
              Qeydiyyatdan sonra 30 başlanğıc coin alırsınız. VÖEN və təsdiq (✓) admin tərəfindən yoxlanır.
            </p>
          </>
        )}

        {error && (
          <div className="rounded-lg bg-rose-50 border border-rose-200 px-3 py-2 text-[11px] text-rose-700">{error}</div>
        )}
        {info && (
          <div className="rounded-lg bg-emerald-50 border border-emerald-200 px-3 py-2 text-[11px] text-emerald-700">{info}</div>
        )}

        <button
          type="submit"
          disabled={busy}
          className="w-full py-3 bg-[#FFC61A] hover:bg-[#FFD24D] text-[#1B1B12] text-xs font-bold rounded-xl disabled:opacity-60 active:scale-95 transition-all"
        >
          {busy ? 'Gözləyin…' : mode === 'login' ? 'Daxil ol' : mode === 'register' ? 'Mağaza aç' : 'Link göndər'}
        </button>

        <div className="flex items-center justify-between text-[11px] pt-1">
          {mode === 'login' ? (
            <>
              <button type="button" className="text-slate-500 hover:text-slate-800" onClick={() => setMode('reset')}>
                Parolu unutdum
              </button>
              <button type="button" className="font-bold text-[#9A5B00]" onClick={() => setMode('register')}>
                Yeni mağaza aç
              </button>
            </>
          ) : (
            <button type="button" className="font-bold text-[#9A5B00]" onClick={() => setMode('login')}>
              ← Girişə qayıt
            </button>
          )}
        </div>
      </form>
    </Sheet>
  );
}

/* ====================================================================== */
/* Mağaza profili: tamamla (create) və ya redaktə et (edit)                */
/* ====================================================================== */

export function StoreProfileModal({
  mode,
  store,
  brands,
  onClose,
}: {
  mode: 'create' | 'edit';
  store: MyStore | null;
  brands: CarBrand[];
  onClose: () => void;
}) {
  const seller = useSeller();
  const [name, setName] = useState(store?.name ?? '');
  const [phone, setPhone] = useState('');
  const [voen, setVoen] = useState('');
  const [address, setAddress] = useState(store?.address ?? '');
  const [selBrands, setSelBrands] = useState<string[]>(store?.supported_brands?.length ? store.supported_brands : [BRAND_ALL]);
  const [selCats, setSelCats] = useState<string[]>(
    store?.categories?.length ? store.categories : CATEGORIES.map((c) => c.key)
  );
  const [provider, setProvider] = useState<ProviderProfileInput>(
    store
      ? {
          providerType: store.provider_type ?? 'shop',
          offerings: store.offerings?.length ? store.offerings : ['parts'],
          serviceCategories: store.service_categories ?? [],
          cities: store.cities ?? [],
          mobile: !!store.mobile_service,
        }
      : DEFAULT_PROVIDER
  );
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const submit = async (e: FormEvent) => {
    e.preventDefault();
    setError(null);
    const problem = validateProfile({ name, phone, brands: selBrands, categories: selCats, provider }, mode === 'create');
    if (problem) return setError(problem);

    setBusy(true);
    try {
      if (mode === 'create') {
        await seller.createStore({
          name: name.trim(),
          voen: voen.trim(),
          phone: normalizeAzPhone(phone) ?? phone,
          address: address.trim(),
          brands: selBrands,
          categories: selCats,
          provider,
        });
        showToast({ title: 'Mağazanız açıldı', body: '30 başlanğıc coin hesabınıza əlavə olundu.', type: 'success' });
      } else {
        await api.updateMyStore({ name: name.trim(), address: address.trim(), brands: selBrands, categories: selCats });
        await api.updateProviderProfile(provider);
        await seller.refresh();
        showToast({ title: 'Profil yeniləndi', type: 'success' });
      }
      onClose();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Yadda saxlanmadı.');
    } finally {
      setBusy(false);
    }
  };

  return (
    <Sheet title={mode === 'create' ? 'Mağaza profilini tamamlayın' : 'Mağaza profili'} onClose={onClose}>
      <form onSubmit={submit} className="space-y-2.5">
        <Field label="Mağaza adı *">
          <input value={name} onChange={(e) => setName(e.target.value)} className={inputCls} />
        </Field>
        {mode === 'create' && (
          <>
            <Field label="WhatsApp / mobil nömrə *">
              <input type="tel" value={phone} onChange={(e) => setPhone(e.target.value)} className={inputCls} placeholder="050 123 45 67" />
            </Field>
            <Field label="VÖEN (könüllü)">
              <input value={voen} onChange={(e) => setVoen(e.target.value)} className={inputCls} inputMode="numeric" maxLength={10} />
            </Field>
          </>
        )}
        <Field label="Ünvan">
          <input value={address} onChange={(e) => setAddress(e.target.value)} className={inputCls} />
        </Field>
        <ProviderFields value={provider} onChange={setProvider} />
        <ChipPickers
          brands={brands}
          selBrands={selBrands}
          setSelBrands={setSelBrands}
          selCats={selCats}
          setSelCats={setSelCats}
          showCats={provider.offerings.includes('parts')}
        />
        {mode === 'edit' && (
          <p className="text-[10px] text-slate-400">Telefon və VÖEN-i dəyişmək üçün admin ilə əlaqə saxlayın.</p>
        )}

        {error && (
          <div className="rounded-lg bg-rose-50 border border-rose-200 px-3 py-2 text-[11px] text-rose-700">{error}</div>
        )}

        <button
          type="submit"
          disabled={busy}
          className="w-full py-3 bg-[#0B4635] text-white text-xs font-bold rounded-xl disabled:opacity-60 active:scale-95 transition-all"
        >
          {busy ? 'Saxlanılır…' : mode === 'create' ? 'Mağaza aç' : 'Yadda saxla'}
        </button>
      </form>
    </Sheet>
  );
}
