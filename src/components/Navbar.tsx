import { useState } from 'react';
import { Bell, ChevronRight, LogOut, Menu, Settings, ShieldAlert, Wrench, X } from 'lucide-react';
import type { Role } from '@/lib/theme';
import { buyerDb, sellerDb } from '@/lib/supabase';
import { useNotifications, useSeller } from '@/lib/auth';
import { PLAN_LABELS, effectivePlan, formatCoin, formatTimeAgo, showToast } from '@/lib/utils';
import type { CarBrand } from '@/lib/types';
import { SellerAuthModal, StoreProfileModal } from '@/components/SellerAuth';
import { DataModal } from '@/components/Report';

type Props = {
  role: Role;
  setRole: (r: Role) => void;
  buyerUserId: string | null;
  brands: CarBrand[];
};

export function Navbar({ role, setRole, buyerUserId, brands }: Props) {
  const seller = useSeller();
  const buyerActive = role === 'buyer';
  const sellerActive = role === 'seller';

  const notifDb = buyerActive ? buyerDb : sellerDb;
  const notifUser = buyerActive ? buyerUserId : seller.userId;
  const { items, unread, markAllRead } = useNotifications(notifDb, notifUser);

  const [showNotifs, setShowNotifs] = useState(false);
  const [menuOpen, setMenuOpen] = useState(false);
  const [authOpen, setAuthOpen] = useState(false);
  const [profileMode, setProfileMode] = useState<'create' | 'edit' | null>(null);
  const [dataModal, setDataModal] = useState<'buyer' | 'seller' | null>(null);
  const termsUrl = import.meta.env.VITE_TERMS_URL as string | undefined;
  const privacyUrl = import.meta.env.VITE_PRIVACY_URL as string | undefined;

  const openNotifs = () => {
    const next = !showNotifs;
    setShowNotifs(next);
    if (next) void markAllRead();
  };

  const goSeller = () => {
    setMenuOpen(false);
    if (!seller.userId) {
      setAuthOpen(true);
      return;
    }
    if (!seller.store && !seller.isAdmin) {
      setProfileMode('create');
      return;
    }
    setRole('seller');
  };

  const logout = async () => {
    try {
      await seller.signOut();
    } catch (e) {
      showToast({ title: 'Çıxış alınmadı', body: e instanceof Error ? e.message : undefined, type: 'error' });
      return;
    }
    setRole('buyer');
    setMenuOpen(false);
  };


  return (
    <>
      <nav
        className="sticky top-0 z-40 bg-[#0B4635] text-white border-b-4 border-[#FFC61A]"
        style={{ paddingTop: 'max(env(safe-area-inset-top, 0px), 0px)' }}
      >
        <div className="px-4 h-14 flex items-center justify-between gap-2 max-w-md mx-auto">
          <div className="flex items-center gap-2.5 flex-shrink-0">
            <div className="w-9 h-9 rounded-lg flex items-center justify-center bg-[#FFC61A] text-[#1B1B12] -rotate-6">
              <Wrench className="w-5 h-5" />
            </div>
            <div className="leading-none">
              <span className="font-display font-extrabold text-lg tracking-tight">
                Auto<span className="text-[#FFC61A]">Tender</span>
              </span>
              <div className="text-[11px] font-medium text-white/70 truncate max-w-[140px] mt-1">
                {sellerActive
                  ? seller.store?.name || 'Satıcı'
                  : role === 'admin'
                    ? 'Admin'
                    : 'Detal və usta — qiymət yarışı'}
              </div>
            </div>
          </div>

          <div className="flex items-center gap-1.5 flex-shrink-0">
            {sellerActive && seller.store && (
              <div className="flex items-center px-2.5 h-9 rounded-xl bg-white/10 border border-white/20 text-xs font-bold text-[#FFC61A]">
                <span className="font-display">
                  {effectivePlan(seller.store) === 'pro' ? '∞ ' : ''}
                  {formatCoin(seller.store.coin_balance)} coin
                </span>
              </div>
            )}

            <button
              type="button"
              onClick={openNotifs}
              aria-label="Bildirişlər"
              className="relative h-9 w-9 rounded-xl flex items-center justify-center bg-white/10 border border-white/20 text-white hover:bg-white/20 active:scale-95"
            >
              <Bell className="w-4 h-4" />
              {unread > 0 && (
                <span className="absolute -top-1 -right-1 w-5 h-5 rounded-full bg-red-500 text-white text-[10px] font-bold flex items-center justify-center shadow-md shadow-red-500/40">
                  {unread > 9 ? '9+' : unread}
                </span>
              )}
            </button>

            <button
              type="button"
              onClick={() => setMenuOpen(true)}
              aria-label="Menyu"
              className="h-9 w-9 rounded-xl flex items-center justify-center bg-white/10 border border-white/20 text-white hover:bg-white/20 active:scale-95"
            >
              <Menu className="w-5 h-5" />
            </button>
          </div>
        </div>

        {showNotifs && (
          <>
            <div className="fixed inset-0 z-40" onClick={() => setShowNotifs(false)} />
            <div className="absolute right-4 top-14 z-50 bg-white rounded-2xl shadow-2xl border border-slate-200 w-72 max-h-80 overflow-y-auto">
              <div className="p-3 border-b border-slate-100 flex items-center justify-between">
                <span className="text-xs font-bold text-slate-700">Bildirişlər</span>
                <span className="text-[10px] text-slate-400">Canlı</span>
              </div>
              {items.length === 0 ? (
                <div className="p-5 text-center text-xs text-slate-400">Bildiriş yoxdur</div>
              ) : (
                items.map((n) => (
                  <div key={n.id} className="p-3 border-b border-slate-100 last:border-0">
                    <div className="text-xs font-bold text-slate-800">{n.title}</div>
                    {n.body && <div className="text-[11px] text-slate-500 mt-0.5">{n.body}</div>}
                    <div className="text-[10px] text-slate-400 mt-1">{formatTimeAgo(n.created_at)}</div>
                  </div>
                ))
              )}
            </div>
          </>
        )}
      </nav>

      {menuOpen && (
        <div className="fixed inset-0 z-50 flex justify-end">
          <div className="fixed inset-0 bg-black/60" onClick={() => setMenuOpen(false)} />
          <div className="relative w-[85%] max-w-xs bg-white h-full p-5 flex flex-col z-10 shadow-2xl overflow-y-auto">
            <div className="flex items-center justify-between pb-3 border-b border-slate-100">
              <h3 className="text-sm font-bold text-slate-900">Menyu</h3>
              <button onClick={() => setMenuOpen(false)} className="p-1 rounded-lg bg-slate-100 text-slate-500" aria-label="Bağla">
                <X className="w-4 h-4" />
              </button>
            </div>

            <div className="mt-4 space-y-3">
              {buyerActive && (
                <>
                  <div className="p-3.5 rounded-2xl bg-slate-50 border border-slate-200">
                    <span className="text-xs font-bold text-slate-800 block mb-1">Siz sürücüsünüz?</span>
                    <p className="text-[11px] text-slate-500">
                      Qeydiyyat tələb olunmur. Sorğunu göndərin, mağazalar qiymət versin, ən yaxşısını seçin.
                    </p>
                  </div>

                  <div className="p-3.5 rounded-2xl bg-slate-50 border border-slate-200">
                    <span className="text-xs font-bold text-slate-800 block mb-1">Ehtiyat hissəsi satıcısısınız?</span>
                    <p className="text-[11px] text-slate-500 mb-3">
                      Mağazanızı açın və sürücülərin təcili sorğularına qiymət verin.
                    </p>
                    <button
                      type="button"
                      onClick={goSeller}
                      className="w-full py-2.5 px-3 bg-[#FFC61A] hover:bg-[#FFD24D] text-[#1B1B12] text-xs font-bold rounded-xl flex items-center justify-center gap-1 active:scale-95"
                    >
                      {seller.userId ? 'Satıcı panelinə keç' : 'Satıcı girişi'}
                      <ChevronRight className="w-4 h-4" />
                    </button>
                  </div>

                  <button
                    type="button"
                    onClick={() => {
                      setMenuOpen(false);
                      setDataModal('buyer');
                    }}
                    className="w-full py-2.5 px-3 border border-slate-200 text-slate-600 text-xs font-semibold rounded-xl"
                  >
                    Mənim məlumatlarım
                  </button>
                </>
              )}

              {!buyerActive && (
                <button
                  type="button"
                  onClick={() => {
                    setRole('buyer');
                    setMenuOpen(false);
                  }}
                  className="w-full py-2.5 px-3 bg-slate-100 hover:bg-slate-200 text-slate-800 text-xs font-bold rounded-xl"
                >
                  Alıcı rejiminə keç
                </button>
              )}

              {seller.isAdmin && role !== 'admin' && (
                <button
                  type="button"
                  onClick={() => {
                    setRole('admin');
                    setMenuOpen(false);
                  }}
                  className="w-full py-2.5 px-3 bg-slate-800 hover:bg-slate-900 text-white text-xs font-bold rounded-xl flex items-center justify-center gap-1.5"
                >
                  <ShieldAlert className="w-4 h-4" /> Admin paneli
                </button>
              )}

              {seller.userId && (
                <div className="p-3.5 rounded-2xl bg-slate-50 border border-slate-200">
                  <span className="text-[10px] font-bold text-slate-400 uppercase tracking-wider block mb-1">Hesab</span>
                  <div className="text-xs font-semibold text-slate-800 truncate">{seller.email}</div>
                  {seller.store && (
                    <div className="text-[11px] text-slate-500 mt-0.5">
                      {seller.store.name} · {formatCoin(seller.store.coin_balance)} coin · {PLAN_LABELS[effectivePlan(seller.store)]}
                    </div>
                  )}
                  <div className="flex gap-2 mt-3">
                    {seller.store && (
                      <button
                        type="button"
                        onClick={() => {
                          setMenuOpen(false);
                          setProfileMode('edit');
                        }}
                        className="flex-1 py-2 bg-white border border-slate-200 text-slate-700 text-[11px] font-bold rounded-lg flex items-center justify-center gap-1"
                      >
                        <Settings className="w-3.5 h-3.5" /> Profil
                      </button>
                    )}
                    <button
                      type="button"
                      onClick={() => {
                        setMenuOpen(false);
                        setDataModal('seller');
                      }}
                      className="flex-1 py-2 bg-white border border-slate-200 text-slate-600 text-[11px] font-bold rounded-lg"
                    >
                      Məlumatlarım
                    </button>
                    <button
                      type="button"
                      onClick={() => void logout()}
                      className="flex-1 py-2 bg-white border border-slate-200 text-slate-600 text-[11px] font-bold rounded-lg flex items-center justify-center gap-1"
                    >
                      <LogOut className="w-3.5 h-3.5" /> Çıxış
                    </button>
                  </div>
                </div>
              )}
            </div>

            {(termsUrl || privacyUrl) && (
              <div className="mt-6 pt-4 border-t border-slate-100 flex gap-4 text-[11px] text-slate-400">
                {termsUrl && <a href={termsUrl} target="_blank" rel="noreferrer" className="underline">İstifadə şərtləri</a>}
                {privacyUrl && <a href={privacyUrl} target="_blank" rel="noreferrer" className="underline">Məxfilik siyasəti</a>}
              </div>
            )}
          </div>
        </div>
      )}

      {dataModal && (
        <DataModal
          db={dataModal === 'buyer' ? buyerDb : sellerDb}
          who={dataModal}
          onClose={() => setDataModal(null)}
          onDeleted={() => {
            try {
              localStorage.removeItem('autotender_last_car');
              localStorage.removeItem('autotender_pending_store');
              localStorage.setItem('autotender_role', 'buyer');
            } catch {
              /* ignore */
            }
            window.location.reload();
          }}
        />
      )}

      {authOpen && (
        <SellerAuthModal
          brands={brands}
          onClose={() => setAuthOpen(false)}
          onSuccess={() => {
            setAuthOpen(false);
            setRole('seller');
          }}
        />
      )}

      {profileMode && (
        <SellerProfileHost
          mode={profileMode}
          brands={brands}
          onClose={() => setProfileMode(null)}
          onCreated={() => setRole('seller')}
        />
      )}
    </>
  );
}

function SellerProfileHost({
  mode,
  brands,
  onClose,
  onCreated,
}: {
  mode: 'create' | 'edit';
  brands: CarBrand[];
  onClose: () => void;
  onCreated: () => void;
}) {
  const seller = useSeller();
  return (
    <StoreProfileModal
      mode={mode}
      store={seller.store}
      brands={brands}
      onClose={() => {
        if (mode === 'create') onCreated();
        onClose();
      }}
    />
  );
}
