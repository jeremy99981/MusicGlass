"use client";

import {
  Dialog,
  DialogBody,
  DialogClose,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@appica/ui-react/dialog";
import { Button } from "@appica/ui-react/button";
import { Heart } from "lucide-react";
import Link from "next/link";
import React from "react";

type AuthRequiredDialogProps = {
  open: boolean;
  onOpenChange: (open: boolean) => void;
};

export function AuthRequiredDialog({ open, onOpenChange }: AuthRequiredDialogProps) {
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="w-[min(calc(100vw-32px),28rem)]" closeLabel="Fermer">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <Heart size={20} aria-hidden="true" /> Garder ce titre
          </DialogTitle>
          <DialogDescription>
            Connectez-vous pour retrouver vos titres aimés sur tous vos appareils.
          </DialogDescription>
        </DialogHeader>
        <DialogBody>
          Votre écoute continue sans compte. Seule la sauvegarde dans votre bibliothèque nécessite une connexion.
        </DialogBody>
        <DialogFooter>
          <DialogClose render={<Button variant="soft" />}>Plus tard</DialogClose>
          <Button render={<Link href="/login" />}>Se connecter</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
