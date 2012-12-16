import csfml, csfml_colors
import strutils

type

  TLegs = enum
    CVLegsStill, CVLegs1, CVLegs2,
    VillLegsStill, VillLegs1, VillLegs2
  
  TOrientation = enum
    Left, Right

  TState = object
    window: PRenderWindow
    view: PView
    defFont: PFont
    fpsText: PText
    player: TVillain
    level: TLevel
    texture: PTexture
    legs: array[TLegs, PSprite]
    bullets: seq[TBullet]
    showBounds: bool
    
  PState = ref TState

  TVillain = object
    sprite: PSprite
    jumping: bool
    yvelocity: float
    beforeJumpY: float
    currentLeg: TLegs
    legTicks: int
    orientation: TOrientation
    health: int

  TBullet = object
    sprite: PSprite
    traj: TVector2f

  TTileType = enum
    TileRailing = 0, TileLamp, TileLampTop, 
    TileSkyClouds, TileSkyClear, TileConcrete
  
  TTile = object
    tile: TTileType
    behind: bool # whether this tile is behind the player
  
  TTiles = seq[TTile] # Allows multiple tiles in a single spot to be drawn.
                      # Yeah, I know, beginning of clusterfuck right?

  TLevel = object
    tiles: seq[seq[TTiles]] # 2d array of tiles.

const
  ScreenW = 800
  ScreenH = 600

proc parseTiles(s: string): TTiles =
  result = @[]
  for tile in s.split(':'):
    var newTile: TTile
    if tile[0] == '!': # Behind
      newTile.behind = true
      newTile.tile = parseInt(tile[1 .. -1]).TTileType
    elif tile[0] == '?': # Front
      newTile.behind = false
      newTile.tile = parseInt(tile[1 .. -1]).TTileType
    else:
      newTile.tile = parseInt(tile).TTileType
      case newTile.tile
      of TileRailing, TileLamp, TileLampTop:
        newTile.behind = false
      of TileSkyClouds, TileSkyClear, TileConcrete:
        newTile.behind = true
    result.add(newTile)
 
proc loadLevel(file: string = "levels/level1.csv"): TLevel =
  result.tiles = @[]
  let csvContents = readFile(file)
  for y in csvContents.splitLines():
    var yList: seq[TTiles] = @[]
    for x in y.split(','):
      let spec = x.strip()
      yList.add(parseTiles(spec))
    result.tiles.add(yList)

proc newSprite2(texture: PTexture, coord: var TIntRect): PSprite =
  result = newSprite(texture, coord)
  result.setScale(vec2f(2,2))

proc loadLegs(state: PState) =
  var coord = intRect(0, 64*4, 64, 64)
  state.legs[CVLegsStill] = newSprite2(state.texture, coord)
  coord.left = 64
  state.legs[CVLegs1] = newSprite2(state.texture, coord)
  coord.left = 128
  state.legs[CVLegs2] = newSprite2(state.texture, coord)

  # Villain legs.
  coord.top = 64
  coord.left = 0
  state.legs[VillLegsStill] = newSprite2(state.texture, coord)
  coord.left = 64
  state.legs[VillLegs1] = newSprite2(state.texture, coord)
  coord.left = 128
  state.legs[VillLegs2] = newSprite2(state.texture, coord)

proc addBullet(state: PState, u: TVector2f, traj: TVector2f) =
  var bullet: TBullet
  var coord = intRect(64*3, 64, 64, 64)
  if traj.x < 0:
    coord.left = 64*4
  
  bullet.sprite = newSprite2(state.texture, coord)
  bullet.sprite.setPosition(u)
  bullet.traj = traj
  state.bullets.add(bullet)

proc getNextLeg(leg: TLegs): TLegs =
  ## Returns the next leg in sequence
  case leg
  of CVLegs2:
    return CVLegsStill
  of VillLegs2:
    return VillLegsStill
  else:
    return TLegs(ord(leg)+1)

proc initVillain(sprite: PSprite): TVillain =
  result.sprite = sprite
  result.sprite.setPosition(vec2f(0.0, 388.0))
  result.sprite.setScale(vec2f(2,2))
  result.currentLeg = VillLegsStill
  result.orientation = right
  result.health = 100

proc update(player: var TVillain) =
  # This is called every 1 tick.
  if player.jumping:
    assert player.beforeJumpY != -1
    let pos = player.sprite.getPosition()
    if pos.y + player.yvelocity < player.beforeJumpY:
      player.sprite.setPosition(vec2f(pos.x, pos.y + player.yvelocity))
      player.yvelocity = player.yvelocity + 11
    else:
      player.sprite.setPosition(vec2f(pos.x, player.beforeJumpY))
      player.beforeJumpY = -1
      player.yvelocity = 0
      player.jumping = false


