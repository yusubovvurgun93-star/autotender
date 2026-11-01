import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from 'react';
import { buyerDb, sellerDb, type Db } from '@/lib/supabase';
import * as api from '@/lib/api';
import { showToast } from '@/lib/utils';
import type { AppNotification, MyStore, StoreProfileInput } from '@/lib/types';

/* ================================================================== */
/* ALICI: qeydiyyatsız (anonim) sessiya                                */
/* ================================================================== */

let buyerSessionPromise: Promise<string> | null = null;

/** Cihazda alıcı sessiyası varsa onu qaytarır, yoxdursa anonim sessiya açır (bir dəfə). */
export function ensureBuyerSession(): Promise<string> {
  if (!buyerSessionPromise) {
    buyerSessionPromise = (async () => {
      const { data } = await buyerDb.auth.getSession();
      if (data.session) return data.session.user.id;
      const res = await buyerDb.auth.signInAnonymously();
      if (res.error || !res.data.user) {
        throw new Error(
          /anonymous/i.test(res.error?.message || '')
            ? 'Anonim giriş söndürülüb. Supabase → Authentication → Sign In / Providers bölməsində "Allow anonymous sign-ins" açın.'
            : api.friendlyError(res.error?.message)
        );
      }
      return res.data.user.id;
    })().catch((e) => {
      buyerSessionPromise = null; // növbəti cəhd yenidən işləsin
      throw e;
    });
  }
  return buyerSessionPromise;
}

export function useBuyerSession() {
  const [state, setState] = useState<{ ready: boolean; userId: string | null; error: string | null }>({
    ready: false,
    userId: null,
    error: null,
  });

  const start = useCallback(async () => {
    setState({ ready: false, userId: null, error: null });
    try {
      const userId = await ensureBuyerSession();
      setState({ ready: true, userId, error: null });
    } catch (e) {
      setState({ ready: true, userId: null, error: e instanceof Error ? e.message : 'Sessiya açılmadı.' });
    }
  }, []);

  useEffect(() => {
    void start();
  }, [start]);

  return { ...state, retry: start };
}

/* ================================================================== */
/* SATICI / ADMİN: e-poçt + parol                                      */
/* ================================================================== */

const PENDING_KEY = 'autotender_pending_store';

function readPending(): StoreProfileInput | null {
  try {
    const raw = localStorage.getItem(PENDING_KEY);
    return raw ? (JSON.parse(raw) as StoreProfileInput) : null;
  } catch {
    return null;
  }
}
function savePending(p: StoreProfileInput) {
  try {
    localStorage.setItem(PENDING_KEY, JSON.stringify(p));
  } catch {
    /* ignore */
  }
}
function clearPending() {
  try {
    localStorage.removeItem(PENDING_KEY);
  } catch {
    /* ignore */
  }
}

export function authErrorText(message: string | undefined | null): string {
  const m = message || '';
  if (/invalid login credentials/i.test(m)) return 'E-poçt və ya parol səhvdir.';
  if (/already registered|already been registered/i.test(m)) return 'Bu e-poçt artıq qeydiyyatdan keçib. "Daxil ol" bölməsindən girin.';
  if (/at least \d+ characters/i.test(m)) return 'Parol ən azı 6 simvol olmalıdır.';
  if (/email not confirmed/i.test(m)) return 'E-poçtunuzu təsdiqləyin (poçt qutusuna göndərilən linkə basın).';
  if (/valid email|invalid format|unable to validate email/i.test(m)) return 'E-poçt ünvanı düzgün deyil.';
  if (/rate limit|too many/i.test(m)) return 'Çox sayda cəhd oldu. Bir az sonra yenidən yoxlayın.';
  return api.friendlyError(m);
}

type SellerSession = {
  loading: boolean;
  userId: string | null;
  email: string | null;
  isAdmin: boolean;
  store: MyStore | null;
};

type SellerApi = SellerSession & {
  refresh: () => Promise<void>;
  signIn: (email: string, password: string) => Promise<void>;
  /** 'registered' — mağaza açıldı; 'confirm_email' — e-poçtu təsdiqləyəndən sonra tamamlanacaq */
  signUp: (email: string, password: string, profile: StoreProfileInput) => Promise<'registered' | 'confirm_email'>;
  createStore: (profile: StoreProfileInput) => Promise<void>;
  signOut: () => Promise<void>;
  resetPassword: (email: string) => Promise<void>;
};

const EMPTY: SellerSession = { loading: false, userId: null, email: null, isAdmin: false, store: null };

const SellerCtx = createContext<SellerApi | null>(null);

