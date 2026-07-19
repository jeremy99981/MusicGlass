"use client";

import { Alert, Badge, Button, Input, Spinner } from "@appica/ui-react";
import { FormEvent, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { CheckCircle2, LogIn, Radio, Users, WifiOff } from "lucide-react";
import Link from "next/link";
import { createSharedSession, endSharedSession, fetchMe, getSharedSession } from "@/lib/session-api";
import { useSharedSessionStore } from "@/store/shared-session-store";

export function SharedSessionPanel({ compact = false }: { compact?: boolean }) {
  const { code, status, isHost, participants, error, setSession, reset, setError } = useSharedSessionStore();
  const [joinCode, setJoinCode] = useState("");
  const [loading, setLoading] = useState(false);
  const { data: me, isLoading: authLoading, refetch: refetchMe } = useQuery({
    queryKey: ["me"],
    queryFn: fetchMe,
    retry: false,
    staleTime: 15_000,
  });
  const authenticated = Boolean(me);

  async function createSession() {
    const auth = me ?? (await refetchMe()).data;
    if (!auth) {
      setError("Connectez-vous pour créer ou rejoindre une session.");
      return;
    }
    setLoading(true);
    setError(null);
    try {
      const session = await createSharedSession();
      setSession({ code: session.code, isHost: true });
    } catch (err) {
      setError(err instanceof Error ? err.message : "Création impossible.");
    } finally {
      setLoading(false);
    }
  }

  async function joinSession(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!joinCode.trim()) return;
    const auth = me ?? (await refetchMe()).data;
    if (!auth) {
      setError("Connectez-vous pour créer ou rejoindre une session.");
      return;
    }
    setLoading(true);
    setError(null);
    try {
      const session = await getSharedSession(joinCode);
      setSession({ code: session.code, isHost: false });
    } catch (err) {
      setError(err instanceof Error ? err.message : "Session introuvable.");
    } finally {
      setLoading(false);
    }
  }

  async function leaveSession() {
    const currentCode = code;
    reset();
    if (currentCode && isHost) {
      try {
        await endSharedSession(currentCode);
      } catch {
        // The local UI should still leave even if the HTTP cleanup fails.
      }
    }
  }

  return (
    <section className={`shared-session ${compact ? "shared-session-compact" : ""}`} aria-label="Session partagée">
      <div className="shared-session-title">
        <Radio size={18} />
        <strong>{code ? "Session partagée" : "Session privée"}</strong>
      </div>

      <p className="shared-session-status">
        État: <Badge size="xs" variant={status === "connected" ? "success" : "soft"} data-status={status}>{status}</Badge>
        {isHost && code ? " · hôte" : code ? " · invité" : ""}
      </p>

      <div className={`account-status ${authenticated ? "account-status-connected" : "account-status-disconnected"}`}>
        {authLoading ? (
          <>
            <Spinner currentColor className="text-[15px]" aria-label="Vérification du compte" />
            <span>Vérification du compte...</span>
          </>
        ) : authenticated ? (
          <>
            <CheckCircle2 size={15} />
            <span>
              Compte connecté{me?.name ? ": " : " · "}
              {me?.name ? <strong>{me.name}</strong> : <strong>session active</strong>}
            </span>
          </>
        ) : (
          <>
            <WifiOff size={15} />
            <span>Compte non connecté</span>
            <Link href="/login"><LogIn size={14} /> Connexion</Link>
          </>
        )}
      </div>

      {code ? (
        <>
          <div className="session-code">Code: {code}</div>
          <div className="session-participants">
            <Users size={15} />
            {participants.length || 1} appareil{(participants.length || 1) > 1 ? "s" : ""} connecté{(participants.length || 1) > 1 ? "s" : ""}
          </div>
          {participants.length > 0 && (
            <div className="session-chips">
              {participants.map((participant) => (
                <Badge key={`${participant.user_id}-${participant.client_id ?? "client"}`} size="xs" variant="soft">
                  {participant.name}{participant.is_host ? " (hôte)" : ""}
                </Badge>
              ))}
            </div>
          )}
          <Button type="button" variant="ghost" size="sm" className="ghost-button session-action" onClick={leaveSession}>
            Quitter
          </Button>
        </>
      ) : (
        <>
          <p className="shared-session-copy">Créez une session ou rejoignez un code existant pour écouter ensemble.</p>
          <div className="session-actions">
            <Button type="button" size="sm" className="primary-button" onClick={createSession} disabled={loading || authLoading}>
              Créer
            </Button>
            <form onSubmit={joinSession} className="session-join-form">
              <Input
                value={joinCode}
                onChange={(event) => setJoinCode(event.target.value.toUpperCase())}
                placeholder="CODE"
                maxLength={8}
                aria-label="Code de session"
                inputSize="sm"
              />
              <Button type="submit" variant="ghost" size="sm" className="ghost-button" disabled={loading || authLoading || joinCode.trim().length < 4}>
                Rejoindre
              </Button>
            </form>
          </div>
        </>
      )}

      {error && (
        <Alert variant="error" className="session-error" role="alert">
          {error.includes("Connectez-vous") || error.includes("unauthorized") ? (
            <>
              <span>{error}</span>
              <Link href="/login">
                <LogIn size={15} /> Connexion
              </Link>
            </>
          ) : (
            error
          )}
        </Alert>
      )}
    </section>
  );
}
