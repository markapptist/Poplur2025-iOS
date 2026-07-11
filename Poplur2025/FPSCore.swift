import Foundation
import CoreGraphics

// MARK: - PoplurFPS native (SpriteKit) — core simulation
//
// Faithful Swift port of the TypeScript raycaster game that previously ran in a
// WKWebView (PoplurFPS/src). Pure simulation here — no rendering. See
// FPSRenderer (software pixel-buffer raycaster) and FPSGameScene (SpriteKit host).

enum FPSK {
    static let screenW = 640
    static let screenH = 360
    static let mapW = 30
    static let mapH = 30
    static let texSize = 64

    static let moveSpeed: Double = 3.5
    static let rotSpeed: Double = 2.0
    static let mouseSens: Double = 0.0025
    static let planeLen: Double = 0.66      // half-FOV ≈ 33° each side → ~66° total
    static let playerR: Double = 0.22
    static let interactD: Double = 1.4

    // Wall tile types
    static let wallDoor = 7      // normal door
    static let wallLocked = 8    // locked (gold key)
    static let wallPink = 9      // locked (pink key)

    // Sprite / entity types
    static let sprSoldier = 100
    static let sprHeavy = 101
    static let sprDrone = 102
    static let sprTurret = 103
    static let sprBoss = 104
    static let sprHealth = 200
    static let sprArmor = 201
    static let sprAmmo = 202
    static let sprKeyG = 203
    static let sprKeyP = 204
    static let sprBarrel = 300
    static let sprCrate = 301
    static let sprSign = 302
    static let sprTorch = 303
    static let sprBanner = 304
}

struct FPSWeapon {
    let name: String
    let damage: Double
    let rate: Double
    let spread: Double
    let ammoType: Int
    let ammoPerShot: Int
    let projectiles: Int
}

/// Horizontal aim-pose frames per weapon sprite (1 = single static image).
let FPS_WEAPON_AIM_FRAMES: [Int] = [9, 1, 1, 1, 1]

let FPS_WEAPONS: [FPSWeapon] = [
    FPSWeapon(name: "SENTINEL", damage: 12, rate: 0.40, spread: 0.02, ammoType: 0, ammoPerShot: 1, projectiles: 1),
    FPSWeapon(name: "SHOTGUN", damage: 8,  rate: 0.85, spread: 0.12, ammoType: 1, ammoPerShot: 1, projectiles: 7),
    FPSWeapon(name: "PLASMA",  damage: 18, rate: 0.22, spread: 0.01, ammoType: 2, ammoPerShot: 1, projectiles: 1),
    FPSWeapon(name: "ROCKET",  damage: 60, rate: 1.10, spread: 0.00, ammoType: 3, ammoPerShot: 1, projectiles: 1),
    FPSWeapon(name: "RAILGUN", damage: 80, rate: 1.50, spread: 0.00, ammoType: 4, ammoPerShot: 1, projectiles: 1),
]

let FPS_WEAPON_KEYS = ["pistol", "shotgun", "plasma", "rocket", "railgun"]
let FPS_AMMO_TYPES = ["BULLETS", "SHELLS", "ENERGY", "ROCKETS", "CELLS"]

// MARK: - Input snapshot (filled by the SpriteKit scene each frame)

struct FPSInput {
    var w = false, s = false, a = false, d = false
    var left = false, right = false
    var fire = false, interact = false
    var weapon1 = false, weapon2 = false, weapon3 = false, weapon4 = false, weapon5 = false
    var lookDX: Double = 0     // accumulated look delta (touch drag), consumed each frame
    var escape = false
}

// MARK: - Level / map

final class FPSDoor {
    var open: Double = 0        // 0 closed → 1 fully open
    var opening = false
    var locked = false
    var keyType: String?       // "gold" | "pink" | nil
}

struct FPSEntitySpawn { let type: Int; let x: Double; let y: Double }

