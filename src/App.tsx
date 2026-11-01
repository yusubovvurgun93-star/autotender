import { useEffect, useState } from 'react';
import { Navbar } from '@/components/Navbar';
import { BuyerPanel } from '@/components/BuyerPanel';
import { SellerPanel } from '@/components/SellerPanel';
import { AdminPanel } from '@/components/AdminPanel';
import { StoreProfileModal } from '@/components/SellerAuth';
import { InstallPrompt } from '@/components/InstallPrompt';
import { ToastContainer } from '@/components/ToastContainer';
import { SellerProvider, useBuyerSession, useSeller } from '@/lib/auth';
import { buyerDb } from '@/lib/supabase';
import { expireRequests, fetchBrands } from '@/lib/api';
import type { Role } from '@/lib/theme';
import type { CarBrand } from '@/lib/types';

const ROLE_KEY = 'autotender_role';

function loadRole(): Role {
  try {
    const v = localStorage.getItem(ROLE_KEY);
    if (v === 'seller' || v === 'admin') return v;
  } catch {
    /* ignore */
  }
  return 'buyer';
}

function saveRole(r: Role) {
  try {
    localStorage.setItem(ROLE_KEY, r);
  } catch {
    /* ignore */
  }
}

function Shell() {
  const [role, setRoleState] = useState<Role>(loadRole);
  const [brands, setBrands] = useState<CarBrand[]>([]);
  const [completeProfile, setCompleteProfile] = useState(false);
  const buyer = useBuyerSession();
  const seller = useSeller();

  const setRole = (r: Role) => {
    setRoleState(r);
    saveRole(r);
  };

  // Alıcı sessiyası hazır olanda: markalar + vaxtı bitmiş sorğuların bağlanması
  useEffect(() => {
    if (!buyer.userId) return;
    let cancelled = false;
    fetchBrands()
      .then((b) => {
        if (!cancelled) setBrands(b);
      })
      .catch(() => undefined);
    void expireRequests(buyerDb);
    const id = setInterval(() => void expireRequests(buyerDb), 60000);
    return () => {
      cancelled = true;
      clearInterval(id);
    };
  }, [buyer.userId]);

  // Rol qoruyucuları (sessiya bitibsə / admin deyilsə alıcı rejiminə qayıt)
  useEffect(() => {
    if (seller.loading) return;
    if (role === 'seller' && !seller.userId) setRole('buyer');
    else if (role === 'seller' && seller.isAdmin && !seller.store) setRole('admin');
    else if (role === 'admin' && !seller.isAdmin) setRole('buyer');
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [role, seller.loading, seller.userId, seller.isAdmin, seller.store]);

  const sellerReady = !seller.loading && !!seller.userId;

  return (
    <div className="app-bg max-w-md mx-auto min-h-screen relative overflow-x-clip pb-24 md:shadow-2xl">
      <Navbar role={role} setRole={setRole} buyerUserId={buyer.userId} brands={brands} />
      <ToastContainer />
      <InstallPrompt />

      <main>
        {role === 'buyer' && (
          <BuyerPanel
            ready={buyer.ready}
            userId={buyer.userId}
            error={buyer.error}
            onRetry={buyer.retry}
            brands={brands}
          />
        )}

        {role === 'seller' &&
          (seller.loading ? (
            <div className="px-3 pt-4 max-w-md mx-auto">
              <div className="skeleton h-24" />
            </div>
          ) : sellerReady && seller.store ? (
            <SellerPanel />
          ) : sellerReady ? (
            <div className="px-3 pt-4 max-w-md mx-auto">
              <div className="card text-center">
                <p className="font-display text-base font-extrabold text-slate-900">Mağaza profili tamamlanmayıb</p>
                <button type="button" onClick={() => setCompleteProfile(true)} className="btn-cta mt-4 px-6">
                  Profili tamamla
                </button>
              </div>
            </div>
          ) : null)}

        {role === 'admin' && seller.isAdmin && <AdminPanel />}
      </main>

      {completeProfile && (
        <StoreProfileModal mode="create" store={null} brands={brands} onClose={() => setCompleteProfile(false)} />
      )}
    </div>
  );
}

export default function App() {
  return (
    <SellerProvider>
      <Shell />
    </SellerProvider>
  );
}
