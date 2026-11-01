import { useCallback, useEffect, useMemo, useState } from 'react';
import {
  Activity,
  CheckCircle2,
  Clock,
  History,
  MessageCircle,
  Phone,
  PlusCircle,
  RotateCcw,
} from 'lucide-react';
import {
  buyerDb,
  CATEGORIES,
  CITIES,
  CONDITION_LABELS,
  PROVIDER_PREFS,
  SERVICE_CATEGORIES,
  URGENCY_CONFIG,
  categoryKey,
  requestCategoryLabel,
} from '@/lib/supabase';
import * as api from '@/lib/api';
import { etaLabel, formatPrice, formatTimeAgo, showToast } from '@/lib/utils';
import { loadLastCar, saveLastCar, telUrl, whatsappUrl } from '@/lib/validate';
import type { BuyerBid, BuyerRequest, CarBrand, DealContact, ProviderPref, Urgency } from '@/lib/types';
import { Chip, Countdown, EmptyState, ImagePicker, PhotoStrip, Stars, StoreBadge, TimeBar, useTick } from '@/components/ui';
import { ReportModal } from '@/components/Report';

type Tab = 'active' | 'create' | 'history';

type Props = {
  ready: boolean;
  userId: string | null;
  error: string | null;
  onRetry: () => void;
  brands: CarBrand[];
};

const inputCls =
  'w-full bg-slate-50 border border-slate-200 rounded-lg px-2.5 py-2 text-xs text-slate-800 focus:outline-none focus:border-[#0B4635]';

function reviewOf(req: BuyerRequest): { stars: number } | null {
  const r = req.store_reviews;
  if (!r) return null;
  return Array.isArray(r) ? r[0] ?? null : r;
}

function isLive(req: BuyerRequest) {
  return req.status === 'active' && new Date(req.expires_at).getTime() > Date.now();
}

function contactText(req: BuyerRequest, price: number) {
  const car = [req.brand, req.model, req.year ? `(${req.year})` : ''].filter(Boolean).join(' ');
  return `Salam, AutoTender-dən yazıram. ${car} üçün "${req.part_name}" təklifiniz (${formatPrice(price)}) ilə maraqlanıram.`;
}

