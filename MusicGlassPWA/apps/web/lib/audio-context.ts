type AudioContextCtor = typeof AudioContext;

function getAudioContextCtor(): AudioContextCtor | null {
  if (typeof window === "undefined") return null;
  const withWebkit = window as typeof window & { webkitAudioContext?: AudioContextCtor };
  return withWebkit.AudioContext || withWebkit.webkitAudioContext || null;
}

let sharedContext: AudioContext | null = null;
let sourceNode: MediaElementAudioSourceNode | null = null;
let sourceElement: HTMLMediaElement | null = null;

// iOS/WKWebView only fully honors play()/resume() calls made from a genuine
// user gesture — and it extends that trust to the Media Session remote-command
// handlers (lock screen / Control Center), but only for calls that go through
// the Web Audio API's session lifecycle. A bare HTMLMediaElement.play() can
// resolve and keep advancing currentTime without the underlying
// AVAudioSession route actually being re-engaged once a standalone PWA has
// been backgrounded. Routing the <audio> element through a persistent
// AudioContext lets us call context.resume() explicitly, which is the API
// WebKit expects for that reactivation.
function ensureAudioGraph(audio: HTMLMediaElement): AudioContext | null {
  const Ctor = getAudioContextCtor();
  if (!Ctor) return null;
  if (!sharedContext) {
    sharedContext = new Ctor();
  }
  if (sourceElement !== audio) {
    sourceNode = null;
    sourceElement = audio;
  }
  if (!sourceNode) {
    try {
      sourceNode = sharedContext.createMediaElementSource(audio);
      sourceNode.connect(sharedContext.destination);
    } catch (error) {
      console.error("Failed to route <audio> through AudioContext:", error);
    }
  }
  return sharedContext;
}

export async function resumeAudioContext(audio: HTMLMediaElement) {
  const context = ensureAudioGraph(audio);
  if (!context) return;
  if (context.state === "running") return;
  try {
    await context.resume();
  } catch (error) {
    console.error("AudioContext.resume() failed:", error);
  }
}
