import { useEffect, useState, useCallback } from 'react';

export type Toast = {
  id: string;
  title: string;
  body?: string;
  type: 'success' | 'error' | 'info' | 'bid' | 'win';
};

let toastListeners: ((toast: Toast) => void)[] = [];

export function showToast(toast: Omit<Toast, 'id'>) {
  const fullToast: Toast = { ...toast, id: crypto.randomUUID() };
  toastListeners.forEach((fn) => fn(fullToast));
}

export function useToasts() {
  const [toasts, setToasts] = useState<Toast[]>([]);

  const dismiss = useCallback((id: string) => {
    setToasts((prev) => prev.filter((t) => t.id !== id));
  }, []);

  useEffect(() => {
    const listener = (toast: Toast) => {
      setToasts((prev) => [...prev, toast]);
      setTimeout(() => {
        setToasts((prev) => prev.filter((t) => t.id !== toast.id));
      }, 5000);
    };
    toastListeners.push(listener);
    return () => {
      toastListeners = toastListeners.filter((fn) => fn !== listener);
    };
  }, []);

  return { toasts, dismiss };
}

export function useCountdown(expiresAt: string) {
  const [remaining, setRemaining] = useState(() => calcRemaining(expiresAt));

  useEffect(() => {
    const interval = setInterval(() => {
      setRemaining(calcRemaining(expiresAt));
    }, 1000);
    return () => clearInterval(interval);
  }, [expiresAt]);

  return remaining;
}

function calcRemaining(expiresAt: string) {
  const diff = new Date(expiresAt).getTime() - Date.now();
  if (diff <= 0) return { expired: true, hours: 0, minutes: 0, seconds: 0, total: 0, label: 'Vaxtı bitib' };
  const hours = Math.floor(diff / 3600000);
  const minutes = Math.floor((diff % 3600000) / 60000);
  const seconds = Math.floor((diff % 60000) / 1000);
  const label = hours > 0 ? `${hours}s ${minutes}d` : `${minutes}d ${seconds}san`;
  return { expired: false, hours, minutes, seconds, total: diff, label };
}

export function formatPrice(price: number | null | undefined): string {
  if (price == null) return 'Razılaşma ilə';
  const n = Number(price);
  return `${Number.isInteger(n) ? n : n.toFixed(2)} AZN`;
}

export function formatTimeAgo(dateStr: string): string {
  const diff = Date.now() - new Date(dateStr).getTime();
  const minutes = Math.floor(diff / 60000);
  if (minutes < 1) return 'İndi';
  if (minutes < 60) return `${minutes} dəqiqə əvvəl`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours} saat əvvəl`;
  const days = Math.floor(hours / 24);
  return `${days} gün əvvəl`;
}

/** Coin: tam rəqəmdirsə 12, yarımdırsa 12.5 */
export function formatCoin(n: number | null | undefined): string {
  const v = Number(n ?? 0);
  return Number.isInteger(v) ? String(v) : v.toFixed(1);
}

export type PlanName = 'free' | 'plus' | 'pro';

/** Vaxtı bitmiş plan 'free' sayılır (server də eyni qaydanı tətbiq edir) */
export function effectivePlan(store: { plan?: string | null; plan_until?: string | null } | null): PlanName {
  if (!store || !store.plan || store.plan === 'free' || !store.plan_until) return 'free';
  if (new Date(store.plan_until).getTime() <= Date.now()) return 'free';
  return store.plan === 'pro' ? 'pro' : store.plan === 'plus' ? 'plus' : 'free';
}

/** Yalnız göstəriş üçündür — real haqqı server hesablayır */
export function displayBidFee(plan: PlanName): number {
  return plan === 'pro' ? 0 : plan === 'plus' ? 0.5 : 1;
}

export const PLAN_LABELS: Record<PlanName, string> = { free: 'Pulsuz', plus: 'Plus', pro: 'Pro' };

/** 1–47 saat → "5 saat"; 48+ → "3 gün" */
export function etaLabel(h: number): string {
  if (h < 48) return `${h} saat`;
  return `${Math.round(h / 24)} gün`;
}

export const ETA_OPTIONS: { hours: number; label: string }[] = [
  { hours: 1, label: '1 saat' },
  { hours: 3, label: '3 saat' },
  { hours: 24, label: '1 gün' },
  { hours: 72, label: '3 gün' },
  { hours: 168, label: '1 həftə' },
];
