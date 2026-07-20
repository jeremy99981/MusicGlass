"use client";

import { ReactNode, useEffect, useRef, useState } from "react";
import { Bell, Check, ChevronRight, CircleAlert, Clock3, Cloud, FileText, Gauge, HelpCircle, Info, LoaderCircle, LogIn, RotateCcw, Server, Shield, SlidersHorizontal, Users, Wifi } from "lucide-react";
import Link from "next/link";
import { getBackendOrigin, normalizeBackendOrigin, probeBackend, setBackendOrigin } from "@/lib/backend-config";
import styles from "./settings.module.css";

type ConnectionState = "idle" | "testing" | "success" | "error";

export default function SettingsPage() {
  const [backend, setBackend] = useState("");
  const backendInputRef = useRef<HTMLInputElement>(null);
  const [connectionState, setConnectionState] = useState<ConnectionState>("idle");
  const [message, setMessage] = useState("Aucun test lancé.");
  const [wifiOnly, setWifiOnly] = useState(true);
  const [crossfade, setCrossfade] = useState(false);
  const [newReleases, setNewReleases] = useState(true);
  const [friendActivity, setFriendActivity] = useState(false);

  useEffect(() => setBackend(getBackendOrigin()), []);

  async function testConnection(value?: string) {
    const candidate = value ?? backendInputRef.current?.value ?? backend;
    setConnectionState("testing");
    setMessage("Connexion au Mac en cours...");
    const controller = new AbortController();
    const timeout = window.setTimeout(() => controller.abort(), 8_000);
    try {
      const result = await probeBackend(candidate, controller.signal);
      setConnectionState("success");
      setMessage(result.origin ? `Backend joignable sur ${result.origin}` : "Backend local joignable via ce site.");
      return true;
    } catch (error) {
      const detail = error instanceof DOMException && error.name === "AbortError"
        ? "Délai dépassé. Vérifiez que Docker et le tunnel sont démarrés."
        : error instanceof Error ? error.message : "Connexion impossible.";
      setConnectionState("error");
      setMessage(detail);
      return false;
    } finally {
      window.clearTimeout(timeout);
    }
  }

  async function saveBackend() {
    let normalized = "";
    try {
      normalized = normalizeBackendOrigin(backendInputRef.current?.value ?? backend);
      setBackend(normalized);
    } catch (error) {
      setConnectionState("error");
      setMessage(error instanceof Error ? error.message : "Adresse invalide.");
      return;
    }
    if (!await testConnection(normalized)) return;
    setBackendOrigin(normalized);
    window.location.reload();
  }

  function resetBackend() {
    setBackendOrigin("");
    setBackend("");
    setConnectionState("idle");
    setMessage("Configuration réinitialisée. Le site utilise maintenant son API intégrée.");
    window.location.reload();
  }

  const StatusIcon = connectionState === "testing" ? LoaderCircle : connectionState === "success" ? Check : connectionState === "error" ? CircleAlert : Clock3;

  return (
    <main className={styles.page}>
      <header className={styles.header}><h1>Réglages</h1></header>
      <div className={styles.content}>
        <SettingsSection title="Compte">
          <Link className={styles.row} href="/login"><span className={styles.avatar}>MG</span><span className={styles.copy}><strong>Invité</strong><small>Non connecté</small></span><ChevronRight /></Link>
          <Link className={styles.row} href="/login"><IconChip><LogIn /></IconChip><span className={styles.copy}><strong>Se connecter</strong></span><ChevronRight /></Link>
        </SettingsSection>

        <section className={styles.section}>
          <h2>Connexion distante</h2>
          <div className={styles.backendCard}>
            <div className={styles.backendTitle}><IconChip><Server /></IconChip><span><strong>Connecter ce lecteur au Mac</strong><small>Backend autonome</small></span></div>
            <p>Indiquez l’adresse HTTPS du tunnel MusicGlass. Catalogue, audio et sessions utiliseront ce serveur.</p>
            <label className={styles.backendInput}><Cloud /><input ref={backendInputRef} type="url" inputMode="url" autoCapitalize="none" autoCorrect="off" placeholder="https://music.example.com" value={backend} onChange={(event) => { setBackend(event.target.value); setConnectionState("idle"); }} aria-label="Adresse publique du backend" /></label>
            <div className={`${styles.status} ${styles[connectionState]}`} role="status" aria-live="polite"><StatusIcon className={connectionState === "testing" ? styles.spin : ""} />{message}</div>
            <div className={styles.backendActions}><button type="button" disabled={connectionState === "testing"} onClick={() => void testConnection()}>Tester</button><button className={styles.save} type="button" disabled={connectionState === "testing"} onClick={() => void saveBackend()}>Enregistrer</button><button className={styles.reset} type="button" onClick={resetBackend} aria-label="Réinitialiser le backend"><RotateCcw /></button></div>
          </div>
        </section>

        <SettingsSection title="Lecture">
          <StaticRow icon={<Gauge />} label="Qualité audio" value="Élevée" />
          <SwitchRow icon={<Wifi />} label="Télécharger en Wi-Fi uniquement" checked={wifiOnly} onChange={setWifiOnly} />
          <StaticRow icon={<SlidersHorizontal />} label="Égaliseur" />
          <SwitchRow icon={<SlidersHorizontal />} label="Crossfade entre les titres" checked={crossfade} onChange={setCrossfade} neutral />
        </SettingsSection>

        <SettingsSection title="Notifications">
          <SwitchRow icon={<Bell />} label="Nouvelles sorties" checked={newReleases} onChange={setNewReleases} />
          <SwitchRow icon={<Users />} label="Activité des amis" checked={friendActivity} onChange={setFriendActivity} neutral />
        </SettingsSection>

        <SettingsSection title="Confidentialité">
          <StaticRow icon={<Clock3 />} label="Historique d’écoute" />
          <StaticRow icon={<Shield />} label="Gérer mes données" neutral />
        </SettingsSection>

        <SettingsSection title="À propos">
          <StaticRow icon={<Info />} label="Version" value="1.4.0" />
          <StaticRow icon={<FileText />} label="Mentions légales" neutral />
          <StaticRow icon={<HelpCircle />} label="Aide & support" />
        </SettingsSection>

        <p className={styles.localNote}>Les préférences de lecture et notifications affichées ici sont locales à cet appareil. La connexion au backend reste enregistrée par MusicGlass.</p>
      </div>
    </main>
  );
}

function SettingsSection({ title, children }: { title: string; children: ReactNode }) {
  return <section className={styles.section}><h2>{title}</h2><div className={styles.list}>{children}</div></section>;
}

function IconChip({ children, neutral = false }: { children: ReactNode; neutral?: boolean }) {
  return <span className={`${styles.iconChip} ${neutral ? styles.neutral : ""}`}>{children}</span>;
}

function StaticRow({ icon, label, value, neutral = false }: { icon: ReactNode; label: string; value?: string; neutral?: boolean }) {
  return <button className={styles.row} type="button"><IconChip neutral={neutral}>{icon}</IconChip><span className={styles.copy}><strong>{label}</strong></span>{value && <span className={styles.value}>{value}</span>}<ChevronRight /></button>;
}

function SwitchRow({ icon, label, checked, onChange, neutral = false }: { icon: ReactNode; label: string; checked: boolean; onChange: (value: boolean) => void; neutral?: boolean }) {
  return <div className={styles.row}><IconChip neutral={neutral}>{icon}</IconChip><span className={styles.copy}><strong>{label}</strong></span><button className={styles.switch} type="button" role="switch" aria-checked={checked} aria-label={label} onClick={() => onChange(!checked)}><span /></button></div>;
}
