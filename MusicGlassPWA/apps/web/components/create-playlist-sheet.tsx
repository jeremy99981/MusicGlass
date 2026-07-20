"use client";

import { FormEvent, useEffect, useId, useState } from "react";
import { Camera, X } from "lucide-react";
import styles from "./create-playlist-sheet.module.css";

const covers = [
  "linear-gradient(145deg,#9184d9,#353b80)",
  "linear-gradient(145deg,#ce729a,#4d314f)",
  "linear-gradient(145deg,#5b9e9b,#263d53)",
  "linear-gradient(145deg,#d0a15c,#5a3b46)",
  "linear-gradient(145deg,#8795d7,#423a6a)",
];

export function CreatePlaylistSheet({ open, pending, error, onClose, onCreate }: { open: boolean; pending: boolean; error?: string; onClose: () => void; onCreate: (name: string) => void }) {
  const titleId = useId();
  const [name, setName] = useState("Ma nouvelle playlist");
  const [description, setDescription] = useState("");
  const [visibility, setVisibility] = useState<"Privée" | "Publique">("Privée");
  const [cover, setCover] = useState(0);

  useEffect(() => {
    if (!open) return;
    const onKeyDown = (event: KeyboardEvent) => { if (event.key === "Escape") onClose(); };
    document.addEventListener("keydown", onKeyDown);
    return () => document.removeEventListener("keydown", onKeyDown);
  }, [open, onClose]);

  if (!open) return null;
  const submit = (event: FormEvent) => { event.preventDefault(); if (name.trim()) onCreate(name.trim()); };

  return <div className={styles.layer} role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget) onClose(); }}>
    <form className={styles.sheet} role="dialog" aria-modal="true" aria-labelledby={titleId} onSubmit={submit}>
      <div className={styles.handle} />
      <header><h2 id={titleId}>Nouvelle playlist</h2><button type="button" onClick={onClose} aria-label="Fermer"><X size={22} /></button></header>
      <div className={styles.identity}>
        <div className={styles.heroCover} style={{ background: covers[cover] }}><Camera size={18} /></div>
        <label><span>Nom</span><input autoFocus value={name} onChange={(event) => setName(event.target.value)} placeholder="Ma nouvelle playlist" /></label>
      </div>
      <fieldset><legend>Ou choisir une pochette</legend><div className={styles.covers}>{covers.map((gradient, index) => <button key={gradient} type="button" aria-label={`Pochette ${index + 1}`} aria-pressed={cover === index} onClick={() => setCover(index)} style={{ background: gradient }} />)}</div></fieldset>
      <label><span>Description (optionnel, aperçu local)</span><textarea value={description} onChange={(event) => setDescription(event.target.value)} placeholder="Décrivez votre playlist..." /></label>
      <fieldset><legend>Visibilité (aperçu local)</legend><div className={styles.visibility}>{(["Privée", "Publique"] as const).map((option) => <button key={option} type="button" className={visibility === option ? styles.selected : ""} aria-pressed={visibility === option} onClick={() => setVisibility(option)}>{option}</button>)}</div></fieldset>
      <div><span className={styles.previewLabel}>Aperçu</span><div className={styles.preview}><span style={{ background: covers[cover] }} /><div><strong>{name.trim() || "Ma nouvelle playlist"}</strong><small>0 titre · {visibility}</small></div></div></div>
      {error && <p className={styles.error} role="alert">{error}</p>}
      <button className={styles.primary} type="submit" disabled={pending || !name.trim()}>{pending ? "Création..." : "Créer la playlist"}</button>
      <button className={styles.cancel} type="button" onClick={onClose}>Annuler</button>
    </form>
  </div>;
}
