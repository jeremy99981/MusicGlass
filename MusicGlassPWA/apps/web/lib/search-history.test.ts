import { beforeEach, describe, expect, it } from "vitest";
import { clearLocalSearchHistory, normalizeSearchHistoryQuery, readLocalSearchHistory, recordLocalSearch } from "./search-history";

describe("local search history", () => {
  beforeEach(clearLocalSearchHistory);

  it("normalizes, deduplicates and promotes recent searches", () => {
    expect(normalizeSearchHistoryQuery("  Ziak   FENG SHUI ")).toBe("Ziak FENG SHUI");
    recordLocalSearch("Ziak");
    recordLocalSearch("Damso");
    recordLocalSearch("ziak");
    expect(readLocalSearchHistory()).toEqual(["ziak", "Damso"]);
  });
});
