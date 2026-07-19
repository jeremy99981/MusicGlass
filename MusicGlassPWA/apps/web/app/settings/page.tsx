"use client";

import { useEffect, useRef, useState } from "react";
import { Alert, AlertIcon, AlertDescription } from "@appica/ui-react/alert";
import { Badge } from "@appica/ui-react/badge";
import { Button, buttonVariants } from "@appica/ui-react/button";
import { Input } from "@appica/ui-react/input";
import { Check, CircleAlert, Cloud, LoaderCircle, LogIn, RotateCcw, Server, Wifi } from "lucide-react";
import Link from "next/link";
import { getBackendOrigin, normalizeBackendOrigin, probeBackend, setBackendOrigin } from "@/lib/backend-config";

type ConnectionState = "idle" | "testing" | "success" | "error";

export default function SettingsPage() {
  const [backend, setBackend] = useState("");
  const backendInputRef = useRef<HTMLInputElement>(null);
  const [connectionState, setConnectionState] = useState<ConnectionState>("idle");
  const [message, setMessage] = useState("Aucun test lancé.");

  useEffect(() => {
    setBackend(getBackendOrigin());
  }, []);

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

  const StatusIcon = connectionState === "testing" ? LoaderCircle : connectionState === "success" ? Check : connectionState === "error" ? CircleAlert : Wifi;
  const updateBackend = (value: string) => {
    setBackend(value);
    setConnectionState("idle");
  };

  return (
    <div className="page settings-page">
      <header className="topbar settings-topbar">
        <div><span className="eyebrow">Connexion distante</span><h1>Réglages</h1></div>
        <Link className={buttonVariants({ variant: "primary", size: "md", className: "primary-button" })} href="/login"><LogIn size={18} /> Se connecter</Link>
      </header>

      <section className="backend-settings-card">
        <div className="backend-settings-copy">
          <Badge className="settings-badge" variant="soft"><Server size={15} /> Backend autonome</Badge>
          <h2>Connecter ce lecteur au Mac</h2>
          <p>Indiquez l’adresse HTTPS du tunnel MusicGlass. Le catalogue, l’audio, les comptes et les sessions synchronisées utiliseront tous ce serveur.</p>
        </div>

        <div className="backend-form">
          <label htmlFor="backend-origin">Adresse publique du backend</label>
          <Input
            id="backend-origin"
            ref={backendInputRef}
            className="backend-input-row"
            inputSize="lg"
            startSlot={<Cloud size={20} />}
            inputMode="url"
            autoCapitalize="none"
            autoCorrect="off"
            placeholder="https://music.example.com"
            value={backend}
            onInput={(event) => updateBackend(event.currentTarget.value)}
            onChange={(event) => updateBackend(event.target.value)}
          />
          <Alert className={`backend-status backend-status-${connectionState}`} variant={connectionState === "error" ? "error" : connectionState === "success" ? "success" : "info"} layout="inline" aria-live="polite">
            <AlertIcon><StatusIcon className={connectionState === "testing" ? "spin" : ""} size={17} /></AlertIcon>
            <AlertDescription>{message}</AlertDescription>
          </Alert>
          <div className="backend-actions">
            <Button className="secondary-button" variant="outline" type="button" disabled={connectionState === "testing"} onClick={() => void testConnection()}>Tester</Button>
            <Button className="primary-button" type="button" disabled={connectionState === "testing"} onClick={() => void saveBackend()}>Enregistrer et reconnecter</Button>
            <Button className="icon-button backend-reset" variant="ghost" size="icon-md" type="button" aria-label="Utiliser le backend du site" onClick={resetBackend}><RotateCcw size={18} /></Button>
          </div>
        </div>
      </section>

      <section className="connection-principles" aria-label="Fonctionnement du backend">
        <article><span>01</span><strong>Docker sur le Mac</strong><p>API, PostgreSQL et Redis restent sur votre machine.</p></article>
        <article><span>02</span><strong>Tunnel chiffré</strong><p>Le téléphone accède au Mac sans ouvrir de port sur la box.</p></article>
        <article><span>03</span><strong>Un seul réglage</strong><p>REST, audio et WebSocket suivent automatiquement la même adresse.</p></article>
      </section>
    </div>
  );
}
