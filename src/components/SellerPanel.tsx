import { useCallback, useEffect, useMemo, useState } from 'react';
import { BarChart3, Clock, Inbox, ListChecks, Archive, Coins, Crown, Wallet } from 'lucide-react';
import {
  CATEGORIES,
  CONDITION_LABELS,
  SERVICE_CATEGORIES,
  URGENCY_CONFIG,
  WARRANTY_OPTIONS,
  categoryKey,
  requestCategoryLabel,
  sellerDb,
} from '@/lib/supabase';
import * as api from '@/lib/api';
import { useSeller } from '@/lib/auth';
import {
  ETA_OPTIONS,
  PLAN_LABELS,
  displayBidFee,
  effectivePlan,
  etaLabel,
  formatCoin,
  formatPrice,
  formatTimeAgo,
  showToast,
} from '@/lib/utils';
import { noteProblem } from '@/lib/validate';
import type { AppTexts, ClosedFeedItem, Condition, MyBid, PriceType, SellerFeedItem } from '@/lib/types';
import { Chip, Countdown, EmptyState, ImagePicker, PhotoStrip, TimeBar, useTick } from '@/components/ui';
import { AccountTab, InsightsView } from '@/components/Billing';
import { ReportModal } from '@/components/Report';

type Tab = 'feed' | 'bids' | 'closed' | 'stats' | 'account';

const inputCls =
  'w-full bg-slate-50 border border-slate-200 rounded-lg px-2.5 py-2 text-xs text-slate-800 focus:outline-none focus:border-[#0B4635]';

