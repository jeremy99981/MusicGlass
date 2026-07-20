// Aperçu léger transmis d'une carte/raccourci vers la page de détail, pour
// afficher immédiatement le header (pochette, titre, sous-titre) pendant que la
// playlist complète se charge — sans attendre l'appel réseau.
export type DetailPreview = {
  title: string;
  subtitle?: string;
  artwork?: string;
};

const previews = new Map<string, DetailPreview>();

export function rememberDetailPreview(id: string, preview: DetailPreview) {
  if (!id) return;
  previews.set(id, preview);
}

export function takeDetailPreview(id: string): DetailPreview | undefined {
  return previews.get(id);
}
