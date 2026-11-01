import { CITIES, PROVIDER_TYPES, SERVICE_CATEGORIES } from '@/lib/supabase';
import type { ProviderProfileInput, ProviderType } from '@/lib/types';
import { Chip } from '@/components/ui';

export const DEFAULT_PROVIDER: ProviderProfileInput = {
  providerType: 'shop',
  offerings: ['parts'],
  serviceCategories: [],
  cities: [],
  mobile: false,
};

function toggle(list: string[], v: string): string[] {
  return list.includes(v) ? list.filter((x) => x !== v) : [...list, v];
}

/** Profil yoxlaması: xəta mətni və ya null */
export function validateProvider(p: ProviderProfileInput): string | null {
  if (p.offerings.length === 0) return 'Nə təklif etdiyinizi seçin (ehtiyat hissəsi və/ya xidmət).';
  if (p.offerings.includes('service')) {
    if (p.serviceCategories.length === 0) return 'Ən azı bir xidmət növü seçin.';
    if (p.cities.length === 0) return 'Xidmət göstərdiyiniz şəhəri seçin.';
  }
  return null;
}

/** "Mağaza / Servis / Usta" + təklif etdikləri + xidmət növləri + şəhərlər + yerinə gəlmə */
export function ProviderFields({
  value,
  onChange,
}: {
  value: ProviderProfileInput;
  onChange: (v: ProviderProfileInput) => void;
}) {
  const hasParts = value.offerings.includes('parts');
  const hasService = value.offerings.includes('service');

  const setType = (t: ProviderType) => {
    // Seçimə görə sahələr dəyişir: mağaza yalnız detal, usta yalnız xidmət, servis ikisini də göstərə bilər
    if (t === 'shop') onChange({ ...value, providerType: t, offerings: ['parts'], mobile: false });
    else if (t === 'master') onChange({ ...value, providerType: t, offerings: ['service'] });
    else onChange({ ...value, providerType: t, offerings: hasService ? value.offerings : ['service'] });
  };

  const setOffering = (key: 'parts' | 'service') => {
    const next = toggle(value.offerings, key);
    onChange({ ...value, offerings: next, ...(key === 'service' && !next.includes('service') ? { mobile: false } : {}) });
  };

  return (
    <div className="space-y-3">
      <div>
        <label className="label">Siz kimsiniz? *</label>
        <div className="grid grid-cols-3 gap-1.5">
          {PROVIDER_TYPES.map((p) => (
            <button
              type="button"
              key={p.key}
              onClick={() => setType(p.key)}
              className={`py-3 rounded-2xl text-center transition active:scale-95 ${
                value.providerType === p.key
                  ? 'bg-[#FFC61A] text-[#0F2A21] shadow-[0_8px_16px_-8px_rgba(255,198,26,0.95)]'
                  : 'bg-[#F4F7F4] text-slate-600'
              }`}
            >
              <div className="text-[13px] font-display font-bold">{p.label}</div>
            </button>
          ))}
        </div>
      </div>

      {value.providerType === 'service_center' && (
        <div>
          <label className="label">Nə təklif edirsiniz? *</label>
          <div className="chips">
            <Chip tone="orange" active={hasService} onClick={() => setOffering('service')}>
              Xidmət
            </Chip>
            <Chip tone="orange" active={hasParts} onClick={() => setOffering('parts')}>
              Ehtiyat hissəsi satışı
            </Chip>
          </div>
        </div>
      )}

      {hasService && (
        <>
          <div>
            <label className="label">Xidmət növləri *</label>
            <div className="flex gap-1.5 flex-wrap">
              {SERVICE_CATEGORIES.map((c) => (
                <Chip
                  tone="orange"
                  key={c.key}
                  active={value.serviceCategories.includes(c.key)}
                  onClick={() => onChange({ ...value, serviceCategories: toggle(value.serviceCategories, c.key) })}
                >
                  {c.short}
                </Chip>
              ))}
            </div>
          </div>
          <div>
            <label className="label">Hansı şəhərlərdə? *</label>
            <div className="flex gap-1.5 flex-wrap">
              {CITIES.map((c) => (
                <Chip
                  tone="orange"
                  key={c}
                  active={value.cities.includes(c)}
                  onClick={() => onChange({ ...value, cities: toggle(value.cities, c) })}
                >
                  {c}
                </Chip>
              ))}
            </div>
          </div>
          <label className="flex items-start gap-2 text-[13px] text-slate-600 cursor-pointer">
            <input
              type="checkbox"
              checked={value.mobile}
              onChange={(e) => onChange({ ...value, mobile: e.target.checked })}
              className="mt-0.5 h-4 w-4 accent-[#0B4635]"
            />
            <span>Müştərinin yanına gedirəm (yerində xidmət / çağırış)</span>
          </label>
        </>
      )}
    </div>
  );
}
