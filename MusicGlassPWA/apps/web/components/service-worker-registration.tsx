"use client";

import { useEffect } from "react";

export function ServiceWorkerRegistration() {
  useEffect(() => {
    if (!("serviceWorker" in navigator) || process.env.NODE_ENV !== "production") return;
    let isRefreshing = false;

    const applyUpdatedWorker = () => {
      if (isRefreshing) return;
      isRefreshing = true;
      window.location.reload();
    };

    const register = () => {
      navigator.serviceWorker.register("/sw.js", { scope: "/", updateViaCache: "none" })
        .then((registration) => registration.update())
        .catch((error) => {
          console.warn("Service worker registration failed", error);
        });
    };

    navigator.serviceWorker.addEventListener("controllerchange", applyUpdatedWorker);

    if (document.readyState === "complete") {
      register();
      return () => navigator.serviceWorker.removeEventListener("controllerchange", applyUpdatedWorker);
    }
    window.addEventListener("load", register, { once: true });
    return () => {
      window.removeEventListener("load", register);
      navigator.serviceWorker.removeEventListener("controllerchange", applyUpdatedWorker);
    };
  }, []);
  return null;
}
