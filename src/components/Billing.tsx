import { useCallback, useEffect, useState, type ReactNode } from 'react';
import { Check, Coins, Crown, Lock, MessageCircle, Send, Sparkles } from 'lucide-react';
import { CATEGORIES } from '@/lib/supabase';
import * as api from '@/lib/api';
import { whatsappUrl } from '@/lib/validate';
import { PLAN_LABELS, formatCoin, formatPrice, formatTimeAgo, showToast } from '@/lib/utils';
import type {
  AppTexts,
  BillingOverview,
  CatalogItem,
  CoinLedgerItem,
  CreatedOrder,
  Insights,
  PaymentOrder,
} from '@/lib/types';

const LEDGER_LABELS: Record<string, string> = {
  SIGNUP: 'Qeydiyyat bonusu',
  BID_FEE: 'Təklif haqqı',
  REFUND: 'Coin geri qaytarıldı',
  SALE_BONUS: 'Satış bonusu',
  BONUS_REVOKED: 'Bonus geri alındı',
  ADMIN_ADJUST: 'Admin düzəlişi',
  PURCHASE: 'Coin alışı',
};

const ORDER_STATUS: Record<string, { text: string; cls: string }> = {
  pending: { text: 'Ödəniş gözlənilir', cls: 'bg-amber-50 text-amber-700 border-amber-200' },
  paid: { text: 'Təsdiqləndi', cls: 'bg-emerald-50 text-emerald-700 border-emerald-200' },
  cancelled: { text: 'Ləğv edilib', cls: 'bg-slate-100 text-slate-500 border-slate-200' },
};

function catName(key: string): string {
  return CATEGORIES.find((c) => c.key === key)?.short ?? 'Digər';
}

function Card({ title, children, icon }: { title?: string; children: ReactNode; icon?: ReactNode }) {
  return (
    <div className="rounded-2xl bg-white border border-slate-100 p-3.5 shadow-xs">
      {title && (
        <h3 className="text-xs font-bold text-slate-800 mb-2 flex items-center gap-1.5">
          {icon}
          {title}
        </h3>
      )}
      {children}
    </div>
  );
}

/* ====================================================================== */
/* Telegram                                                                */
/* ====================================================================== */