proc floatRect2(x, y, w, h: float): TFloatRect {.inline.} =
  return floatRect(x, y, w*2, h*2)

proc getBoundBox(player: TVillain): seq[TFloatRect] =
  result = @[]
  let pos = player.sprite.getPosition()
  # Body
  if player.orientation == right:
    # 14x33
    result.add(floatRect2(pos.x+22, pos.y+14, 14, 33+22)) # +22 is legs
  elif player.orientation == left:
    result.add(floatRect2(pos.x+49-28, pos.y+14, 14, 33+22))
  # Arm
  if player.orientation == right:
    # 20x5
    result.add(floatRect2(pos.x+48, pos.y+38, 20, 5))
  elif player.orientation == left:
    # 20x5
    result.add(floatRect2(pos.x+10-28, pos.y+38, 20, 5))

proc getBoundBox(bullet: TBullet): TFloatRect =
  let bpos = bullet.sprite.getPosition()
  return floatRect(bpos.x, bpos.y, 16.0, 6.0)

proc bulletHits(bullet: TBullet, player: TVillain): bool =
  var bCorrectRect = getBoundBox(bullet)
  var pCorrectRects = getBoundBox(player)
  var intersection: TFloatRect
  for i in 0..pCorrectRects.len-1:
    result = result or intersects(addr bCorrectRect, addr pCorrectRects[i], addr intersection)
  
proc updateBullets(state: PState) =
  # every 1 tick
  template deleteBullet() {.immediate.} =
    bullet.sprite.destroy()
    state.bullets.delete(i-removed)
    inc(removed)
    
  var removed = 0
  for i in 0..state.bullets.len-1:
    let bullet = state.bullets[i-removed]
    let currentBulletPos = bullet.sprite.getPosition()
    var newPos = vec2f(currentBulletPos.x + bullet.traj.x,
                      currentBulletPos.y + bullet.traj.y)
    bullet.sprite.setPosition(newPos)
    # Check if bullet hit player
    # TODO: Better collision detection?
    if bulletHits(bullet, state.player):
      echo("YOU JUST GOT HIT BRO.")
      # TODO: -10 on screen
      state.player.health.dec(10)
      deleteBullet()
    

proc handleView(state: PState, left: bool, playerSpeed: float) =
  let viewPosX = state.window.convertCoords(vec2i(0, 0), state.view).x
  let playerPosX = state.player.sprite.getPosition().x
  if playerPosX - viewPosX <= 50.0 and left:
    # We are close to the left side of the camera, and moving towards it.
    # We should move it.
    if viewPosX == 0.0 or viewPosX - playerSpeed <= 0.0:
      state.view.move(vec2f(0-viewPosX, 0)) # Move it to 0,0
    else:
      state.view.move(vec2f(0-playerSpeed, 0))
  elif (screenW + viewPosX) - playerPosX <= 200 and not left:
    # We are close to the right edge, and moving towards it.
    state.view.move(vec2f(playerSpeed,0))

proc handleLegs(player: var TVillain) =
  if player.legTicks >= 3:
    player.currentLeg = getNextLeg(player.currentLeg)
    player.legTicks = 0
  player.legTicks.inc

proc action(state: PState, player: var TVillain, keyCode: TKeyCode) =
  # This is called when a key is pressed every 1 tick.
  let pos = player.sprite.getPosition()
  var playerSpeed = 6.0
  if player.jumping:
    playerSpeed = 15.0
  case keyCode
  of keyLeft:
    player.sprite.setPosition(vec2f(pos.x - playerSpeed, pos.y))
    player.sprite.setOrigin(vec2f(28, 0))
    player.sprite.setTextureRect(intRect(64, 0, 64, 64))
    player.orientation = left
    handleView(state, true, playerSpeed)
    handleLegs(player)
  of keyRight:
    player.sprite.setPosition(vec2f(pos.x + playerSpeed, pos.y))
    player.sprite.setOrigin(vec2f(0, 0))
    player.sprite.setTextureRect(intRect(0, 0, 64, 64))
    player.orientation = right
    handleView(state, false, playerSpeed)
    handleLegs(player)
  else:
    nil

proc jump(player: var TVillain) =
  if not player.jumping:
    player.beforeJumpY = player.sprite.getPosition().y
    player.jumping = true
    player.yvelocity = -50

proc getTileRect(tile: TTileType, coord: var TIntRect) =
  case tile
  of TileRailing:
    coord = intRect(0, 192, 64, 64)
  of TileLamp:
    coord = intRect(64, 192, 64, 64)
  of TileLampTop:
    coord = intRect(64, 128, 64, 64)
  of TileSkyClouds:
    coord = intRect(128, 192, 64, 64)
  of TileSkyClear:
    coord = intRect(192, 192, 64, 64)
  of TileConcrete:
    coord = intRect(256, 192, 64, 64)

