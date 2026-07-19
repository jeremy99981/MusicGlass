export class MusicGlassApi {
  constructor(private readonly baseUrl = "/api/v2") {}
  async request<T>(path: string, init?: RequestInit): Promise<T> {
    const csrf = typeof document === "undefined" ? "" : document.cookie.split("; ").find((item) => item.startsWith("mg_csrf="))?.split("=")[1] ?? "";
    const response = await fetch(`${this.baseUrl}${path}`, { ...init, credentials: "include", headers: { "Content-Type": "application/json", ...(csrf ? { "X-CSRF-Token": decodeURIComponent(csrf) } : {}), ...init?.headers } });
    if (!response.ok) throw new Error(`MusicGlass API ${response.status}`);
    return response.json() as Promise<T>;
  }
}