export function TelegramCard({ botUsername }: { botUsername: string | undefined }) {
  const [linked, setLinked] = useState<boolean | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    try {
      setLinked((await api.telegramStatus()).linked);
    } catch {
      setLinked(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  // Bağlama linkinə keçəndən sonra qayıdanda statusu yenilə
  useEffect(() => {
    const onVisible = () => {
      if (document.visibilityState === 'visible') void load();
    };
    document.addEventListener('visibilitychange', onVisible);
    return () => document.removeEventListener('visibilitychange', onVisible);
  }, [load]);

  const connect = async () => {
    setError(null);
    if (!botUsername) {
      setError('Telegram bot hələ qurulmayıb. Dəstək ilə əlaqə saxlayın.');
      return;
    }
    setBusy(true);
    try {
      const code = await api.telegramCreateCode();
      window.open(`https://t.me/${botUsername.replace(/^@/, '')}?start=${code}`, '_blank', 'noopener');
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Kod yaradılmadı.');
    } finally {
      setBusy(false);
    }
  };

  const unlink = async () => {
    setBusy(true);
    try {
      await api.telegramUnlink();
      setLinked(false);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Ayrılmadı.');
    } finally {
      setBusy(false);
    }
  };

  return (
    <Card title="Telegram bildirişləri" icon={<Send className="w-3.5 h-3.5 text-sky-500" />}>
      <p className="text-[11px] text-slate-500">
        Yeni sorğular və təklif nəticələri telefonunuza Telegram-da düşsün — tətbiqi açıq saxlamağa ehtiyac yoxdur.
      </p>
      {linked ? (
        <div className="mt-2.5 flex items-center justify-between gap-2">
          <span className="text-[11px] font-bold text-emerald-700 flex items-center gap-1">
            <Check className="w-3.5 h-3.5" /> Bağlıdır
          </span>
          <button
            onClick={unlink}
            disabled={busy}
            className="text-[11px] font-semibold text-slate-500 border border-slate-200 rounded-lg px-3 py-1.5"
          >
            Ayır
          </button>
        </div>
      ) : (
        <button
          onClick={connect}
          disabled={busy || linked === null}
          className="mt-2.5 w-full py-2 bg-sky-500 hover:bg-sky-600 text-white text-[11px] font-bold rounded-lg disabled:opacity-60"
        >
          {busy ? 'Hazırlanır…' : 'Telegram-ı bağla'}
        </button>
      )}
      {error && <p className="text-[11px] text-rose-600 mt-2">{error}</p>}
    </Card>
  );
}

/* ====================================================================== */
/* Hesab: balans, plan, paketlər, sifarişlər, coin tarixçəsi               */
/* ====================================================================== */

const PLAN_FEATURES: Record<'free' | 'plus' | 'pro', string[]> = {
  free: ['Təklif haqqı: 1 coin', 'Əsas statistika', 'Arxiv: son 7 gün'],
  plus: ['Təklif haqqı 50% endirimli (0.5 coin)', 'Bazar analizi: kateqoriya və marka üzrə orta satış qiymətləri', 'Cavabsız qalan tələb'],
  pro: [
    'Təkliflər pulsuz (limitsiz coin)',
    'Plus-ın hamısı',
    'Ən çox axtarılan detallar və qiymət aralığı',
    'Saatlara görə tələb, qiymət mövqeyi, cavab sürəti',
  ],
};

export function AccountTab({
  texts,
  onChanged,
  focusOrderId,
}: {
  texts: AppTexts;
  onChanged: () => Promise<void> | void;
  focusOrderId?: string | null;
}) {
  const [data, setData] = useState<BillingOverview | null>(null);
  const [ledger, setLedger] = useState<CoinLedgerItem[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [busyKey, setBusyKey] = useState<string | null>(null);
  const [created, setCreated] = useState<CreatedOrder | null>(null);

  const load = useCallback(async () => {
    try {
      const [o, l] = await Promise.all([api.billingOverview(), api.fetchCoinLedger()]);
      setData(o);
      setLedger(l);
      setError(null);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Hesab yüklənmədi.');
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  const order = async (item: CatalogItem) => {
    setBusyKey(item.key);
    setError(null);
    try {
      const o = await api.createPaymentOrder(item.key);
      setCreated(o);
      await load();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Sifariş yaradılmadı.');
    } finally {
      setBusyKey(null);
    }
  };

  const cancel = async (o: PaymentOrder) => {
    try {
      await api.cancelPaymentOrder(o.id);
      if (created?.id === o.id) setCreated(null);
      await load();
    } catch (e) {
      showToast({ title: 'Ləğv edilmədi', body: e instanceof Error ? e.message : undefined, type: 'error' });
    }
  };

  const refreshAll = async () => {
    await load();
    await onChanged();
  };

  if (!data) {
    return error ? (
      <div className="rounded-xl bg-rose-50 border border-rose-200 p-3 text-[11px] text-rose-700">{error}</div>
    ) : (
      <div className="space-y-2.5">
        {[1, 2, 3].map((i) => (
          <div key={i} className="rounded-2xl bg-white border border-slate-100 h-20 animate-pulse" />
        ))}
      </div>
    );
  }

  const coins = data.catalog.filter((c) => c.kind === 'coins');
  const plans = data.catalog.filter((c) => c.kind === 'plan');
  const pending = data.orders.filter((o) => o.status === 'pending');
  const shown = created ?? (focusOrderId ? pending.find((o) => o.id === focusOrderId) : null);

  const planUntil = data.plan_until ? new Date(data.plan_until).toLocaleDateString('az-AZ') : null;

  return (
    <div className="space-y-3">
      {error && <div className="rounded-xl bg-rose-50 border border-rose-200 p-2.5 text-[11px] text-rose-700">{error}</div>}

      <Card>
        <div className="flex items-center justify-between">
          <div>
            <div className="text-[10px] uppercase tracking-wider text-slate-400 font-semibold">Balans</div>
            <div className="text-2xl font-black text-[#0B4635] flex items-center gap-1.5">
              <Coins className="w-5 h-5 text-amber-500" /> {formatCoin(data.coin_balance)}
            </div>
          </div>
          <div className="text-right">
            <div className="text-[10px] uppercase tracking-wider text-slate-400 font-semibold">Plan</div>
            <div className="text-sm font-black text-slate-800 flex items-center gap-1 justify-end">
              {data.plan !== 'free' && <Crown className="w-4 h-4 text-amber-500" />}
              {PLAN_LABELS[data.plan]}
            </div>
            <div className="text-[10px] text-slate-400">{planUntil ? `${planUntil}-dək` : `Təklif: ${formatCoin(data.bid_fee)} coin`}</div>
          </div>
        </div>
        <p className="text-[10px] text-slate-400 mt-2">
          Təklif seçilməsə və sorğunun vaxtı bitsə, ödədiyiniz coin geri qayıdır. Satış olanda +5 coin bonus alırsınız.
        </p>
      </Card>

      {/* Ödəniş təlimatı */}
      {shown && 'reference' in shown && (
        <PaymentInstructions
          reference={shown.reference}
          amount={Number(shown.amount_azn)}
          title={shown.title}
          texts={texts}
          onClose={() => setCreated(null)}
        />
      )}

      {/* Coin paketləri */}
      <Card title="Coin al" icon={<Coins className="w-3.5 h-3.5 text-amber-500" />}>
        <div className="grid grid-cols-3 gap-2">
          {coins.map((c) => (
            <button
              key={c.key}
              disabled={busyKey === c.key}
              onClick={() => void order(c)}
              className="rounded-xl border border-slate-200 bg-slate-50 hover:border-[#0B4635] p-2.5 text-center disabled:opacity-60"
            >
              <div className="text-base font-black text-[#0B4635]">{formatCoin(c.coins)}</div>
              <div className="text-[9px] text-slate-400 -mt-0.5">coin</div>
              <div className="text-xs font-bold text-slate-800 mt-1">{formatPrice(c.price_azn)}</div>
              {c.coins ? (
                <div className="text-[9px] text-slate-400">{(c.price_azn / c.coins).toFixed(2)} AZN/coin</div>
              ) : null}
            </button>
          ))}
        </div>
      </Card>

      {/* Planlar */}
      <Card title="Abunəlik" icon={<Sparkles className="w-3.5 h-3.5 text-[#9A5B00]" />}>
        <div className="space-y-2.5">
          {(['free', ...plans.map((p) => p.plan)] as ('free' | 'plus' | 'pro')[]).map((key) => {
            const item = plans.find((p) => p.plan === key);
            const active = data.plan === key;
            return (
              <div
                key={key}
                className={`rounded-xl border p-3 ${active ? 'border-[#0B4635] bg-emerald-50/40' : 'border-slate-200'}`}
              >
                <div className="flex items-center justify-between">
                  <span className="text-xs font-black text-slate-800 flex items-center gap-1">
                    {key !== 'free' && <Crown className="w-3.5 h-3.5 text-amber-500" />}
                    {PLAN_LABELS[key]}
                    {active && <span className="text-[9px] font-bold text-emerald-700 bg-emerald-100 px-1.5 py-0.5 rounded ml-1">Aktiv</span>}
                  </span>
                  {item && <span className="text-xs font-bold text-slate-800">{formatPrice(item.price_azn)} / {item.days} gün</span>}
                </div>
                <ul className="mt-1.5 space-y-0.5">
                  {PLAN_FEATURES[key].map((f) => (
                    <li key={f} className="text-[11px] text-slate-600 flex gap-1.5">
                      <Check className="w-3 h-3 mt-0.5 text-emerald-600 flex-shrink-0" /> {f}
                    </li>
                  ))}
                </ul>
                {item && !active && (
                  <button
                    disabled={busyKey === item.key}
                    onClick={() => void order(item)}
                    className="mt-2.5 w-full py-2 bg-[#FFC61A] hover:bg-[#FFD24D] text-[#1B1B12] text-[11px] font-bold rounded-lg disabled:opacity-60"
                  >
                    {data.plan === key ? 'Uzat' : `${PLAN_LABELS[key]}-a keç`}
                  </button>
                )}
                {item && active && (
                  <button
                    disabled={busyKey === item.key}
                    onClick={() => void order(item)}
                    className="mt-2.5 w-full py-2 bg-white border border-slate-200 text-slate-700 text-[11px] font-bold rounded-lg disabled:opacity-60"
                  >
                    {item.days} gün uzat
                  </button>
                )}
              </div>
            );
          })}
        </div>
      </Card>

      {/* Sifarişlər */}
      {data.orders.length > 0 && (
        <Card title="Sifarişlər">
          <div className="divide-y divide-slate-100">
            {data.orders.map((o) => {
              const st = ORDER_STATUS[o.status];
              return (
                <div key={o.id} className="py-2 flex items-center justify-between gap-2 text-[11px]">
                  <div className="min-w-0">
                    <div className="font-semibold text-slate-800">
                      {o.title} · {formatPrice(o.amount_azn)}
                    </div>
                    <div className="text-[10px] text-slate-400 font-mono">
                      {o.reference} · {formatTimeAgo(o.created_at)}
                    </div>
                  </div>
                  <div className="flex flex-col items-end gap-1 flex-shrink-0">
                    <span className={`text-[10px] font-bold px-2 py-0.5 rounded-full border ${st.cls}`}>{st.text}</span>
                    {o.status === 'pending' && (
                      <div className="flex gap-2">
                        <button
                          className="text-[10px] font-semibold text-[#0B4635]"
                          onClick={() =>
                            setCreated({ id: o.id, reference: o.reference, amount_azn: o.amount_azn, title: o.title })
                          }
                        >
                          Necə ödəyim?
                        </button>
                        <button className="text-[10px] text-slate-400" onClick={() => void cancel(o)}>
                          Ləğv
                        </button>
                      </div>
                    )}
                  </div>
                </div>
              );
            })}
          </div>
        </Card>
      )}

      <TelegramCard botUsername={texts.telegram_bot_username} />

      <Card title="Coin hərəkətləri">
        {ledger.length === 0 ? (
          <p className="text-[11px] text-slate-400">Hələ hərəkət yoxdur.</p>
        ) : (
          <div className="divide-y divide-slate-100">
            {ledger.map((l) => (
              <div key={l.id} className="py-1.5 flex items-center justify-between text-[11px]">
                <div>
                  <div className="text-slate-700 font-medium">{LEDGER_LABELS[l.type] ?? l.type}</div>
                  <div className="text-[10px] text-slate-400">{formatTimeAgo(l.created_at)}</div>
                </div>
                <span className={`font-bold ${l.amount >= 0 ? 'text-emerald-600' : 'text-rose-500'}`}>
                  {l.amount > 0 ? `+${formatCoin(l.amount)}` : formatCoin(l.amount)}
                </span>
              </div>
            ))}
          </div>
        )}
      </Card>

      <button onClick={() => void refreshAll()} className="w-full text-[11px] text-slate-400 py-1">
        Yenilə
      </button>
    </div>
  );
}

function PaymentInstructions({
  reference,
  amount,
  title,
  texts,
  onClose,
}: {
  reference: string;
  amount: number;
  title: string;
  texts: AppTexts;
  onClose: () => void;
}) {
  const wa = texts.support_whatsapp
    ? whatsappUrl(texts.support_whatsapp, `Salam, AutoTender sifarişi ${reference} (${title}, ${amount} AZN) üçün ödəniş etdim.`)
    : null;
  return (
    <div className="rounded-2xl border-2 border-[#FFC61A] bg-amber-50/50 p-3.5">
      <div className="flex items-start justify-between gap-2">
        <h3 className="text-xs font-black text-slate-900">Sifariş yaradıldı</h3>
        <button onClick={onClose} className="text-[10px] text-slate-400">
          Bağla
        </button>
      </div>
      <div className="mt-2 grid grid-cols-2 gap-2 text-center">
        <div className="rounded-lg bg-white border border-slate-200 p-2">
          <div className="text-[9px] text-slate-400 uppercase">Məbləğ</div>
          <div className="text-sm font-black text-slate-900">{formatPrice(amount)}</div>
        </div>
        <div className="rounded-lg bg-white border border-slate-200 p-2">
          <div className="text-[9px] text-slate-400 uppercase">Ödəniş kodu</div>
          <div className="text-sm font-black font-mono text-[#9A5B00]">{reference}</div>
        </div>
      </div>
      <p className="text-[11px] text-slate-700 mt-2.5 whitespace-pre-line">{texts.payment_instructions}</p>
      <p className="text-[10px] text-slate-500 mt-1.5">
        Ödənişin izahına yuxarıdakı kodu yazın. Təsdiqdən sonra {title} hesabınıza əlavə olunur.
      </p>
      {wa && (
        <a
          href={wa}
          target="_blank"
          rel="noreferrer"
          className="mt-2.5 w-full py-2.5 bg-[#25D366] hover:bg-[#1fb857] text-white text-[11px] font-bold rounded-lg flex items-center justify-center gap-1"
        >
          <MessageCircle className="w-3.5 h-3.5" /> Ödənişi WhatsApp-da bildir
        </a>
      )}
    </div>
  );
}

/* ====================================================================== */
/* Analiz (Plus / Pro)                                                     */
/* ====================================================================== */

function Bar({ value, max, tone = 'green' }: { value: number; max: number; tone?: 'green' | 'orange' }) {
  const w = max > 0 ? Math.max(4, Math.round((value / max) * 100)) : 0;
  return (
    <div className="h-1.5 rounded-full bg-slate-100 overflow-hidden">
      <div className={`h-full rounded-full ${tone === 'green' ? 'bg-[#0B4635]' : 'bg-[#FFC61A]'}`} style={{ width: `${w}%` }} />
    </div>
  );
}

function Locked({ need, text, onUpgrade }: { need: 'Plus' | 'Pro'; text: string; onUpgrade: () => void }) {
  return (
    <div className="rounded-2xl border border-dashed border-slate-300 bg-white p-4 text-center">
      <Lock className="w-5 h-5 text-slate-400 mx-auto" />
      <p className="text-xs font-bold text-slate-800 mt-1.5">{need} planında açılır</p>
      <p className="text-[11px] text-slate-500 mt-0.5">{text}</p>
      <button onClick={onUpgrade} className="mt-2.5 px-4 py-2 bg-[#FFC61A] text-[#1B1B12] text-[11px] font-bold rounded-lg">
        {need}-a bax
      </button>
    </div>
  );
}

export function InsightsView({ onUpgrade }: { onUpgrade: () => void }) {
  const [data, setData] = useState<Insights | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    api
      .sellerInsights()
      .then((d) => {
        if (!cancelled) setData(d);
      })
      .catch((e) => {
        if (!cancelled) setError(e instanceof Error ? e.message : 'Analiz yüklənmədi.');
      });
    return () => {
      cancelled = true;
    };
  }, []);

  if (error) return <div className="rounded-xl bg-rose-50 border border-rose-200 p-2.5 text-[11px] text-rose-700">{error}</div>;
  if (!data) return <div className="rounded-2xl bg-white border border-slate-100 h-24 animate-pulse" />;

  const market = data.market;
  const pro = data.pro;
  const maxReq = Math.max(1, ...(market?.by_category.map((c) => c.requests) ?? [1]));
  const maxHour = Math.max(1, ...(pro?.hourly ?? [1]));

  return (
    <div className="space-y-3">
      <Card title="Bazar (son 30 gün)">
        <div className="grid grid-cols-2 gap-2 text-center">
          <div className="rounded-xl bg-slate-50 p-2.5">
            <div className="text-lg font-black text-[#0B4635]">{data.teaser.requests_30d}</div>
            <div className="text-[10px] text-slate-500">sizin markalara sorğu</div>
          </div>
          <div className="rounded-xl bg-slate-50 p-2.5">
            <div className="text-lg font-black text-[#0B4635]">{data.teaser.completed_30d}</div>
            <div className="text-[10px] text-slate-500">satışla bitən</div>
          </div>
        </div>
      </Card>

      {!market ? (
        <Locked
          need="Plus"
          text="Kateqoriya və marka üzrə orta satış qiymətləri, cavabsız qalan tələb."
          onUpgrade={onUpgrade}
        />
      ) : (
        <>
          <Card title="Kateqoriya üzrə bazar">
            {market.by_category.length === 0 ? (
              <p className="text-[11px] text-slate-400">Hələ kifayət qədər məlumat yoxdur.</p>
            ) : (
              <div className="space-y-3">
                {market.by_category.map((c) => (
                  <div key={c.category}>
                    <div className="flex items-center justify-between text-[11px]">
                      <span className="font-semibold text-slate-800">{catName(c.category)}</span>
                      <span className="text-slate-500">{c.requests} sorğu</span>
                    </div>
                    <Bar value={c.requests} max={maxReq} />
                    <div className="text-[10px] text-slate-500 mt-1 flex flex-wrap gap-x-3">
                      <span>Orta satış: {c.avg_win_price != null ? formatPrice(c.avg_win_price) : '—'}</span>
                      <span>Orta təklif: {c.avg_bids ?? 0}</span>
                      <span>Təkliflənməyən: {c.no_bid_requests}</span>
                      <span>Sizin: {c.my_bids} təklif / {c.my_wins} satış</span>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </Card>

          <Card title="Marka üzrə">
            <div className="divide-y divide-slate-100">
              {market.by_brand.map((b) => (
                <div key={b.brand} className="py-1.5 flex items-center justify-between text-[11px]">
                  <span className="font-semibold text-slate-800">{b.brand}</span>
                  <span className="text-slate-500">
                    {b.requests} sorğu · orta satış {b.avg_win_price != null ? formatPrice(b.avg_win_price) : '—'}
                  </span>
                </div>
              ))}
              {market.by_brand.length === 0 && <p className="text-[11px] text-slate-400">Məlumat yoxdur.</p>}
            </div>
            <p className="text-[10px] text-slate-400 mt-2">Orta qiymət ən azı 3 satış olanda göstərilir.</p>
          </Card>
        </>
      )}

      {!pro ? (
        <Locked
          need="Pro"
          text="Ən çox axtarılan detallar, saatlara görə tələb, qiymət mövqeyiniz və cavab sürətiniz."
          onUpgrade={onUpgrade}
        />
      ) : (
        <>
          <Card title="Sizin qiymət mövqeyiniz">
            <div className="grid grid-cols-3 gap-2 text-center">
              <div className="rounded-xl bg-slate-50 p-2.5">
                <div className="text-lg font-black text-[#0B4635]">{pro.price_position.wins}</div>
                <div className="text-[10px] text-slate-500">satış</div>
              </div>
              <div className="rounded-xl bg-slate-50 p-2.5">
                <div className="text-lg font-black text-slate-700">{pro.price_position.losses}</div>
                <div className="text-[10px] text-slate-500">uduzma</div>
              </div>
              <div className="rounded-xl bg-slate-50 p-2.5">
                <div className="text-lg font-black text-[#9A5B00]">
                  {pro.price_position.avg_gap_pct != null ? `${pro.price_position.avg_gap_pct > 0 ? '+' : ''}${pro.price_position.avg_gap_pct}%` : '—'}
                </div>
                <div className="text-[10px] text-slate-500">uduzanda fərq</div>
              </div>
            </div>
            {pro.by_category_position.length > 0 && (
              <div className="mt-2.5 divide-y divide-slate-100">
                {pro.by_category_position.map((c) => (
                  <div key={c.category} className="py-1.5 flex items-center justify-between text-[11px]">
                    <span className="font-semibold text-slate-800">{catName(c.category)}</span>
                    <span className="text-slate-500">
                      {c.wins} satış / {c.losses} uduzma
                      {c.avg_gap_pct != null ? ` · ${c.avg_gap_pct > 0 ? '+' : ''}${c.avg_gap_pct}%` : ''}
                    </span>
                  </div>
                ))}
              </div>
            )}
            <p className="text-[10px] text-slate-400 mt-2">
              “Uduzanda fərq” — qalibdən nə qədər bahalı olduğunuz (müsbət = bahalı).
            </p>
          </Card>

          <Card title="Ən çox axtarılan detallar">
            {pro.top_parts.length === 0 ? (
              <p className="text-[11px] text-slate-400">Hələ təkrarlanan axtarış yoxdur.</p>
            ) : (
              <div className="divide-y divide-slate-100">
                {pro.top_parts.map((p) => (
                  <div key={p.part} className="py-1.5 text-[11px]">
                    <div className="flex items-center justify-between">
                      <span className="font-semibold text-slate-800 capitalize">{p.part}</span>
                      <span className="text-slate-500">{p.requests} sorğu</span>
                    </div>
                    {p.avg_win_price != null && (
                      <div className="text-[10px] text-slate-500">
                        Satış qiyməti: {formatPrice(p.min_win_price)} – {formatPrice(p.max_win_price)} (orta {formatPrice(p.avg_win_price)})
                      </div>
                    )}
                  </div>
                ))}
              </div>
            )}
          </Card>

          <Card title="Sorğular hansı saatlarda gəlir?">
            <div className="flex items-end gap-0.5 h-16">
              {pro.hourly.map((n, h) => (
                <div key={h} className="flex-1 flex flex-col items-center justify-end h-full" title={`${h}:00 — ${n}`}>
                  <div className="w-full rounded-t bg-[#0B4635]/80" style={{ height: `${Math.max(3, (n / maxHour) * 100)}%` }} />
                </div>
              ))}
            </div>
            <div className="flex justify-between text-[9px] text-slate-400 mt-1">
              <span>00</span>
              <span>06</span>
              <span>12</span>
              <span>18</span>
              <span>23</span>
            </div>
            <p className="text-[10px] text-slate-400 mt-1">Bakı vaxtı ilə. Ən hündür sütunlarda tez cavab verin.</p>
          </Card>

          <Card title="Cavab sürəti">
            <div className="grid grid-cols-2 gap-2 text-center">
              <div className="rounded-xl bg-slate-50 p-2.5">
                <div className="text-lg font-black text-[#0B4635]">
                  {pro.response_speed.my_median_min != null ? `${pro.response_speed.my_median_min} dəq` : '—'}
                </div>
                <div className="text-[10px] text-slate-500">sizin orta cavab</div>
              </div>
              <div className="rounded-xl bg-slate-50 p-2.5">
                <div className="text-lg font-black text-[#9A5B00]">
                  {pro.response_speed.winner_median_min != null ? `${pro.response_speed.winner_median_min} dəq` : '—'}
                </div>
                <div className="text-[10px] text-slate-500">qazanan təkliflərin orta cavabı</div>
              </div>
            </div>
          </Card>

          <Card title="Cavabsız qalan tələb (son 7 gün)">
            {pro.unanswered_7d.length === 0 ? (
              <p className="text-[11px] text-slate-400">Cavabsız sorğu yoxdur.</p>
            ) : (
              <div className="divide-y divide-slate-100">
                {pro.unanswered_7d.map((u) => (
                  <div key={u.brand} className="py-1.5 flex items-center justify-between text-[11px]">
                    <span className="font-semibold text-slate-800">{u.brand}</span>
                    <span className="text-slate-500">{u.requests} sorğuya heç kim təklif verməyib</span>
                  </div>
                ))}
              </div>
            )}
          </Card>
        </>
      )}
    </div>
  );
}
