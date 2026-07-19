import { z } from "zod";

export const artworkCandidateSchema = z.object({ url: z.string().url(), width: z.number().int().positive().optional(), height: z.number().int().positive().optional(), source: z.string().optional() });
export const artistSchema = z.object({ id: z.string(), name: z.string().min(1) });
export const trackSchema = z.object({
  id: z.string(), providerId: z.string(), provider: z.enum(["youtube", "spotify", "local"]), title: z.string().min(1), artists: z.array(artistSchema).min(1), album: z.string().nullable(), durationMs: z.number().int().nonnegative().nullable(), artworks: z.array(artworkCandidateSchema), playable: z.boolean(), explicit: z.boolean().default(false), live: z.boolean().default(false), provenance: z.record(z.string()).default({}),
});
export const playbackSnapshotSchema = z.object({ version: z.number().int().nonnegative(), track: trackSchema.nullable(), queue: z.array(trackSchema), queueVersion: z.number().int().nonnegative(), isPlaying: z.boolean(), positionMs: z.number().int().nonnegative(), updatedAt: z.string().datetime(), hostId: z.number().int(), participants: z.array(z.object({ clientId: z.string(), userId: z.number().int(), name: z.string(), isHost: z.boolean() })) });
export type Track = z.infer<typeof trackSchema>;
export type PlaybackSnapshot = z.infer<typeof playbackSnapshotSchema>;
