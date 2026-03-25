-----------------------------------------------------------------------------------------
--
-- main.lua
--
-----------------------------------------------------------------------------------------

local socket = require("socket")
local json = require("json")
local widget = require("widget")

-- Device constants
local actualW = display.actualContentWidth
local actualH = display.actualContentHeight
local centerX = display.contentCenterX
local centerY = display.contentCenterY

local W = display.contentWidth
local H = display.contentHeight
local FLOOR_Y = 450

-- Game state
local STATE = "MENU"
local udp = nil
local server_ip = "[IP_ADDRESS]"
local server_port = 5555
local player_id = 0

-- Physics / Input states
local keys = { w=false, a=false, s=false, d=false, up=false, down=false, left=false, right=false }
local player_vy = 0
local swipe_yStart = 0
local swipe_triggered = false

-- Display groups
local Groupbg = display.newGroup()
local menuGroup = display.newGroup()
local gameGroup = display.newGroup()
Groupbg.isVisible = false
gameGroup.isVisible = false

-- Game objects
local bgImage
local p1Obj
local p2Obj
local ballObj
local scoreText
local scoreShadow
local timeText
local timeShadow
local statusText
local gameoverText
local boundsRect -- Visible bounding box for debugging and clarity

-- Function for drop shadow text
local function createTextWithShadow(group, textString, x, y, font, size, color)
    local shadow = display.newText(group, textString, x+3, y+3, font, size)
    shadow:setFillColor(0, 0, 0, 0.7)
    local text = display.newText(group, textString, x, y, font, size)
    text:setFillColor(unpack(color))
    return text, shadow
end

-- ================= MENU STATE =================

local menuBg = display.newRect(menuGroup, centerX, centerY, actualW, actualH)
menuBg:setFillColor(0.12, 0.15, 0.22)

local titleText, titleShadow = createTextWithShadow(menuGroup, "BOUNCING BALL ARENA", W/2, 60, native.systemFontBold, 40, {1, 0.8, 0.2})

local ipGroup = display.newGroup()
menuGroup:insert(ipGroup)

local ipLabelText = display.newText(menuGroup, "Server IP:", W/2 - 120, 150, native.systemFontBold, 22)
ipLabelText.anchorX = 1

local ipField = native.newTextField( W/2 + 50, 150, 240, 50 )
ipField.text = server_ip
ipField.font = native.newFont(native.systemFont, 18)
menuGroup:insert(ipField)

local portLabelText = display.newText(menuGroup, "Server Port:", W/2 - 120, 220, native.systemFontBold, 22)
portLabelText.anchorX = 1

local portField = native.newTextField( W/2 + 50, 220, 240, 50 )
portField.text = tostring(server_port)
portField.font = native.newFont(native.systemFont, 18)
menuGroup:insert(portField)

statusText, _ = createTextWithShadow(menuGroup, "Enter server details to connect", W/2, 350, native.systemFont, 22, {0.8, 0.8, 0.8})

-- Function to connect
local function connectToServer(event)
    if event.phase == "ended" then
        server_ip = ipField.text
        server_port = tonumber(portField.text)
        
        if not server_ip or not server_port then
            statusText.text = "Invalid IP or Port"
            statusText:setFillColor(1, 0, 0)
            return
        end
        
        -- Initialize UDP
        udp = socket.udp()
        udp:settimeout(0)
        udp:setpeername(server_ip, server_port)
        
        -- Send JOIN message
        local msg = json.encode({type = "JOIN"})
        udp:send(msg)
        
        statusText.text = "Connecting to Server..."
        statusText:setFillColor(1, 1, 0)
        STATE = "CONNECTING"
        
        -- Hide inputs
        ipField.isVisible = false
        portField.isVisible = false
    end
end

local connectBtn = widget.newButton(
    {
        x = W/2,
        y = 290,
        id = "connect",
        label = "CONNECT",
        font = native.systemFontBold,
        fontSize = 24,
        onEvent = connectToServer,
        shape = "roundedRect",
        width = 200, height = 60,
        cornerRadius = 8,
        fillColor = { default={0.15, 0.65, 0.95, 1}, over={0.1, 0.45, 0.75, 1} },
        labelColor = { default={1,1,1}, over={0.8,0.8,0.8} },
        strokeColor = { default={1,1,1}, over={0.8,0.8,0.8}},
        strokeWidth = 3
    }
)
menuGroup:insert(connectBtn)

-- ================= GAME STATE =================

