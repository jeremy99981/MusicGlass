import { SearchView } from "@/components/search-view";
import { Suspense } from "react";

export default function SearchPage() {
  return (
    <Suspense fallback={<div>Chargement...</div>}>
      <SearchView />
    </Suspense>
  );
}
