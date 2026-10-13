import {
  createIcons, Reply, Trash2, Flag, Settings, Settings2, MessagesSquare, ChevronDown, Plus, Ellipsis, Pencil, Archive, RotateCcw, BadgeCheck, Smile, Compass, Search, CircleHelp, ArrowLeft, Activity, ArrowLeftRight, ArrowRight, BookOpen, BookOpenCheck,
  Briefcase, BriefcaseBusiness, Calculator, CalendarClock, CalendarDays,
  Check, CheckCircle2, CircleAlert, Cloud, Dumbbell, FileCheck, FileClock,
  FlaskConical, Footprints, Globe, GraduationCap, Hammer, HeartHandshake,
  Hash, School, UserMinus, Info, Landmark, Languages, LockKeyhole, LogIn, LogOut, Mail, MapPin, Megaphone, MessageCircle, Monitor,
  MonitorPlay, Palette, Paperclip, Presentation, RefreshCw, Repeat2, Send, ShieldCheck,
  SlidersHorizontal, Sprout, Sun, TriangleAlert, UserCheck, UserPlus, Users, UsersRound, Utensils,
  Vote, Wallet, WifiOff, X
} from 'lucide';

// Explicit registry keeps the other 1,500+ Lucide icons out of the app bundle.
const registry = { Reply, Trash2, Flag, Settings, Settings2, MessagesSquare, ChevronDown, Plus, Ellipsis, Pencil, Archive, RotateCcw, BadgeCheck, Smile, Compass, Search, CircleHelp, ArrowLeft,
  Activity, ArrowLeftRight, ArrowRight, BookOpen, BookOpenCheck, Briefcase,
  BriefcaseBusiness, Calculator, CalendarClock, CalendarDays, Check,
  CheckCircle2, CircleAlert, Cloud, CloudCheck: Cloud, Dumbbell, FileCheck,
  FileClock, FlaskConical, Footprints, Globe, GraduationCap, Hammer,
  HeartHandshake, Hash, School, UserMinus, Info, Landmark, Languages, LockKeyhole, LogIn, LogOut, Mail, MapPin,
  Megaphone, MessageCircle, Monitor, MonitorPlay, Palette, Paperclip, Presentation, RefreshCw, Repeat2,
  Send, ShieldCheck, SlidersHorizontal, Sprout, Sun, TriangleAlert, UserCheck, UserPlus, Users,
  UsersRound, Utensils, Vote, Wallet, WifiOff, X
};
const pascalCase = name => String(name).split('-').map(part => part.charAt(0).toUpperCase() + part.slice(1)).join('');
export function hasIcon(name) { return Object.hasOwn(registry, pascalCase(name)); }

export function paintIcons() {
  // New subjects from older/newer clients always receive a useful safe fallback.
  document.querySelectorAll('[data-lucide]').forEach(element => {
    if (!hasIcon(element.getAttribute('data-lucide'))) element.setAttribute('data-lucide', 'circle-help');
  });
  createIcons({ icons: registry, attrs: { 'stroke-width': 1.8 } });
}