export function BuyerPanel({ ready, userId, error, onRetry, brands }: Props) {
  const [tab, setTab] = useState<Tab>('active');
  const [requests, setRequests] = useState<BuyerRequest[]>([]);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [expandedId, setExpandedId] = useState<string | null>(null);
  const [contacts, setContacts] = useState<Record<string, DealContact>>({});

  // ---- Forma ----
  const last = useMemo(() => loadLastCar(), []);
  const [brand, setBrand] = useState(last.brand);
  const [model, setModel] = useState(last.model);
  const [year, setYear] = useState(last.year);
  const [vin, setVin] = useState('');
  const [category, setCategory] = useState<string | null>(null);
  const [partName, setPartName] = useState('');
  const [urgency, setUrgency] = useState<Urgency>('standard');
  const [budget, setBudget] = useState('');
  const [images, setImages] = useState<string[]>([]);
  const [uploading, setUploading] = useState(false);
  const [kind, setKind] = useState<'part' | 'service'>('part');
  const [svcCategory, setSvcCategory] = useState<string | null>(null);
  const [city, setCity] = useState<string>(last.city ?? 'Bakı');
  const [area, setArea] = useState('');
  const [onSite, setOnSite] = useState(false);
  const [providerPref, setProviderPref] = useState<ProviderPref>('any');
  const [submitting, setSubmitting] = useState(false);
  const [formError, setFormError] = useState<string | null>(null);

  const [historyCat, setHistoryCat] = useState<string>('all');
  const [report, setReport] = useState<{ storeId: string; name: string; requestId: string } | null>(null);

  useTick(30000);

  const refresh = useCallback(async () => {
    try {
      const rows = await api.fetchMyRequests();
      setRequests(rows);
      setLoadError(null);
    } catch (e) {
      setLoadError(e instanceof Error ? e.message : 'Məlumat yüklənmədi.');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    if (!ready || !userId) return;
    void refresh();
    let t: ReturnType<typeof setTimeout> | undefined;
    const debounced = () => {
      if (t) clearTimeout(t);
      t = setTimeout(() => void refresh(), 400);
    };
    const channel = buyerDb
      .channel(`buyer-sync-${userId}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'requests' }, debounced)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'bids' }, debounced)
      .subscribe();
    const poll = setInterval(() => void refresh(), 30000); // realtime qoşulmasa belə yenilənsin
    return () => {
      if (t) clearTimeout(t);
      clearInterval(poll);
      void buyerDb.removeChannel(channel);
    };
  }, [ready, userId, refresh]);

  const activeRequests = requests.filter(isLive);
  const historyRequests = requests.filter((r) => !isLive(r));
  const filteredHistory = historyRequests.filter(
    (r) => historyCat === 'all' || categoryKey(r.category) === historyCat
  );

  /* ---------------- Əməliyyatlar ---------------- */

  const handleCreate = async () => {
    setFormError(null);
    if (!brand) return setFormError('Avtomobilin markasını seçin.');
    if (!model.trim()) return setFormError('Modeli qeyd edin (məs: F10, Camry).');
    if (kind === 'part' && partName.trim().length < 2) return setFormError('Detalın adını qeyd edin.');
    if (kind === 'service') {
      if (!svcCategory) return setFormError('Xidmət növünü seçin.');
      if (partName.trim().length < 3) return setFormError('Nə lazım olduğunu qısaca yazın.');
      if (!city) return setFormError('Şəhəri seçin.');
    }
    const yearNum = year ? parseInt(year, 10) : null;
    const budgetNum = budget ? parseFloat(budget) : null;
    if (budgetNum !== null && !(budgetNum > 0)) return setFormError('Büdcə düzgün deyil.');

    setSubmitting(true);
    try {
      if (kind === 'service') {
        await api.createServiceRequest({
          category: svcCategory as string,
          title: partName.trim(),
          brand,
          model: model.trim(),
          year: yearNum,
          city,
          area: area.trim(),
          onSite,
          providerPref,
          urgency,
          budget: budgetNum,
          images,
        });
      } else {
        await api.createRequest({
          brand,
          model: model.trim(),
          year: yearNum,
          vin: vin.trim() ? vin.trim().toUpperCase() : null,
          partName: partName.trim(),
          category,
          urgency,
          budget: budgetNum,
          images,
        });
      }
      saveLastCar({ brand, model: model.trim(), year, city });
      showToast({
        title: 'Sorğu göndərildi',
        body: 'Uyğun mağazalara bildiriş getdi. Təkliflər burada görünəcək.',
        type: 'success',
      });
      setPartName('');
      setVin('');
      setBudget('');
      setImages([]);
      setCategory(null);
      setSvcCategory(null);
      setArea('');
      setOnSite(false);
      setProviderPref('any');
      await refresh();
      setTab('active');
    } catch (e) {
      setFormError(e instanceof Error ? e.message : 'Sorğu göndərilə bilmədi.');
    } finally {
      setSubmitting(false);
    }
  };

  const repost = (req: BuyerRequest) => {
    setBrand(req.brand);
    setModel(req.model ?? '');
    setYear(req.year ? String(req.year) : '');
    setPartName(req.part_name);
    setKind(req.request_type === 'service' ? 'service' : 'part');
    setCategory(req.request_type === 'service' ? null : categoryKey(req.category));
    setSvcCategory(req.request_type === 'service' ? req.category : null);
    if (req.city) setCity(req.city);
    setArea(req.area ?? '');
    setOnSite(!!req.on_site);
    setProviderPref(req.provider_pref ?? 'any');
    setImages([]);
    setFormError(null);
    setTab('create');
  };

  const handleAccept = async (req: BuyerRequest, bid: BuyerBid) => {
    try {
      const contact = await api.acceptBid(bid.id);
      setContacts((c) => ({ ...c, [req.id]: contact }));
      showToast({ title: 'Təklif seçildi', body: 'Satıcının nömrəsi açıldı. WhatsApp-da yazın.', type: 'win' });
      await refresh();
      setTab('history');
      setExpandedId(req.id);
    } catch (e) {
      showToast({ title: 'Seçilmədi', body: e instanceof Error ? e.message : undefined, type: 'error' });
      await refresh();
    }
  };

  const handleCancel = async (req: BuyerRequest) => {
    try {
      await api.cancelRequest(req.id);
      showToast({ title: 'Sorğu ləğv edildi', type: 'info' });
      await refresh();
    } catch (e) {
      showToast({ title: 'Ləğv edilmədi', body: e instanceof Error ? e.message : undefined, type: 'error' });
    }
  };

  const handleConfirm = async (req: BuyerRequest, stars: number | null) => {
    try {
      await api.confirmDeal(req.id, stars, null);
      showToast({
        title: stars ? 'Təşəkkürlər! Qiymətləndirmə qeyd olundu' : 'Razılaşma təsdiqləndi',
        type: 'success',
      });
      await refresh();
    } catch (e) {
      showToast({ title: 'Təsdiqlənmədi', body: e instanceof Error ? e.message : undefined, type: 'error' });
    }
  };

  const handleFail = async (req: BuyerRequest) => {
    try {
      await api.reportDealFailed(req.id);
      showToast({
        title: 'Sorğu yenidən açıldı',
        body: 'Digər təkliflər yenidən seçimə qayıtdı.',
        type: 'info',
      });
      setContacts((c) => {
        const { [req.id]: _removed, ...rest } = c;
        return rest;
      });
      await refresh();
      setTab('active');
      setExpandedId(req.id);
    } catch (e) {
      showToast({ title: 'Ləğv edilmədi', body: e instanceof Error ? e.message : undefined, type: 'error' });
    }
  };

  /* ---------------- Görünüş ---------------- */

  if (error) {
    return (
      <div className="px-3 pt-4 max-w-md mx-auto">
        <div className="rounded-3xl bg-white border border-rose-100 p-6 text-center shadow-xs">
          <p className="text-xs font-bold text-rose-600">Sessiya açılmadı</p>
          <p className="text-[11px] text-slate-500 mt-1">{error}</p>
          <button
            type="button"
            onClick={onRetry}
            className="mt-3 px-4 py-2 bg-[#0B4635] text-white text-xs font-bold rounded-xl"
          >
            Yenidən cəhd et
          </button>
        </div>
      </div>
    );
  }

  return (
    <div className="text-slate-800 pb-36 pt-2.5 px-3 max-w-md mx-auto">
      {!ready || loading ? (
        <div className="space-y-2.5">
          {[1, 2].map((i) => (
            <div key={i} className="rounded-2xl bg-white border border-slate-100 h-24 animate-pulse" />
          ))}
        </div>
      ) : (
        <>
          {loadError && (
            <div className="mb-2 rounded-xl bg-amber-50 border border-amber-200 p-2.5 text-[11px] text-amber-800">
              {loadError}
            </div>
          )}

          {/* ===== AKTİV ===== */}
          {tab === 'active' && (
            <div>
              <Hero
                compact={activeRequests.length > 0}
                onPick={(k) => {
                  setKind(k);
                  setTab('create');
                }}
              />
              {activeRequests.length === 0 ? null : (
                <div className="space-y-2.5">
                  <div className="text-[11px] font-bold text-slate-500 uppercase tracking-wider px-1">
                    Aktiv sorğularınız ({activeRequests.length})
                  </div>
                  {activeRequests.map((req) => (
                    <ActiveCard
                      key={req.id}
                      req={req}
                      open={expandedId === req.id}
                      onToggle={() => setExpandedId(expandedId === req.id ? null : req.id)}
                      onAccept={(bid) => handleAccept(req, bid)}
                      onCancel={() => handleCancel(req)}
                      onReport={(bid) =>
                        setReport({ storeId: bid.store_id, name: bid.store?.name ?? 'Mağaza', requestId: req.id })
                      }
                    />
                  ))}
                </div>
              )}
            </div>
          )}

          {/* ===== YENİ SORĞU ===== */}
          {tab === 'create' && (
            <div className="rounded-3xl bg-white border border-slate-200/70 p-4 shadow-[0_10px_30px_-18px_rgba(11,70,53,0.35)]">
              <div className="grid grid-cols-2 gap-2 mb-3">
                {(
                  [
                    { k: 'part', icon: '🔩', title: 'Detal axtarıram', sub: 'Ehtiyat hissəsi' },
                    { k: 'service', icon: '🔧', title: 'Usta / servis', sub: 'Təmir, diaqnostika, xidmət' },
                  ] as const
                ).map((o) => (
                  <button
                    key={o.k}
                    type="button"
                    onClick={() => setKind(o.k)}
                    className={`p-2.5 rounded-xl border text-left transition-all ${
                      kind === o.k ? 'bg-[#0B4635] border-[#0B4635] text-white' : 'bg-slate-50 border-slate-200 text-slate-600'
                    }`}
                  >
                    <div className="text-lg leading-none">{o.icon}</div>
                    <div className="text-xs font-bold mt-1">{o.title}</div>
                    <div className={`text-[10px] ${kind === o.k ? 'text-white/70' : 'text-slate-400'}`}>{o.sub}</div>
                  </button>
                ))}
              </div>

              <div className="grid grid-cols-2 gap-2 mb-2">
                <div>
                  <label className="text-[11px] text-slate-500 mb-0.5 block font-medium">Marka *</label>
                  <select value={brand} onChange={(e) => setBrand(e.target.value)} className={inputCls}>
                    <option value="">Seçin</option>
                    {brands.map((b) => (
                      <option key={b.id} value={b.name}>
                        {b.name}
                      </option>
                    ))}
                  </select>
                </div>
                <div>
                  <label className="text-[11px] text-slate-500 mb-0.5 block font-medium">Model *</label>
                  <input
                    type="text"
                    placeholder="F10, Camry"
                    value={model}
                    onChange={(e) => setModel(e.target.value)}
                    className={inputCls}
                  />
                </div>
              </div>

              <div className={`grid ${kind === 'part' ? 'grid-cols-2' : 'grid-cols-1'} gap-2 mb-2`}>
                <div>
                  <label className="text-[11px] text-slate-500 mb-0.5 block font-medium">İl</label>
                  <input
                    type="number"
                    inputMode="numeric"
                    placeholder="2015"
                    value={year}
                    onChange={(e) => setYear(e.target.value)}
                    className={inputCls}
                  />
                </div>
                {kind === 'part' && (
                  <div>
                    <label className="text-[11px] text-slate-500 mb-0.5 block font-medium">
                      VIN (dəqiq təklif üçün)
                    </label>
                    <input
                      type="text"
                      placeholder="Ban nömrəsi"
                      value={vin}
                      maxLength={17}
                      onChange={(e) => setVin(e.target.value)}
                      className={`${inputCls} uppercase`}
                    />
                  </div>
                )}
              </div>

              {kind === 'part' ? (
                <>
                  <div className="mb-2">
                    <label className="text-[11px] text-slate-500 mb-1 block font-medium">Kateqoriya (könüllü)</label>
                    <div className="flex gap-1.5 overflow-x-auto pb-1">
                      {CATEGORIES.map((c) => (
                        <Chip key={c.key} active={category === c.key} onClick={() => setCategory(category === c.key ? null : c.key)}>
                          {c.icon} {c.short}
                        </Chip>
                      ))}
                    </div>
                  </div>

                  <div className="mb-2">
                    <label className="text-[11px] text-slate-500 mb-0.5 block font-medium">Detalın adı *</label>
                    <input
                      type="text"
                      placeholder="Məs: qabaq amortizator, 5W-30 yağ"
                      value={partName}
                      onChange={(e) => setPartName(e.target.value)}
                      className={inputCls}
                    />
                  </div>
                </>
              ) : (
                <>
                  <div className="mb-2">
                    <label className="text-[11px] text-slate-500 mb-1 block font-medium">Hansı xidmət? *</label>
                    <div className="flex gap-1.5 flex-wrap">
                      {SERVICE_CATEGORIES.map((c) => (
                        <Chip key={c.key} active={svcCategory === c.key} onClick={() => setSvcCategory(svcCategory === c.key ? null : c.key)}>
                          {c.icon} {c.short}
                        </Chip>
                      ))}
                    </div>
                  </div>

                  <div className="mb-2">
                    <label className="text-[11px] text-slate-500 mb-0.5 block font-medium">Nə lazımdır? *</label>
                    <input
                      type="text"
                      placeholder="Məs: motor səs edir, akkumulyator dəyişmək, diaqnostika"
                      value={partName}
                      maxLength={120}
                      onChange={(e) => setPartName(e.target.value)}
                      className={inputCls}
                    />
                  </div>

                  <div className="grid grid-cols-2 gap-2 mb-2">
                    <div>
                      <label className="text-[11px] text-slate-500 mb-0.5 block font-medium">Şəhər *</label>
                      <select value={city} onChange={(e) => setCity(e.target.value)} className={inputCls}>
                        {CITIES.map((c) => (
                          <option key={c} value={c}>
                            {c}
                          </option>
                        ))}
                      </select>
                    </div>
                    <div>
                      <label className="text-[11px] text-slate-500 mb-0.5 block font-medium">Rayon / ərazi</label>
                      <input
                        type="text"
                        placeholder="Nəsimi, Xırdalan…"
                        value={area}
                        maxLength={40}
                        onChange={(e) => setArea(e.target.value)}
                        className={inputCls}
                      />
                    </div>
                  </div>

                  <div className="mb-2">
                    <label className="text-[11px] text-slate-500 mb-1 block font-medium">Kim baxsın?</label>
                    <div className="flex gap-1.5 flex-wrap">
                      {PROVIDER_PREFS.map((p) => (
                        <Chip key={p.key} active={providerPref === p.key} onClick={() => setProviderPref(p.key)}>
                          {p.label}
                        </Chip>
                      ))}
                    </div>
                  </div>

                  <label className="flex items-start gap-2 text-[11px] text-slate-600 mb-2 cursor-pointer">
                    <input type="checkbox" checked={onSite} onChange={(e) => setOnSite(e.target.checked)} className="mt-0.5" />
                    <span>Usta mənim yanıma gəlsin (yerində xidmət)</span>
                  </label>
                </>
              )}

              <div className="mb-3">
                <ImagePicker
                  db={buyerDb}
                  userId={userId}
                  urls={images}
                  onChange={setImages}
                  onBusy={setUploading}
                  hint={
                    kind === 'part'
                      ? 'Şəkil (ən çox 3) — satıcı dəqiq təklif versin'
                      : 'Şəkil (ən çox 3) — nasazlığı və ya avtomobili göstərin'
                  }
                />
              </div>

              <div className="mb-2">
                <label className="text-[11px] text-slate-500 mb-1 block font-medium">Nə qədər tez lazımdır?</label>
                <div className="grid grid-cols-3 gap-1.5">
                  {(Object.keys(URGENCY_CONFIG) as Urgency[]).map((k) => (
                    <button
                      type="button"
                      key={k}
                      onClick={() => setUrgency(k)}
                      className={`py-2 rounded-lg border text-center transition-all ${
                        urgency === k
                          ? 'bg-[#0B4635] border-[#0B4635] text-white'
                          : 'bg-slate-50 border-slate-200 text-slate-600'
                      }`}
                    >
                      <div className="text-sm leading-none">{URGENCY_CONFIG[k].icon}</div>
                      <div className="text-[11px] font-bold mt-1">{URGENCY_CONFIG[k].shortLabel}</div>
                    </button>
                  ))}
                </div>
                <p className="text-[10px] text-slate-400 mt-1">
                  Bu müddət ərzində mağazalar təklif verir. Müddət bitəndə sorğu bağlanır.
                </p>
              </div>

              <div className="mb-3">
                <label className="text-[11px] text-slate-500 mb-0.5 block font-medium">Büdcə (AZN, könüllü)</label>
                <input
                  type="number"
                  inputMode="decimal"
                  placeholder="Razılaşma ilə"
                  value={budget}
                  onChange={(e) => setBudget(e.target.value)}
                  className={inputCls}
                />
              </div>

              {formError && (
                <div className="mb-2 rounded-lg bg-rose-50 border border-rose-200 px-3 py-2 text-[11px] text-rose-700">
                  {formError}
                </div>
              )}

              <button
                type="button"
                onClick={handleCreate}
                disabled={submitting || uploading}
                className="w-full py-3.5 bg-[#FFC61A] hover:bg-[#FFD24D] text-[#1B1B12] font-display font-extrabold rounded-xl text-sm transition-all active:scale-[0.98] disabled:opacity-60 shadow-[0_3px_0_#C99700]"
              >
                {submitting ? 'Göndərilir…' : 'Sorğunu göndər'}
              </button>
              <p className="text-[10px] text-slate-400 text-center mt-2">
                Nömrəniz mağazalara göstərilmir. Siz təklif seçəndən sonra yalnız seçdiyiniz mağazanın nömrəsi açılır.
              </p>
            </div>
          )}

          {/* ===== TARİXÇƏ ===== */}
          {tab === 'history' && (
            <div>
              <div className="flex gap-1.5 overflow-x-auto pb-1 mb-2.5">
                <Chip active={historyCat === 'all'} onClick={() => setHistoryCat('all')}>
                  Hamısı
                </Chip>
                {CATEGORIES.map((c) => (
                  <Chip key={c.key} active={historyCat === c.key} onClick={() => setHistoryCat(c.key)}>
                    {c.short}
                  </Chip>
                ))}
              </div>

              {filteredHistory.length === 0 ? (
                <EmptyState title="Tarixçə boşdur" text="Tamamlanmış və ya bağlanmış sorğularınız burada görünəcək." />
              ) : (
                <div className="space-y-2.5">
                  {filteredHistory.map((req) => (
                    <HistoryCard
                      key={req.id}
                      req={req}
                      open={expandedId === req.id}
                      contact={contacts[req.id] ?? null}
                      onToggle={() => setExpandedId(expandedId === req.id ? null : req.id)}
                      onContact={(c) => setContacts((prev) => ({ ...prev, [req.id]: c }))}
                      onConfirm={(stars) => handleConfirm(req, stars)}
                      onFail={() => handleFail(req)}
                      onRepost={() => repost(req)}
                      onReport={(bid) =>
                        setReport({ storeId: bid.store_id, name: bid.store?.name ?? 'Mağaza', requestId: req.id })
                      }
                    />
                  ))}
                </div>
              )}
            </div>
          )}
        </>
      )}

      {report && (
        <ReportModal
          db={buyerDb}
          kind="store"
          storeId={report.storeId}
          requestId={report.requestId}
          targetName={report.name}
          onClose={() => setReport(null)}
        />
      )}

      {/* ===== ALT MENYU ===== */}
      <div className="fixed bottom-14 left-1/2 -translate-x-1/2 w-[90%] max-w-sm rounded-full bg-[#0B4635]/95 backdrop-blur-md shadow-2xl shadow-black/30 border border-white/10 py-2.5 px-6 flex justify-around items-center z-30">
        <button
          onClick={() => setTab('active')}
          className={`flex flex-col items-center gap-1 transition-all ${
            tab === 'active' ? 'text-[#FFC61A] font-bold scale-105' : 'text-white/60 hover:text-white'
          }`}
        >
          <div className="relative">
            <Activity className="w-5 h-5" />
            {activeRequests.length > 0 && (
              <span className="absolute -top-1 -right-2 bg-[#FFC61A] text-[#1B1B12] text-[9px] font-black w-3.5 h-3.5 rounded-full flex items-center justify-center">
                {activeRequests.length}
              </span>
            )}
          </div>
          <span className="text-[10px]">Aktiv</span>
        </button>

        <button onClick={() => setTab('create')} className="flex flex-col items-center transition-all">
          <div className="w-12 h-12 -mt-5 rounded-full flex items-center justify-center shadow-lg border-4 border-[#0B4635] bg-[#FFC61A]">
            <PlusCircle className="w-6 h-6 text-[#1B1B12]" />
          </div>
          <span className="text-[10px] font-bold text-white mt-0.5">Yeni sorğu</span>
        </button>

        <button
          onClick={() => setTab('history')}
          className={`flex flex-col items-center gap-1 transition-all ${
            tab === 'history' ? 'text-[#FFC61A] font-bold scale-105' : 'text-white/60 hover:text-white'
          }`}
        >
          <History className="w-5 h-5" />
          <span className="text-[10px]">Tarixçə</span>
        </button>
      </div>
    </div>
  );
}

/* ====================================================================== */
/* Sürücü bloku: ilk baxışda nə edəcəyini göstərir                         */
/* ====================================================================== */

function Hero({ compact, onPick }: { compact: boolean; onPick: (k: 'part' | 'service') => void }) {
  return (
    <section className="relative overflow-hidden rounded-3xl bg-[#0B4635] text-white mb-3.5">
      <div className="p-4 pb-5">
        {!compact && (
          <>
            <h1 className="font-display text-[26px] font-extrabold leading-[1.1]">Nə lazımdır?</h1>
            <p className="text-[13px] text-white/75 mt-1.5 max-w-[19rem]">
              Sorğunu göndər, mağaza və ustalar qiymət yazsın. Qeydiyyat yoxdur, nömrən gizli qalır.
            </p>
          </>
        )}
        <div className={`grid grid-cols-2 gap-2 ${compact ? '' : 'mt-3.5'}`}>
          <button
            type="button"
            onClick={() => onPick('part')}
            className="rounded-2xl bg-[#FFC61A] text-[#1B1B12] p-3 text-left active:scale-[0.98] transition-transform shadow-[0_3px_0_#C99700]"
          >
            <span className="text-xl leading-none">🔩</span>
            <span className="block font-display font-extrabold text-sm mt-1.5">Detal axtar</span>
            <span className="block text-[11px] text-[#1B1B12]/70">Ehtiyat hissəsi</span>
          </button>
          <button
            type="button"
            onClick={() => onPick('service')}
            className="rounded-2xl bg-white/10 border border-white/25 text-white p-3 text-left active:scale-[0.98] transition-transform"
          >
            <span className="text-xl leading-none">🔧</span>
            <span className="block font-display font-extrabold text-sm mt-1.5">Usta / servis tap</span>
            <span className="block text-[11px] text-white/65">Təmir, diaqnostika</span>
          </button>
        </div>
        {!compact && (
          <ol className="mt-4 flex items-start gap-2 text-[11px] text-white/80">
            {['Sorğunu göndər', 'Qiymətləri müqayisə et', 'Seç, WhatsApp-da yaz'].map((t, i) => (
              <li key={t} className="flex-1 flex items-start gap-1.5">
                <span className="font-display font-extrabold text-[#FFC61A] text-sm leading-none">{i + 1}</span>
                <span className="leading-tight">{t}</span>
              </li>
            ))}
          </ol>
        )}
      </div>
      <div className="road-dash" />
    </section>
  );
}

/* ====================================================================== */
/* Aktiv sorğu kartı                                                       */
/* ====================================================================== */

function ActiveCard({
  req,
  open,
  onToggle,
  onAccept,
  onCancel,
  onReport,
}: {
  req: BuyerRequest;
  open: boolean;
  onToggle: () => void;
  onAccept: (bid: BuyerBid) => Promise<void>;
  onCancel: () => Promise<void>;
  onReport: (bid: BuyerBid) => void;
}) {
  const [confirmBid, setConfirmBid] = useState<string | null>(null);
  const [confirmCancel, setConfirmCancel] = useState(false);
  const [busy, setBusy] = useState(false);

  const bids = req.bids.filter((b) => b.status === 'pending').sort((a, b) => a.price_azn - b.price_azn);
  const cheapest = bids.length > 0 ? bids[0].id : null;
  const reopened = req.deal_status === 'failed';

  const accept = async (bid: BuyerBid) => {
    setBusy(true);
    try {
      await onAccept(bid);
    } finally {
      setBusy(false);
      setConfirmBid(null);
    }
  };

  return (
    <div className="relative overflow-hidden rounded-2xl bg-white border border-slate-200/70 p-3.5 pt-4 shadow-[0_8px_22px_-16px_rgba(11,70,53,0.45)]">
      <TimeBar createdAt={req.created_at} expiresAt={req.expires_at} />
      <div className="flex items-start justify-between gap-2">
        <div className="min-w-0">
          <div className="flex items-center gap-1.5 flex-wrap">
            <span className="text-xs font-bold text-slate-800">
              {req.brand} {req.model} {req.year ?? ''}
            </span>
            <span className="text-[9px] bg-slate-100 text-slate-600 px-1.5 py-0.5 rounded font-medium">
              {requestCategoryLabel(req)}
            </span>
            {req.request_type === 'service' && (
              <span className="text-[9px] bg-indigo-50 text-indigo-700 px-1.5 py-0.5 rounded font-semibold">
                🔧 Xidmət{req.city ? ` · ${req.city}` : ''}{req.on_site ? ' · yerində' : ''}
              </span>
            )}
            {reopened && (
              <span className="text-[9px] bg-amber-50 text-amber-700 border border-amber-200 px-1.5 py-0.5 rounded font-semibold">
                Yenidən açılıb
              </span>
            )}
          </div>
          <p className="font-display text-base font-bold text-[#0B4635] mt-0.5 leading-snug">{req.part_name}</p>
        </div>
        <span className="text-[11px] font-mono font-bold text-[#0B4635] bg-emerald-50 border border-emerald-100 px-2 py-0.5 rounded-md whitespace-nowrap">
          {bids.length} təklif
        </span>
      </div>

      <PhotoStrip urls={req.part_images} />

      <div className="flex items-center gap-3 text-[11px] text-slate-500 mt-2 pt-2 border-t border-slate-100">
        <span>Büdcə: {req.budget_azn ? formatPrice(req.budget_azn) : 'Razılaşma'}</span>
        <span className="flex items-center gap-1 font-semibold text-[#9A5B00]">
          <Clock className="w-3 h-3" />
          <Countdown expiresAt={req.expires_at} />
        </span>
      </div>

      <button
        onClick={onToggle}
        className="w-full mt-2 pt-1.5 text-[11px] font-bold text-slate-500 hover:text-[#0B4635] text-center border-t border-slate-50"
      >
        {open ? 'Təklifləri bağla' : bids.length > 0 ? `Təklifləri gör (${bids.length})` : 'Təkliflər gözlənilir'}
      </button>

      {open && (
        <div className="space-y-2 mt-2 pt-2 border-t border-slate-100">
          {bids.length === 0 ? (
            <p className="text-[11px] text-slate-400 text-center py-2">
              Uyğun mağazalara bildiriş getdi. Təkliflər gələndə burada görünəcək.
            </p>
          ) : (
            bids.map((b) => (
              <div key={b.id} className="p-2.5 bg-slate-50 border border-slate-100 rounded-xl">
                <div className="flex items-start justify-between gap-2">
                  <StoreBadge store={b.store} />
                  <div className="text-right flex-shrink-0">
                    <div className="font-display text-lg font-extrabold text-[#0B4635] leading-none">
                      {b.price_type === 'from' && <span className="text-[10px] font-semibold text-slate-500">dən </span>}
                      {formatPrice(b.price_azn)}
                    </div>
                    {b.id === cheapest && bids.length > 1 && (
                      <span className="text-[9px] font-bold text-emerald-700 bg-emerald-100 px-1.5 py-0.5 rounded">
                        Ən ucuz
                      </span>
                    )}
                  </div>
                </div>
                <div className="text-[10px] text-slate-500 mt-1.5">
                  {req.request_type === 'service'
                    ? `${b.eta_hours ? `~${etaLabel(b.eta_hours)}` : 'Müddət razılaşma ilə'} · ${b.warranty || 'Zəmanətsiz'}`
                    : `${CONDITION_LABELS[b.condition] || b.condition} · ${b.warranty || 'Zəmanətsiz'}`}
                </div>
                <PhotoStrip urls={b.images} alt="Mağazanın şəkli" />
                {b.note && <div className="text-[11px] text-slate-600 mt-1">“{b.note}”</div>}
                <button type="button" onClick={() => onReport(b)} className="mt-1 text-[10px] text-slate-400 hover:text-rose-500">
                  Şikayət et
                </button>

                {confirmBid === b.id ? (
                  <div className="mt-2 flex items-center gap-2">
                    <button
                      onClick={() => setConfirmBid(null)}
                      className="flex-1 py-1.5 bg-slate-100 text-slate-600 text-[11px] font-bold rounded-lg"
                    >
                      Geri
                    </button>
                    <button
                      onClick={() => accept(b)}
                      disabled={busy}
                      className="flex-[2] py-1.5 bg-[#0B4635] text-white text-[11px] font-bold rounded-lg disabled:opacity-60"
                    >
                      {busy ? 'Seçilir…' : 'Bəli, bunu seçirəm'}
                    </button>
                  </div>
                ) : (
                  <button
                    onClick={() => setConfirmBid(b.id)}
                    className="mt-2 w-full py-2.5 bg-[#FFC61A] hover:bg-[#FFD24D] text-[#1B1B12] text-xs font-display font-extrabold rounded-lg transition-all active:scale-[0.98] shadow-[0_2px_0_#C99700]"
                  >
                    Seç və əlaqə qur
                  </button>
                )}
              </div>
            ))
          )}

          <div className="pt-1">
            {confirmCancel ? (
              <div className="flex items-center gap-2">
                <button
                  onClick={() => setConfirmCancel(false)}
                  className="flex-1 py-1.5 bg-slate-100 text-slate-600 text-[11px] font-bold rounded-lg"
                >
                  Saxla
                </button>
                <button
                  onClick={() => void onCancel()}
                  className="flex-1 py-1.5 bg-rose-50 border border-rose-200 text-rose-600 text-[11px] font-bold rounded-lg"
                >
                  Bəli, ləğv et
                </button>
              </div>
            ) : (
              <button
                onClick={() => setConfirmCancel(true)}
                className="w-full text-[11px] text-slate-400 hover:text-rose-500 py-1"
              >
                Sorğunu ləğv et
              </button>
            )}
          </div>
        </div>
      )}
    </div>
  );
}

/* ====================================================================== */
/* Tarixçə kartı                                                           */
/* ====================================================================== */

function HistoryCard({
  req,
  open,
  contact,
  onToggle,
  onContact,
  onConfirm,
  onFail,
  onRepost,
  onReport,
}: {
  req: BuyerRequest;
  open: boolean;
  contact: DealContact | null;
  onToggle: () => void;
  onContact: (c: DealContact) => void;
  onConfirm: (stars: number | null) => Promise<void>;
  onFail: () => Promise<void>;
  onRepost: () => void;
  onReport: (bid: BuyerBid) => void;
}) {
  const [mode, setMode] = useState<'idle' | 'rate' | 'fail'>('idle');
  const [stars, setStars] = useState(5);
  const [busy, setBusy] = useState(false);
  const [contactError, setContactError] = useState<string | null>(null);

  const acceptedBid = req.bids.find((b) => b.id === req.accepted_bid_id || b.status === 'accepted') ?? null;
  const completed = req.status === 'completed';
  const review = reviewOf(req);
  const confirmed = req.deal_status === 'confirmed';
  const pendingCount = req.bids.filter((b) => b.status === 'expired' || b.status === 'pending').length;

  useEffect(() => {
    if (!open || !completed || contact) return;
    let cancelled = false;
    api
      .getDealContact(req.id)
      .then((c) => {
        if (!cancelled) onContact(c);
      })
      .catch((e) => {
        if (!cancelled) setContactError(e instanceof Error ? e.message : 'Əlaqə məlumatı alınmadı.');
      });
    return () => {
      cancelled = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open, completed, contact, req.id]);

  const statusBadge =
    req.status === 'completed' ? (
      confirmed ? (
        <span className="text-[10px] px-2 py-0.5 rounded-full font-bold bg-emerald-50 text-emerald-700 border border-emerald-200">
          Razılaşdıq ✓
        </span>
      ) : (
        <span className="text-[10px] px-2 py-0.5 rounded-full font-bold bg-blue-50 text-blue-700 border border-blue-200">
          Satıcı seçildi
        </span>
      )
    ) : req.status === 'cancelled' ? (
      <span className="text-[10px] px-2 py-0.5 rounded-full font-bold bg-slate-100 text-slate-600">Ləğv edilib</span>
    ) : (
      <span className="text-[10px] px-2 py-0.5 rounded-full font-bold bg-slate-100 text-slate-600">Vaxtı bitib</span>
    );

  const run = async (fn: () => Promise<void>) => {
    setBusy(true);
    try {
      await fn();
    } finally {
      setBusy(false);
      setMode('idle');
    }
  };

  const price = contact?.price ?? acceptedBid?.price_azn ?? null;
  const storeName = contact?.store_name ?? acceptedBid?.store?.name ?? 'Seçilmiş mağaza';

  return (
    <div className="rounded-2xl bg-white border border-slate-100 p-3.5 shadow-xs">
      <button type="button" onClick={onToggle} className="w-full text-left">
        <div className="flex justify-between items-start gap-2">
          <div className="min-w-0">
            <p className="text-xs font-bold text-slate-700">
              {req.brand} {req.model} {req.year ?? ''}
            </p>
            <p className="text-xs font-semibold text-slate-900 mt-0.5">{req.part_name}</p>
            <p className="text-[10px] text-slate-400 mt-0.5">{formatTimeAgo(req.created_at)}</p>
          </div>
          <div className="flex flex-col items-end gap-1">
            {completed && price != null && <span className="font-bold text-xs text-[#0B4635]">{formatPrice(price)}</span>}
            {statusBadge}
          </div>
        </div>
      </button>

      {open && (
        <div className="mt-3 pt-2.5 border-t border-slate-100">
          {completed ? (
            <>
              <div className="flex items-center justify-between mb-2">
                <div>
                  <span className="text-[10px] text-slate-400 block">Mağaza</span>
                  <span className="text-xs font-bold text-slate-800">{storeName}</span>
                  {acceptedBid && (
                    <button type="button" onClick={() => onReport(acceptedBid)} className="ml-2 text-[10px] text-slate-400 hover:text-rose-500">
                      Şikayət et
                    </button>
                  )}
                </div>
                {review && <Stars value={review.stars} size="sm" />}
              </div>

              {contact ? (
                <div className="flex gap-2">
                  <a
                    href={whatsappUrl(contact.phone, contactText(req, contact.price))}
                    target="_blank"
                    rel="noreferrer"
                    className="flex-[2] py-2 bg-[#25D366] hover:bg-[#1fb857] text-white text-center text-[11px] font-bold rounded-lg flex items-center justify-center gap-1"
                  >
                    <MessageCircle className="w-3.5 h-3.5" /> WhatsApp-da yaz
                  </a>
                  <a
                    href={telUrl(contact.phone)}
                    className="flex-1 py-2 bg-slate-100 hover:bg-slate-200 text-slate-700 text-center text-[11px] font-bold rounded-lg flex items-center justify-center gap-1"
                  >
                    <Phone className="w-3.5 h-3.5" /> Zəng
                  </a>
                </div>
              ) : contactError ? (
                <p className="text-[11px] text-rose-600">{contactError}</p>
              ) : (
                <p className="text-[11px] text-slate-400">Əlaqə məlumatı yüklənir…</p>
              )}

              {!confirmed && mode === 'idle' && (
                <div className="flex gap-2 mt-2">
                  <button
                    onClick={() => setMode('rate')}
                    className="flex-1 py-2 bg-emerald-50 hover:bg-emerald-100 text-emerald-700 border border-emerald-200 text-[11px] font-bold rounded-lg flex items-center justify-center gap-1"
                  >
                    <CheckCircle2 className="w-3.5 h-3.5" /> Razılaşdıq
                  </button>
                  <button
                    onClick={() => setMode('fail')}
                    className="flex-1 py-2 bg-amber-50 hover:bg-amber-100 text-[#9A5B00] border border-amber-200 text-[11px] font-bold rounded-lg"
                  >
                    Razılaşma alınmadı
                  </button>
                </div>
              )}

              {!confirmed && mode === 'rate' && (
                <div className="mt-2 p-3 rounded-xl bg-slate-50 border border-slate-100 text-center">
                  <p className="text-[11px] font-semibold text-slate-700 mb-1">Mağazanı qiymətləndirin</p>
                  <div className="flex justify-center">
                    <Stars value={stars} onChange={setStars} size="lg" />
                  </div>
                  <div className="flex gap-2 mt-2">
                    <button
                      disabled={busy}
                      onClick={() => void run(() => onConfirm(null))}
                      className="flex-1 py-1.5 bg-slate-100 text-slate-600 text-[11px] font-bold rounded-lg"
                    >
                      Qiymətsiz təsdiqlə
                    </button>
                    <button
                      disabled={busy}
                      onClick={() => void run(() => onConfirm(stars))}
                      className="flex-1 py-1.5 bg-[#0B4635] text-white text-[11px] font-bold rounded-lg"
                    >
                      Təsdiqlə
                    </button>
                  </div>
                </div>
              )}

              {!confirmed && mode === 'fail' && (
                <div className="mt-2 p-3 rounded-xl bg-amber-50 border border-amber-100">
                  <p className="text-[11px] text-slate-700">
                    Sorğunuz yenidən açılacaq və digər təkliflər yenidən seçimə qayıdacaq. Davam edək?
                  </p>
                  <div className="flex gap-2 mt-2">
                    <button
                      onClick={() => setMode('idle')}
                      className="flex-1 py-1.5 bg-white border border-slate-200 text-slate-600 text-[11px] font-bold rounded-lg"
                    >
                      Geri
                    </button>
                    <button
                      disabled={busy}
                      onClick={() => void run(onFail)}
                      className="flex-1 py-1.5 bg-[#FFC61A] text-[#1B1B12] text-[11px] font-bold rounded-lg"
                    >
                      Bəli, yenidən aç
                    </button>
                  </div>
                </div>
              )}

              {confirmed && !review && (
                <div className="mt-2 p-3 rounded-xl bg-slate-50 border border-slate-100 text-center">
                  <p className="text-[11px] font-semibold text-slate-700 mb-1">Mağazanı qiymətləndirmək istəyirsiniz?</p>
                  <div className="flex justify-center">
                    <Stars value={stars} onChange={setStars} size="lg" />
                  </div>
                  <button
                    disabled={busy}
                    onClick={() => void run(() => onConfirm(stars))}
                    className="mt-2 w-full py-1.5 bg-[#0B4635] text-white text-[11px] font-bold rounded-lg"
                  >
                    Qiymət ver
                  </button>
                </div>
              )}
            </>
          ) : (
            <>
              <p className="text-[11px] text-slate-500">
                {req.status === 'expired'
                  ? pendingCount > 0
                    ? `Müddət bitdi, ${pendingCount} təklif seçilməmiş qaldı.`
                    : 'Müddət bitdi, təklif gəlmədi.'
                  : 'Bu sorğu ləğv edilib.'}
              </p>
              <button
                onClick={onRepost}
                className="mt-2 w-full py-2 bg-[#0B4635] text-white text-[11px] font-bold rounded-lg flex items-center justify-center gap-1"
              >
                <RotateCcw className="w-3.5 h-3.5" /> Yenidən göndər
              </button>
            </>
          )}
        </div>
      )}
    </div>
  );
}
