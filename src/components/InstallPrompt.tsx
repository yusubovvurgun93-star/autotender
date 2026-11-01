import { useEffect, useState } from 'react';
import { Download, Share, X } from 'lucide-react';

const DISMISS_KEY = 'autotender_install_dismissed';
const DISMISS_DAYS = 7;

type BeforeInstallPromptEvent = Event & {
  prompt: () => Promise<void>;
  userChoice: Promise<{ outcome: 'accepted' | 'dismissed' }>;
};

function recentlyDismissed(): boolean {
  try {
    const t = Number(localStorage.getItem(DISMISS_KEY) || 0);
    return t > 0 && Date.now() - t < DISMISS_DAYS * 86400000;
  } catch {
    return false;
  }
}

function isStandalone(): boolean {
  return (
    window.matchMedia?.('(display-mode: standalone)').matches ||
    (navigator as unknown as { standalone?: boolean }).standalone === true
  );
}

/** "Ana ekrana əlavə et" təklifi: Android-də bir toxunuşla, iPhone-da qısa izahatla */
export function InstallPrompt() {
  const [deferred, setDeferred] = useState<BeforeInstallPromptEvent | null>(null);
  const [iosHint, setIosHint] = useState(false);
  const [hidden, setHidden] = useState(true);

  useEffect(() => {
    if (isStandalone() || recentlyDismissed()) return;

    const onPrompt = (e: Event) => {
      e.preventDefault();
      setDeferred(e as BeforeInstallPromptEvent);
      setHidden(false);
    };
    window.addEventListener('beforeinstallprompt', onPrompt);

    const ua = navigator.userAgent;
    const isIos = /iPad|iPhone|iPod/.test(ua) && !/CriOS|FxiOS/.test(ua);
    if (isIos) {
      setIosHint(true);
      setHidden(false);
    }
    const onInstalled = () => setHidden(true);
    window.addEventListener('appinstalled', onInstalled);
    return () => {
      window.removeEventListener('beforeinstallprompt', onPrompt);
      window.removeEventListener('appinstalled', onInstalled);
    };
  }, []);

  const dismiss = () => {
    setHidden(true);
    try {
      localStorage.setItem(DISMISS_KEY, String(Date.now()));
    } catch {
      /* ignore */
    }
  };

  const install = async () => {
    if (!deferred) return;
    await deferred.prompt();
    await deferred.userChoice.catch(() => undefined);
    setDeferred(null);
    setHidden(true);
  };

  if (hidden || (!deferred && !iosHint)) return null;

  return (
    <div className="mx-3 mt-2 rounded-2xl bg-white border border-slate-200 shadow-sm p-3 flex items-start gap-3">
      <div className="w-9 h-9 rounded-xl bg-[#0B4635] text-white flex items-center justify-center flex-shrink-0">
        <Download className="w-4 h-4" />
      </div>
      <div className="min-w-0 flex-1">
        <p className="text-xs font-bold text-slate-800">Tətbiq kimi quraşdırın</p>
        {deferred ? (
          <>
            <p className="text-[11px] text-slate-500">Ana ekrandan bir toxunuşla açın, bildirişləri qaçırmayın.</p>
            <button onClick={install} className="mt-2 px-3 py-1.5 bg-[#0B4635] text-white text-[11px] font-bold rounded-lg">
              Quraşdır
            </button>
          </>
        ) : (
          <p className="text-[11px] text-slate-500 flex flex-wrap items-center gap-1">
            Safari-də <Share className="w-3.5 h-3.5 inline" /> “Paylaş” düyməsinə basın, sonra “Ana ekrana əlavə et” seçin.
          </p>
        )}
      </div>
      <button onClick={dismiss} aria-label="Bağla" className="p-1 text-slate-400">
        <X className="w-4 h-4" />
      </button>
    </div>
  );
}
