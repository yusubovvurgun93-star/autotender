import { useCallback, useEffect, useState } from 'react';
import { Activity, Coins, Crown, Gavel, Gift, Minus, Package, Plus, ShieldCheck, Store as StoreIcon, TrendingUp, Wallet } from 'lucide-react';
import { GRADE_COLORS, sellerDb } from '@/lib/supabase';
import * as api from '@/lib/api';
import { formatPhone } from '@/lib/validate';
import { effectivePlan, formatCoin, formatPrice, formatTimeAgo, showToast } from '@/lib/utils';
import { TelegramCard } from '@/components/Billing';
import type { AdminBidRow, AdminBillingStats, AdminOrder, AdminReport, AdminRequestRow, AdminStats, AdminStore } from '@/lib/types';
import { REASON_LABELS } from '@/components/Report';

const REQ_STATUS: Record<string, string> = {
  active: 'Aktiv',
  completed: 'Tamamlandı',
  expired: 'Vaxtı bitib',
  cancelled: 'Ləğv',
};
const BID_STATUS: Record<string, string> = {
  pending: 'Gözləyir',
  accepted: 'Qəbul',
  rejected: 'Rədd',
  expired: 'Vaxtı bitib',
};

export function AdminPanel() {
  const [stats, setStats] = useState<AdminStats | null>(null);
  const [stores, setStores] = useState<AdminStore[]>([]);
  const [requests, setRequests] = useState<AdminRequestRow[]>([]);
  const [bids, setBids] = useState<AdminBidRow[]>([]);
  const [billing, setBilling] = useState<AdminBillingStats | null>(null);
  const [orders, setOrders] = useState<AdminOrder[]>([]);
  const [reports, setReports] = useState<AdminReport[]>([]);
  const [textDraft, setTextDraft] = useState<Record<string, string>>({});
  const [priceDraft, setPriceDraft] = useState<Record<string, string>>({});
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [busyId, setBusyId] = useState<string | null>(null);

  const load = useCallback(async () => {
    try {
      const [s, st, rq, bd, bl, od, rp] = await Promise.all([
        api.adminDashboard(),
        api.adminListStores(),
        api.adminRecentRequests(),
        api.adminRecentBids(),
        api.adminBillingStats(),
        api.adminListOrders(null),
        api.adminListReports('open'),
      ]);
      setReports(rp);
      setBilling(bl);
      setOrders(od);
      setStats(s);
      setStores(st);
      setRequests(rq);
      setBids(bd);
      setError(null);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Məlumat yüklənmədi.');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void load();
    let t: ReturnType<typeof setTimeout> | undefined;
    const debounced = () => {
      if (t) clearTimeout(t);
      t = setTimeout(() => void load(), 600);
    };
    const channel = sellerDb
      .channel('admin-sync')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'requests' }, debounced)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'bids' }, debounced)
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'in_app_notifications' }, debounced)
      .subscribe();
    return () => {
      if (t) clearTimeout(t);
      void sellerDb.removeChannel(channel);
    };
  }, [load]);

  const adjust = async (store: AdminStore, delta: number) => {
    setBusyId(store.id);
    try {
      const balance = await api.adminAdjustCoins(store.id, delta, 'Admin düzəlişi');
      showToast({ title: 'Coin yeniləndi', body: `${store.name}: ${balance} coin`, type: 'success' });
      await load();
    } catch (e) {
      showToast({ title: 'Coin yenilənmədi', body: e instanceof Error ? e.message : undefined, type: 'error' });
    } finally {
      setBusyId(null);
    }
  };

  const confirmOrder = async (o: AdminOrder) => {
    setBusyId(o.id);
    try {
      await api.adminConfirmOrder(o.id);
      showToast({ title: 'Təsdiqləndi', body: `${o.store_name}: ${o.title}`, type: 'success' });
      await load();
    } catch (e) {
      showToast({ title: 'Təsdiqlənmədi', body: e instanceof Error ? e.message : undefined, type: 'error' });
    } finally {
      setBusyId(null);
    }
  };

  const cancelOrder = async (o: AdminOrder) => {
    setBusyId(o.id);
    try {
      await api.adminCancelOrder(o.id);
      await load();
    } catch (e) {
      showToast({ title: 'Ləğv edilmədi', body: e instanceof Error ? e.message : undefined, type: 'error' });
    } finally {
      setBusyId(null);
    }
  };

  const resolveReport = async (rp: AdminReport, status: 'resolved' | 'dismissed') => {
    setBusyId(rp.id);
    try {
      await api.adminResolveReport(rp.id, status);
      await load();
    } catch (e) {
      showToast({ title: 'Xəta', body: e instanceof Error ? e.message : undefined, type: 'error' });
    } finally {
      setBusyId(null);
    }
  };

  const suspend = async (storeId: string, suspended: boolean, reason?: string) => {
    setBusyId(storeId);
    try {
      await api.adminSetSuspended(storeId, suspended, reason);
      showToast({ title: suspended ? 'Mağaza dayandırıldı' : 'Mağaza bərpa olundu', type: 'success' });
      await load();
    } catch (e) {
      showToast({ title: 'Xəta', body: e instanceof Error ? e.message : undefined, type: 'error' });
    } finally {
      setBusyId(null);
    }
  };

  const removeRequest = async (rp: AdminReport) => {
    if (!rp.request_id) return;
    setBusyId(rp.id);
    try {
      await api.adminCancelRequest(rp.request_id);
      await api.adminResolveReport(rp.id, 'resolved', 'Sorğu silindi');
      await load();
    } catch (e) {
      showToast({ title: 'Xəta', body: e instanceof Error ? e.message : undefined, type: 'error' });
    } finally {
      setBusyId(null);
    }
  };

  const setPlan = async (store: AdminStore, plan: string) => {
    setBusyId(store.id);
    try {
      await api.adminSetPlan(store.id, plan, 30);
      showToast({ title: 'Plan dəyişdi', body: `${store.name}: ${plan}${plan === 'free' ? '' : ' (30 gün)'}`, type: 'success' });
      await load();
    } catch (e) {
      showToast({ title: 'Dəyişmədi', body: e instanceof Error ? e.message : undefined, type: 'error' });
    } finally {
      setBusyId(null);
    }
  };

  const saveText = async (key: string) => {
    try {
      await api.adminSetText(key, textDraft[key] ?? '');
      showToast({ title: 'Yadda saxlanıldı', type: 'success' });
      setTextDraft((d) => {
        const { [key]: _x, ...rest } = d;
        return rest;
      });
      await load();
    } catch (e) {
      showToast({ title: 'Saxlanmadı', body: e instanceof Error ? e.message : undefined, type: 'error' });
    }
  };

  const savePrice = async (key: string) => {
    const v = parseFloat(priceDraft[key] ?? '');
    try {
      await api.adminSetCatalogPrice(key, v);
      showToast({ title: 'Qiymət yeniləndi', type: 'success' });
      setPriceDraft((d) => {
        const { [key]: _x, ...rest } = d;
        return rest;
      });
      await load();
    } catch (e) {
      showToast({ title: 'Saxlanmadı', body: e instanceof Error ? e.message : undefined, type: 'error' });
    }
  };

  const toggleVerified = async (store: AdminStore) => {
    setBusyId(store.id);
    try {
      await api.adminSetVerified(store.id, !store.verified);
      await load();
    } catch (e) {
      showToast({ title: 'Dəyişmədi', body: e instanceof Error ? e.message : undefined, type: 'error' });
    } finally {
      setBusyId(null);
    }
  };

  if (loading) {
    return (
      <div className="px-3 pt-4 max-w-md mx-auto space-y-2.5">
        {[1, 2, 3].map((i) => (
          <div key={i} className="rounded-2xl bg-white border border-slate-100 h-20 animate-pulse" />
        ))}
      </div>
    );
  }

  const kpis = stats
    ? [
        { label: 'Mağaza', value: stats.total_stores, sub: `${stats.verified_stores} təsdiqli`, icon: StoreIcon },
        { label: 'Sorğu', value: stats.total_requests, sub: `${stats.active_requests} aktiv · ${stats.requests_7d} (7 gün)`, icon: Package },
        { label: 'Təklif', value: stats.total_bids, sub: `${stats.completed_requests} satış`, icon: Gavel },
        { label: 'Xərclənən coin', value: stats.coins_spent, sub: `${stats.coins_refunded} qaytarılıb`, icon: Coins },
        { label: 'Bonus coin', value: stats.bonus_coins_given, sub: 'satış bonusları', icon: Gift },
        { label: 'Uğursuz razılaşma', value: stats.failed_deals, sub: `${stats.expired_requests} vaxtı bitən sorğu`, icon: Activity },
      ]
    : [];

  return (
    <div className="px-3 pt-2.5 pb-24 max-w-md mx-auto text-slate-800">
      {error && (
        <div className="mb-2 rounded-xl bg-rose-50 border border-rose-200 p-2.5 text-[11px] text-rose-700">{error}</div>
      )}

      <div className="grid grid-cols-2 gap-2 mb-4">
        {kpis.map(({ label, value, sub, icon: Icon }) => (
          <div key={label} className="rounded-2xl bg-white border border-slate-100 p-3 shadow-xs">
            <div className="flex items-center justify-between">
              <span className="text-[10px] font-semibold text-slate-500 uppercase tracking-wide">{label}</span>
              <Icon className="w-3.5 h-3.5 text-slate-400" />
            </div>
            <div className="text-xl font-black text-slate-900 mt-1">{value}</div>
            <div className="text-[10px] text-slate-400 mt-0.5">{sub}</div>
          </div>
        ))}
      </div>

      {/* Şikayətlər */}
      <h2 className="text-[11px] font-bold text-slate-500 uppercase tracking-wider px-1 mb-1.5">
        Şikayətlər ({reports.length})
      </h2>
      <div className="rounded-2xl bg-white border border-slate-100 divide-y divide-slate-100 mb-4 shadow-xs">
        {reports.length === 0 ? (
          <p className="p-3 text-[11px] text-slate-400">Açıq şikayət yoxdur.</p>
        ) : (
          reports.map((rp) => (
            <div key={rp.id} className="p-2.5 text-[11px]">
              <div className="flex items-start justify-between gap-2">
                <div className="min-w-0">
                  <div className="font-semibold text-slate-800">
                    {rp.kind === 'store' ? `Mağaza: ${rp.store_name ?? '—'}` : `Sorğu: ${rp.request_title ?? '—'}`}
                  </div>
                  <div className="text-[10px] text-slate-500">
                    {REASON_LABELS[rp.reason] ?? rp.reason} · {rp.reporter_role === 'buyer' ? 'alıcıdan' : 'satıcıdan'} ·{' '}
                    {formatTimeAgo(rp.created_at)}
                    {rp.kind === 'store' && rp.store_total_reports ? ` · bu mağaza üzrə cəmi ${rp.store_total_reports} şikayət` : ''}
                  </div>
                  {rp.details && <div className="text-[11px] text-slate-600 mt-1">“{rp.details}”</div>}
                </div>
              </div>
              <div className="flex gap-1.5 mt-2 flex-wrap">
                <button disabled={busyId === rp.id} onClick={() => void resolveReport(rp, 'resolved')} className="px-2.5 py-1.5 bg-[#0B4635] text-white font-bold rounded-lg disabled:opacity-50">
                  Həll edildi
                </button>
                <button disabled={busyId === rp.id} onClick={() => void resolveReport(rp, 'dismissed')} className="px-2.5 py-1.5 bg-slate-100 text-slate-600 font-bold rounded-lg disabled:opacity-50">
                  Əsassız
                </button>
                {rp.kind === 'store' && rp.store_id && !rp.store_suspended && (
                  <button disabled={busyId === rp.id} onClick={() => void suspend(rp.store_id!, true, REASON_LABELS[rp.reason])} className="px-2.5 py-1.5 bg-rose-50 text-rose-600 border border-rose-200 font-bold rounded-lg disabled:opacity-50">
                    Mağazanı dayandır
                  </button>
                )}
                {rp.kind === 'request' && rp.request_id && rp.request_status === 'active' && (
                  <button disabled={busyId === rp.id} onClick={() => void removeRequest(rp)} className="px-2.5 py-1.5 bg-rose-50 text-rose-600 border border-rose-200 font-bold rounded-lg disabled:opacity-50">
                    Sorğunu sil
                  </button>
                )}
              </div>
            </div>
          ))
        )}
      </div>

      {/* Gəlir və sifarişlər */}
      {billing && (
        <>
          <h2 className="text-[11px] font-bold text-slate-500 uppercase tracking-wider px-1 mb-1.5 flex items-center gap-1.5">
            <Wallet className="w-3.5 h-3.5" /> Gəlir və sifarişlər
          </h2>
          <div className="grid grid-cols-2 gap-2 mb-2.5">
            <div className="rounded-2xl bg-white border border-slate-100 p-3 shadow-xs">
              <div className="text-[10px] font-semibold text-slate-500 uppercase">Gəlir (30 gün)</div>
              <div className="text-xl font-black text-[#0B4635] mt-1">{formatPrice(billing.revenue_30d)}</div>
              <div className="text-[10px] text-slate-400">cəmi {formatPrice(billing.revenue_total)}</div>
            </div>
            <div className="rounded-2xl bg-white border border-slate-100 p-3 shadow-xs">
              <div className="text-[10px] font-semibold text-slate-500 uppercase">Abunələr</div>
              <div className="text-xl font-black text-slate-900 mt-1">
                {billing.active_plus} Plus · {billing.active_pro} Pro
              </div>
              <div className="text-[10px] text-slate-400">{billing.pending_orders} gözləyən sifariş</div>
            </div>
          </div>

          <div className="rounded-2xl bg-white border border-slate-100 divide-y divide-slate-100 mb-4 shadow-xs">
            {orders.length === 0 ? (
              <p className="p-3 text-[11px] text-slate-400">Sifariş yoxdur.</p>
            ) : (
              orders.slice(0, 20).map((o) => (
                <div key={o.id} className="p-2.5 text-[11px]">
                  <div className="flex items-start justify-between gap-2">
                    <div className="min-w-0">
                      <div className="font-semibold text-slate-800 truncate">
                        {o.store_name} — {o.title}
                      </div>
                      <div className="text-[10px] text-slate-500">
                        <span className="font-mono font-bold text-[#9A5B00]">{o.reference}</span> · {formatPrice(o.amount_azn)} ·{' '}
                        {formatPhone(o.store_phone)} · {formatTimeAgo(o.created_at)}
                      </div>
                    </div>
                    <span
                      className={`text-[10px] font-bold px-2 py-0.5 rounded-full whitespace-nowrap ${
                        o.status === 'pending'
                          ? 'bg-amber-50 text-amber-700'
                          : o.status === 'paid'
                          ? 'bg-emerald-50 text-emerald-700'
                          : 'bg-slate-100 text-slate-500'
                      }`}
                    >
                      {o.status === 'pending' ? 'Gözləyir' : o.status === 'paid' ? 'Ödənilib' : 'Ləğv'}
                    </span>
                  </div>
                  {o.status !== 'paid' && (
                    <div className="flex gap-2 mt-2">
                      <button
                        disabled={busyId === o.id}
                        onClick={() => void confirmOrder(o)}
                        className="flex-[2] py-1.5 bg-[#0B4635] text-white text-[11px] font-bold rounded-lg disabled:opacity-50"
                      >
                        Ödənişi təsdiqlə
                      </button>
                      {o.status === 'pending' && (
                        <button
                          disabled={busyId === o.id}
                          onClick={() => void cancelOrder(o)}
                          className="flex-1 py-1.5 bg-slate-100 text-slate-600 text-[11px] font-bold rounded-lg disabled:opacity-50"
                        >
                          Ləğv et
                        </button>
                      )}
                    </div>
                  )}
                </div>
              ))
            )}
          </div>

          <h2 className="text-[11px] font-bold text-slate-500 uppercase tracking-wider px-1 mb-1.5">Qiymətlər və mətnlər</h2>
          <div className="rounded-2xl bg-white border border-slate-100 p-3 mb-4 shadow-xs space-y-2.5">
            {billing.catalog.map((c) => (
              <div key={c.key} className="flex items-center gap-2 text-[11px]">
                <span className="flex-1 font-semibold text-slate-700">{c.title}</span>
                <input
                  type="number"
                  inputMode="decimal"
                  value={priceDraft[c.key] ?? String(c.price_azn)}
                  onChange={(e) => setPriceDraft((d) => ({ ...d, [c.key]: e.target.value }))}
                  className="w-20 bg-slate-50 border border-slate-200 rounded-lg px-2 py-1.5 text-xs"
                />
                <span className="text-slate-400">AZN</span>
                <button
                  disabled={priceDraft[c.key] === undefined}
                  onClick={() => void savePrice(c.key)}
                  className="px-2.5 py-1.5 bg-[#0B4635] text-white font-bold rounded-lg disabled:opacity-30"
                >
                  Saxla
                </button>
              </div>
            ))}
            {(
              [
                ['payment_instructions', 'Ödəniş təlimatı (kart nömrəsi, ad və s.)', true],
                ['support_whatsapp', 'Dəstək WhatsApp nömrəsi (994501234567)', false],
                ['telegram_bot_username', 'Telegram bot adı (@olmadan)', false],
              ] as const
            ).map(([key, label, multi]) => {
              const value = textDraft[key] ?? billing.texts[key] ?? '';
              return (
                <div key={key}>
                  <label className="text-[10px] text-slate-500 font-medium block mb-0.5">{label}</label>
                  <div className="flex gap-2">
                    {multi ? (
                      <textarea
                        rows={3}
                        value={value}
                        onChange={(e) => setTextDraft((d) => ({ ...d, [key]: e.target.value }))}
                        className="flex-1 bg-slate-50 border border-slate-200 rounded-lg px-2 py-1.5 text-xs"
                      />
                    ) : (
                      <input
                        value={value}
                        onChange={(e) => setTextDraft((d) => ({ ...d, [key]: e.target.value }))}
                        className="flex-1 bg-slate-50 border border-slate-200 rounded-lg px-2 py-1.5 text-xs"
                      />
                    )}
                    <button
                      disabled={textDraft[key] === undefined}
                      onClick={() => void saveText(key)}
                      className="px-2.5 bg-[#0B4635] text-white text-[11px] font-bold rounded-lg disabled:opacity-30"
                    >
                      Saxla
                    </button>
                  </div>
                </div>
              );
            })}
          </div>

          <div className="mb-4">
            <TelegramCard botUsername={billing.texts.telegram_bot_username} />
          </div>
        </>
      )}

      {/* Mağazalar */}
      <h2 className="text-[11px] font-bold text-slate-500 uppercase tracking-wider px-1 mb-1.5 flex items-center gap-1.5">
        <TrendingUp className="w-3.5 h-3.5" /> Mağazalar ({stores.length})
      </h2>
      <div className="space-y-2 mb-4">
        {stores.map((s) => (
          <div key={s.id} className="rounded-2xl bg-white border border-slate-100 p-3 shadow-xs">
            <div className="flex items-start justify-between gap-2">
              <div className="min-w-0">
                <div className="flex items-center gap-1.5">
                  <span className="text-xs font-bold text-slate-800 truncate">{s.name}</span>
                  {s.verified && <ShieldCheck className="w-3.5 h-3.5 text-[#0B4635] flex-shrink-0" />}
                  {s.suspended && (
                    <span className="text-[9px] font-bold text-rose-700 bg-rose-50 border border-rose-200 rounded px-1">Dayandırılıb</span>
                  )}
                  {effectivePlan(s) !== 'free' && (
                    <span className="inline-flex items-center gap-0.5 text-[9px] font-bold text-amber-700 bg-amber-50 border border-amber-200 rounded px-1">
                      <Crown className="w-2.5 h-2.5" /> {effectivePlan(s) === 'pro' ? 'Pro' : 'Plus'}
                    </span>
                  )}
                  <span className={`text-[10px] font-bold ${GRADE_COLORS[s.grade] ?? 'text-slate-500'}`}>{s.grade}</span>
                </div>
                <div className="text-[10px] text-slate-500 mt-0.5">
                  {formatPhone(s.phone)}
                  {s.voen ? ` · VÖEN ${s.voen}` : ''}
                </div>
                <div className="text-[10px] text-slate-400 mt-0.5">
                  {s.review_count > 0 ? `★ ${Number(s.rating).toFixed(1)} (${s.review_count})` : 'Rəy yoxdur'} · uğursuz:{' '}
                  {s.failed_deals} · {s.owner_id ? 'hesab bağlı' : 'HESAB BAĞLI DEYİL'}
                </div>
              </div>
              <div className="text-right flex-shrink-0">
                <div className="text-sm font-black text-[#0B4635]">{formatCoin(s.coin_balance)}</div>
                <div className="text-[9px] text-slate-400">coin</div>
              </div>
            </div>

            <div className="flex items-center gap-1.5 mt-2 pt-2 border-t border-slate-100">
              {(['free', 'plus', 'pro'] as const).map((p) => (
                <button
                  key={p}
                  disabled={busyId === s.id}
                  onClick={() => void setPlan(s, p)}
                  className={`flex-1 py-1 rounded-lg border text-[10px] font-bold disabled:opacity-50 ${
                    effectivePlan(s) === p ? 'bg-amber-50 border-amber-300 text-amber-700' : 'bg-white border-slate-200 text-slate-500'
                  }`}
                >
                  {p === 'free' ? 'Free' : p === 'plus' ? 'Plus' : 'Pro'}
                </button>
              ))}
            </div>
            <div className="flex items-center gap-1.5 mt-1.5">
              <button
                disabled={busyId === s.id}
                onClick={() => void suspend(s.id, !s.suspended, 'Admin qərarı')}
                className={`px-2 py-1.5 rounded-lg border text-[10px] font-bold disabled:opacity-50 ${
                  s.suspended ? 'bg-emerald-50 border-emerald-200 text-emerald-700' : 'bg-white border-slate-200 text-slate-500'
                }`}
              >
                {s.suspended ? 'Bərpa et' : 'Dayandır'}
              </button>
              {[-10, -1, 1, 10].map((d) => (
                <button
                  key={d}
                  disabled={busyId === s.id}
                  onClick={() => void adjust(s, d)}
                  className="flex-1 py-1.5 rounded-lg bg-slate-50 hover:bg-slate-100 border border-slate-200 text-[11px] font-bold text-slate-700 flex items-center justify-center gap-0.5 disabled:opacity-50"
                >
                  {d > 0 ? <Plus className="w-3 h-3" /> : <Minus className="w-3 h-3" />}
                  {Math.abs(d)}
                </button>
              ))}
              <button
                disabled={busyId === s.id}
                onClick={() => void toggleVerified(s)}
                className={`flex-[1.5] py-1.5 rounded-lg text-[11px] font-bold border disabled:opacity-50 ${
                  s.verified
                    ? 'bg-emerald-50 border-emerald-200 text-emerald-700'
                    : 'bg-white border-slate-200 text-slate-600'
                }`}
              >
                {s.verified ? 'Təsdiqli ✓' : 'Təsdiqlə'}
              </button>
            </div>
          </div>
        ))}
      </div>

      {/* Son sorğular */}
      <h2 className="text-[11px] font-bold text-slate-500 uppercase tracking-wider px-1 mb-1.5">Son sorğular</h2>
      <div className="rounded-2xl bg-white border border-slate-100 divide-y divide-slate-100 mb-4 shadow-xs">
        {requests.length === 0 ? (
          <p className="p-3 text-[11px] text-slate-400">Sorğu yoxdur.</p>
        ) : (
          requests.map((r) => (
            <div key={r.id} className="p-2.5 flex items-center justify-between gap-2 text-[11px]">
              <div className="min-w-0">
                <div className="font-semibold text-slate-800 truncate">
                  {r.brand} {r.model} — {r.part_name}
                </div>
                <div className="text-[10px] text-slate-400">{formatTimeAgo(r.created_at)}</div>
              </div>
              <span className="text-[10px] font-bold text-slate-600 bg-slate-100 px-2 py-0.5 rounded-full whitespace-nowrap">
                {REQ_STATUS[r.status] ?? r.status}
              </span>
            </div>
          ))
        )}
      </div>

      {/* Son təkliflər */}
      <h2 className="text-[11px] font-bold text-slate-500 uppercase tracking-wider px-1 mb-1.5">Son təkliflər</h2>
      <div className="rounded-2xl bg-white border border-slate-100 divide-y divide-slate-100 shadow-xs">
        {bids.length === 0 ? (
          <p className="p-3 text-[11px] text-slate-400">Təklif yoxdur.</p>
        ) : (
          bids.map((b) => (
            <div key={b.id} className="p-2.5 flex items-center justify-between gap-2 text-[11px]">
              <div className="min-w-0">
                <div className="font-semibold text-slate-800 truncate">{b.store?.name ?? 'Mağaza'}</div>
                <div className="text-[10px] text-slate-400">{formatTimeAgo(b.created_at)}</div>
              </div>
              <div className="text-right">
                <div className="font-bold text-[#0B4635]">{formatPrice(b.price_azn)}</div>
                <div className="text-[10px] text-slate-500">{BID_STATUS[b.status] ?? b.status}</div>
              </div>
            </div>
          ))
        )}
      </div>
    </div>
  );
}
