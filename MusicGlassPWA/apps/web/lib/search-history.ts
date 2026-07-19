const LOCAL_SEARCH_HISTORY_KEY = "musicglass-search-history-v1";
const LOCAL_SEARCH_HISTORY_LIMIT = 12;

export function normalizeSearchHistoryQuery(value: string) {
  return value.replace(/\s+/g, " ").trim().slice(0, 160);
}

export function readLocalSearchHistory() {
  if (typeof window === "undefined") return [];
  try {
    const parsed = JSON.parse(window.localStorage.getItem(LOCAL_SEARCH_HISTORY_KEY) ?? "[]");
    if (!Array.isArray(parsed)) return [];
    return parsed
      .filter((value): value is string => typeof value === "string")
      .map(normalizeSearchHistoryQuery)
      .filter(Boolean)
      .slice(0, LOCAL_SEARCH_HISTORY_LIMIT);
  } catch {
    return [];
  }
}

export function recordLocalSearch(value: string) {
  const query = normalizeSearchHistoryQuery(value);
  if (!query || typeof window === "undefined") return readLocalSearchHistory();
  const history = readLocalSearchHistory().filter((item) => item.toLocaleLowerCase("fr") !== query.toLocaleLowerCase("fr"));
  const next = [query, ...history].slice(0, LOCAL_SEARCH_HISTORY_LIMIT);
  window.localStorage.setItem(LOCAL_SEARCH_HISTORY_KEY, JSON.stringify(next));
  return next;
}

export function clearLocalSearchHistory() {
  if (typeof window !== "undefined") window.localStorage.removeItem(LOCAL_SEARCH_HISTORY_KEY);
}
