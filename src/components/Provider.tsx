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
    // Usta üçün ağlabatan ilkin seçim: yalnız xidmət
    if (t === 'master' && hasParts && !hasService) onChange({ ...value, providerType: t, offerings: ['service'] });
    else onChange({ ...value, providerType: t });
  };

  const setOffering = (key: 'parts' | 'service') => {
    const next = toggle(value.offerings, key);
    onChange({ ...value, offerings: next, ...(key === 'service' && !next.includes('service') ? { mobile: false } : {}) });
  };

  return (
    <div className="space-y-2.5">
      <div>
        <label className="text-[11px] text-slate-500 mb-1 block font-medium">Siz kimsiniz? *</label>
        <div className="grid grid-cols-3 gap-1.5">
          {PROVIDER_TYPES.map((p) => (
            <button
              type="button"
              key={p.key}
              onClick={() => setType(p.key)}
              className={`py-2 rounded-lg border text-center transition-all ${
                value.providerType === p.key
                  ? 'bg-[#FFC61A] border-[#FFC61A] text-[#1B1B12]'
                  : 'bg-slate-50 border-slate-200 text-slate-600'
              }`}
            >
              <div className="text-base leading-none">{p.icon}</div>
              <div className="text-[11px] font-bold mt-1">{p.label}</div>
            </button>
          ))}
        </div>
      </div>

      <div>
        <label className="text-[11px] text-slate-500 mb-1 block font-medium">Nə təklif edirsiniz? *</label>
        <div className="flex gap-1.5 flex-wrap">
          <Chip tone="orange" active={hasParts} onClick={() => setOffering('parts')}>
            🔩 Ehtiyat hissəsi satışı
          </Chip>
          <Chip tone="orange" active={hasService} onClick={() => setOffering('service')}>
            🔧 Usta / servis xidməti
          </Chip>
        </div>
      </div>

      {hasService && (
        <>
          <div>
            <label className="text-[11px] text-slate-500 mb-1 block font-medium">Xidmət növləri *</label>
            <div className="flex gap-1.5 flex-wrap">
              {SERVICE_CATEGORIES.map((c) => (
                <Chip
                  tone="orange"
                  key={c.key}
                  active={value.serviceCategories.includes(c.key)}
                  onClick={() => onChange({ ...value, serviceCategories: toggle(value.serviceCategories, c.key) })}
                >
                  {c.icon} {c.short}
                </Chip>
              ))}
            </div>
          </div>
          <div>
            <label className="text-[11px] text-slate-500 mb-1 block font-medium">Hansı şəhərlərdə? *</label>
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
          <label className="flex items-start gap-2 text-[11px] text-slate-600 cursor-pointer">
            <input
              type="checkbox"
              checked={value.mobile}
              onChange={(e) => onChange({ ...value, mobile: e.target.checked })}
              className="mt-0.5"
            />
            <span>Müştərinin yanına gedirəm (yerində xidmət / çağırış)</span>
          </label>
        </>
      )}
    </div>
  );
}
