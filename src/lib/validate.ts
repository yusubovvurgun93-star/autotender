// Telefon və qeyd yoxlamaları. Server (SQL) ilə eyni qaydalar — server həmişə son sözü deyir,
// buradakı yoxlama isə istifadəçiyə dərhal və aydın mesaj göstərmək üçündür.

/** 050 123 45 67 / +994501234567 / 501234567 → 994501234567 (düzgün deyilsə null) */
export function normalizeAzPhone(input: string): string | null {
  const d = (input || '').replace(/\D/g, '');
  if (d.length === 12 && d.startsWith('994')) return d;
  if (d.length === 10 && d.startsWith('0')) return '994' + d.slice(1);
  if (d.length === 9) return '994' + d;
  return null;
}

/** 994501234567 → 050 123 45 67 */
export function formatPhone(p: string | null | undefined): string {
  const n = normalizeAzPhone(p || '');
  if (!n) return p || '';
  return `0${n.slice(3, 5)} ${n.slice(5, 8)} ${n.slice(8, 10)} ${n.slice(10, 12)}`;
}

/** WhatsApp linki (beynəlxalq formatda, hazır mesajla) */
export function whatsappUrl(phone: string, text?: string): string {
  const n = normalizeAzPhone(phone) ?? phone.replace(/\D/g, '');
  return `https://wa.me/${n}${text ? `?text=${encodeURIComponent(text)}` : ''}`;
}

export function telUrl(phone: string): string {
  const n = normalizeAzPhone(phone) ?? phone.replace(/\D/g, '');
  return `tel:+${n}`;
}

const MOBILE_RE = /(^|[^0-9])(\+?994|0)?(10|50|51|55|60|70|77|99)[0-9]{7}([^0-9]|$)/;
const WORD_RE =
  /(^|[^\p{L}\p{N}])(wp|wa|whatsapp|watsap|vatsap|vatsapp|telegram|tg|insta|instagram|call)(?![\p{L}\p{N}])/u;
const CONTACT_RE = /(zəng|zeng|əlaqə|elaqe|@)/;

/**
 * Qeyddə telefon / mesajlaşma yönləndirməsi varsa mesaj qaytarır.
 * Detal (OEM) nömrələrini bloklamır — yalnız mobil nömrə nümunələrini və əlaqə sözlərini tutur.
 */
export function noteProblem(note: string): string | null {
  const t = (note || '').trim().toLowerCase();
  if (!t) return null;
  const squeezed = t.replace(/[\s.\-()_/]/g, '');
  if (MOBILE_RE.test(squeezed) || WORD_RE.test(t) || CONTACT_RE.test(t)) {
    return 'Qeydə telefon nömrəsi və ya əlaqə yönləndirməsi yazmaq olmaz. Əlaqə məlumatları təklif qəbul ediləndən sonra açılır.';
  }
  return null;
}

/** Cihaza yadda qalan son avtomobil (alıcı hər dəfə yenidən yazmasın) */
const LAST_CAR_KEY = 'autotender_last_car';

export type LastCar = { brand: string; model: string; year: string; city?: string };

export function loadLastCar(): LastCar {
  try {
    const raw = localStorage.getItem(LAST_CAR_KEY);
    if (raw) return { brand: '', model: '', year: '', ...JSON.parse(raw) };
  } catch {
    /* ignore */
  }
  return { brand: '', model: '', year: '' };
}

export function saveLastCar(car: LastCar) {
  try {
    localStorage.setItem(LAST_CAR_KEY, JSON.stringify(car));
  } catch {
    /* ignore */
  }
}