proc draw(state: PState, level: TLevel, behind: bool) =
  var xCoord = 0
  var yCoord = 0
  for y in level.tiles:
    for x in y:
      for t in x:
        if t.behind == behind:
          var coord: TIntRect
          getTileRect(t.tile, coord)
          var spr = newSprite(state.texture, coord)
          spr.setScale(vec2f(2,2))
          spr.setPosition(vec2f(xCoord.float, yCoord.float))
          state.window.draw(spr)
          destroy(spr)
      inc(xCoord, 128)
    xCoord = 0
    inc(yCoord, 128)

proc draw(state: PState, player: var TVillain) =
  # Draw legs.
  var plyrPos = player.sprite.getPosition()
  
  state.legs[player.currentLeg].setPosition(plyrPos)
  state.window.draw state.legs[player.currentLeg]

  # Player
  state.window.draw player.sprite

  # Bounding box.
  if state.showBounds:
    for box in getBoundBox(player):
      var rectShape = newRectangleShape()
      rectShape.setPosition(vec2f(box.left, box.top))
      rectShape.setSize(vec2f(box.width, box.height))
      rectShape.setFillColor(transparent)
      rectShape.setOutlineColor(magenta)
      rectShape.setOutlineThickness(1.0)
      state.window.draw rectShape
      rectShape.destroy()
    
proc drawBullets(state: PState) =
  for bullet in state.bullets:
    state.window.draw bullet.sprite

proc draw(state: PState) =

  state.draw(state.level, true)

  
  state.draw state.player
  state.drawBullets()
  
  state.draw(state.level, false)

when isMainModule:

  var state: PState
  new(state)
  state.bullets = @[]
  state.window = newRenderWindow(videoMode(screenW, ScreenH, 32), "LD25", sfTitlebar or sfClose)
  state.level = loadLevel()
  
  var event: TEvent
  
  var fpsClock = newClock()
  var tickClock = newClock()
  var framesPassed = 0
  state.view = state.window.getDefaultView.copy()
  state.defFont = newFont("fonts/DejaVuSansMono.ttf")
  state.fpsText = newText("", state.defFont, 12)
  
  # Load texture.
  var villainRect = intRect(0, 0, 64, 64)
  state.texture = newTexture("textures.png", nil)
  
  state.player = initVillain(newSprite(state.texture, villainRect))
  
  state.loadLegs()
  
  state.window.set_framerate_limit 60

  var keysPressed: seq[TKeyCode] = @[]
  while state.window.isOpen:
    while state.window.pollEvent(event):
      case event.kind
      of evtClosed:
        state.window.close()
      of evtKeyPressed:
        if event.key.code notin keysPressed:
          keysPressed.add(event.key.code)
        
        case event.key.code
        of keyUp:
          state.player.jump()
        of keyZ:
          echo(state.player.sprite.getPosition().x.formatFloat())
          echo(state.window.convertCoords(vec2i(0, 0), state.view).x.formatFloat())
        of keyP:
          state.addBullet(vec2f(400, 450), vec2f(-3, 0))
        of keyB:
          state.showBounds = not state.showBounds
        else: nil
        
      of evtKeyReleased:
        var indexReleased = -1
        for i in 0 .. len(keysPressed)-1:
          if keysPressed[i] == event.key.code:
            indexReleased = i
            break
        assert indexReleased != -1
        keysPressed.del(indexReleased) # TODO: Inefficient?
      
      of evtMouseWheelMoved:
        case event.mouseWheel.delta
        of 1: ## UP
          state.view.zoom(0.5)
        else: ## DOWN
          state.view.zoom(1.5)
      else:
        echo event.kind
    
    # FPS
    if fpsClock.getElapsedTime.asSeconds >= 1.0:
      discard fpsClock.restart()
      state.fpsText.setString($framesPassed & "FPS")
      framesPassed = 0
    
    # Time keeping.
    if tickClock.getElapsedTime.asMilliseconds >= 25:
      tickClock.restart()
      # 1 tick has passed.
      state.player.update()
      state.updateBullets()
      # Keyboard
      for keyPressed in keysPressed:
        state.action(state.player, keyPressed)
        # Debugging
        case keyPressed
        of keyS:
          state.view.move(vec2f(0.0, 15.0))
        of keyW:
          state.view.move(vec2f(0.0, -15.0))
        of keyD:
          state.view.move(vec2f(15.0, 0))
        of keyA:
          state.view.move(vec2f(-15.0, 0))
        else: nil
    
    state.window.clear gray
    
    state.window.setView state.view
    
    state.draw()
    
    state.window.setView state.window.getDefaultView()
    # Draw things independent of the view.
    state.window.draw state.FPSText
    state.window.display
    
    framesPassed.inc