final class FPSLevel {
    // 0=floor 1-6=wall 7=door 8=locked(gold) 9=locked(pink)
    static let rawMap: [[Int]] = [
        [1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1],
        [1,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,1],
        [1,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,1],
        [1,0,0,0,0,0,0,0,7,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,1],
        [1,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,1],
        [1,1,1,7,1,1,1,1,1,1,1,1,2,2,2,2,1,0,0,0,0,0,0,0,0,0,0,0,0,1],
        [1,0,0,0,0,0,0,0,0,0,0,0,2,0,0,0,1,0,0,0,3,3,3,3,3,3,0,0,0,1],
        [1,0,0,0,0,0,0,0,0,0,0,0,2,0,0,0,7,0,0,0,3,0,0,0,0,3,0,0,0,1],
        [1,0,0,0,0,0,0,0,0,0,0,0,2,0,0,0,1,0,0,0,3,0,0,0,0,3,0,0,0,1],
        [1,0,0,0,0,0,0,0,0,0,0,0,2,2,2,7,1,0,0,0,3,3,7,3,3,3,0,0,0,1],
        [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
        [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
        [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
        [1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,8,1,1,1,1,1,1,1,1,1,1,1,1,1,1],
        [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
        [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
        [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
        [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
        [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
        [1,0,0,0,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,0,0,0,1],
        [1,0,0,0,4,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,4,0,0,0,1],
        [1,0,0,0,4,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,4,0,0,0,1],
        [1,0,0,0,4,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,4,0,0,0,1],
        [1,0,0,0,4,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,4,0,0,0,1],
        [1,0,0,0,4,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,4,0,0,0,1],
        [1,0,0,0,4,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,4,0,0,0,1],
        [1,0,0,0,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,0,0,0,1],
        [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
        [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
        [1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1],
    ]

    static let entitySpawns: [FPSEntitySpawn] = [
        // enemies
        FPSEntitySpawn(type: FPSK.sprSoldier, x: 11.5, y: 3.5),
        FPSEntitySpawn(type: FPSK.sprSoldier, x: 13.5, y: 7.5),
        FPSEntitySpawn(type: FPSK.sprHeavy,   x: 23.5, y: 7.5),
        FPSEntitySpawn(type: FPSK.sprDrone,   x: 9.5,  y: 10.5),
        FPSEntitySpawn(type: FPSK.sprSoldier, x: 20.5, y: 11.5),
        FPSEntitySpawn(type: FPSK.sprHeavy,   x: 16.5, y: 16.5),
        FPSEntitySpawn(type: FPSK.sprSoldier, x: 8.5,  y: 17.5),
        FPSEntitySpawn(type: FPSK.sprBoss,    x: 15.5, y: 22.5),
        // pickups
        FPSEntitySpawn(type: FPSK.sprHealth, x: 4.5,  y: 1.5),
        FPSEntitySpawn(type: FPSK.sprAmmo,   x: 3.5,  y: 5.5),
        FPSEntitySpawn(type: FPSK.sprHealth, x: 14.5, y: 7.5),
        FPSEntitySpawn(type: FPSK.sprArmor,  x: 23.5, y: 8.5),
        FPSEntitySpawn(type: FPSK.sprAmmo,   x: 10.5, y: 11.5),
        FPSEntitySpawn(type: FPSK.sprHealth, x: 15.5, y: 16.5),
        FPSEntitySpawn(type: FPSK.sprAmmo,   x: 8.5,  y: 15.5),
        FPSEntitySpawn(type: FPSK.sprKeyG,   x: 24.5, y: 6.5),
        // props
        FPSEntitySpawn(type: FPSK.sprBarrel, x: 1.5,  y: 1.5),
        FPSEntitySpawn(type: FPSK.sprBarrel, x: 7.5,  y: 1.5),
        FPSEntitySpawn(type: FPSK.sprTorch,  x: 8.5,  y: 6.5),
        FPSEntitySpawn(type: FPSK.sprCrate,  x: 10.5, y: 7.5),
        FPSEntitySpawn(type: FPSK.sprSign,   x: 2.5,  y: 10.5),
        FPSEntitySpawn(type: FPSK.sprTorch,  x: 16.5, y: 13.5),
        FPSEntitySpawn(type: FPSK.sprBanner, x: 15.5, y: 20.5),
        FPSEntitySpawn(type: FPSK.sprBarrel, x: 5.5,  y: 20.5),
        FPSEntitySpawn(type: FPSK.sprBarrel, x: 24.5, y: 20.5),
        FPSEntitySpawn(type: FPSK.sprCrate,  x: 7.5,  y: 22.5),
    ]

    private var map: [[Int]]
    private(set) var doors: [Int: FPSDoor] = [:]   // key = y * mapW + x

    init() {
        map = FPSLevel.rawMap
        for y in 0..<map.count {
            for x in 0..<map[y].count {
                let t = map[y][x]
                if t == FPSK.wallDoor || t == FPSK.wallLocked || t == FPSK.wallPink {
                    let d = FPSDoor()
                    d.locked = t != FPSK.wallDoor
                    d.keyType = t == FPSK.wallLocked ? "gold" : (t == FPSK.wallPink ? "pink" : nil)
                    doors[y * FPSK.mapW + x] = d
                }
            }
        }
    }

    func getCell(_ x: Double, _ y: Double) -> Int {
        let ix = Int(floor(x)), iy = Int(floor(y))
        if iy < 0 || iy >= map.count || ix < 0 || ix >= map[iy].count { return 1 }
        return map[iy][ix]
    }

    func getDoor(_ x: Double, _ y: Double) -> FPSDoor? {
        doors[Int(floor(y)) * FPSK.mapW + Int(floor(x))]
    }

    func isSolid(_ x: Double, _ y: Double) -> Bool {
        let t = getCell(x, y)
        if t == 0 { return false }
        if t == FPSK.wallDoor || t == FPSK.wallLocked || t == FPSK.wallPink {
            guard let d = getDoor(x, y) else { return true }
            return d.open < 0.85
        }
        return true
    }

    @discardableResult
    func tryOpenDoor(_ x: Double, _ y: Double, hasGold: Bool, hasPink: Bool) -> Bool {
        guard let d = getDoor(x, y) else { return false }
        if d.locked {
            if d.keyType == "gold" && !hasGold { return false }
            if d.keyType == "pink" && !hasPink { return false }
        }
        d.opening = true
        return true
    }

    func update(_ dt: Double) {
        for d in doors.values where d.opening && d.open < 1 {
            d.open = min(1, d.open + dt * 1.4)
        }
    }
}

// MARK: - Player

final class FPSPlayer {
    var x = 2.5, y = 2.5
    var dirX = 1.0, dirY = 0.0
    var planeX = 0.0, planeY = FPSK.planeLen

    var health = 100.0, maxHealth = 100.0
    var armor = 0.0, maxArmor = 100.0
    var ammo = [100, 20, 50, 5, 10]     // bullets, shells, energy, rockets, cells
    var weapon = 0
    var hasKey: [String: Bool] = [:]

    var score = 0
    var kills = 0

    var bobPhase = 0.0
    var bobActive = false
    var flashAlpha = 0.0
    var weaponKick = 0.0
    /// -1 = aiming hard left, 0 = straight ahead, +1 = hard right. Eases toward the
    /// current turn so the weapon viewmodel swings instead of snapping.
    var aimLean = 0.0

    var fireCooldown = 0.0
    var interactCooldown = 0.0

    var dead = false
    var deadTimer = 0.0

    private func tryMove(_ level: FPSLevel, _ nx: Double, _ ny: Double) {
        if !level.isSolid(nx, y) { x = nx }
        if !level.isSolid(x, ny) { y = ny }
    }

    func update(_ dt: Double, _ input: FPSInput, _ level: FPSLevel) {
        if dead { deadTimer += dt; return }

        if input.left || input.right {
            rotate((input.right ? 1 : -1) * FPSK.rotSpeed * dt)
        }
        if input.lookDX != 0 { rotate(input.lookDX * FPSK.mouseSens) }

        // Aim lean: turning swings the weapon; releasing recentres it.
        var target = 0.0
        if input.right { target += 1 }
        if input.left { target -= 1 }
        target += max(-1, min(1, input.lookDX * FPSK.mouseSens * 26))
        target = max(-1, min(1, target))
        let k = min(1, dt * 7)
        aimLean += (target - aimLean) * k

        let speed = FPSK.moveSpeed * dt
        let strafe = speed * 0.8
        var moving = false
        if input.w { tryMove(level, x + dirX * speed, y + dirY * speed); moving = true }
        if input.s { tryMove(level, x - dirX * speed, y - dirY * speed); moving = true }
        if input.a { tryMove(level, x + dirY * strafe, y - dirX * strafe); moving = true }
        if input.d { tryMove(level, x - dirY * strafe, y + dirX * strafe); moving = true }

        bobActive = moving
        if moving { bobPhase += dt * 6 } else { bobPhase *= 0.85 }

        fireCooldown = max(0, fireCooldown - dt)
        interactCooldown = max(0, interactCooldown - dt)
        flashAlpha = max(0, flashAlpha - dt * 3)
        weaponKick = max(0, weaponKick - dt * 8)

        if input.weapon1 { weapon = 0 }
        if input.weapon2 { weapon = 1 }
        if input.weapon3 { weapon = 2 }
        if input.weapon4 { weapon = 3 }
        if input.weapon5 { weapon = 4 }

        if input.interact && interactCooldown <= 0 {
            interactCooldown = 0.4
            var step = 0.5
            while step <= FPSK.interactD {
                let cx = x + dirX * step, cy = y + dirY * step
                let cell = level.getCell(cx, cy)
                if cell == 7 || cell == 8 || cell == 9 {
                    level.tryOpenDoor(cx, cy, hasGold: hasKey["gold"] ?? false, hasPink: hasKey["pink"] ?? false)
                    break
                }
                step += 0.5
            }
        }
    }

    func rotate(_ angle: Double) {
        let c = cos(angle), s = sin(angle)
        let ox = dirX, oy = dirY
        dirX = ox * c - oy * s
        dirY = ox * s + oy * c
        let px = planeX, py = planeY
        planeX = px * c - py * s
        planeY = px * s + py * c
    }

    func takeDamage(_ dmg: Double) {
        if dead { return }
        let absorb = min(armor, floor(dmg * 0.33))
        armor -= absorb
        health -= (dmg - absorb)
        flashAlpha = min(1, flashAlpha + 0.4)
        if health <= 0 { health = 0; dead = true }
    }

    func canFire() -> Bool {
        let w = FPS_WEAPONS[weapon]
        return fireCooldown <= 0 && ammo[w.ammoType] >= w.ammoPerShot
    }

    func consumeAmmo() {
        let w = FPS_WEAPONS[weapon]
        ammo[w.ammoType] = max(0, ammo[w.ammoType] - w.ammoPerShot)
        fireCooldown = w.rate
        weaponKick = 1
    }
}

// MARK: - Enemy

struct FPSEnemyDef {
    let hp: Double, speed: Double, damage: Double, fireRate: Double
    let score: Int, sightRange: Double
}

let FPS_ENEMY_DEFS: [Int: FPSEnemyDef] = [
    FPSK.sprSoldier: FPSEnemyDef(hp: 40,  speed: 2.0, damage: 8,  fireRate: 1.5, score: 100,  sightRange: 12),
    FPSK.sprHeavy:   FPSEnemyDef(hp: 100, speed: 1.0, damage: 15, fireRate: 2.0, score: 300,  sightRange: 10),
    FPSK.sprDrone:   FPSEnemyDef(hp: 25,  speed: 3.0, damage: 5,  fireRate: 0.8, score: 150,  sightRange: 14),
    FPSK.sprTurret:  FPSEnemyDef(hp: 60,  speed: 0.0, damage: 12, fireRate: 1.2, score: 200,  sightRange: 12),
    FPSK.sprBoss:    FPSEnemyDef(hp: 600, speed: 1.2, damage: 25, fireRate: 0.7, score: 2000, sightRange: 20),
]

final class FPSEnemy {
    var x: Double, y: Double
    let type: Int
    var angle = 0.0
    var hp: Double
    let def: FPSEnemyDef

    enum State { case idle, patrol, chase, attack, dead }
    var state: State = .idle
    var fireCooldown = 0.0
    var idleTimer = 0.0
    var patrolAngle = 0.0
    var patrolTimer = 0.0
    var animFrame = 0
    var animTimer = 0.0
    var deathTimer = 0.0
    var hitFlash = 0.0
    var dead = false

    init(_ type: Int, _ x: Double, _ y: Double) {
        self.type = type
        self.x = x; self.y = y
        self.def = FPS_ENEMY_DEFS[type] ?? FPS_ENEMY_DEFS[FPSK.sprSoldier]!
        self.hp = def.hp
        self.patrolAngle = Double.random(in: 0..<(2 * .pi))
    }

    private func hasLineOfSight(_ player: FPSPlayer, _ level: FPSLevel) -> Bool {
        let dx = player.x - x, dy = player.y - y
        let dist = (dx * dx + dy * dy).squareRoot()
        if dist > def.sightRange { return false }
        let steps = Int(ceil(dist * 4))
        var i = 1
        while i < steps {
            let t = Double(i) / Double(steps)
            if level.isSolid(x + dx * t, y + dy * t) { return false }
            i += 1
        }
        return true
    }

    func update(_ dt: Double, _ player: FPSPlayer, _ level: FPSLevel, onDamage: () -> Void) {
        if dead { deathTimer += dt; return }

        fireCooldown = max(0, fireCooldown - dt)
        hitFlash = max(0, hitFlash - dt * 4)
        animTimer += dt
        if animTimer > 0.18 { animFrame = (animFrame + 1) % 4; animTimer = 0 }

        let canSee = hasLineOfSight(player, level)

        switch state {
        case .idle:
            idleTimer += dt
            if canSee { state = .chase; break }
            if idleTimer > 2.0 { state = .patrol; patrolTimer = 3 + Double.random(in: 0..<3) }
        case .patrol:
            if canSee { state = .chase; break }
            patrolTimer -= dt
            if patrolTimer <= 0 { state = .idle; idleTimer = 0; break }
            if def.speed > 0 {
                let nx = x + cos(patrolAngle) * def.speed * dt
                let ny = y + sin(patrolAngle) * def.speed * dt
                if !level.isSolid(nx, ny) { x = nx; y = ny }
                else { patrolAngle += Double.pi * (0.5 + Double.random(in: 0..<0.5)) }
            }
        case .chase:
            if !canSee { state = .patrol; patrolTimer = 4; break }
            let dx = player.x - x, dy = player.y - y
            let dist = (dx * dx + dy * dy).squareRoot()
            angle = atan2(dy, dx)
            let attackDist = type == FPSK.sprBoss ? 4.0 : 2.5
            if dist < attackDist { state = .attack }
            else if def.speed > 0 {
                let sp = def.speed * dt
                let nx = x + (dx / dist) * sp, ny = y + (dy / dist) * sp
                if !level.isSolid(nx, y) { x = nx }
                if !level.isSolid(x, ny) { y = ny }
            }
        case .attack:
            if !canSee { state = .chase; break }
            let dx = player.x - x, dy = player.y - y
            let dist = (dx * dx + dy * dy).squareRoot()
            angle = atan2(dy, dx)
            let attackDist = type == FPSK.sprBoss ? 5.0 : 3.0
            if dist > attackDist + 1 { state = .chase; break }
            if fireCooldown <= 0 { fireCooldown = def.fireRate; onDamage() }
        case .dead:
            break
        }
    }

    func hit(_ dmg: Double) {
        if dead { return }
        hp -= dmg
        hitFlash = 1
        if state == .idle || state == .patrol { state = .chase }
        if hp <= 0 { hp = 0; dead = true; state = .dead }
    }
}

// MARK: - Pickup / prop

final class FPSPickup {
    var x: Double, y: Double
    let type: Int
    var collected = false
    var bobPhase = Double.random(in: 0..<(2 * .pi))

    init(_ type: Int, _ x: Double, _ y: Double) { self.type = type; self.x = x; self.y = y }

    func tryCollect(_ p: FPSPlayer) -> Bool {
        if collected { return false }
        let dx = x - p.x, dy = y - p.y
        if dx * dx + dy * dy > 0.6 * 0.6 { return false }
        switch type {
        case FPSK.sprHealth:
            if p.health >= p.maxHealth { return false }
            p.health = min(p.maxHealth, p.health + 25)
        case FPSK.sprArmor:
            if p.armor >= p.maxArmor { return false }
            p.armor = min(p.maxArmor, p.armor + 50)
        case FPSK.sprAmmo:
            p.ammo[0] = min(300, p.ammo[0] + 50)
            p.ammo[1] = min(50,  p.ammo[1] + 10)
            p.ammo[2] = min(150, p.ammo[2] + 30)
            p.ammo[3] = min(20,  p.ammo[3] + 3)
            p.ammo[4] = min(30,  p.ammo[4] + 5)
        case FPSK.sprKeyG: p.hasKey["gold"] = true
        case FPSK.sprKeyP: p.hasKey["pink"] = true
        default: return false
        }
        collected = true
        return true
    }
}

func fpsIsEnemy(_ t: Int) -> Bool { t >= 100 && t < 200 }
func fpsIsPickup(_ t: Int) -> Bool { t >= 200 && t < 300 }
func fpsIsProp(_ t: Int) -> Bool { t >= 300 }

func fpsSpriteAssetKey(_ t: Int) -> String {
    switch t {
    case FPSK.sprHealth: return "health"
    case FPSK.sprArmor:  return "armor"
    case FPSK.sprAmmo:   return "ammo"
    case FPSK.sprKeyG:   return "key_g"
    case FPSK.sprKeyP:   return "key_p"
    case FPSK.sprBarrel: return "barrel"
    case FPSK.sprCrate:  return "crate"
    case FPSK.sprSign:   return "sign"
    case FPSK.sprTorch:  return "torch"
    case FPSK.sprBanner: return "banner"
    default: return "barrel"
    }
}

func fpsEnemyKey(_ t: Int) -> String {
    switch t {
    case 100: return "soldier"
    case 101: return "heavy"
    case 102: return "drone"
    case 103: return "turret"
    case 104: return "boss"
    default:  return "soldier"
    }
}
