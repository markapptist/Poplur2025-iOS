import Foundation
import UIKit

// MARK: - PoplurFPS game state machine (port of Game.ts)

final class FPSGame {
    enum State { case loading, menu, zoom, playing, paused, dead, win }

    var state: State = .loading
    var level = FPSLevel()
    var player = FPSPlayer()
    var enemies: [FPSEnemy] = []
    var pickups: [FPSPickup] = []
    var props: [FPSPickup] = []

    var score = 0
    var kills = 0
    var gameTime = 0.0

    var selectedMenu = 0
    var menuTick = 0.0
    var zoomT = 0.0

    var loadProgress = 0.0
    var assets: FPSAssets?

    private var menuFirePressed = false
    private var escPressed = false

    private var muzzleFlash = 0.0
    private var torchPhase = 0.0

    func setAssets(_ a: FPSAssets) {
        assets = a
        spawnEntities()
        state = .menu
    }

    private func spawnEntities() {
        enemies = []; pickups = []; props = []
        for s in FPSLevel.entitySpawns {
            if fpsIsEnemy(s.type) { enemies.append(FPSEnemy(s.type, s.x, s.y)) }
            else if fpsIsPickup(s.type) { pickups.append(FPSPickup(s.type, s.x, s.y)) }
            else if fpsIsProp(s.type) { props.append(FPSPickup(s.type, s.x, s.y)) }
        }
    }

    private func resetGame() {
        level = FPSLevel()
        player = FPSPlayer()
        score = 0; kills = 0; gameTime = 0
        spawnEntities()
    }

    /// DEBUG: jump straight into gameplay (used by the FPS_AUTOPLAY verification hook).
    func debugStartPlaying() { state = .playing; resetGame() }

    func update(_ dt: Double, _ input: FPSInput) {
        switch state {
        case .loading:
            break

        case .menu:
            menuTick += dt
            let up = input.w || input.left
            let down = input.s || input.right
            let fire = input.fire || input.interact
            if up { selectedMenu = 0 }
            if down { selectedMenu = 1 }
            if fire && !menuFirePressed { state = .zoom; zoomT = 0 }
            menuFirePressed = fire

        case .zoom:
            zoomT += dt * 0.85
            if zoomT >= 1 { zoomT = 1; state = .playing; resetGame() }

        case .playing:
            gameTime += dt
            muzzleFlash = max(0, muzzleFlash - dt * 12)
            torchPhase += dt * 3

            if input.escape && !escPressed { state = .paused; escPressed = true; break }
            escPressed = input.escape

            player.update(dt, input, level)
            level.update(dt)

            if input.fire && player.canFire() { doShoot() }

            for e in enemies where !e.dead {
                e.update(dt, player, level) { [weak self] in
                    self?.player.takeDamage(e.def.damage)
                }
            }

            for p in pickups where !p.collected {
                if p.tryCollect(player) {
                    score += (p.type >= 203) ? 500 : 50
                }
            }

            if player.dead { state = .dead }

            if let boss = enemies.first(where: { $0.type == FPSK.sprBoss }),
               boss.dead, boss.deathTimer > 1.5 {
                state = .win
            }

        case .paused:
            if input.escape && !escPressed { state = .playing }
            escPressed = input.escape

        case .dead:
            if player.deadTimer > 2.0 && input.interact {
                state = .playing
                player.dead = false
                player.health = 50
                player.deadTimer = 0
                player.flashAlpha = 0
            }

        case .win:
            if input.interact { state = .menu; zoomT = 0 }
        }
    }

    private func doShoot() {
        let w = FPS_WEAPONS[player.weapon]
        player.consumeAmmo()
        muzzleFlash = 1

        for _ in 0..<w.projectiles {
            let spread = (Double.random(in: 0..<1) - 0.5) * w.spread * 2
            let c = cos(spread), s = sin(spread)
            let rdx = player.dirX * c - player.dirY * s
            let rdy = player.dirX * s + player.dirY * c

            var closest = Double.infinity
            var hitEnemy: FPSEnemy?

            for e in enemies where !e.dead {
                let ex = e.x - player.x, ey = e.y - player.y
                let dot = ex * rdx + ey * rdy
                if dot <= 0 { continue }
                let dist = (ex * ex + ey * ey).squareRoot()
                let perp = abs(ex * rdy - ey * rdx)
                if perp > 0.5 { continue }
                var wallHit = false
                let steps = Int(ceil(dist * 3))
                var i = 1
                while i < steps {
                    let t = Double(i) / Double(steps)
                    if level.isSolid(player.x + rdx * dist * t, player.y + rdy * dist * t) { wallHit = true; break }
                    i += 1
                }
                if !wallHit && dist < closest { closest = dist; hitEnemy = e }
            }

            if let e = hitEnemy {
                let variance = Double.random(in: 0..<1) * w.damage * 0.4 - w.damage * 0.2
                e.hit(w.damage + variance)
                if e.dead {
                    kills += 1
                    score += e.def.score
                    player.score = score
                }
            }
        }
    }

    // MARK: Render dispatch

    func render(_ r: FPSRenderer) {
        guard let assets = assets else { return }
        switch state {
        case .loading:
            r.renderLoading(loadProgress)
        case .menu:
            r.renderMenuCabinet(assets, selected: selectedMenu, tick: menuTick, t: 0)
        case .zoom:
            r.renderMenuCabinet(assets, selected: selectedMenu, tick: menuTick, t: zoomT)
        case .playing, .paused, .dead, .win:
            var sprites: [FPSRenderer.RenderSprite] = []
            for e in enemies {
                if e.dead && e.deathTimer > 2.5 { continue }
                let img = assets.enemies[fpsEnemyKey(e.type)]
                let alpha = e.dead ? max(0, 1 - (e.deathTimer - 0.5) / 2) : 1
                sprites.append(.init(x: e.x, y: e.y, img: img,
                                     scale: e.type == FPSK.sprBoss ? 1.5 : 1,
                                     bright: e.hitFlash > 0, alpha: alpha))
            }
            for p in pickups where !p.collected {
                sprites.append(.init(x: p.x, y: p.y, img: assets.pickups[fpsSpriteAssetKey(p.type)], scale: 0.65))
            }
            for p in props {
                let key = fpsSpriteAssetKey(p.type)
                let scale = key == "torch" ? 0.5 + sin(torchPhase) * 0.04 : 0.75
                sprites.append(.init(x: p.x, y: p.y, img: assets.props[key], scale: scale))
            }

            r.renderScene(player, level, assets, sprites)
            if muzzleFlash > 0 {
                r.tintFullScreen(UIColor(red: 1, green: 0.78, blue: 0.31, alpha: 1), alpha: CGFloat(muzzleFlash) * 0.18)
            }
            r.drawWeapon(player, assets.weapons[FPS_WEAPON_KEYS[player.weapon]])
            r.renderHUD(player, assets, level, score: score, kills: kills, gameTime: gameTime)

            if state == .paused { r.renderPause() }
            if state == .dead { r.renderDeath(min(1, player.deadTimer / 1.5)) }
            if state == .win { r.renderWin(score, kills) }
        }
    }
}
