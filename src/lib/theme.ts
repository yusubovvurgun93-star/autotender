export type Role = 'buyer' | 'seller' | 'admin';

export type Theme = {
  bg: string;
  cardBg: string;
  cardBorder: string;
  navbarBg: string;
  navbarBorder: string;
  textPrimary: string;
  textSecondary: string;
  textMuted: string;
  accent: string;
  accentBg: string;
  accentHover: string;
  actionBg: string;
  actionHover: string;
  actionText: string;
  inputBg: string;
  inputBorder: string;
  badgeBg: string;
  badgeText: string;
  shadow: string;
  isDark: boolean;
};

const glassCard = 'bg-slate-900/80 backdrop-blur-md border border-slate-800/80 rounded-2xl shadow-xl';
const glassInput = 'bg-slate-800/60 border-slate-700/60 text-white placeholder-slate-500';

export const buyerTheme: Theme = {
  bg: 'bg-[#0B0F19]',
  cardBg: glassCard,
  cardBorder: 'border-slate-800/80',
  navbarBg: 'bg-[#0B0F19]/90 backdrop-blur-xl',
  navbarBorder: 'border-slate-800/60',
  textPrimary: 'text-white',
  textSecondary: 'text-slate-400',
  textMuted: 'text-slate-500',
  accent: 'text-indigo-400',
  accentBg: 'bg-indigo-500',
  accentHover: 'hover:bg-indigo-400',
  actionBg: 'bg-emerald-500 hover:bg-emerald-400',
  actionHover: 'hover:bg-emerald-400',
  actionText: 'text-slate-950',
  inputBg: glassInput,
  inputBorder: 'border-slate-700/60',
  badgeBg: 'bg-indigo-500/10',
  badgeText: 'text-indigo-400',
  shadow: 'shadow-xl shadow-black/40',
  isDark: true,
};

export const sellerTheme: Theme = {
  bg: 'bg-[#0B0F19]',
  cardBg: glassCard,
  cardBorder: 'border-slate-800/80',
  navbarBg: 'bg-[#0B0F19]/90 backdrop-blur-xl',
  navbarBorder: 'border-slate-800/60',
  textPrimary: 'text-white',
  textSecondary: 'text-slate-400',
  textMuted: 'text-slate-500',
  accent: 'text-amber-400',
  accentBg: 'bg-amber-500',
  accentHover: 'hover:bg-amber-400',
  actionBg: 'bg-emerald-500 hover:bg-emerald-400',
  actionHover: 'hover:bg-emerald-400',
  actionText: 'text-slate-950',
  inputBg: glassInput,
  inputBorder: 'border-slate-700/60',
  badgeBg: 'bg-amber-500/10',
  badgeText: 'text-amber-400',
  shadow: 'shadow-xl shadow-black/40',
  isDark: true,
};

export const adminTheme: Theme = {
  bg: 'bg-[#0B0F19]',
  cardBg: glassCard,
  cardBorder: 'border-slate-800/80',
  navbarBg: 'bg-[#0B0F19]/90 backdrop-blur-xl',
  navbarBorder: 'border-slate-800/60',
  textPrimary: 'text-white',
  textSecondary: 'text-slate-400',
  textMuted: 'text-slate-500',
  accent: 'text-cyan-400',
  accentBg: 'bg-cyan-500',
  accentHover: 'hover:bg-cyan-400',
  actionBg: 'bg-cyan-500 hover:bg-cyan-400',
  actionHover: 'hover:bg-cyan-400',
  actionText: 'text-slate-950',
  inputBg: glassInput,
  inputBorder: 'border-slate-700/60',
  badgeBg: 'bg-cyan-500/10',
  badgeText: 'text-cyan-400',
  shadow: 'shadow-xl shadow-black/40',
  isDark: true,
};

export function getTheme(role: Role): Theme {
  if (role === 'buyer') return buyerTheme;
  if (role === 'seller') return sellerTheme;
  return adminTheme;
}
