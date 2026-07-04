// The nexus-asset:// URL for a Nexus-relative image path, served by the main process on desktop.
// One definition so a non-Electron host (mobile WebView) can swap the scheme in a single place.
export const assetUrl = (rel: string): string => `nexus-asset://nexus/${encodeURI(rel)}`
