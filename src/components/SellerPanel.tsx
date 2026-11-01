import { useCallback, useEffect, useMemo, useState } from 'react';
import { Archive, BarChart3, Inbox, ListChecks, Wallet } from 'lucide-react';
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

const inputCls = 'input';

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

  // Navbar-dakı coin düyməsi "Hesab" bölməsini açır
  useEffect(() => {
    const onTab = (e: Event) => {
      const t = (e as CustomEvent<string>).detail;
      if (t === 'account' || t === 'feed' || t === 'bids') setTab(t);
    };
    window.addEventListener('autotender:tab', onTab);
    return () => window.removeEventListener('autotender:tab', onTab);
  }, []);

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
    <div className="text-slate-800 pb-36 pt-1 px-3 max-w-md mx-auto">
      {/* Mağaza: ad, reytinq, dərəcə — coin yalnız yuxarıdakı düymədə göstərilir */}
      <div className="flex items-center justify-between gap-2 px-1 mb-3">
        <div className="min-w-0">
          <h2 className="font-display text-2xl font-extrabold text-[#0B4635] truncate">{store.name}</h2>
          <div className="flex items-center gap-1.5 flex-wrap mt-1.5">
            {store.review_count > 0 || Number(store.rating) < 5 ? (
              <span className="tag-amber">
                {Number(store.rating).toFixed(1)} ulduz{store.review_count > 0 ? ` (${store.review_count} rəy)` : ''}
              </span>
            ) : (
              <span className="tag">Yeni mağaza</span>
            )}
            <span className="tag-green">Dərəcə {store.grade}</span>
            {store.verified && <span className="tag-green">Təsdiqlənib</span>}
            {plan !== 'free' && <span className="tag-blue">{PLAN_LABELS[plan]}</span>}
          </div>
        </div>
      </div>

      {loadError && <div className="mb-3 rounded-2xl bg-amber-50 p-3 text-sm text-amber-800">{loadError}</div>}

      {/* ===== LENT ===== */}
      {tab === 'feed' && (
        <div className="rise">
          {(hasBothTypes || typeFilter !== 'all') && (
            <div className="chips mb-2">
              <Chip tone="orange" active={typeFilter === 'all'} onClick={() => setType('all')}>
                Hamısı ({liveFeed.length})
              </Chip>
              <Chip tone="orange" active={typeFilter === 'part'} onClick={() => setType('part')}>
                Detal
              </Chip>
              <Chip tone="orange" active={typeFilter === 'service'} onClick={() => setType('service')}>
                Xidmət
              </Chip>
            </div>
          )}
          {chipCats.length > 0 && (
            <div className="chips mb-3">
              <Chip tone="orange" active={cat === 'all'} onClick={() => setCat('all')}>
                Bütün növlər
              </Chip>
              {chipCats.map((c) => (
                <Chip tone="orange" key={c.key} active={cat === c.key} onClick={() => setCat(c.key)}>
                  {c.short}
                </Chip>
              ))}
            </div>
          )}

          {loading ? (
            <div className="space-y-3">
              {[1, 2].map((i) => (
                <div key={i} className="skeleton h-32" />
              ))}
            </div>
          ) : visibleFeed.length === 0 ? (
            <EmptyState title="Hazırda uyğun sorğu yoxdur" text="Yeni sorğu gələndə bildiriş alacaqsınız." />
          ) : (
            <div className="space-y-3">
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
                  onNeedCoin={() => setTab('account')}
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
        <div className="rise">
          {myBids.length === 0 ? (
            <EmptyState title="Hələ təklifiniz yoxdur" text="Lentdən sorğu seçib qiymət verin." />
          ) : (
            <div className="space-y-3">
              {pendingBids.length > 0 && (
                <div className="text-sm font-semibold text-slate-500 px-1">Cavab gözləyən: {pendingBids.length}</div>
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
        <div className="rise">
          {closed.length === 0 ? (
            <EmptyState title="Arxiv boşdur" />
          ) : (
            <div className="space-y-2.5">
              {closed.map((c) => (
                <div key={c.id} className="card !p-3.5">
                  <div className="flex justify-between items-start gap-3">
                    <div className="min-w-0">
                      <p className="text-[13px] font-bold text-slate-500">
                        {c.brand} {c.model} {c.year ?? ''}
                      </p>
                      <p className="text-sm font-bold text-slate-900 mt-0.5">{c.part_name}</p>
                      <p className="text-xs text-slate-400 mt-1">
                        {requestCategoryLabel(c)}
                        {c.request_type === 'service' && c.city ? `, ${c.city}` : ''}, {formatTimeAgo(c.created_at)}
                      </p>
                    </div>
                    <div className="text-right flex-shrink-0">
                      {c.accepted_price != null ? (
                        <>
                          <div className="font-display text-lg font-extrabold text-[#0B4635] leading-none">
                            {formatPrice(c.accepted_price)}
                          </div>
                          <div className="text-[11px] text-slate-400 mt-1">satış qiyməti</div>
                        </>
                      ) : (
                        <div className="text-xs text-slate-400">
                          {c.status === 'completed' ? 'Satılıb' : c.status === 'cancelled' ? 'Ləğv' : 'Satılmayıb'}
                        </div>
                      )}
                      <div className="text-xs text-slate-400 mt-1">{c.bid_count} təklif</div>
                    </div>
                  </div>
                  {c.i_bid && <span className="tag-amber mt-2">Siz təklif vermisiniz</span>}
                </div>
              ))}
            </div>
          )}
        </div>
      )}

      {/* ===== STATİSTİKA ===== */}
      {tab === 'stats' && (
        <div className="rise">
          <Stats bids={myBids} onUpgrade={() => setTab('account')} />
        </div>
      )}

      {/* ===== HESAB ===== */}
      {tab === 'account' && (
        <div className="rise">
          <AccountTab texts={texts} onChanged={refresh} />
        </div>
      )}

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
      <div className="dock glass">
        {(
          [
            { k: 'feed', label: 'Lent', icon: Inbox, badge: liveFeed.filter((r) => !r.my_bid_id).length },
            { k: 'bids', label: 'Təkliflər', icon: ListChecks, badge: pendingBids.length },
            { k: 'closed', label: 'Arxiv', icon: Archive, badge: 0 },
            { k: 'stats', label: 'Analiz', icon: BarChart3, badge: 0 },
            { k: 'account', label: 'Hesab', icon: Wallet, badge: 0 },
          ] as const
        ).map(({ k, label, icon: Icon, badge }) => (
          <button key={k} onClick={() => setTab(k)} aria-current={tab === k} className="dock-item">
            <div className="relative">
              <Icon className="w-5 h-5" />
              {badge > 0 && (
                <span className="absolute -top-1.5 -right-3 bg-[#FFC61A] text-[#0F2A21] text-[10px] font-black min-w-[16px] h-4 px-1 rounded-full flex items-center justify-center">
                  {badge}
                </span>
              )}
            </div>
            {label}
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
  onNeedCoin,
  onDone,
}: {
  item: SellerFeedItem;
  open: boolean;
  balance: number;
  fee: number;
  userId: string | null;
  onReport: () => void;
  onToggle: () => void;
  onNeedCoin: () => void;
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
  const lowCoin = balance < fee;

  const submit = async () => {
    setError(null);
    if (!Number.isFinite(priceNum) || priceNum <= 0) return setError('Qiyməti düzgün yazın.');
    if (noteIssue) return setError(noteIssue);
    if (lowCoin) return setError('Coin çatmır. Hesab bölməsindən coin ala bilərsiniz.');
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
        body: fee === 0 ? 'Pro: pulsuz.' : `−${formatCoin(fee)} coin. Seçilməsə, geri qayıdır.`,
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
    <div className="card pt-5">
      <TimeBar createdAt={item.created_at} expiresAt={item.expires_at} />
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <div className="flex items-center gap-1.5 flex-wrap">
            <span className="text-[13px] font-bold text-slate-500">
              {item.brand} {item.model} {item.year ?? ''}
            </span>
            <span className="tag">{requestCategoryLabel(item)}</span>
            {isService && (
              <span className="tag-blue">
                {item.city}
                {item.area ? `, ${item.area}` : ''}
                {item.on_site ? ', yerində' : ''}
                {item.provider_pref === 'master' ? ', usta' : item.provider_pref === 'service_center' ? ', servis' : ''}
              </span>
            )}
            {urg && item.urgency === 'express' && <span className="tag-rose">Təcili</span>}
          </div>
          <p className="font-display text-xl font-extrabold text-[#0B4635] mt-1 leading-tight">{item.part_name}</p>
          {!isService && item.vin && <p className="text-xs font-mono text-slate-500 mt-1">VIN: {item.vin}</p>}
        </div>
        <div className="text-right flex-shrink-0">
          <div className="font-display text-lg font-extrabold text-[#9A5B00] leading-none">
            <Countdown expiresAt={item.expires_at} />
          </div>
          <div className="text-[11px] text-slate-400 mt-1">qalıb</div>
        </div>
      </div>

      <PhotoStrip urls={item.part_images} />

      <div className="flex items-center justify-between text-[13px] text-slate-500 mt-3">
        <span>Büdcə: {item.budget_azn ? formatPrice(item.budget_azn) : 'razılaşma ilə'}</span>
        <span>
          {item.bid_count}/5 təklif{item.slots_full ? ', dolub' : ''}
        </span>
      </div>

      {alreadyBid ? (
        <div className="mt-3 rounded-2xl bg-emerald-50 px-3 py-2.5 text-sm font-semibold text-emerald-800 text-center">
          Təklifiniz göndərilib
        </div>
      ) : item.slots_full ? (
        <div className="mt-3 rounded-2xl bg-[#F4F7F4] px-3 py-2.5 text-sm font-semibold text-slate-500 text-center">
          Təklif limiti dolub
        </div>
      ) : (
        <button onClick={onToggle} className={`${open ? 'btn-ghost' : 'btn-cta'} w-full mt-3`}>
          {open ? 'Bağla' : 'Qiymət ver'}
        </button>
      )}

      {open && !alreadyBid && !item.slots_full && (
        <div className="mt-3.5 pt-3.5 border-t border-black/5 space-y-3.5">
          <div>
            <label className="label">Qiymət (AZN) *</label>
            <input
              type="number"
              inputMode="decimal"
              value={price}
              onChange={(e) => setPrice(e.target.value)}
              placeholder="0"
              className={`${inputCls} font-display text-xl font-bold`}
            />
            {overBudget && (
              <p className="text-xs text-amber-700 mt-1.5">Alıcının büdcəsindən ({formatPrice(item.budget_azn)}) yüksəkdir.</p>
            )}
          </div>

          {isService ? (
            <>
              <div>
                <label className="label">Qiymət növü</label>
                <div className="chips">
                  <Chip tone="orange" active={priceType === 'fixed'} onClick={() => setPriceType('fixed')}>
                    Dəqiq qiymət
                  </Chip>
                  <Chip tone="orange" active={priceType === 'from'} onClick={() => setPriceType('from')}>
                    …dən başlayır
                  </Chip>
                </div>
              </div>
              <div>
                <label className="label">İş nə qədər çəkəcək?</label>
                <div className="chips">
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
              <label className="label">Vəziyyət</label>
              <div className="chips">
                {(['original', 'analog', 'used'] as Condition[]).map((c) => (
                  <Chip tone="orange" key={c} active={condition === c} onClick={() => setCondition(c)}>
                    {CONDITION_LABELS[c]}
                  </Chip>
                ))}
              </div>
            </div>
          )}

          <div>
            <label className="label">Zəmanət</label>
            <div className="chips">
              {WARRANTY_OPTIONS.map((w) => (
                <Chip tone="orange" key={w} active={warranty === w} onClick={() => setWarranty(w)}>
                  {w}
                </Chip>
              ))}
            </div>
          </div>

          <div>
            <label className="label">Qeyd (könüllü)</label>
            <input
              type="text"
              value={note}
              maxLength={140}
              onChange={(e) => setNote(e.target.value)}
              placeholder={isService ? 'Məs: diaqnostika pulsuz' : 'Məs: OEM 31316-8X, anbarda var'}
              className={inputCls}
            />
            {noteIssue && <p className="text-xs text-rose-600 mt-1">{noteIssue}</p>}
          </div>

          <ImagePicker
            db={sellerDb}
            userId={userId}
            urls={images}
            onChange={setImages}
            onBusy={setUploading}
            hint={isService ? 'Şəkil (könüllü): əvvəlki işləriniz' : 'Şəkil (könüllü): sizdəki detal'}
          />

          {error && <div className="rounded-2xl bg-rose-50 px-3.5 py-2.5 text-sm text-rose-700">{error}</div>}

          {lowCoin && fee > 0 ? (
            <button onClick={onNeedCoin} className="btn-cta w-full">
              Coin çatmır, coin al
            </button>
          ) : (
            <button onClick={submit} disabled={busy || uploading} className="btn-primary w-full text-base">
              {busy ? 'Göndərilir…' : fee === 0 ? 'Təklifi göndər' : `Təklifi göndər (−${formatCoin(fee)} coin)`}
            </button>
          )}
          <button type="button" onClick={onReport} className="w-full text-xs text-slate-400 hover:text-rose-500">
            Sorğu barədə şikayət
          </button>
        </div>
      )}
    </div>
  );
}

/* ====================================================================== */
/* Mənim təklifim                                                          */
/* ====================================================================== */

function MyBidCard({ bid }: { bid: MyBid }) {
  const gap = bid.price_difference != null ? Number(bid.price_difference) : null;
  let badge: { text: string; cls: string };
  let info: string | null = null;
  let winner: number | null = null;

  if (bid.bid_status === 'accepted') {
    badge = { text: 'Seçildi', cls: 'tag-green' };
    info = 'Alıcı sizi seçdi və sizinlə əlaqə saxlayacaq. Satış bonusu hesabınıza yazıldı.';
  } else if (bid.bid_status === 'rejected' && bid.deal_status === 'failed') {
    badge = { text: 'Razılaşma alınmadı', cls: 'tag-rose' };
    info = 'Alıcı ilə razılaşma alınmadı. Satış bonusu geri alındı.';
  } else if (bid.bid_status === 'rejected' && bid.winning_price != null) {
    badge = { text: 'Başqası seçildi', cls: 'tag' };
    winner = Number(bid.winning_price);
    if (gap != null && Math.abs(gap) > 0) {
      info = `Sizin təklif ${formatPrice(Math.abs(gap))} ${gap > 0 ? 'baha' : 'ucuz'} idi${
        bid.winning_warranty ? `, seçilən zəmanət: ${bid.winning_warranty}` : ''
      }.`;
    } else if (bid.winning_warranty) {
      info = `Seçilən zəmanət: ${bid.winning_warranty}.`;
    }
  } else if (bid.bid_status === 'rejected') {
    badge = { text: 'Seçilmədi', cls: 'tag' };
  } else if (bid.bid_status === 'expired') {
    badge = { text: 'Vaxtı bitib', cls: 'tag' };
    info = 'Alıcı seçmədi. Coin geri qaytarıldı.';
  } else if (bid.request_status === 'active') {
    badge = { text: 'Gözləyir', cls: 'tag-amber' };
  } else {
    badge = { text: 'Bağlanıb', cls: 'tag' };
  }

  return (
    <div className="card !p-4">
      <div className="flex justify-between items-start gap-3">
        <div className="min-w-0">
          <p className="text-[13px] font-bold text-slate-500">
            {bid.brand} {bid.model} {bid.year ?? ''}
          </p>
          <p className="font-display text-base font-extrabold text-slate-900 mt-0.5 leading-snug">{bid.part_name}</p>
          <p className="text-xs text-slate-400 mt-1">{formatTimeAgo(bid.bid_created_at)}</p>
        </div>
        <div className="text-right flex-shrink-0">
          <div className="text-[11px] text-slate-400">Sizin təklif</div>
          <div className="font-display text-xl font-extrabold text-[#0B4635] leading-none mt-0.5">
            {bid.price_type === 'from' && <span className="text-[11px] font-semibold text-slate-500">dən </span>}
            {formatPrice(bid.price_azn)}
          </div>
          <div className="mt-1.5">
            <span className={badge.cls}>{badge.text}</span>
          </div>
        </div>
      </div>

      {winner != null && (
        <div className="mt-3 flex items-center justify-between rounded-2xl bg-[#F4F7F4] px-3.5 py-2.5">
          <span className="text-sm text-slate-500">Seçilən qiymət</span>
          <span className="font-display text-xl font-extrabold text-slate-900">{formatPrice(winner)}</span>
        </div>
      )}

      <div className="text-[13px] text-slate-500 mt-2.5 flex items-center gap-2 flex-wrap">
        <span>
          {bid.request_type === 'service'
            ? `${bid.city ?? ''}${bid.eta_hours ? `, ~${etaLabel(bid.eta_hours)}` : ''}`
            : CONDITION_LABELS[bid.condition] || bid.condition}
          {bid.warranty ? `, ${bid.warranty}` : ''}
        </span>
        {bid.bid_status === 'pending' && bid.request_status === 'active' && (
          <span className="ml-auto font-semibold text-[#9A5B00]">
            <Countdown expiresAt={bid.request_expires_at} /> qalıb
          </span>
        )}
      </div>
      {info && <p className="text-sm text-slate-600 mt-2.5">{info}</p>}
    </div>
  );
}

/* ====================================================================== */
/* Analiz                                                                  */
/* ====================================================================== */

function Stats({ bids, onUpgrade }: { bids: MyBid[]; onUpgrade: () => void }) {
  const s = useMemo(() => {
    const won = bids.filter((b) => b.bid_status === 'accepted').length;
    const lost = bids.filter((b) => b.bid_status === 'rejected' && b.winning_price != null);
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
      <div className="grid grid-cols-3 gap-2.5">
        <StatTile label="Təklif" value={String(s.total)} />
        <StatTile label="Satış" value={String(s.won)} />
        <StatTile label="Qazanma" value={s.rate == null ? '—' : `${s.rate}%`} />
      </div>

      <div className="card">
        <h3 className="font-display text-base font-extrabold text-slate-900">Qiymət məsləhəti</h3>
        <p className="text-sm text-slate-600 mt-1.5">
          {s.avgGap != null
            ? `Uduzduğunuz sorğularda qazanan qiymətdən orta hesabla ${formatPrice(
                Math.round(s.avgGap * 100) / 100
              )} fərqli olmusunuz.`
            : 'Başqa mağaza seçiləndə, qazanan qiymətlə fərq burada görünəcək.'}
        </p>
      </div>

      <InsightsView onUpgrade={onUpgrade} />
    </div>
  );
}

function StatTile({ label, value }: { label: string; value: string }) {
  return (
    <div className="card !p-3.5 text-center">
      <div className="font-display text-2xl font-extrabold text-[#0B4635] leading-none">{value}</div>
      <div className="text-xs text-slate-500 font-medium mt-1.5">{label}</div>
    </div>
  );
}