-- Network Download Images
local function downloadImages(bgNum)
    local bgStr = "BG" .. tostring(bgNum) .. ".jpg"
    local bgUrl = "https://raw.githubusercontent.com/meowinwza06/project_game/main/" .. bgStr
    local p1Url = "https://raw.githubusercontent.com/meowinwza06/project_game/main/CHA12.png"
    local p2Url = "https://raw.githubusercontent.com/meowinwza06/project_game/main/CHA2.png"
    
    local imgDir = system.TemporaryDirectory
    
    local function bgListener(event)
        if not event.isError and STATE == "PLAYING" then
            if bgImage then bgImage:removeSelf() end
            -- Make it cover exactly the actual screen bounds
            bgImage = display.newImage(Groupbg, bgStr, imgDir)
            if bgImage then
                bgImage.x, bgImage.y = centerX, centerY
                bgImage.width, bgImage.height = actualW, actualH
            end
        end
    end
    network.download(bgUrl, "GET", bgListener, bgStr, imgDir)

    local function p1Listener(event)
        if not event.isError and STATE == "PLAYING" then
            display.remove(p1Obj)
            p1Obj = display.newImage(gameGroup, "CHA1.png", imgDir)
            if p1Obj then
                p1Obj.width, p1Obj.height = 80, 100
                p1Obj.x, p1Obj.y = 120, FLOOR_Y - 50
            end
        end
    end
    network.download(p1Url, "GET", p1Listener, "CHA1.png", imgDir)

    local function p2Listener(event)
        if not event.isError and STATE == "PLAYING" then
            display.remove(p2Obj)
            p2Obj = display.newImage(gameGroup, "CHA2.png", imgDir)
            if p2Obj then
                p2Obj.width, p2Obj.height = 80, 100
                p2Obj.x, p2Obj.y = W - 120, FLOOR_Y - 50
            end
        end
    end
    network.download(p2Url, "GET", p2Listener, "CHA2.png", imgDir)
end

local function initGameUI(bgNum)
    -- Draw placeholders until downloaded
    bgImage = display.newRect(Groupbg, centerX, centerY, actualW, actualH)
    bgImage:setFillColor(0.3, 0.6, 0.9)
    
    -- Outline the game area to clearly show bounds vs letterbox
    boundsRect = display.newRect(Groupbg, centerX, centerY, actualW, actualH)
    boundsRect:setFillColor(0, 0, 0, 0)
    boundsRect.strokeWidth = 0
    boundsRect:setStrokeColor(1, 1, 1, 0.5)

    -- Draw net
    local net = display.newRect(gameGroup, W/2, FLOOR_Y - 60, 12, 120)
    net:setFillColor(0.9, 0.9, 0.9, 0.9)
    net.strokeWidth = 2
    net:setStrokeColor(0.5, 0.5, 0.5)
    
    p1Obj = display.newRect(gameGroup, 120, FLOOR_Y - 50, 80, 100)
    p1Obj:setFillColor(1, 0.5, 0.5)
    
    p2Obj = display.newRect(gameGroup, W - 120, FLOOR_Y - 50, 80, 100)
    p2Obj:setFillColor(0.5, 0.5, 1)
    
    -- Ball
    ballObj = display.newCircle(gameGroup, W/2, 50, 15)
    ballObj:setFillColor(1, 0.95, 0)
    ballObj.strokeWidth = 3
    ballObj:setStrokeColor(0.8, 0.5, 0)
    
    -- UI texts
    scoreText, scoreShadow = createTextWithShadow(gameGroup, "0 - 0", W/2, 40, native.systemFontBold, 48, {1, 1, 1})
    timeText, timeShadow = createTextWithShadow(gameGroup, "Time: 90", W/2, 90, native.systemFontBold, 28, {1, 1, 1})
    
    gameoverText, _ = createTextWithShadow(gameGroup, "", W/2, H/2, native.systemFontBold, 64, {1, 0.2, 0.2})
    gameoverText.isVisible = false
    
    downloadImages(bgNum)
end

local function startGame(bgNum)
    STATE = "PLAYING"
    menuGroup.isVisible = false
    Groupbg.isVisible = true
    gameGroup.isVisible = true
    initGameUI(bgNum)
end

-- Keyboard handling for WASD
local function onKeyEvent( event )
    local keyName = event.keyName
    if event.phase == "down" then
        keys[keyName] = true
    elseif event.phase == "up" then
        keys[keyName] = false
    end
    return false
end
Runtime:addEventListener( "key", onKeyEvent )