export function SellerPanel() {
  const { store, refresh, userId } = useSeller();
  const [tab, setTab] = useState<Tab>('feed');
  const [feed, setFeed] = useState<SellerFeedItem[]>([]);
  const [closed, setClosed] = useState<ClosedFeedItem[]>([]);
  const [myBids, setMyBids] = useState<MyBid[]>([]);
  const [texts, setTexts] = useState<AppTexts>({});
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [cat, setCat] = useState<string>('all');
  const [typeFilter, setTypeFilter] = useState<'all' | 'part' | 'service'>('all');
  const [openId, setOpenId] = useState<string | null>(null);
  const [report, setReport] = useState<SellerFeedItem | null>(null);

  useTick(30000);

  const storeId = store?.id ?? null;

  const loadFeed = useCallback(async () => {
    try {
      const rows = await api.sellerFeed();
      setFeed(rows);
      setLoadError(null);
    } catch (e) {
      setLoadError(e instanceof Error ? e.message : 'Sorğular yüklənmədi.');
    } finally {
      setLoading(false);
    }
  }, []);

  const loadBids = useCallback(async () => {
    try {
      setMyBids(await api.sellerMyBids());
    } catch (e) {
      setLoadError(e instanceof Error ? e.message : 'Təkliflər yüklənmədi.');
    }
  }, []);

  const loadClosed = useCallback(async () => {
    try {
      setClosed(await api.sellerClosedFeed());
    } catch (e) {
      setLoadError(e instanceof Error ? e.message : 'Arxiv yüklənmədi.');
    }
  }, []);

  const loadAll = useCallback(async () => {
    await Promise.all([loadFeed(), loadBids()]);
  }, [loadFeed, loadBids]);

  useEffect(() => {
    if (!storeId) return;
    void loadAll();
    let t: ReturnType<typeof setTimeout> | undefined;
    const debounced = () => {
      if (t) clearTimeout(t);
      t = setTimeout(() => void loadAll(), 500);
    };
    const channel = sellerDb
      .channel(`seller-sync-${storeId}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'requests' }, debounced)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'bids' }, debounced)
      .subscribe();
    const poll = setInterval(() => void loadAll(), 30000);
    return () => {
      if (t) clearTimeout(t);
      clearInterval(poll);
      void sellerDb.removeChannel(channel);
    };
  }, [storeId, loadAll]);

  useEffect(() => {
    if (!storeId) return;
    if (tab === 'closed') void loadClosed();
    if (tab === 'stats') void loadBids();
  }, [tab, storeId, loadClosed, loadBids]);

  useEffect(() => {
    if (!storeId) return;
    api.getAppTexts().then(setTexts).catch(() => undefined);
  }, [storeId]);

  const liveFeed = feed.filter((r) => new Date(r.expires_at).getTime() > Date.now());
  const hasBothTypes = liveFeed.some((r) => r.request_type === 'service') && liveFeed.some((r) => r.request_type !== 'service');
  const visibleFeed = liveFeed.filter((r) => {
    if (typeFilter !== 'all' && (r.request_type === 'service' ? 'service' : 'part') !== typeFilter) return false;
    if (cat === 'all') return true;
    return r.request_type === 'service' ? r.category === cat : categoryKey(r.category) === cat;
  });
  const chipCats = typeFilter === 'service' ? SERVICE_CATEGORIES : typeFilter === 'part' ? CATEGORIES : [];
  const setType = (t: 'all' | 'part' | 'service') => {
    setTypeFilter(t);
    setCat('all');
  };
  const balance = Number(store?.coin_balance ?? 0);
  const plan = effectivePlan(store);
  const fee = displayBidFee(plan);

  const pendingBids = myBids.filter((b) => b.bid_status === 'pending' && b.request_status === 'active');

  if (!store) return null;

  return (
    <div className="text-slate-800 pb-36 pt-2.5 px-3 max-w-md mx-auto">
      {/* Balans */}
      <button
        type="button"
        onClick={() => setTab('account')}
        className="relative overflow-hidden w-full text-left rounded-2xl bg-[#0B4635] text-white p-3.5 pb-4 mb-3 flex items-center justify-between"
      >
        <div>
          <div className="text-[10px] uppercase tracking-wider text-white/60 font-semibold flex items-center gap-1">
            Coin balansı
            {plan !== 'free' && (
              <span className="inline-flex items-center gap-0.5 text-amber-300 normal-case tracking-normal">
                <Crown className="w-3 h-3" /> {PLAN_LABELS[plan]}
              </span>
            )}
          </div>
          <div className="font-display text-3xl font-extrabold flex items-center gap-2 mt-1 leading-none">
            <Coins className="w-6 h-6 text-[#FFC61A]" /> {formatCoin(balance)}
          </div>
        </div>
        <div className="text-right text-[10px] text-white/70 leading-snug">
          Təklif: {fee === 0 ? 'pulsuz' : `−${formatCoin(fee)} coin`}
          <br />
          Satış: +5 coin bonus
          <br />
          {balance < 1 && fee > 0 ? <span className="text-[#FFC61A] font-bold">Coin al</span> : 'Seçilməsə, coin qayıdır'}
        </div>
        <div className="road-dash absolute inset-x-0 bottom-0" />
      </button>

      {loadError && (
        <div className="mb-2 rounded-xl bg-amber-50 border border-amber-200 p-2.5 text-[11px] text-amber-800">
          {loadError}
        </div>
      )}

      {/* ===== LENT ===== */}
      {tab === 'feed' && (
        <div>
          {(hasBothTypes || typeFilter !== 'all') && (
            <div className="flex gap-1.5 mb-2">
              <Chip tone="orange" active={typeFilter === 'all'} onClick={() => setType('all')}>
                Hamısı ({liveFeed.length})
              </Chip>
              <Chip tone="orange" active={typeFilter === 'part'} onClick={() => setType('part')}>
                🔩 Detal
              </Chip>
              <Chip tone="orange" active={typeFilter === 'service'} onClick={() => setType('service')}>
                🔧 Xidmət
              </Chip>
            </div>
          )}
          {chipCats.length > 0 && (
            <div className="flex gap-1.5 overflow-x-auto pb-1 mb-2.5">
              <Chip tone="orange" active={cat === 'all'} onClick={() => setCat('all')}>
                Hamısı
              </Chip>
              {chipCats.map((c) => (
                <Chip tone="orange" key={c.key} active={cat === c.key} onClick={() => setCat(c.key)}>
                  {c.icon} {c.short}
                </Chip>
              ))}
            </div>
          )}

          {loading ? (
            <div className="space-y-2.5">
              {[1, 2].map((i) => (
                <div key={i} className="rounded-2xl bg-white border border-slate-100 h-28 animate-pulse" />
              ))}
            </div>
          ) : visibleFeed.length === 0 ? (
            <EmptyState
              title="Hazırda uyğun sorğu yoxdur"
              text="Yeni sorğu gələndə bildiriş alacaqsınız. Mağaza profilinizdə marka və kateqoriyaları yoxlayın."
            />
          ) : (
            <div className="space-y-2.5">
              {visibleFeed.map((r) => (
                <FeedCard
                  key={r.id}
                  item={r}
                  open={openId === r.id}
                  balance={balance}
                  fee={fee}
                  userId={userId}
                  onReport={() => setReport(r)}
                  onToggle={() => setOpenId(openId === r.id ? null : r.id)}
                  onDone={async () => {
                    setOpenId(null);
                    await Promise.all([loadAll(), refresh()]);
                  }}
                />
              ))}
            </div>
          )}
        </div>
      )}

      {/* ===== MƏNİM TƏKLİFLƏRİM ===== */}
      {tab === 'bids' && (
        <div>
          {myBids.length === 0 ? (
            <EmptyState title="Hələ təklifiniz yoxdur" text="Lentdən sorğu seçib qiymət verin." />
          ) : (
            <div className="space-y-2.5">
              {pendingBids.length > 0 && (
                <div className="text-[11px] font-bold text-slate-500 uppercase tracking-wider px-1">
                  Cavab gözləyən: {pendingBids.length}
                </div>
              )}
              {myBids.map((b) => (
                <MyBidCard key={b.bid_id} bid={b} />
              ))}
            </div>
          )}
        </div>
      )}

      {/* ===== ARXİV ===== */}
      {tab === 'closed' && (
        <div>
          <p className="text-[11px] text-slate-500 px-1 mb-2">
            Bağlanmış sorğular və satış qiymətləri — bazarı izləmək üçün. Alıcı məlumatları göstərilmir.
          </p>
          {closed.length === 0 ? (
            <EmptyState title="Arxiv boşdur" />
          ) : (
            <div className="space-y-2">
              {closed.map((c) => (
                <div key={c.id} className="rounded-2xl bg-white border border-slate-100 p-3 shadow-xs">
                  <div className="flex justify-between items-start gap-2">
                    <div className="min-w-0">
                      <p className="text-xs font-bold text-slate-800">
                        {c.brand} {c.model} {c.year ?? ''}
                      </p>
                      <p className="text-[11px] text-slate-600 mt-0.5">{c.part_name}</p>
                      <p className="text-[10px] text-slate-400 mt-0.5">
                        {requestCategoryLabel(c)}
                        {c.request_type === 'service' && c.city ? ` · ${c.city}` : ''} · {formatTimeAgo(c.created_at)}
                      </p>
                    </div>
                    <div className="text-right flex-shrink-0">
                      {c.accepted_price != null ? (
                        <>
                          <div className="text-xs font-bold text-[#0B4635]">{formatPrice(c.accepted_price)}</div>
                          <div className="text-[9px] text-slate-400">satış qiyməti</div>
                        </>
                      ) : (
                        <div className="text-[10px] text-slate-400">
                          {c.status === 'completed' ? 'Satılıb' : c.status === 'cancelled' ? 'Ləğv' : 'Satılmayıb'}
                        </div>
                      )}
                      <div className="text-[10px] text-slate-400 mt-0.5">{c.bid_count} təklif</div>
                    </div>
                  </div>
                  {c.i_bid && (
                    <div className="mt-1.5 text-[10px] font-semibold text-[#9A5B00]">Siz təklif vermisiniz</div>
                  )}
                </div>
              ))}
            </div>
          )}
        </div>
      )}

      {/* ===== STATİSTİKA ===== */}
      {tab === 'stats' && <Stats bids={myBids} onUpgrade={() => setTab('account')} />}

      {/* ===== HESAB ===== */}
      {tab === 'account' && <AccountTab texts={texts} onChanged={refresh} />}

      {report && (
        <ReportModal
          db={sellerDb}
          kind="request"
          requestId={report.id}
          targetName={`${report.brand} ${report.model ?? ''} — ${report.part_name}`}
          onClose={() => setReport(null)}
        />
      )}

      {/* ===== ALT MENYU ===== */}
      <div className="fixed bottom-14 left-1/2 -translate-x-1/2 w-[92%] max-w-sm rounded-full bg-[#0B4635]/95 backdrop-blur-md shadow-2xl shadow-black/30 border border-white/10 py-2.5 px-3 flex justify-around items-center z-30">
        {(
          [
            { k: 'feed', label: 'Lent', icon: Inbox, badge: liveFeed.filter((r) => !r.my_bid_id).length },
            { k: 'bids', label: 'Təkliflər', icon: ListChecks, badge: pendingBids.length },
            { k: 'closed', label: 'Arxiv', icon: Archive, badge: 0 },
            { k: 'stats', label: 'Analiz', icon: BarChart3, badge: 0 },
            { k: 'account', label: 'Hesab', icon: Wallet, badge: 0 },
          ] as const
        ).map(({ k, label, icon: Icon, badge }) => (
          <button
            key={k}
            onClick={() => setTab(k)}
            className={`flex flex-col items-center gap-1 transition-all ${
              tab === k ? 'text-[#FFC61A] font-bold scale-105' : 'text-white/60 hover:text-white'
            }`}
          >
            <div className="relative">
              <Icon className="w-5 h-5" />
              {badge > 0 && (
                <span className="absolute -top-1 -right-2.5 bg-[#FFC61A] text-[#1B1B12] text-[9px] font-black min-w-[14px] h-3.5 px-0.5 rounded-full flex items-center justify-center">
                  {badge}
                </span>
              )}
            </div>
            <span className="text-[10px]">{label}</span>
          </button>
        ))}
      </div>
    </div>
  );
}

/* ====================================================================== */
/* Lent kartı + təklif formu                                               */
/* ====================================================================== */

function FeedCard({
  item,
  open,
  balance,
  fee,
  userId,
  onReport,
  onToggle,
  onDone,
}: {
  item: SellerFeedItem;
  open: boolean;
  balance: number;
  fee: number;
  userId: string | null;
  onReport: () => void;
  onToggle: () => void;
  onDone: () => Promise<void>;
}) {
  const [price, setPrice] = useState('');
  const [condition, setCondition] = useState<Condition>('original');
  const [warranty, setWarranty] = useState(WARRANTY_OPTIONS[0]);
  const [note, setNote] = useState('');
  const [images, setImages] = useState<string[]>([]);
  const [uploading, setUploading] = useState(false);
  const [priceType, setPriceType] = useState<PriceType>('fixed');
  const [eta, setEta] = useState<number>(24);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const isService = item.request_type === 'service';

  const alreadyBid = !!item.my_bid_id;
  const priceNum = parseFloat(price);
  const overBudget = item.budget_azn != null && Number.isFinite(priceNum) && priceNum > Number(item.budget_azn);
  const urg = URGENCY_CONFIG[item.urgency];
  const noteIssue = noteProblem(note);

  const submit = async () => {
    setError(null);
    if (!Number.isFinite(priceNum) || priceNum <= 0) return setError('Qiyməti düzgün yazın.');
    if (noteIssue) return setError(noteIssue);
    if (balance < fee) return setError('Coin balansınız çatmır. "Hesab" bölməsindən coin ala bilərsiniz.');
    setBusy(true);
    try {
      if (isService) {
        await api.submitServiceBid({
          requestId: item.id,
          price: priceNum,
          priceType,
          etaHours: eta,
          warranty,
          note: note.trim(),
          images,
        });
      } else {
        await api.submitBid({
          requestId: item.id,
          price: priceNum,
          condition,
          warranty,
          note: note.trim(),
          images,
        });
      }
      showToast({
        title: 'Təklif göndərildi',
        body: fee === 0 ? 'Pro planı: təklif pulsuzdur.' : `−${formatCoin(fee)} coin. Seçilməsə, vaxt bitəndə geri qayıdacaq.`,
        type: 'success',
      });
      setPrice('');
      setNote('');
      setImages([]);
      await onDone();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Təklif göndərilmədi.');
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="relative overflow-hidden rounded-2xl bg-white border border-slate-200/70 p-3.5 pt-4 shadow-[0_8px_22px_-16px_rgba(11,70,53,0.45)]">
      <TimeBar createdAt={item.created_at} expiresAt={item.expires_at} />
      <div className="flex items-start justify-between gap-2">
        <div className="min-w-0">
          <div className="flex items-center gap-1.5 flex-wrap">
            <span className="text-xs font-bold text-slate-800">
              {item.brand} {item.model} {item.year ?? ''}
            </span>
            <span className="text-[9px] bg-slate-100 text-slate-600 px-1.5 py-0.5 rounded font-medium">
              {requestCategoryLabel(item)}
            </span>
            {isService && (
              <span className="text-[9px] bg-indigo-50 text-indigo-700 px-1.5 py-0.5 rounded font-semibold">
                🔧 {item.city}
                {item.area ? `, ${item.area}` : ''}
                {item.on_site ? ' · yerində' : ''}
                {item.provider_pref === 'master' ? ' · usta' : item.provider_pref === 'service_center' ? ' · servis' : ''}
              </span>
            )}
            {urg && <span className="text-[10px]">{urg.icon}</span>}
          </div>
          <p className="font-display text-base font-bold text-[#0B4635] mt-0.5 leading-snug">{item.part_name}</p>
          {!isService && item.vin && <p className="text-[10px] font-mono text-slate-500 mt-0.5">VIN: {item.vin}</p>}
        </div>
        <span className="text-[11px] font-mono font-bold text-[#9A5B00] bg-amber-50 border border-amber-100 px-2 py-0.5 rounded-md whitespace-nowrap flex items-center gap-1">
          <Clock className="w-3 h-3" />
          <Countdown expiresAt={item.expires_at} />
        </span>
      </div>

      <PhotoStrip urls={item.part_images} />

      <div className="flex items-center justify-between text-[11px] text-slate-500 mt-2 pt-2 border-t border-slate-100">
        <span>Büdcə: {item.budget_azn ? formatPrice(item.budget_azn) : 'Razılaşma'}</span>
        <span>
          {item.bid_count}/5 təklif{item.slots_full ? ' · dolub' : ''}
        </span>
      </div>
      <button type="button" onClick={onReport} className="mt-1 text-[10px] text-slate-400 hover:text-rose-500">
        Şikayət et
      </button>

      {alreadyBid ? (
        <div className="mt-2 text-[11px] font-bold text-emerald-700 bg-emerald-50 border border-emerald-100 rounded-lg px-2.5 py-1.5 text-center">
          Təklifiniz göndərilib ✓
        </div>
      ) : item.slots_full ? (
        <div className="mt-2 text-[11px] font-semibold text-slate-500 bg-slate-50 border border-slate-100 rounded-lg px-2.5 py-1.5 text-center">
          Təklif limiti dolub
        </div>
      ) : (
        <button
          onClick={onToggle}
          className="w-full mt-2.5 py-2.5 bg-[#FFC61A] hover:bg-[#FFD24D] text-[#1B1B12] text-xs font-display font-extrabold rounded-lg transition-all active:scale-[0.98] shadow-[0_2px_0_#C99700]"
        >
          {open ? 'Bağla' : 'Qiymət ver'}
        </button>
      )}

      {open && !alreadyBid && !item.slots_full && (
        <div className="mt-2.5 pt-2.5 border-t border-slate-100 space-y-2">
          <div>
            <label className="text-[11px] text-slate-500 mb-0.5 block font-medium">Qiymət (AZN) *</label>
            <input
              type="number"
              inputMode="decimal"
              value={price}
              onChange={(e) => setPrice(e.target.value)}
              placeholder="0"
              className={inputCls}
            />
            {overBudget && (
              <p className="text-[10px] text-amber-700 mt-1">
                Qiymət alıcının büdcəsindən ({formatPrice(item.budget_azn)}) yüksəkdir — seçilmə ehtimalı azalır.
              </p>
            )}
          </div>

          {isService ? (
            <>
              <div>
                <label className="text-[11px] text-slate-500 mb-1 block font-medium">Qiymət növü</label>
                <div className="flex gap-1.5">
                  <Chip tone="orange" active={priceType === 'fixed'} onClick={() => setPriceType('fixed')}>
                    Dəqiq qiymət
                  </Chip>
                  <Chip tone="orange" active={priceType === 'from'} onClick={() => setPriceType('from')}>
                    …dən başlayır
                  </Chip>
                </div>
              </div>
              <div>
                <label className="text-[11px] text-slate-500 mb-1 block font-medium">İş nə qədər çəkəcək?</label>
                <div className="flex gap-1.5 flex-wrap">
                  {ETA_OPTIONS.map((o) => (
                    <Chip tone="orange" key={o.hours} active={eta === o.hours} onClick={() => setEta(o.hours)}>
                      {o.label}
                    </Chip>
                  ))}
                </div>
              </div>
            </>
          ) : (
            <div>
              <label className="text-[11px] text-slate-500 mb-1 block font-medium">Vəziyyət</label>
              <div className="flex gap-1.5 flex-wrap">
                {(['original', 'analog', 'used'] as Condition[]).map((c) => (
                  <Chip tone="orange" key={c} active={condition === c} onClick={() => setCondition(c)}>
                    {CONDITION_LABELS[c]}
                  </Chip>
                ))}
              </div>
            </div>
          )}

          <div>
            <label className="text-[11px] text-slate-500 mb-1 block font-medium">Zəmanət</label>
            <div className="flex gap-1.5 flex-wrap">
              {WARRANTY_OPTIONS.map((w) => (
                <Chip tone="orange" key={w} active={warranty === w} onClick={() => setWarranty(w)}>
                  {w}
                </Chip>
              ))}
            </div>
          </div>

          <div>
            <label className="text-[11px] text-slate-500 mb-0.5 block font-medium">
              {isService ? 'Qeyd (könüllü: nə daxildir, hansı hissə ilə)' : 'Qeyd (könüllü: OEM nömrə, mənşə, çatdırılma)'}
            </label>
            <input
              type="text"
              value={note}
              maxLength={140}
              onChange={(e) => setNote(e.target.value)}
              placeholder={
                isService ? 'Məs: diaqnostika pulsuz, hissə ayrıca' : 'Məs: OEM 31316-8X, Almaniya istehsalı, anbarda var'
              }
              className={inputCls}
            />
            {noteIssue && <p className="text-[10px] text-rose-600 mt-1">{noteIssue}</p>}
          </div>

          <ImagePicker
            db={sellerDb}
            userId={userId}
            urls={images}
            onChange={setImages}
            onBusy={setUploading}
            hint={isService ? 'Şəkil (könüllü): əvvəlki işləriniz, iş yeri' : 'Şəkil (könüllü): sizdəki həmin detalın şəkli'}
          />

          {error && (
            <div className="rounded-lg bg-rose-50 border border-rose-200 px-3 py-2 text-[11px] text-rose-700">
              {error}
            </div>
          )}

          <button
            onClick={submit}
            disabled={busy || uploading}
            className="w-full py-3 bg-[#0B4635] hover:bg-[#0d5544] text-white text-sm font-display font-extrabold rounded-xl disabled:opacity-60 transition-all active:scale-[0.98]"
          >
            {busy ? 'Göndərilir…' : fee === 0 ? 'Təklifi göndər (pulsuz)' : `Təklifi göndər (−${formatCoin(fee)} coin)`}
          </button>
          <p className="text-[10px] text-slate-400 text-center">
            Alıcının nömrəsi yalnız təklifiniz seçiləndən sonra açılır.
          </p>
        </div>
      )}
    </div>
  );
}

/* ====================================================================== */
/* Mənim təklifim                                                          */
/* ====================================================================== */

function MyBidCard({ bid }: { bid: MyBid }) {
  const gap = bid.price_difference;
  let badge: { text: string; cls: string };
  let info: string | null = null;

  if (bid.bid_status === 'accepted') {
    badge = { text: 'Seçildi 🎉', cls: 'bg-emerald-50 text-emerald-700 border-emerald-200' };
    info =
      bid.deal_status === 'failed'
        ? 'Alıcı razılaşmanın alınmadığını bildirdi.'
        : 'Alıcı sizin təklifi seçdi və sizinlə əlaqə saxlayacaq. Satış bonusu hesabınıza əlavə olunub.';
  } else if (bid.bid_status === 'rejected') {
    badge = { text: 'Başqası seçildi', cls: 'bg-slate-100 text-slate-600 border-slate-200' };
    if (bid.winning_price != null) {
      const diff = gap != null ? Math.abs(Number(gap)) : null;
      info = `Qazanan qiymət: ${formatPrice(bid.winning_price)}${
        bid.winning_warranty ? ` (${bid.winning_warranty})` : ''
      }${diff != null && diff > 0 ? ` · sizin təklif ${formatPrice(diff)} fərqli idi` : ''}.`;
    }
  } else if (bid.bid_status === 'expired') {
    badge = { text: 'Vaxtı bitib', cls: 'bg-slate-100 text-slate-500 border-slate-200' };
    info = 'Alıcı seçmədi — ödədiyiniz coin geri qaytarıldı.';
  } else if (bid.request_status === 'active') {
    badge = { text: 'Gözləyir', cls: 'bg-amber-50 text-[#9A5B00] border-amber-200' };
  } else {
    badge = { text: 'Bağlanıb', cls: 'bg-slate-100 text-slate-500 border-slate-200' };
  }

  return (
    <div className="rounded-2xl bg-white border border-slate-100 p-3.5 shadow-xs">
      <div className="flex justify-between items-start gap-2">
        <div className="min-w-0">
          <p className="text-xs font-bold text-slate-800">
            {bid.brand} {bid.model} {bid.year ?? ''}
          </p>
          <p className="text-[11px] text-slate-600 mt-0.5">{bid.part_name}</p>
          <p className="text-[10px] text-slate-400 mt-0.5">{formatTimeAgo(bid.bid_created_at)}</p>
        </div>
        <div className="text-right flex-shrink-0">
          <div className="font-display text-lg font-extrabold text-[#0B4635] leading-none">
            {bid.price_type === 'from' && <span className="text-[10px] font-semibold text-slate-500">dən </span>}
            {formatPrice(bid.price_azn)}
          </div>
          <span className={`inline-block mt-0.5 text-[10px] px-2 py-0.5 rounded-full font-bold border ${badge.cls}`}>
            {badge.text}
          </span>
        </div>
      </div>
      <div className="text-[10px] text-slate-500 mt-1.5 flex items-center gap-1">
        {bid.request_type === 'service'
          ? `🔧 ${bid.city ?? ''}${bid.eta_hours ? ` · ~${etaLabel(bid.eta_hours)}` : ''}`
          : CONDITION_LABELS[bid.condition] || bid.condition}{' '}
        · {bid.warranty}
        {bid.bid_status === 'pending' && bid.request_status === 'active' && (
          <span className="ml-auto flex items-center gap-1 text-[#9A5B00] font-semibold">
            <Clock className="w-3 h-3" />
            <Countdown expiresAt={bid.request_expires_at} />
          </span>
        )}
      </div>
      {info && <p className="text-[11px] text-slate-600 mt-1.5 bg-slate-50 rounded-lg px-2.5 py-1.5">{info}</p>}
    </div>
  );
}

/* ====================================================================== */
/* Analiz                                                                  */
/* ====================================================================== */

function Stats({ bids, onUpgrade }: { bids: MyBid[]; onUpgrade: () => void }) {
  const s = useMemo(() => {
    const won = bids.filter((b) => b.bid_status === 'accepted').length;
    const lost = bids.filter((b) => b.bid_status === 'rejected');
    const decided = won + lost.length;
    const rate = decided > 0 ? Math.round((won / decided) * 100) : null;
    const gaps = lost
      .map((b) => (b.price_difference != null ? Math.abs(Number(b.price_difference)) : null))
      .filter((x): x is number => x != null && x > 0);
    const avgGap = gaps.length > 0 ? gaps.reduce((a, b) => a + b, 0) / gaps.length : null;
    return { total: bids.length, won, rate, avgGap };
  }, [bids]);

  return (
    <div className="space-y-3">
      <div className="grid grid-cols-3 gap-2">
        <StatTile label="Təklif" value={String(s.total)} />
        <StatTile label="Satış" value={String(s.won)} />
        <StatTile label="Qazanma" value={s.rate == null ? '—' : `${s.rate}%`} />
      </div>

      <div className="rounded-2xl bg-white border border-slate-100 p-3.5 shadow-xs">
        <h3 className="text-xs font-bold text-slate-800">Qiymət məsləhəti</h3>
        <p className="text-[11px] text-slate-600 mt-1.5">
          {s.avgGap != null
            ? `Uduzduğunuz sorğularda qazanan qiymətdən orta hesabla ${formatPrice(
                Math.round(s.avgGap * 100) / 100
              )} fərqli olmusunuz. Qeyd və zəmanətlə fərqlənin, lazım gələndə qiyməti bu qədər düzəldin.`
            : 'Başqa mağaza seçiləndə, qazanan qiymətlə aranızdakı fərq burada görünəcək.'}
        </p>
      </div>

      <InsightsView onUpgrade={onUpgrade} />
    </div>
  );
}

function StatTile({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-2xl bg-white border border-slate-100 p-3 text-center shadow-xs">
      <div className="text-lg font-black text-[#0B4635]">{value}</div>
      <div className="text-[10px] text-slate-500 font-medium mt-0.5">{label}</div>
    </div>
  );
}
