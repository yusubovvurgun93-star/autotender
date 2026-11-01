import { useEffect, useState } from 'react';
import { X } from 'lucide-react';

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
    <div className="glass sheet-up mx-3 mt-1 rounded-3xl p-3.5 flex items-start gap-3">
      <div className="min-w-0 flex-1">
        <p className="font-display text-[13px] font-extrabold text-slate-900">Tətbiq kimi quraşdırın</p>
        {deferred ? (
          <>
            <p className="text-xs text-slate-500 mt-0.5">Ana ekrandan bir toxunuşla açın.</p>
            <button onClick={install} className="btn-primary mt-2.5 !py-2 !px-5 !text-xs">
              Quraşdır
            </button>
          </>
        ) : (
          <p className="text-xs text-slate-500 mt-0.5">
            Safari-də “Paylaş” düyməsinə basın, sonra “Ana ekrana əlavə et” seçin.
          </p>
        )}
      </div>
      <button onClick={dismiss} aria-label="Bağla" className="h-8 w-8 rounded-full bg-black/5 text-slate-500 flex items-center justify-center flex-shrink-0">
        <X className="w-4 h-4" />
      </button>
    </div>
  );
}
