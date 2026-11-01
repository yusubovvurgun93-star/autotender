import { useCallback, useEffect, useState, type ReactNode } from 'react';
import { CATEGORIES } from '@/lib/supabase';
import * as api from '@/lib/api';
import { whatsappUrl } from '@/lib/validate';
import { PLAN_LABELS, formatCoin, formatPrice, formatTimeAgo, showToast } from '@/lib/utils';
import { Sheet } from '@/components/ui';
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
  PLAN_BONUS: 'Plan hədiyyəsi',
};

const ORDER_STATUS: Record<string, { text: string; cls: string }> = {
  pending: { text: 'Ödəniş gözlənilir', cls: 'tag-amber' },
  paid: { text: 'Təsdiqləndi', cls: 'tag-green' },
  cancelled: { text: 'Ləğv edilib', cls: 'tag' },
};

function catName(key: string): string {
  return CATEGORIES.find((c) => c.key === key)?.short ?? 'Digər';
}

function Card({ title, children }: { title?: string; children: ReactNode }) {
  return (
    <div className="card">
      {title && <h3 className="font-display text-sm font-extrabold text-slate-900 mb-2.5">{title}</h3>}
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
    <Card title="Telegram bildirişləri">
      <p className="text-xs text-slate-500">Yeni sorğular və nəticələr telefonunuza Telegram-da düşür.</p>
      {linked ? (
        <div className="mt-3 flex items-center justify-between gap-2">
          <span className="tag-green">Bağlıdır</span>
          <button onClick={unlink} disabled={busy} className="btn-ghost !py-2">
            Ayır
          </button>
        </div>
      ) : (
        <button onClick={connect} disabled={busy || linked === null} className="btn-primary mt-3 w-full">
          {busy ? 'Hazırlanır…' : 'Telegram-ı bağla'}
        </button>
      )}
      {error && <p className="text-xs text-rose-600 mt-2">{error}</p>}
    </Card>
  );
}

/* ====================================================================== */
/* Hesab: plan, paketlər, sifarişlər, coin tarixçəsi                       */
/* ====================================================================== */

