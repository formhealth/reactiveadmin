import {
  Activity, Archive, Banknote, Bell, BookOpen, Boxes, Briefcase, Building, Building2, Calendar, CalendarDays, ChartBar, ChartLine, ChartPie,
  CircleHelp, ClipboardCheck, ClipboardList, Cog, CreditCard, Database, DollarSign, Factory, FileText, Files, FlaskConical, Flag, Folder,
  GraduationCap, Globe, Handshake, HandCoins, HeartPulse, History, Hospital, IdCard, Inbox, Info, KeyRound, Landmark, Layers, LayoutDashboard,
  LifeBuoy, Link, ListChecks, Lock, Mail, MapPin, MessageSquare, MessagesSquare, Package, Percent, Phone, Pill, Plug, Receipt, RefreshCw,
  Scale, ScrollText, Search, Send, Server, Settings, Shield, ShieldCheck, ShoppingCart, SlidersHorizontal, Smartphone, Sparkles, Star, Stethoscope,
  Syringe, Tag, Tags, TestTube, Truck, User, UserCog, Users, Wallet, Workflow, Wrench, Zap,
  type LucideIcon,
} from 'lucide-react'

// The whole lucide set would bloat the bundle, so menu icons come from a curated set of admin-flavoured names.
// Names match case-insensitively and ignore dashes, so `heart-pulse`, `HeartPulse` and `heart_pulse` agree.
const ICONS: Record<string, LucideIcon> = {
  Activity, Archive, Banknote, Bell, BookOpen, Boxes, Briefcase, Building, Building2, Calendar, CalendarDays, ChartBar, ChartLine, ChartPie,
  CircleHelp, ClipboardCheck, ClipboardList, Cog, CreditCard, Database, DollarSign, Factory, FileText, Files, FlaskConical, Flag, Folder,
  GraduationCap, Globe, Handshake, HandCoins, HeartPulse, History, Hospital, IdCard, Inbox, Info, KeyRound, Landmark, Layers, LayoutDashboard,
  LifeBuoy, Link, ListChecks, Lock, Mail, MapPin, MessageSquare, MessagesSquare, Package, Percent, Phone, Pill, Plug, Receipt, RefreshCw,
  Scale, ScrollText, Search, Send, Server, Settings, Shield, ShieldCheck, ShoppingCart, SlidersHorizontal, Smartphone, Sparkles, Star, Stethoscope,
  Syringe, Tag, Tags, TestTube, Truck, User, UserCog, Users, Wallet, Workflow, Wrench, Zap,
}

const normalize = (name: string) => name.toLowerCase().replace(/[^a-z0-9]/g, '')
const BY_NAME = new Map(Object.entries(ICONS).map(([name, icon]) => [normalize(name), icon]))

export const iconFor = (name?: string | null): LucideIcon | undefined => (name ? BY_NAME.get(normalize(name)) : undefined)
