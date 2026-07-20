"use client";

import { useQuery } from "@tanstack/react-query";
import { ChevronLeft } from "lucide-react";
import Image from "next/image";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { Suspense } from "react";
import { fetchHome } from "@/lib/api";
import { handleArtworkError } from "@/lib/artwork";
import { parseHome, type HomeItem } from "@/lib/youtube";
import styles from "./collection.module.css";

function itemHref(item: HomeItem) {
  if (item.type === "artist") return `/artist/${encodeURIComponent(item.id)}`;
  if (item.type === "album") return `/album/${encodeURIComponent(item.id)}`;
  if (item.type === "playlist") return `/playlist/${encodeURIComponent(item.id)}`;
  return `/search?q=${encodeURIComponent(item.title)}`;
}

export default function CollectionPage() {
  return <Suspense fallback={<CollectionLoading />}><CollectionContent /></Suspense>;
}

function CollectionContent() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const requestedTitle = searchParams.get("title")?.trim();
  const { data, isLoading } = useQuery({
    queryKey: ["home", "collection"],
    queryFn: async () => parseHome(await fetchHome()),
  });
  const section = data?.sections.find((candidate) => candidate.title === requestedTitle) ?? data?.sections[0];
  const title = requestedTitle || section?.title || "Collection";
  const items = section?.items ?? [];

  return (
    <main className={styles.page}>
      <header className={styles.header}>
        <button type="button" onClick={() => router.back()} aria-label="Retour" className={styles.back}>
          <ChevronLeft size={19} />
        </button>
        <h1>{title}</h1>
      </header>
      <section className={styles.grid} aria-busy={isLoading}>
        {isLoading && Array.from({ length: 10 }, (_, index) => <div className={styles.skeleton} key={index} />)}
        {!isLoading && items.map((item) => (
          <Link href={itemHref(item)} className={styles.card} key={`${item.type}-${item.id}`}>
            <span className={styles.artwork}>
              {item.artwork ? <Image src={item.artwork} alt="" fill sizes="(max-width: 639px) 50vw, 20vw" unoptimized onError={handleArtworkError} /> : null}
            </span>
            <strong>{item.title}</strong>
            <small>{item.subtitle}</small>
          </Link>
        ))}
      </section>
      {!isLoading && !items.length ? <p className={styles.empty}>Cette collection est momentanément indisponible.</p> : null}
    </main>
  );
}

function CollectionLoading() {
  return (
    <main className={styles.page}>
      <header className={styles.header}><span className={styles.back} /><h1>Collection</h1></header>
      <section className={styles.grid} aria-label="Chargement de la collection">
        {Array.from({ length: 10 }, (_, index) => <div className={styles.skeleton} key={index} />)}
      </section>
    </main>
  );
}
