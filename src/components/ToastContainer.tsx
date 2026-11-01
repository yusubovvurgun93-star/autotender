import { X } from 'lucide-react';
import { useToasts } from '@/lib/utils';

const dotMap = {
  success: 'bg-emerald-500',
  error: 'bg-rose-500',
  info: 'bg-sky-500',
  bid: 'bg-[#FFC61A]',
  win: 'bg-emerald-500',
};

export function ToastContainer() {
  const { toasts, dismiss } = useToasts();

  return (
    <div
      className="fixed left-1/2 -translate-x-1/2 z-[100] flex flex-col gap-2 w-[calc(100%-24px)] max-w-sm pointer-events-none"
      style={{ top: 'max(76px, calc(env(safe-area-inset-top, 0px) + 68px))' }}
    >
      {toasts.map((toast) => (
        <div key={toast.id} className="glass sheet-up pointer-events-auto flex items-start gap-3 rounded-2xl p-3.5 text-slate-800">
          <span className={`mt-1.5 h-2.5 w-2.5 rounded-full flex-shrink-0 ${dotMap[toast.type]}`} />
          <div className="flex-1 min-w-0">
            <p className="font-display font-bold text-sm">{toast.title}</p>
            {toast.body && <p className="text-xs mt-0.5 text-slate-500">{toast.body}</p>}
          </div>
          <button
            onClick={() => dismiss(toast.id)}
            aria-label="Bağla"
            className="flex-shrink-0 text-slate-400 hover:text-slate-600 transition-colors"
          >
            <X className="w-4 h-4" />
          </button>
        </div>
      ))}
    </div>
  );
}
