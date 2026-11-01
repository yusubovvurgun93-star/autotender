import { useState } from 'react';
import { Sheet } from '@/components/ui';
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
      <p className="text-[13px] font-bold text-slate-800 mb-3">{targetName}</p>
      <div className="space-y-1.5">
        {reasons.map(([k, label]) => (
          <button
            key={k}
            type="button"
            onClick={() => setReason(k)}
            className={`w-full text-left px-4 py-3 rounded-2xl text-[13px] transition ${
              reason === k ? 'bg-[#0B4635] text-white font-bold' : 'bg-[#F4F7F4] text-slate-700'
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
        className="input mt-3"
      />
      {error && (
        <div className="mt-3 rounded-2xl bg-rose-50 px-3.5 py-2.5 text-[13px] text-rose-700">{error}</div>
      )}
      <button
        onClick={send}
        disabled={busy}
        className="btn-primary w-full mt-4"
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
    <Sheet title={who === 'buyer' ? 'Tarixçəni sil' : 'Mağaza hesabını sil'} onClose={onClose}>
      <div className="rounded-2xl bg-rose-50 p-3.5">
        <p className="text-xs text-slate-600 mt-1.5">
          {who === 'buyer'
            ? 'Aktiv sorğularınız ləğv olunur, VIN və şəkillər sorğulardan silinir, cihazdakı kimliyiniz sıfırlanır. Bu geri qaytarılmır.'
            : 'Mağaza məlumatlarınız (ad, telefon, VÖEN, ünvan) silinir, qalan coin və abunəlik itirilir. Maliyyə qeydləri qanuni tələblərə görə anonim saxlanır. Bu geri qaytarılmır.'}
        </p>
        {confirm ? (
          <div className="mt-2.5">
            <label className="label">
              Təsdiq üçün <b>{word}</b> yazın:
            </label>
            <input
              value={typed}
              onChange={(e) => setTyped(e.target.value)}
              className="input !bg-white"
            />
            <div className="flex gap-2 mt-2">
              <button
                onClick={() => {
                  setConfirm(false);
                  setTyped('');
                }}
                className="btn-ghost flex-1"
              >
                Vaz keç
              </button>
              <button
                onClick={remove}
                disabled={busy || typed.trim().toLocaleUpperCase('az') !== word}
                className="btn flex-1 py-2.5 text-xs bg-rose-600 text-white"
              >
                {busy ? 'Silinir…' : 'Həmişəlik sil'}
              </button>
            </div>
          </div>
        ) : (
          <button
            onClick={() => setConfirm(true)}
            className="btn-danger mt-3 w-full !bg-white"
          >
            Silməyə davam et
          </button>
        )}
      </div>
      {error && (
        <div className="mt-3 rounded-2xl bg-rose-50 px-3.5 py-2.5 text-[13px] text-rose-700">{error}</div>
      )}
    </Sheet>
  );
}
