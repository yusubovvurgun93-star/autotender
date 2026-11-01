import { CheckCircle2, XCircle, Info, Bell, Trophy, X } from 'lucide-react';
import { useToasts } from '@/lib/utils';

const iconMap = {
  success: CheckCircle2,
  error: XCircle,
  info: Info,
  bid: Bell,
  win: Trophy,
};

const colorMap = {
  success: 'border-emerald-200 bg-white text-emerald-600',
  error: 'border-rose-200 bg-white text-rose-600',
  info: 'border-blue-200 bg-white text-blue-600',
  bid: 'border-amber-200 bg-white text-amber-600',
  win: 'border-emerald-200 bg-white text-emerald-600',
};

export function ToastContainer() {
  const { toasts, dismiss } = useToasts();

  return (
    <div className="fixed top-20 right-4 z-[100] flex flex-col gap-2 max-w-sm w-full pointer-events-none">
      {toasts.map((toast) => {
        const Icon = iconMap[toast.type];
        return (
          <div
            key={toast.id}
            className={`pointer-events-auto flex items-start gap-3 rounded-2xl border p-4 shadow-xl animate-in slide-in-from-right duration-300 text-slate-800 ${colorMap[toast.type]}`}
          >
            <Icon className="w-5 h-5 flex-shrink-0 mt-0.5" />
            <div className="flex-1 min-w-0">
              <p className="font-semibold text-sm">{toast.title}</p>
              {toast.body && <p className="text-xs mt-0.5 text-slate-500">{toast.body}</p>}
            </div>
            <button
              onClick={() => dismiss(toast.id)}
              className="flex-shrink-0 text-slate-400 hover:text-slate-600 transition-colors"
            >
              <X className="w-4 h-4" />
            </button>
          </div>
        );
      })}
    </div>
  );
}
