import { useState, type ReactNode } from 'react';
import { Download, Trash2, X } from 'lucide-react';
import * as api from '@/lib/api';
import type { Db } from '@/lib/supabase';
import { showToast } from '@/lib/utils';
import type { ReportReason } from '@/lib/types';

const STORE_REASONS: [ReportReason, string][] = [
  ['wrong_price', 'Razılaşdığımızdan fərqli qiymət istədi'],
  ['bad_part', 'Detal saxta / keyfiyyətsiz / uyğun deyil'],
  ['no_response', 'Cavab vermir'],
  ['rude', 'Kobud davranış'],
  ['bypass', 'Platformadan kənara yönləndirir'],
  ['other', 'Digər'],
];

const REQUEST_REASONS: [ReportReason, string][] = [
  ['spam', 'Spam / təkrar sorğu'],
  ['fake', 'Saxta sorğu'],
  ['rude', 'Təhqiramiz məzmun'],
  ['other', 'Digər'],
];

export const REASON_LABELS: Record<string, string> = Object.fromEntries([...STORE_REASONS, ...REQUEST_REASONS]);

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

/** Alıcı → mağaza, satıcı → sorğu şikayəti */
export function ReportModal({
  db,
  kind,
  storeId,
  requestId,
  targetName,
  onClose,
}: {
  db: Db;
  kind: 'store' | 'request';
  storeId?: string | null;
  requestId?: string | null;
  targetName: string;
  onClose: () => void;
}) {
  const reasons = kind === 'store' ? STORE_REASONS : REQUEST_REASONS;
  const [reason, setReason] = useState<ReportReason | null>(null);
  const [details, setDetails] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const send = async () => {
    setError(null);
    if (!reason) return setError('Səbəbi seçin.');
    setBusy(true);
    try {
      await api.submitReport(db, { kind, storeId, requestId, reason, details });
      showToast({ title: 'Şikayət göndərildi', body: 'Komandamız baxacaq. Təşəkkür edirik.', type: 'success' });
      onClose();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Göndərilmədi.');
    } finally {
      setBusy(false);
    }
  };

  return (
    <Sheet title="Şikayət et" onClose={onClose}>
      <p className="text-[11px] text-slate-500 mb-2.5">
        <span className="font-bold text-slate-800">{targetName}</span>
      </p>
      <div className="space-y-1.5">
        {reasons.map(([k, label]) => (
          <button
            key={k}
            type="button"
            onClick={() => setReason(k)}
            className={`w-full text-left px-3 py-2 rounded-xl border text-xs ${
              reason === k ? 'border-[#0B4635] bg-emerald-50 font-bold text-[#0B4635]' : 'border-slate-200 text-slate-700'
            }`}
          >
            {label}
          </button>
        ))}
      </div>
      <textarea
        rows={3}
        maxLength={500}
        value={details}
        onChange={(e) => setDetails(e.target.value)}
        placeholder={reason === 'other' ? 'Qısa izah yazın (məcburi)' : 'Əlavə izah (könüllü)'}
        className="w-full mt-2.5 bg-slate-50 border border-slate-200 rounded-lg px-3 py-2 text-xs focus:outline-none focus:border-[#0B4635]"
      />
      {error && (
        <div className="mt-2 rounded-lg bg-rose-50 border border-rose-200 px-3 py-2 text-[11px] text-rose-700">{error}</div>
      )}
      <button
        onClick={send}
        disabled={busy}
        className="w-full mt-3 py-3 bg-[#0B4635] text-white text-xs font-bold rounded-xl disabled:opacity-60"
      >
        {busy ? 'Göndərilir…' : 'Göndər'}
      </button>
    </Sheet>
  );
}

/** Məlumatlarımı yüklə / hesabı sil */
export function DataModal({
  db,
  who,
  onDeleted,
  onClose,
}: {
  db: Db;
  who: 'buyer' | 'seller';
  onDeleted: () => void;
  onClose: () => void;
}) {
  const [busy, setBusy] = useState(false);
  const [confirm, setConfirm] = useState(false);
  const [typed, setTyped] = useState('');
  const [error, setError] = useState<string | null>(null);

  const download = async () => {
    setBusy(true);
    setError(null);
    try {
      const data = await api.exportMyData(db);
      const blob = new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = 'autotender-melumatlarim.json';
      a.click();
      URL.revokeObjectURL(url);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Yüklənmədi.');
    } finally {
      setBusy(false);
    }
  };

  const remove = async () => {
    setBusy(true);
    setError(null);
    try {
      await api.deleteMyAccount(db);
      await db.auth.signOut({ scope: 'local' }).catch(() => undefined);
      onDeleted();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Silinmədi.');
      setBusy(false);
    }
  };

  const word = 'SİL';
  return (
    <Sheet title="Mənim məlumatlarım" onClose={onClose}>
      <button
        onClick={download}
        disabled={busy}
        className="w-full py-2.5 border border-slate-200 rounded-xl text-xs font-bold text-slate-700 flex items-center justify-center gap-1.5"
      >
        <Download className="w-4 h-4" /> Məlumatlarımı yüklə (JSON)
      </button>

      <div className="mt-4 rounded-2xl border border-rose-200 bg-rose-50/50 p-3.5">
        <h4 className="text-xs font-bold text-rose-700 flex items-center gap-1.5">
          <Trash2 className="w-3.5 h-3.5" /> {who === 'buyer' ? 'Tarixçəmi və məlumatlarımı sil' : 'Hesabımı sil'}
        </h4>
        <p className="text-[11px] text-slate-600 mt-1">
          {who === 'buyer'
            ? 'Aktiv sorğularınız ləğv olunur, VIN və şəkillər sorğulardan silinir, cihazdakı kimliyiniz sıfırlanır. Bu geri qaytarılmır.'
            : 'Mağaza məlumatlarınız (ad, telefon, VÖEN, ünvan) silinir, qalan coin və abunəlik itirilir. Maliyyə qeydləri qanuni tələblərə görə anonim saxlanır. Bu geri qaytarılmır.'}
        </p>
        {confirm ? (
          <div className="mt-2.5">
            <label className="text-[11px] text-slate-600 block mb-1">
              Təsdiq üçün <b>{word}</b> yazın:
            </label>
            <input
              value={typed}
              onChange={(e) => setTyped(e.target.value)}
              className="w-full bg-white border border-rose-200 rounded-lg px-3 py-2 text-xs"
            />
            <div className="flex gap-2 mt-2">
              <button
                onClick={() => {
                  setConfirm(false);
                  setTyped('');
                }}
                className="flex-1 py-2 bg-white border border-slate-200 text-slate-600 text-xs font-bold rounded-lg"
              >
                Vaz keç
              </button>
              <button
                onClick={remove}
                disabled={busy || typed.trim().toLocaleUpperCase('az') !== word}
                className="flex-1 py-2 bg-rose-600 text-white text-xs font-bold rounded-lg disabled:opacity-40"
              >
                {busy ? 'Silinir…' : 'Həmişəlik sil'}
              </button>
            </div>
          </div>
        ) : (
          <button
            onClick={() => setConfirm(true)}
            className="mt-2.5 w-full py-2 bg-white border border-rose-200 text-rose-600 text-xs font-bold rounded-lg"
          >
            Silməyə davam et
          </button>
        )}
      </div>
      {error && (
        <div className="mt-3 rounded-lg bg-rose-50 border border-rose-200 px-3 py-2 text-[11px] text-rose-700">{error}</div>
      )}
    </Sheet>
  );
}
