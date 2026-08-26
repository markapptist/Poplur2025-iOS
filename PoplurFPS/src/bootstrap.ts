const params = new URLSearchParams(window.location.search)
const isRawEmbed = params.get('externalController') === '1' || window.parent !== window
const isBundledStandalone = /\/games\/fps(?:\/|$)/.test(window.location.pathname)

// The raw FPS document is only the raycasting engine. Direct entry must hand
// off to the Games host, which owns the visible PoplurStation 3D controller and
// translates that model's sticks/buttons into the engine's message contract.
// The host then embeds this same document with externalController=1, so there
// is one controller and one input owner rather than a second set of overlays.
if (!isRawEmbed && isBundledStandalone) {
  const host = new URL('../../', window.location.href)
  host.search = ''
  host.hash = ''
  host.searchParams.set('view', 'games')
  host.searchParams.set('launch', 'fps')
  window.location.replace(host)
} else {
  void import('./main.ts')
}
