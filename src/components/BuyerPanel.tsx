import { useCallback, useEffect, useMemo, useState } from 'react';
import { Activity, History, Plus } from 'lucide-react';
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

const inputCls = 'input';

/** İki-üç seçimli düymə sırası (sürüşdürmə yoxdur, hamısı ekranda görünür) */
function Seg<T extends string>({
  value,
  options,
  onChange,
}: {
  value: T;
  options: { key: T; label: string }[];
  onChange: (k: T) => void;
}) {
  return (
    <div className="flex gap-1 rounded-2xl bg-[#E3EAE4] p-1">
      {options.map((o) => (
        <button
          key={o.key}
          type="button"
          onClick={() => onChange(o.key)}
          aria-pressed={value === o.key}
          className={`flex-1 py-2.5 rounded-xl text-xs font-display font-bold transition ${
            value === o.key ? 'bg-white text-[#0B4635] shadow-sm' : 'text-slate-500'
          }`}
        >
          {o.label}
        </button>
      ))}
    </div>
  );
}

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

  const [historyType, setHistoryType] = useState<'all' | 'part' | 'service'>('all');
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
  const filteredHistory = historyRequests.filter((r) => {
    const isSvc = r.request_type === 'service';
    if (historyType === 'part' && isSvc) return false;
    if (historyType === 'service' && !isSvc) return false;
    if (historyCat === 'all') return true;
    return isSvc ? r.category === historyCat : categoryKey(r.category) === historyCat;
  });
  const hasSvcHistory = historyRequests.some((r) => r.request_type === 'service');
  const hasPartHistory = historyRequests.some((r) => r.request_type !== 'service');
  const historyChips = historyType === 'service' ? SERVICE_CATEGORIES : historyType === 'part' ? CATEGORIES : [];

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
      showToast({ title: 'Sorğu göndərildi', body: 'Təkliflər burada görünəcək.', type: 'success' });
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
      showToast({ title: 'Təklif seçildi', body: 'Nömrə açıldı, tarixçədən yazın.', type: 'win' });
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
      showToast({ title: 'Razılaşma alınmadı', body: 'Sorğu yenidən aktivdir.', type: 'info' });
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
        <div className="card text-center">
          <p className="font-display text-sm font-extrabold text-rose-600">Sessiya açılmadı</p>
          <p className="text-[13px] text-slate-500 mt-1">{error}</p>
          <button type="button" onClick={onRetry} className="btn-primary mt-4">
            Yenidən cəhd et
          </button>
        </div>
      </div>
    );
  }

  return (
    <div className="text-slate-800 pb-44 pt-1 px-3 max-w-md mx-auto">
      {!ready || loading ? (
        <div className="space-y-3">
          {[1, 2].map((i) => (
            <div key={i} className="skeleton h-28" />
          ))}
        </div>
      ) : (
        <>
          {loadError && <div className="mb-3 rounded-2xl bg-amber-50 p-3 text-[13px] text-amber-800">{loadError}</div>}

          {/* ===== AKTİV ===== */}
          {tab === 'active' && (
            <div className="rise">
              {activeRequests.length === 0 ? (
                <EmptyState
                  title="Aktiv sorğunuz yoxdur"
                  text="Detal və ya usta üçün sorğu göndərin, qiymətlər burada görünəcək."
                  action={{ label: 'Yeni sorğu', onClick: () => setTab('create') }}
                />
              ) : (
                <div className="space-y-3">
                  <h2 className="font-display text-xl font-extrabold text-[#0B4635] px-1">
                    Aktiv sorğular
                  </h2>
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
            <div className="rise">
              <h2 className="font-display text-xl font-extrabold text-[#0B4635] px-1 mb-3">Nə lazımdır?</h2>
              <div className="card space-y-3.5">
                <Seg
                  value={kind}
                  onChange={setKind}
                  options={[
                    { key: 'part', label: 'Detal' },
                    { key: 'service', label: 'Usta / servis' },
                  ]}
                />

                <div className="grid grid-cols-2 gap-2.5">
                  <div>
                    <label className="label">Marka *</label>
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
                    <label className="label">Model *</label>
                    <input
                      type="text"
                      placeholder="F10, Camry"
                      value={model}
                      onChange={(e) => setModel(e.target.value)}
                      className={inputCls}
                    />
                  </div>
                </div>

                <div className={`grid ${kind === 'part' ? 'grid-cols-2' : 'grid-cols-1'} gap-2.5`}>
                  <div>
                    <label className="label">İl</label>
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
                      <label className="label">VIN (könüllü)</label>
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
                    <div>
                      <label className="label">Kateqoriya (könüllü)</label>
                      <div className="chips">
                        {CATEGORIES.map((c) => (
                          <Chip key={c.key} active={category === c.key} onClick={() => setCategory(category === c.key ? null : c.key)}>
                            {c.short}
                          </Chip>
                        ))}
                      </div>
                    </div>
                    <div>
                      <label className="label">Detalın adı *</label>
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
                    <div>
                      <label className="label">Hansı xidmət? *</label>
                      <div className="chips">
                        {SERVICE_CATEGORIES.map((c) => (
                          <Chip key={c.key} active={svcCategory === c.key} onClick={() => setSvcCategory(svcCategory === c.key ? null : c.key)}>
                            {c.short}
                          </Chip>
                        ))}
                      </div>
                    </div>
                    <div>
                      <label className="label">Nə lazımdır? *</label>
                      <input
                        type="text"
                        placeholder="Məs: motor səs edir, diaqnostika"
                        value={partName}
                        maxLength={120}
                        onChange={(e) => setPartName(e.target.value)}
                        className={inputCls}
                      />
                    </div>
                    <div className="grid grid-cols-2 gap-2.5">
                      <div>
                        <label className="label">Şəhər *</label>
                        <select value={city} onChange={(e) => setCity(e.target.value)} className={inputCls}>
                          {CITIES.map((c) => (
                            <option key={c} value={c}>
                              {c}
                            </option>
                          ))}
                        </select>
                      </div>
                      <div>
                        <label className="label">Rayon</label>
                        <input
                          type="text"
                          placeholder="Nəsimi"
                          value={area}
                          maxLength={40}
                          onChange={(e) => setArea(e.target.value)}
                          className={inputCls}
                        />
                      </div>
                    </div>
                    <div>
                      <label className="label">Kim baxsın?</label>
                      <div className="chips">
                        {PROVIDER_PREFS.map((p) => (
                          <Chip key={p.key} active={providerPref === p.key} onClick={() => setProviderPref(p.key)}>
                            {p.label}
                          </Chip>
                        ))}
                      </div>
                    </div>
                    <label className="flex items-center gap-2.5 text-[13px] text-slate-700 cursor-pointer">
                      <input
                        type="checkbox"
                        checked={onSite}
                        onChange={(e) => setOnSite(e.target.checked)}
                        className="h-5 w-5 accent-[#0B4635]"
                      />
                      Usta mənim yanıma gəlsin
                    </label>
                  </>
                )}

                <ImagePicker
                  db={buyerDb}
                  userId={userId}
                  urls={images}
                  onChange={setImages}
                  onBusy={setUploading}
                  hint="Şəkil (ən çox 3, könüllü)"
                />

                <div>
                  <label className="label">Nə qədər tez?</label>
                  <Seg
                    value={urgency}
                    onChange={setUrgency}
                    options={(Object.keys(URGENCY_CONFIG) as Urgency[]).map((k) => ({
                      key: k,
                      label: URGENCY_CONFIG[k].shortLabel,
                    }))}
                  />
                </div>

                <div>
                  <label className="label">Büdcə, AZN (könüllü)</label>
                  <input
                    type="number"
                    inputMode="decimal"
                    placeholder="Razılaşma ilə"
                    value={budget}
                    onChange={(e) => setBudget(e.target.value)}
                    className={inputCls}
                  />
                </div>

                {formError && <div className="rounded-2xl bg-rose-50 px-3.5 py-2.5 text-[13px] text-rose-700">{formError}</div>}

                <div>
                  <button type="button" onClick={handleCreate} disabled={submitting || uploading} className="btn-cta w-full text-sm">
                    {submitting ? 'Göndərilir…' : 'Sorğunu göndər'}
                  </button>
                  <p className="text-xs text-slate-400 text-center mt-2.5">Nömrəniz yalnız seçdiyiniz mağazaya açılır.</p>
                </div>
              </div>
            </div>
          )}

          {/* ===== TARİXÇƏ ===== */}
          {tab === 'history' && (
            <div className="rise">
              <h2 className="font-display text-xl font-extrabold text-[#0B4635] px-1 mb-3">Tarixçə</h2>
              {(hasSvcHistory && hasPartHistory) || historyType !== 'all' ? (
                <div className="chips mb-2">
                  {(
                    [
                      ['all', 'Hamısı'],
                      ['part', 'Detal'],
                      ['service', 'Xidmət'],
                    ] as const
                  ).map(([k, label]) => (
                    <Chip
                      key={k}
                      active={historyType === k}
                      onClick={() => {
                        setHistoryType(k);
                        setHistoryCat('all');
                      }}
                    >
                      {label}
                    </Chip>
                  ))}
                </div>
              ) : null}
              {historyChips.length > 0 && (
                <div className="chips mb-3">
                  <Chip active={historyCat === 'all'} onClick={() => setHistoryCat('all')}>
                    Bütün növlər
                  </Chip>
                  {historyChips.map((c) => (
                    <Chip key={c.key} active={historyCat === c.key} onClick={() => setHistoryCat(c.key)}>
                      {c.short}
                    </Chip>
                  ))}
                </div>
              )}

              {filteredHistory.length === 0 ? (
                <EmptyState title="Tarixçə boşdur" text="Bağlanmış sorğularınız burada görünəcək." />
              ) : (
                <div className="space-y-3">
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
      <div className="dock glass">
        <button className="dock-item" aria-current={tab === 'active'} onClick={() => setTab('active')}>
          <div className="relative">
            <Activity className="w-5 h-5" />
            {activeRequests.length > 0 && (
              <span className="absolute -top-1.5 -right-3 bg-[#FFC61A] text-[#0F2A21] text-[10px] font-black min-w-[16px] h-4 px-1 rounded-full flex items-center justify-center">
                {activeRequests.length}
              </span>
            )}
          </div>
          Aktiv
        </button>

        <button
          onClick={() => setTab('create')}
          aria-current={tab === 'create'}
          className="btn-cta !rounded-[22px] !py-3 px-5 mx-1 flex items-center gap-1.5 text-xs"
        >
          <Plus className="w-4 h-4" strokeWidth={3} />
          Yeni sorğu
        </button>

        <button className="dock-item" aria-current={tab === 'history'} onClick={() => setTab('history')}>
          <History className="w-5 h-5" />
          Tarixçə
        </button>
      </div>
    </div>
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
  const failedBefore = req.deal_status === 'failed';
  const sealed = !!req.sealed;

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
    <div className="card pt-5">
      <TimeBar createdAt={req.created_at} expiresAt={req.expires_at} />
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <div className="flex items-center gap-1.5 flex-wrap">
            <span className="text-xs font-bold text-slate-500">
              {req.brand} {req.model} {req.year ?? ''}
            </span>
            <span className="tag">{requestCategoryLabel(req)}</span>
            {req.request_type === 'service' && (
              <span className="tag-blue">
                {req.city ?? 'Xidmət'}
                {req.on_site ? ', yerində' : ''}
              </span>
            )}
          </div>
          <p className="font-display text-lg font-extrabold text-[#0B4635] mt-1 leading-tight">{req.part_name}</p>
        </div>
        <div className="text-right flex-shrink-0">
          <div className="font-display text-2xl font-extrabold text-[#0B4635] leading-none">{bids.length}</div>
          <div className="text-[11px] text-slate-500 mt-1">təklif</div>
        </div>
      </div>

      {failedBefore && (
        <p className="mt-2.5 rounded-2xl bg-amber-50 px-3 py-2 text-xs text-amber-900">
          {sealed
            ? 'Razılaşma alınmadı. Əvvəl təklif verən mağazalar arasından seçin.'
            : 'Razılaşma alınmadı. Sorğu yenidən bütün mağazalara açıldı.'}
        </p>
      )}

      <PhotoStrip urls={req.part_images} />

      <div className="flex items-center justify-between text-xs text-slate-500 mt-3">
        <span>Büdcə: {req.budget_azn ? formatPrice(req.budget_azn) : 'razılaşma ilə'}</span>
        <span className="font-semibold text-[#9A5B00]">
          <Countdown expiresAt={req.expires_at} /> qalıb
        </span>
      </div>

      <button onClick={onToggle} className="btn-soft w-full mt-3">
        {open ? 'Bağla' : bids.length > 0 ? `Təklifləri gör (${bids.length})` : 'Təkliflər gözlənilir'}
      </button>

      {open && (
        <div className="space-y-2.5 mt-3">
          {bids.length === 0 ? (
            <p className="text-[13px] text-slate-400 text-center py-2">Təklif gələndə burada görünəcək.</p>
          ) : (
            bids.map((b) => (
              <div key={b.id} className="card-flat !p-3.5">
                <div className="flex items-start justify-between gap-3">
                  <StoreBadge store={b.store} />
                  <div className="text-right flex-shrink-0">
                    <div className="font-display text-xl font-extrabold text-[#0B4635] leading-none">
                      {b.price_type === 'from' && <span className="text-[11px] font-semibold text-slate-500">dən </span>}
                      {formatPrice(b.price_azn)}
                    </div>
                    {b.id === cheapest && bids.length > 1 && <span className="tag-green mt-1.5">Ən ucuz</span>}
                  </div>
                </div>
                <div className="text-xs text-slate-500 mt-2">
                  {req.request_type === 'service'
                    ? `${b.eta_hours ? `~${etaLabel(b.eta_hours)}` : 'Müddət razılaşma ilə'}, ${b.warranty || 'zəmanətsiz'}`
                    : `${CONDITION_LABELS[b.condition] || b.condition}, ${b.warranty || 'zəmanətsiz'}`}
                </div>
                <PhotoStrip urls={b.images} alt="Mağazanın şəkli" />
                {b.note && <div className="text-[13px] text-slate-700 mt-1.5">“{b.note}”</div>}

                {confirmBid === b.id ? (
                  <div className="mt-3 flex items-center gap-2">
                    <button onClick={() => setConfirmBid(null)} className="btn-ghost flex-1">
                      Geri
                    </button>
                    <button onClick={() => accept(b)} disabled={busy} className="btn-primary flex-[2]">
                      {busy ? 'Seçilir…' : 'Bəli, bunu seçirəm'}
                    </button>
                  </div>
                ) : (
                  <div className="mt-3 flex items-center gap-2">
                    <button onClick={() => setConfirmBid(b.id)} className="btn-cta flex-1">
                      Seç
                    </button>
                    <button type="button" onClick={() => onReport(b)} className="btn-ghost !py-3 !text-rose-600">
                      Şikayət et
                    </button>
                  </div>
                )}
              </div>
            ))
          )}

          <div className="pt-1">
            {confirmCancel ? (
              <div className="flex items-center gap-2">
                <button onClick={() => setConfirmCancel(false)} className="btn-ghost flex-1">
                  Saxla
                </button>
                <button onClick={() => void onCancel()} className="btn-danger flex-1">
                  Bəli, ləğv et
                </button>
              </div>
            ) : (
              <button onClick={() => setConfirmCancel(true)} className="w-full text-[13px] text-slate-400 hover:text-rose-500 py-1.5">
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
  const othersCount = req.bids.filter((b) => b.status === 'rejected' && b.deal_status !== 'failed' && b.id !== acceptedBid?.id).length;

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
        <span className="tag-green">Razılaşdıq</span>
      ) : (
        <span className="tag-blue">Satıcı seçildi</span>
      )
    ) : req.status === 'cancelled' ? (
      <span className="tag">Ləğv edilib</span>
    ) : (
      <span className="tag">Vaxtı bitib</span>
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
    <div className="card">
      <button type="button" onClick={onToggle} className="w-full text-left">
        <div className="flex justify-between items-start gap-3">
          <div className="min-w-0">
            <p className="text-xs font-bold text-slate-500">
              {req.brand} {req.model} {req.year ?? ''}
            </p>
            <p className="font-display text-sm font-extrabold text-slate-900 mt-0.5 leading-snug">{req.part_name}</p>
            <p className="text-xs text-slate-400 mt-1">
              {formatTimeAgo(req.created_at)}
              {req.request_type === 'service' ? ', xidmət' : ''}
            </p>
          </div>
          <div className="flex flex-col items-end gap-1.5 flex-shrink-0">
            {completed && price != null && (
              <span className="font-display text-base font-extrabold text-[#0B4635] leading-none">{formatPrice(price)}</span>
            )}
            {statusBadge}
          </div>
        </div>
      </button>

      {open && (
        <div className="mt-3.5 pt-3.5 border-t border-black/5">
          {completed ? (
            <>
              <div className="flex items-center justify-between mb-3">
                <div className="min-w-0">
                  <span className="text-xs text-slate-400 block">Mağaza</span>
                  <span className="text-[13px] font-bold text-slate-900">{storeName}</span>
                </div>
                {review && <Stars value={review.stars} size="sm" />}
              </div>

              {contact ? (
                <div className="flex gap-2">
                  <a
                    href={whatsappUrl(contact.phone, contactText(req, contact.price))}
                    target="_blank"
                    rel="noreferrer"
                    className="btn flex-[2] py-3 text-[13px] bg-[#25D366] text-white text-center shadow-[0_10px_20px_-10px_rgba(37,211,102,0.9)]"
                  >
                    WhatsApp-da yaz
                  </a>
                  <a href={telUrl(contact.phone)} className="btn-ghost flex-1 !py-3">
                    Zəng
                  </a>
                </div>
              ) : contactError ? (
                <p className="text-[13px] text-rose-600">{contactError}</p>
              ) : (
                <p className="text-[13px] text-slate-400">Əlaqə məlumatı yüklənir…</p>
              )}

              {acceptedBid && (
                <button type="button" onClick={() => onReport(acceptedBid)} className="btn-ghost !text-rose-600 w-full mt-2">
                  Mağaza barədə şikayət et
                </button>
              )}

              {!confirmed && mode === 'idle' && (
                <div className="flex gap-2 mt-2.5">
                  <button onClick={() => setMode('rate')} className="btn-soft flex-1">
                    Razılaşdıq
                  </button>
                  <button onClick={() => setMode('fail')} className="btn-ghost flex-1">
                    Razılaşma alınmadı
                  </button>
                </div>
              )}

              {!confirmed && mode === 'rate' && (
                <div className="mt-3 card-flat text-center">
                  <p className="text-[13px] font-semibold text-slate-700 mb-1.5">Mağazanı qiymətləndirin</p>
                  <div className="flex justify-center">
                    <Stars value={stars} onChange={setStars} size="lg" />
                  </div>
                  <div className="flex gap-2 mt-3">
                    <button disabled={busy} onClick={() => void run(() => onConfirm(null))} className="btn-ghost flex-1">
                      Qiymətsiz
                    </button>
                    <button disabled={busy} onClick={() => void run(() => onConfirm(stars))} className="btn-primary flex-1">
                      Təsdiqlə
                    </button>
                  </div>
                </div>
              )}

              {!confirmed && mode === 'fail' && (
                <div className="mt-3 rounded-2xl bg-amber-50 p-3.5">
                  <p className="text-[13px] text-slate-800">
                    {othersCount > 0
                      ? 'Sorğu əvvəl təklif verən digər mağazalara qayıdacaq. Onlardan seçə bilərsiniz.'
                      : 'Başqa təklif yoxdur. Sorğu yenidən bütün mağazalara açılacaq.'}
                  </p>
                  <div className="flex gap-2 mt-3">
                    <button onClick={() => setMode('idle')} className="btn-ghost flex-1 !bg-white">
                      Geri
                    </button>
                    <button disabled={busy} onClick={() => void run(onFail)} className="btn-cta flex-1 !py-2.5 text-xs">
                      Davam et
                    </button>
                  </div>
                </div>
              )}

              {confirmed && !review && (
                <div className="mt-3 card-flat text-center">
                  <p className="text-[13px] font-semibold text-slate-700 mb-1.5">Mağazanı qiymətləndirin</p>
                  <div className="flex justify-center">
                    <Stars value={stars} onChange={setStars} size="lg" />
                  </div>
                  <button disabled={busy} onClick={() => void run(() => onConfirm(stars))} className="btn-primary mt-3 w-full">
                    Qiymət ver
                  </button>
                </div>
              )}
            </>
          ) : (
            <>
              <p className="text-[13px] text-slate-500">
                {req.status === 'expired'
                  ? pendingCount > 0
                    ? `Müddət bitdi, ${pendingCount} təklif seçilməmiş qaldı.`
                    : 'Müddət bitdi, təklif gəlmədi.'
                  : 'Bu sorğu ləğv edilib.'}
              </p>
              <button onClick={onRepost} className="btn-primary mt-3 w-full">
                Yenidən göndər
              </button>
            </>
          )}
        </div>
      )}
    </div>
  );
}
