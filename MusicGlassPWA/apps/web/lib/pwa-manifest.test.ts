import { describe, expect, it } from "vitest";
import manifest from "../app/manifest";

describe("web app manifest", () => {
  it("keeps identity, launch URL and scope stable", () => {
    const value = manifest();
    expect(value).toMatchObject({ id: "/", start_url: "/", scope: "/", display: "standalone" });
  });

  it("provides installable any-purpose and maskable icons", () => {
    const value = manifest();
    expect(value.icons).toEqual(expect.arrayContaining([
      expect.objectContaining({ sizes: "192x192", purpose: "any" }),
      expect.objectContaining({ sizes: "512x512", purpose: "any" }),
      expect.objectContaining({ sizes: "512x512", purpose: "maskable" }),
    ]));
  });

  it("keeps every shortcut inside the application scope", () => {
    const value = manifest();
    expect(value.shortcuts).not.toHaveLength(0);
    expect(value.shortcuts?.every((shortcut) => shortcut.url.startsWith("/"))).toBe(true);
  });
});