-- Input handling
local isDragging = false
local function onTouch(event)
    if STATE ~= "PLAYING" then return true end
    
    local target = nil
    if player_id == 1 then target = p1Obj
    elseif player_id == 2 then target = p2Obj end
    
    if not target then return true end
    
    if event.phase == "began" then
        isDragging = true
        swipe_yStart = event.y
        swipe_triggered = false
        display.getCurrentStage():setFocus(target)
        target.isFocus = true
    elseif event.phase == "moved" and isDragging then
        -- Only move X with dragging
        target.x = event.x
        
        -- Check swipe up for jump
        if (swipe_yStart - event.y > 60) and not swipe_triggered then
            -- Jump if on the ground
            if target.y >= FLOOR_Y - 50 then
                player_vy = -20
                swipe_triggered = true
            end
        end
        -- Reset baseline if moving down
        if event.y > swipe_yStart then
            swipe_yStart = event.y
            swipe_triggered = false
        end

        -- Clamp X strictly to game bounds
        if player_id == 1 then
            if target.x < 40 then target.x = 40 end
            if target.x > W/2 - 46 then target.x = W/2 - 46 end
        else
            if target.x < W/2 + 46 then target.x = W/2 + 46 end
            if target.x > W - 40 then target.x = W - 40 end
        end
        
    elseif event.phase == "ended" or event.phase == "cancelled" then
        if isDragging then
            display.getCurrentStage():setFocus(nil)
            target.isFocus = false
            isDragging = false
        end
    end
    return true
end

Runtime:addEventListener("touch", onTouch)

-- Main Loop
local function update()
    if STATE == "PLAYING" and player_id > 0 then
        local target = (player_id == 1) and p1Obj or p2Obj
        if target then
            
            -- Horizontal WASD movement
            if not isDragging then
                local speed = 12 -- Move speed per frame
                local dx = 0
                if keys.a or keys.left then dx = -speed end
                if keys.d or keys.right then dx = speed end
                target.x = target.x + dx
                
                -- Clamp X strictly to game bounds
                if player_id == 1 then
                    if target.x < 40 then target.x = 40 end
                    if target.x > W/2 - 46 then target.x = W/2 - 46 end
                else
                    if target.x < W/2 + 46 then target.x = W/2 + 46 end
                    if target.x > W - 40 then target.x = W - 40 end
                end
            end
            
            -- Gravity & Jump physics
            local isGrounded = (target.y >= FLOOR_Y - 50)
            
            if not isGrounded then
                player_vy = player_vy + 1.2 -- Gravity
            else
                player_vy = 0
                target.y = FLOOR_Y - 50
            end
            
            -- Jump with W/Up
            if (keys.w or keys.up) and isGrounded then
                player_vy = -22
            end
            
            target.y = target.y + player_vy
            
            -- Floor clamping
            if target.y > FLOOR_Y - 50 then
                target.y = FLOOR_Y - 50
                player_vy = 0
            end
            
            -- Always send position so jump and movement syncs
            local msg = json.encode({ type = "MOVE", x = target.x, y = target.y })
            udp:send(msg)
        end
    end

    if udp then
        while true do
            local data, err = udp:receive()
            if not data then
                break
            end
            
            local msg = json.decode(data)
            if msg then
                if STATE == "CONNECTING" then
                    if msg.type == "ACCEPTED" then
                        player_id = msg.player_id
                        statusText.text = "Waiting for Player 2..."
                        statusText:setFillColor(0.4, 1, 0.4)
                    elseif msg.type == "START" then
                        local bgNum = msg.bg_num or 2
                        startGame(bgNum)
                    end
                elseif STATE == "PLAYING" then
                    if msg.type == "STATE" then
                        if ballObj then
                            ballObj.x, ballObj.y = msg.ball.x, msg.ball.y
                        end
                        if p1Obj and (player_id ~= 1) then
                            p1Obj.x, p1Obj.y = msg.p1.x, msg.p1.y
                        end
                        if p2Obj and (player_id ~= 2) then
                            p2Obj.x, p2Obj.y = msg.p2.x, msg.p2.y
                        end
                        
                        scoreText.text = msg.p1.score .. " - " .. msg.p2.score
                        scoreShadow.text = scoreText.text
                        timeText.text = "Time: " .. msg.time
                        timeShadow.text = timeText.text
                    elseif msg.type == "GAMEOVER" then
                        STATE = "GAMEOVER"
                        timeText.text = "Time: 0"
                        timeShadow.text = "Time: 0"
                        
                        local winStr = ""
                        if msg.winner == 0 then winStr = "DRAW!" 
                        else winStr = "PLAYER " .. msg.winner .. " WINS!" end
                        
                        gameoverText.text = winStr
                        gameoverText.isVisible = true
                    end
                end
            end
        end
    end
end

Runtime:addEventListener("enterFrame", update)