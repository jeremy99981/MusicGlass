"use client";

import { ArrowLeft, LoaderCircle, ShieldCheck } from "lucide-react";
import { Alert, AlertDescription } from "@appica/ui-react/alert";
import { Badge } from "@appica/ui-react/badge";
import { Button } from "@appica/ui-react/button";
import { Field, FieldLabel } from "@appica/ui-react/field";
import { Input } from "@appica/ui-react/input";
import { Tabs, TabsList, TabsTrigger } from "@appica/ui-react/tabs";
import Link from "next/link";
import { FormEvent, useState } from "react";
import { login, signup } from "@/lib/session-api";

export default function LoginPage() {
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);
  const [mode, setMode] = useState<"login" | "signup">("login");

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setLoading(true);
    setError("");
    const form = new FormData(event.currentTarget);
    try {
      if (mode === "signup") {
        await signup(String(form.get("name") ?? ""), String(form.get("email") ?? ""), String(form.get("password") ?? ""));
      } else {
        await login(String(form.get("email") ?? ""), String(form.get("password") ?? ""));
      }
      window.location.assign("/");
    } catch (err) {
      setError(err instanceof Error ? err.message : "Erreur d’authentification.");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="auth-page">
      <Link href="/" className="auth-back">
        <ArrowLeft /> Retour
      </Link>
      <section className="auth-card">
        <Badge className="settings-badge" variant="soft">
          <ShieldCheck size={15} /> Connexion sécurisée
        </Badge>
        <h1>{mode === "login" ? "Retrouvez votre musique." : "Créez votre espace."}</h1>
        <p>Vos comptes, playlists et favoris existants restent compatibles.</p>
        <Tabs className="auth-tabs" value={mode} onValueChange={(value) => setMode(value as "login" | "signup")} variant="pill">
          <TabsList>
            <TabsTrigger value="login">Connexion</TabsTrigger>
            <TabsTrigger value="signup">Inscription</TabsTrigger>
          </TabsList>
        </Tabs>
        <form method="post" onSubmit={submit}>
          {mode === "signup" && (
            <Field><FieldLabel>Nom</FieldLabel><Input name="name" autoComplete="name" minLength={2} required /></Field>
          )}
          <Field><FieldLabel>Adresse e-mail</FieldLabel><Input name="email" type="email" autoComplete="email" required /></Field>
          <Field>
            <FieldLabel>Mot de passe</FieldLabel>
            <Input
              name="password"
              type="password"
              autoComplete={mode === "login" ? "current-password" : "new-password"}
              minLength={8}
              required
            />
          </Field>
          {error && <Alert className="form-error" variant="error"><AlertDescription>{error}</AlertDescription></Alert>}
          <Button type="submit" className="primary-button" disabled={loading}>
            {loading ? <LoaderCircle className="spin" /> : mode === "login" ? "Se connecter" : "Créer le compte"}
          </Button>
        </form>
      </section>
    </div>
  );
}
