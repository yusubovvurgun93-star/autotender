import { useState } from 'react';
import { Bell, Menu, X } from 'lucide-react';
import type { Role } from '@/lib/theme';
import { buyerDb, sellerDb } from '@/lib/supabase';
import { useNotifications, useSeller } from '@/lib/auth';
import { PLAN_LABELS, effectivePlan, formatCoin, formatTimeAgo, showToast } from '@/lib/utils';
import { Sheet } from '@/components/ui';
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
    if (!seller.store) {
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


  const goAccount = () => window.dispatchEvent(new CustomEvent('autotender:tab', { detail: 'account' }));
  const pick = (r: Role) => {
    setMenuOpen(false);
    setRole(r);
  };
  const store = seller.store;
  return (
    <>
      <div
        className="sticky top-0 z-40 px-3 pb-2"
        style={{ paddingTop: 'max(env(safe-area-inset-top, 0px), 8px)' }}
      >
        <nav className="glass rounded-[22px] pl-3 pr-2 h-14 flex items-center justify-between gap-2">
          <div className="flex items-center gap-2.5 min-w-0">
            <img src="/logo-96.png" alt="" width={36} height={36} className="w-9 h-9 rounded-[12px] flex-shrink-0" />
            <div className="leading-none min-w-0">
              <div className="font-display font-extrabold text-[19px] tracking-tight text-[#0B4635]">AutoTender</div>
              {(sellerActive || role === 'admin') && (
                <div className="text-[11px] font-medium text-slate-500 truncate max-w-[130px] mt-1">
                  {sellerActive ? seller.store?.name || 'Satıcı' : 'Admin paneli'}
                </div>
              )}
            </div>
          </div>

          <div className="flex items-center gap-1.5 flex-shrink-0">
            {sellerActive && seller.store && (
              <button
                type="button"
                onClick={goAccount}
                aria-label="Hesab və coin"
                className="h-10 px-3 rounded-2xl bg-[#FFC61A] text-[#0F2A21] font-display font-extrabold text-[13px] active:scale-95 transition shadow-[0_6px_14px_-6px_rgba(255,198,26,0.95)]"
              >
                {effectivePlan(seller.store) === 'pro' ? '∞ ' : ''}
                {formatCoin(seller.store.coin_balance)}
                <span className="text-[11px] font-bold ml-1 opacity-70">coin</span>
              </button>
            )}

            <button
              type="button"
              onClick={openNotifs}
              aria-label="Bildirişlər"
              className="relative h-10 w-10 rounded-2xl flex items-center justify-center bg-black/5 text-slate-700 active:scale-95 transition"
            >
              <Bell className="w-[18px] h-[18px]" />
              {unread > 0 && (
                <span className="absolute -top-0.5 -right-0.5 min-w-[18px] h-[18px] px-1 rounded-full bg-rose-500 text-white text-[10px] font-bold flex items-center justify-center">
                  {unread > 9 ? '9+' : unread}
                </span>
              )}
            </button>

            <button
              type="button"
              onClick={() => setMenuOpen(true)}
              aria-label="Menyu"
              className="h-10 w-10 rounded-2xl flex items-center justify-center bg-[#0B4635] text-white active:scale-95 transition"
            >
              <Menu className="w-5 h-5" />
            </button>
          </div>
        </nav>

        {showNotifs && (
          <>
            <div className="fixed inset-0 z-40" onClick={() => setShowNotifs(false)} />
            <div className="glass sheet-up absolute left-3 right-3 top-[calc(100%-2px)] z-50 rounded-3xl max-h-[60vh] overflow-y-auto bg-white/90">
              <div className="p-3.5 border-b border-black/5">
                <span className="font-display text-[13px] font-extrabold text-slate-800">Bildirişlər</span>
              </div>
              {items.length === 0 ? (
                <div className="p-6 text-center text-[13px] text-slate-400">Bildiriş yoxdur</div>
              ) : (
                items.map((n) => (
                  <div key={n.id} className="p-3.5 border-b border-black/5 last:border-0">
                    <div className="text-[13px] font-bold text-slate-800">{n.title}</div>
                    {n.body && <div className="text-xs text-slate-500 mt-0.5">{n.body}</div>}
                    <div className="text-[11px] text-slate-400 mt-1">{formatTimeAgo(n.created_at)}</div>
                  </div>
                ))
              )}
            </div>
          </>
        )}
      </div>

      {menuOpen && (
        <Sheet title="Menyu" onClose={() => setMenuOpen(false)}>
          <div className="space-y-3">
            {/* Rejim keçidləri: yalnız mövcud olanlar göstərilir */}
            <div className="space-y-2">
              {role !== 'buyer' && (
                <button type="button" onClick={() => pick('buyer')} className="btn-primary w-full">
                  Alıcı rejiminə keç
                </button>
              )}
              {role !== 'seller' && (
                <button type="button" onClick={goSeller} className={`${role === 'buyer' ? 'btn-cta' : 'btn-ghost'} w-full`}>
                  {!seller.userId
                    ? 'Satıcı kimi qoşul'
                    : store
                      ? 'Satıcı panelinə keç'
                      : 'Mağaza profilini tamamla'}
                </button>
              )}
              {seller.isAdmin && role !== 'admin' && (
                <button type="button" onClick={() => pick('admin')} className="btn-ghost w-full">
                  Admin panelinə keç
                </button>
              )}
            </div>

            {seller.userId && (
              <div className="card-flat">
                <div className="text-[13px] font-bold text-slate-900 truncate">{store ? store.name : seller.email}</div>
                {store && (
                  <div className="text-[11px] text-slate-500 mt-1">
                    {Number(store.rating).toFixed(1)} ulduz
                    {store.review_count > 0 ? ` (${store.review_count} rəy)` : ''}, dərəcə {store.grade}, {PLAN_LABELS[effectivePlan(store)]}
                  </div>
                )}
                <div className="text-[11px] text-slate-400 mt-0.5 truncate">{seller.email}</div>
                <div className="flex gap-1.5 mt-2.5">
                  {store && (
                    <button
                      type="button"
                      onClick={() => {
                        setMenuOpen(false);
                        setProfileMode('edit');
                      }}
                      className="btn-ghost flex-1"
                    >
                      Profil
                    </button>
                  )}
                  <button type="button" onClick={() => void logout()} className="btn-ghost flex-1">
                    Çıxış
                  </button>
                </div>
              </div>
            )}

            <div className="flex items-center justify-center gap-4 pt-1 text-xs">
              <button
                type="button"
                onClick={() => {
                  setMenuOpen(false);
                  setDataModal('buyer');
                }}
                className="text-slate-400 hover:text-rose-600"
              >
                Tarixçəni sil
              </button>
              {seller.userId && (
                <button
                  type="button"
                  onClick={() => {
                    setMenuOpen(false);
                    setDataModal('seller');
                  }}
                  className="text-slate-400 hover:text-rose-600"
                >
                  Mağaza hesabını sil
                </button>
              )}
            </div>

            {(termsUrl || privacyUrl) && (
              <div className="pt-2 border-t border-black/5 flex gap-4 text-xs text-slate-400">
                {termsUrl && <a href={termsUrl} target="_blank" rel="noreferrer" className="underline">İstifadə şərtləri</a>}
                {privacyUrl && <a href={privacyUrl} target="_blank" rel="noreferrer" className="underline">Məxfilik siyasəti</a>}
              </div>
            )}
          </div>
        </Sheet>
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