const PLAN_FEATURES: Record<'free' | 'plus' | 'pro', string[]> = {
  free: ['Təklif: 1 coin', 'Əsas statistika'],
  plus: ['Hər ay 30 hədiyyə coin', 'Təklif 50% ucuz: 0.5 coin', 'Bazar analizi'],
  pro: ['Təkliflər pulsuz', 'Plus-ın hamısı', 'Dərin analiz: qiymət mövqeyi, saatlar, cavab sürəti'],
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
  const [payFor, setPayFor] = useState<CreatedOrder | null>(null);

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

  // Bildirişdən gələn sifariş avtomatik açılsın
  useEffect(() => {
    if (!focusOrderId || !data) return;
    const o = data.orders.find((x) => x.id === focusOrderId && x.status === 'pending');
    if (o) setPayFor({ id: o.id, reference: o.reference, amount_azn: o.amount_azn, title: o.title });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [focusOrderId, data?.orders.length]);

  const order = async (item: CatalogItem) => {
    setBusyKey(item.key);
    setError(null);
    try {
      const o = await api.createPaymentOrder(item.key);
      setPayFor(o);
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
      if (payFor?.id === o.id) setPayFor(null);
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
      <div className="rounded-2xl bg-rose-50 p-3 text-[13px] text-rose-700">{error}</div>
    ) : (
      <div className="space-y-3">
        {[1, 2, 3].map((i) => (
          <div key={i} className="skeleton h-24" />
        ))}
      </div>
    );
  }

  const coins = data.catalog.filter((c) => c.kind === 'coins');
  const plans = data.catalog.filter((c) => c.kind === 'plan');
  const planUntil = data.plan_until ? new Date(data.plan_until).toLocaleDateString('az-AZ') : null;
  const bonus = data.sale_bonus ?? 2;

  return (
    <div className="space-y-3">
      {error && <div className="rounded-2xl bg-rose-50 p-3 text-[13px] text-rose-700">{error}</div>}

      <div className="px-1">
        <h2 className="font-display text-xl font-extrabold text-[#0B4635]">Hesab</h2>
        <div className="chips mt-2">
          <span className="tag-blue">{PLAN_LABELS[data.plan]}{planUntil ? `, ${planUntil}-dək` : ''}</span>
          <span className="tag">Təklif: {data.bid_fee === 0 ? 'pulsuz' : `−${formatCoin(data.bid_fee)} coin`}</span>
          <span className="tag">Satış: +{formatCoin(bonus)} coin</span>
        </div>
      </div>

      <Card title="Coin al">
        <div className="grid grid-cols-3 gap-2.5">
          {coins.map((c) => (
            <button
              key={c.key}
              disabled={busyKey === c.key}
              onClick={() => void order(c)}
              className="rounded-2xl bg-[#F4F7F4] p-3 text-center transition active:scale-95 hover:bg-[#E9F0EA] disabled:opacity-60"
            >
              <div className="font-display text-xl font-extrabold text-[#0B4635] leading-none">{formatCoin(c.coins)}</div>
              <div className="text-[11px] text-slate-400 mt-0.5">coin</div>
              <div className="text-[13px] font-bold text-slate-900 mt-1.5">{formatPrice(c.price_azn)}</div>
            </button>
          ))}
        </div>
      </Card>

      <Card title="Abunəlik">
        <div className="space-y-2.5">
          {(['free', ...plans.map((p) => p.plan)] as ('free' | 'plus' | 'pro')[]).map((key) => {
            const item = plans.find((p) => p.plan === key);
            const active = data.plan === key;
            return (
              <div
                key={key}
                className={`rounded-2xl p-3.5 ${active ? 'bg-[#0B4635]/[0.07] ring-2 ring-[#0B4635]' : 'bg-[#F4F7F4]'}`}
              >
                <div className="flex items-center justify-between gap-2">
                  <span className="font-display text-sm font-extrabold text-slate-900">
                    {PLAN_LABELS[key]}
                    {active && <span className="tag-green ml-2 align-middle">Aktiv</span>}
                  </span>
                  {item && (
                    <span className="font-display text-[13px] font-bold text-slate-800">
                      {formatPrice(item.price_azn)} / {item.days} gün
                    </span>
                  )}
                </div>
                <ul className="mt-2 space-y-1">
                  {PLAN_FEATURES[key].map((f) => (
                    <li key={f} className="text-xs text-slate-600">
                      {f}
                    </li>
                  ))}
                </ul>
                {item && (
                  <button
                    disabled={busyKey === item.key}
                    onClick={() => void order(item)}
                    className={`${active ? 'btn-ghost' : 'btn-cta'} mt-3 w-full !py-2.5`}
                  >
                    {active ? `${item.days} gün uzat` : `${PLAN_LABELS[key]}-a keç`}
                  </button>
                )}
              </div>
            );
          })}
        </div>
      </Card>

      {data.orders.length > 0 && (
        <Card title="Sifarişlər">
          <div className="divide-y divide-black/5">
            {data.orders.map((o) => {
              const st = ORDER_STATUS[o.status];
              return (
                <div key={o.id} className="py-2.5 flex items-center justify-between gap-2">
                  <div className="min-w-0">
                    <div className="text-[13px] font-semibold text-slate-900">
                      {o.title}, {formatPrice(o.amount_azn)}
                    </div>
                    <div className="text-xs text-slate-400 font-mono mt-0.5">
                      {o.reference}, {formatTimeAgo(o.created_at)}
                    </div>
                  </div>
                  <div className="flex flex-col items-end gap-1.5 flex-shrink-0">
                    <span className={st.cls}>{st.text}</span>
                    {o.status === 'pending' && (
                      <div className="flex gap-3">
                        <button
                          className="text-xs font-bold text-[#0B4635]"
                          onClick={() =>
                            setPayFor({ id: o.id, reference: o.reference, amount_azn: o.amount_azn, title: o.title })
                          }
                        >
                          Necə ödəyim?
                        </button>
                        <button className="text-xs text-slate-400" onClick={() => void cancel(o)}>
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
          <p className="text-[13px] text-slate-400">Hələ hərəkət yoxdur.</p>
        ) : (
          <div className="divide-y divide-black/5">
            {ledger.map((l) => (
              <div key={l.id} className="py-2 flex items-center justify-between">
                <div>
                  <div className="text-[13px] text-slate-800 font-medium">{LEDGER_LABELS[l.type] ?? l.type}</div>
                  <div className="text-xs text-slate-400">{formatTimeAgo(l.created_at)}</div>
                </div>
                <span className={`font-display font-extrabold ${l.amount >= 0 ? 'text-emerald-600' : 'text-rose-500'}`}>
                  {l.amount > 0 ? `+${formatCoin(l.amount)}` : formatCoin(l.amount)}
                </span>
              </div>
            ))}
          </div>
        )}
      </Card>

      <button onClick={() => void refreshAll()} className="w-full text-[13px] text-slate-400 py-1">
        Yenilə
      </button>

      {payFor && (
        <PaymentSheet
          reference={payFor.reference}
          amount={Number(payFor.amount_azn)}
          title={payFor.title}
          texts={texts}
          onClose={() => setPayFor(null)}
        />
      )}
    </div>
  );
}

/* ====================================================================== */
/* Ödəniş pəncərəsi: 3 addım                                               */
/* ====================================================================== */

async function copyText(text: string, what: string) {
  try {
    await navigator.clipboard.writeText(text);
    showToast({ title: `${what} köçürüldü`, type: 'success' });
  } catch {
    showToast({ title: 'Köçürülmədi', body: 'Mətni əl ilə seçib köçürün.', type: 'error' });
  }
}

function Step({ n, title, children }: { n: number; title: string; children: ReactNode }) {
  return (
    <li className="flex gap-3">
      <span className="h-7 w-7 flex-shrink-0 rounded-full bg-[#0B4635] text-white font-display font-extrabold text-[13px] flex items-center justify-center mt-0.5">
        {n}
      </span>
      <div className="min-w-0 flex-1">
        <p className="font-display font-extrabold text-slate-900">{title}</p>
        <div className="mt-1.5">{children}</div>
      </div>
    </li>
  );
}

function PaymentSheet({
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
  const instr = (texts.payment_instructions ?? '').trim();
  // Admin kart nömrəsini "Ödəniş təlimatı"na yazır; 13-19 rəqəmli ardıcıllığı kart sayırıq
  const cardMatch = instr.match(/(?:\d[ -]?){13,19}/);
  const card = cardMatch ? cardMatch[0].trim() : null;
  const support = texts.support_whatsapp;
  const waPaid = support
    ? whatsappUrl(support, `Salam, AutoTender sifarişi ${reference} (${title}, ${amount} AZN) üçün ödəniş etdim. Qəbz əlavədədir.`)
    : null;
  const waAsk = support ? whatsappUrl(support, `Salam, AutoTender sifarişi ${reference} (${title}, ${amount} AZN) üçün ödəniş kartı lazımdır.`) : null;

  return (
    <Sheet title="Ödəniş" onClose={onClose}>
      <div className="rounded-3xl bg-[#0B4635] text-white p-4 flex items-center justify-between">
        <div>
          <div className="text-xs text-white/60">{title}</div>
          <div className="font-display text-2xl font-extrabold leading-none mt-1">{formatPrice(amount)}</div>
        </div>
        <div className="text-right">
          <div className="text-xs text-white/60">Ödəniş kodu</div>
          <div className="font-display text-lg font-extrabold text-[#FFC61A] mt-1 font-mono">{reference}</div>
        </div>
      </div>

      <ol className="space-y-5 mt-5">
        <Step n={1} title="Məbləği karta köçürün">
          {card ? (
            <div className="rounded-2xl bg-[#F4F7F4] p-3.5">
              <p className="text-[13px] text-slate-700 whitespace-pre-line">{instr}</p>
              <button onClick={() => void copyText(card.replace(/\D/g, ''), 'Kart nömrəsi')} className="btn-soft mt-3 w-full">
                Kart nömrəsini köçür
              </button>
            </div>
          ) : (
            <div className="rounded-2xl bg-amber-50 p-3.5">
              <p className="text-[13px] text-amber-900">Kart məlumatı hələ əlavə olunmayıb. Dəstəyə yazın, kartı göndərəcəklər.</p>
              {waAsk && (
                <a href={waAsk} target="_blank" rel="noreferrer" className="btn-cta mt-3 w-full">
                  Kartı WhatsApp-da istə
                </a>
              )}
            </div>
          )}
        </Step>

        <Step n={2} title="Köçürmənin izahına kodu yazın">
          <p className="text-[13px] text-slate-500">Bank tətbiqində “Təyinat” və ya “Qeyd” xanasına:</p>
          <button
            onClick={() => void copyText(reference, 'Kod')}
            className="mt-2 w-full rounded-2xl bg-[#F4F7F4] py-3 font-mono text-lg font-extrabold text-[#0B4635] active:scale-[0.98] transition"
          >
            {reference}
          </button>
          <p className="text-xs text-slate-400 mt-1.5 text-center">Toxunsanız köçürülür</p>
        </Step>

        <Step n={3} title="Qəbzi bildirin">
          <p className="text-[13px] text-slate-500">Təsdiqdən sonra {title.toLowerCase().includes('coin') ? 'coin' : 'plan'} hesabınıza əlavə olunur.</p>
          {waPaid ? (
            <a href={waPaid} target="_blank" rel="noreferrer" className="btn mt-2 w-full py-3 text-[13px] bg-[#25D366] text-white shadow-[0_10px_20px_-10px_rgba(37,211,102,0.9)]">
              WhatsApp-da bildir
            </a>
          ) : (
            <p className="text-[13px] text-slate-500 mt-1">Dəstək nömrəsi hələ əlavə olunmayıb.</p>
          )}
        </Step>
      </ol>

      <button onClick={onClose} className="btn-ghost w-full mt-6">
        Bağla
      </button>
    </Sheet>
  );
}

/* ====================================================================== */
/* Analiz (Plus / Pro)                                                     */
/* ====================================================================== */

function Bar({ value, max, tone = 'green' }: { value: number; max: number; tone?: 'green' | 'orange' }) {
  const w = max > 0 ? Math.max(4, Math.round((value / max) * 100)) : 0;
  return (
    <div className="h-2 rounded-full bg-[#EAF0EB] overflow-hidden">
      <div className={`h-full rounded-full ${tone === 'green' ? 'bg-[#0B4635]' : 'bg-[#FFC61A]'}`} style={{ width: `${w}%` }} />
    </div>
  );
}

function Locked({ need, text, onUpgrade }: { need: 'Plus' | 'Pro'; text: string; onUpgrade: () => void }) {
  return (
    <div className="rounded-3xl border-2 border-dashed border-[#0B4635]/20 bg-white/60 p-5 text-center">
      <p className="font-display text-sm font-extrabold text-slate-900">{need} planında açılır</p>
      <p className="text-xs text-slate-500 mt-1">{text}</p>
      <button onClick={onUpgrade} className="btn-cta mt-3 px-6">
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

  if (error) return <div className="rounded-2xl bg-rose-50 p-3 text-[13px] text-rose-700">{error}</div>;
  if (!data) return <div className="skeleton h-24" />;

  const market = data.market;
  const pro = data.pro;
  const maxReq = Math.max(1, ...(market?.by_category.map((c) => c.requests) ?? [1]));
  const maxHour = Math.max(1, ...(pro?.hourly ?? [1]));

  return (
    <div className="space-y-3">
      <Card title="Bazar (son 30 gün)">
        <div className="grid grid-cols-2 gap-2 text-center">
          <div className="rounded-2xl bg-[#F4F7F4] p-3">
            <div className="font-display text-lg font-extrabold text-[#0B4635]">{data.teaser.requests_30d}</div>
            <div className="text-xs text-slate-500">sizin markalara sorğu</div>
          </div>
          <div className="rounded-2xl bg-[#F4F7F4] p-3">
            <div className="font-display text-lg font-extrabold text-[#0B4635]">{data.teaser.completed_30d}</div>
            <div className="text-xs text-slate-500">satışla bitən</div>
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
              <p className="text-xs text-slate-400">Hələ kifayət qədər məlumat yoxdur.</p>
            ) : (
              <div className="space-y-3">
                {market.by_category.map((c) => (
                  <div key={c.category}>
                    <div className="flex items-center justify-between text-xs">
                      <span className="font-semibold text-slate-800">{catName(c.category)}</span>
                      <span className="text-slate-500">{c.requests} sorğu</span>
                    </div>
                    <Bar value={c.requests} max={maxReq} />
                    <div className="text-xs text-slate-500 mt-1 flex flex-wrap gap-x-3">
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
                <div key={b.brand} className="py-1.5 flex items-center justify-between text-xs">
                  <span className="font-semibold text-slate-800">{b.brand}</span>
                  <span className="text-slate-500">
                    {b.requests} sorğu · orta satış {b.avg_win_price != null ? formatPrice(b.avg_win_price) : '—'}
                  </span>
                </div>
              ))}
              {market.by_brand.length === 0 && <p className="text-xs text-slate-400">Məlumat yoxdur.</p>}
            </div>
            <p className="text-xs text-slate-400 mt-2">Orta qiymət ən azı 3 satış olanda göstərilir.</p>
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
              <div className="rounded-2xl bg-[#F4F7F4] p-3">
                <div className="font-display text-lg font-extrabold text-[#0B4635]">{pro.price_position.wins}</div>
                <div className="text-xs text-slate-500">satış</div>
              </div>
              <div className="rounded-2xl bg-[#F4F7F4] p-3">
                <div className="font-display text-lg font-extrabold text-slate-700">{pro.price_position.losses}</div>
                <div className="text-xs text-slate-500">uduzma</div>
              </div>
              <div className="rounded-2xl bg-[#F4F7F4] p-3">
                <div className="font-display text-lg font-extrabold text-[#9A5B00]">
                  {pro.price_position.avg_gap_pct != null ? `${pro.price_position.avg_gap_pct > 0 ? '+' : ''}${pro.price_position.avg_gap_pct}%` : '—'}
                </div>
                <div className="text-xs text-slate-500">uduzanda fərq</div>
              </div>
            </div>
            {pro.by_category_position.length > 0 && (
              <div className="mt-2.5 divide-y divide-slate-100">
                {pro.by_category_position.map((c) => (
                  <div key={c.category} className="py-1.5 flex items-center justify-between text-xs">
                    <span className="font-semibold text-slate-800">{catName(c.category)}</span>
                    <span className="text-slate-500">
                      {c.wins} satış / {c.losses} uduzma
                      {c.avg_gap_pct != null ? ` · ${c.avg_gap_pct > 0 ? '+' : ''}${c.avg_gap_pct}%` : ''}
                    </span>
                  </div>
                ))}
              </div>
            )}
            <p className="text-xs text-slate-400 mt-2">
              “Uduzanda fərq” — qalibdən nə qədər bahalı olduğunuz (müsbət = bahalı).
            </p>
          </Card>

          <Card title="Ən çox axtarılan detallar">
            {pro.top_parts.length === 0 ? (
              <p className="text-xs text-slate-400">Hələ təkrarlanan axtarış yoxdur.</p>
            ) : (
              <div className="divide-y divide-slate-100">
                {pro.top_parts.map((p) => (
                  <div key={p.part} className="py-1.5 text-xs">
                    <div className="flex items-center justify-between">
                      <span className="font-semibold text-slate-800 capitalize">{p.part}</span>
                      <span className="text-slate-500">{p.requests} sorğu</span>
                    </div>
                    {p.avg_win_price != null && (
                      <div className="text-xs text-slate-500">
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
            <div className="flex justify-between text-[11px] text-slate-400 mt-1">
              <span>00</span>
              <span>06</span>
              <span>12</span>
              <span>18</span>
              <span>23</span>
            </div>
            <p className="text-xs text-slate-400 mt-1">Bakı vaxtı ilə. Ən hündür sütunlarda tez cavab verin.</p>
          </Card>

          <Card title="Cavab sürəti">
            <div className="grid grid-cols-2 gap-2 text-center">
              <div className="rounded-2xl bg-[#F4F7F4] p-3">
                <div className="font-display text-lg font-extrabold text-[#0B4635]">
                  {pro.response_speed.my_median_min != null ? `${pro.response_speed.my_median_min} dəq` : '—'}
                </div>
                <div className="text-xs text-slate-500">sizin orta cavab</div>
              </div>
              <div className="rounded-2xl bg-[#F4F7F4] p-3">
                <div className="font-display text-lg font-extrabold text-[#9A5B00]">
                  {pro.response_speed.winner_median_min != null ? `${pro.response_speed.winner_median_min} dəq` : '—'}
                </div>
                <div className="text-xs text-slate-500">qazanan təkliflərin orta cavabı</div>
              </div>
            </div>
          </Card>

          <Card title="Cavabsız qalan tələb (son 7 gün)">
            {pro.unanswered_7d.length === 0 ? (
              <p className="text-xs text-slate-400">Cavabsız sorğu yoxdur.</p>
            ) : (
              <div className="divide-y divide-slate-100">
                {pro.unanswered_7d.map((u) => (
                  <div key={u.brand} className="py-1.5 flex items-center justify-between text-xs">
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