export function SellerProvider({ children }: { children: ReactNode }) {
  const [state, setState] = useState<SellerSession>({ ...EMPTY, loading: true });
  const loadingRef = useRef(false);

  const load = useCallback(async () => {
    if (loadingRef.current) return;
    loadingRef.current = true;
    try {
      const { data } = await sellerDb.auth.getSession();
      const session = data.session;
      if (!session) {
        setState(EMPTY);
        return;
      }
      const role = await api.getMyRole();
      let store = await api.getMyStore();

      // E-poçt təsdiqindən sonra yarımçıq qalmış qeydiyyatı tamamla
      if (!store && !role.is_admin) {
        const pending = readPending();
        if (pending) {
          try {
            await api.registerStore(pending);
            store = await api.getMyStore();
            showToast({ title: 'Mağazanız açıldı', body: '30 başlanğıc coin hesabınıza əlavə olundu.', type: 'success' });
          } catch (e) {
            showToast({
              title: 'Mağaza açılmadı',
              body: e instanceof Error ? e.message : undefined,
              type: 'error',
            });
          } finally {
            clearPending();
          }
        }
      }

      setState({
        loading: false,
        userId: session.user.id,
        email: session.user.email ?? null,
        isAdmin: role.is_admin,
        store,
      });
    } catch (e) {
      showToast({ title: 'Profil yüklənmədi', body: e instanceof Error ? e.message : undefined, type: 'error' });
      setState((s) => ({ ...s, loading: false }));
    } finally {
      loadingRef.current = false;
    }
  }, []);

  useEffect(() => {
    void load();
    const { data } = sellerDb.auth.onAuthStateChange((event) => {
      if (event === 'SIGNED_IN' || event === 'SIGNED_OUT' || event === 'USER_UPDATED') {
        // callback daxilində Supabase çağırışı etmək donmaya səbəb ola bilər — növbəyə atırıq
        setTimeout(() => void load(), 0);
      }
    });
    return () => data.subscription.unsubscribe();
  }, [load]);

  const signIn = useCallback(
    async (email: string, password: string) => {
      const { error } = await sellerDb.auth.signInWithPassword({ email: email.trim(), password });
      if (error) throw new Error(authErrorText(error.message));
      await load();
    },
    [load]
  );

  const createStore = useCallback(
    async (profile: StoreProfileInput) => {
      await api.registerStore(profile);
      clearPending();
      await load();
    },
    [load]
  );

  const signUp = useCallback(
    async (email: string, password: string, profile: StoreProfileInput) => {
      const { data, error } = await sellerDb.auth.signUp({ email: email.trim(), password });
      if (error) throw new Error(authErrorText(error.message));
      if (!data.session) {
        // "Confirm email" açıqdır: təsdiqdən sonra ilk girişdə mağaza avtomatik açılacaq
        savePending(profile);
        return 'confirm_email' as const;
      }
      try {
        await api.registerStore(profile);
      } catch (e) {
        // Hesab yaranıb, mağaza yox: istifadəçi "mağaza profilini tamamla" formasına düşəcək
        await load();
        throw e;
      }
      await load();
      return 'registered' as const;
    },
    [load]
  );

  const signOut = useCallback(async () => {
    await sellerDb.auth.signOut();
    setState(EMPTY);
  }, []);

  const resetPassword = useCallback(async (email: string) => {
    const { error } = await sellerDb.auth.resetPasswordForEmail(email.trim(), {
      redirectTo: window.location.origin,
    });
    if (error) throw new Error(authErrorText(error.message));
  }, []);

  const value = useMemo<SellerApi>(
    () => ({ ...state, refresh: load, signIn, signUp, createStore, signOut, resetPassword }),
    [state, load, signIn, signUp, createStore, signOut, resetPassword]
  );

  return <SellerCtx.Provider value={value}>{children}</SellerCtx.Provider>;
}

export function useSeller(): SellerApi {
  const ctx = useContext(SellerCtx);
  if (!ctx) throw new Error('useSeller yalnız SellerProvider daxilində işləyir');
  return ctx;
}

/* ================================================================== */
/* BİLDİRİŞLƏR (realtime)                                              */
/* ================================================================== */

export function useNotifications(db: Db, userId: string | null) {
  const [items, setItems] = useState<AppNotification[]>([]);

  useEffect(() => {
    if (!userId) {
      setItems([]);
      return;
    }
    let cancelled = false;
    api
      .fetchNotifications(db)
      .then((rows) => {
        if (!cancelled) setItems(rows);
      })
      .catch(() => undefined);

    const channel = db
      .channel(`notifs-${userId}`)
      .on(
        'postgres_changes',
        { event: 'INSERT', schema: 'public', table: 'in_app_notifications', filter: `user_id=eq.${userId}` },
        (payload) => {
          const n = payload.new as AppNotification;
          setItems((prev) => [n, ...prev].slice(0, 30));
          showToast({
            title: n.title,
            body: n.body || undefined,
            type: n.kind === 'bid_accepted' ? 'win' : 'bid',
          });
        }
      )
      .subscribe();

    return () => {
      cancelled = true;
      void db.removeChannel(channel);
    };
  }, [db, userId]);

  const unread = items.filter((n) => !n.is_read).length;

  const markAllRead = useCallback(async () => {
    if (!userId || unread === 0) return;
    setItems((prev) => prev.map((n) => ({ ...n, is_read: true })));
    await api.markNotificationsRead(db, userId);
  }, [db, userId, unread]);

  return { items, unread, markAllRead };
}
