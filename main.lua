-----------------------------------------------------------------------------------------
--
-- main.lua
--
-----------------------------------------------------------------------------------------

local socket = require("socket")
local json = require("json")
local widget = require("widget")

-- Global SFX
local sfx = {}
local function initAudio()
    local files = {"pop.mp3", "win.mp3", "lose.mp3"}
    local baseUrl = "https://raw.githubusercontent.com/meowinwza06/project_game_Test/main/"
    for _, file in ipairs(files) do
        local function listener(event)
            if not event.isError then
                if file == "pop.mp3" then sfx.pop = audio.loadSound(file, system.TemporaryDirectory) end
                if file == "win.mp3" then sfx.win = audio.loadSound(file, system.TemporaryDirectory) end
                if file == "lose.mp3" then sfx.lose = audio.loadSound(file, system.TemporaryDirectory) end
            end
        end
        network.download(baseUrl .. file, "GET", listener, file, system.TemporaryDirectory)
    end
end
initAudio()

-- Device constants
local actualW = display.actualContentWidth
local actualH = display.actualContentHeight
local centerX = display.contentCenterX
local centerY = display.contentCenterY

local W = display.contentWidth
local H = display.contentHeight
local FLOOR_Y = 500  -- floor at screen bottom edge

-- Game state
local STATE = "MENU"
local udp = nil
local server_ip = ""
local server_port = 5555
local player_id = 0
local isPaused = false
local pauseMenuVisible = false

-- Physics / Input states
local keys = { w=false, a=false, s=false, d=false, up=false, down=false, left=false, right=false }
local player_vy = 0
local swipe_yStart = 0
local swipe_triggered = false

-- Client-side ball physics (P1 is authoritative)
local BALL_R     = 70    -- must match visual circle radius
local NET_W      = 80    -- must match visual net width
local NET_H      = 340   -- must match visual net height
local ball_x     = 500
local ball_y     = 50
local ball_vx    = 300
local ball_vy    = -50
local ball_last_t = system.getTimer()
local ball_scored = false  -- throttle sending SCORE once per landing

-- Display groups
local Groupbg = display.newGroup()
local menuGroup = display.newGroup()
local gameGroup = display.newGroup()
local pauseMenuGroup = display.newGroup()
local pauseRequestGroup = display.newGroup()
local hudGroup = display.newGroup()  -- For HUD elements like pause button
local warningGroup = display.newGroup()

Groupbg.isVisible = false
warningGroup.isVisible = false
gameGroup.isVisible = false
pauseMenuGroup.isVisible = false
pauseRequestGroup.isVisible = false
hudGroup.isVisible = false

-- Game objects
local bgImage
local p1Obj
local p2Obj
local ballObj
local netObj
local scoreText
local scoreShadow
local timeText
local timeShadow
local statusText
local gameoverText
local gameoverShadow
local pauseBtn
local ipBg
local portBg

-- Function for drop shadow text
local function createTextWithShadow(group, textString, x, y, font, size, color)
    local shadow = display.newText(group, textString, x+3, y+3, font, size)
    shadow:setFillColor(0, 0, 0, 0.7)
    local text = display.newText(group, textString, x, y, font, size)
    text:setFillColor(unpack(color))
    return text, shadow
end

-- ================= MENU STATE =================

local menuBg = display.newRect(menuGroup, centerX, centerY, 2000, 1500)
local bgGradient = {
    type="gradient",
    color1={ 0.05, 0.08, 0.15, 1 },
    color2={ 0.15, 0.20, 0.35, 1 },
    direction="down"
}
menuBg:setFillColor(bgGradient)

local titleText, titleShadow = createTextWithShadow(menuGroup, "BOUNCING BALL ARENA", W/2, H*0.15, native.systemFontBold, 46, {1, 1, 1})
local titleGradient = {
    type = "gradient",
    color1 = { 1, 0.9, 0.2, 1 },
    color2 = { 1, 0.5, 0.0, 1 },
    direction = "down"
}
titleText:setFillColor(titleGradient)
-- Subtle pulse effect
transition.to(titleText, { time=2000, xScale=1.03, yScale=1.03, transition=easing.continuousLoop, iterations=-1 })
transition.to(titleShadow, { time=2000, xScale=1.03, yScale=1.03, transition=easing.continuousLoop, iterations=-1 })

local ipLabelText = display.newText(menuGroup, "SERVER IP", W/2, H*0.24, native.systemFontBold, 26)
ipLabelText:setFillColor(0.6, 0.8, 1)

ipBg = display.newRoundedRect(menuGroup, W/2, H*0.32, 440, 72, 36)
ipBg:setFillColor(1, 1, 1, 0.2)
ipBg.strokeWidth = 2
ipBg:setStrokeColor(0.2, 0.6, 1, 0.8)

local ipField = native.newTextField( W/2, H*0.32, 400, 50 )
ipField.text = server_ip
ipField.font = native.newFont(native.systemFont, 28)
menuGroup:insert(ipField)

local portLabelText = display.newText(menuGroup, "SERVER PORT", W/2, H*0.46, native.systemFontBold, 26)
portLabelText:setFillColor(0.6, 0.8, 1)

portBg = display.newRoundedRect(menuGroup, W/2, H*0.54, 440, 72, 36)
portBg:setFillColor(1, 1, 1, 0.2)
portBg.strokeWidth = 2
portBg:setStrokeColor(0.2, 0.6, 1, 0.8)

local portField = native.newTextField( W/2, H*0.54, 400, 50 )
portField.text = tostring(server_port)
portField.font = native.newFont(native.systemFont, 28)
menuGroup:insert(portField)

statusText, _ = createTextWithShadow(menuGroup, "Enter server details to connect", W/2, H*0.88, native.systemFont, 20, {0.8, 0.8, 0.8})
transition.to(statusText, { time=1000, alpha=0.3, transition=easing.continuousLoop, iterations=-1 })

local waitingText  -- text for waiting state

-- Function to show loading animation and text
local function showLoadingAnimation()
    waitingText = display.newText(menuGroup, "กำลังรอผู้เล่นคนที่ 2...", W/2, centerY, native.systemFontBold, 32)
    waitingText:setFillColor(0.2, 0.9, 0.5)
    transition.to(waitingText, { time=800, alpha=0.3, transition=easing.continuousLoop, iterations=-1 })
    transition.to(waitingText, { time=1500, xScale=1.1, yScale=1.1, transition=easing.continuousLoop, iterations=-1 })
end

local function hideLoadingAnimation()
    if waitingText then
        transition.cancel(waitingText)
        waitingText:removeSelf()
        waitingText = nil
    end
end

-- Function to connect
local function closeWarningPopup()
    warningGroup.isVisible = false
    if ipField then ipField.isVisible = true end
    if portField then portField.isVisible = true end
end

local function showWarningPopup()
    warningGroup:toFront()
    warningGroup.isVisible = true
    if ipField then ipField.isVisible = false end
    if portField then portField.isVisible = false end
end

local function buildWarningPopup()
    local overlay = display.newRect(warningGroup, centerX, centerY, 3000, 2000)
    overlay:setFillColor(0, 0, 0, 0.8)
    overlay:addEventListener("tap", function() return true end)
    overlay:addEventListener("touch", function() return true end)

    local panel = display.newRoundedRect(warningGroup, centerX, centerY, 600, 360, 30)
    panel:setFillColor(0.1, 0.13, 0.2, 0.98)
    panel.strokeWidth = 4
    panel:setStrokeColor(1, 0.4, 0.2)

    local warningTitle = display.newText(warningGroup, "⚠️ ข้อมูลไม่ครบถ้วน", centerX, centerY - 100, native.systemFontBold, 44)
    warningTitle:setFillColor(1, 0.4, 0.2)

    local warningMsg = display.newText(warningGroup, "กรุณากรอกหมายเลข IP และ Port\nของเครื่องเซิร์ฟเวอร์ให้ถูกต้องครบถ้วน\n(เช่น 192.168.1.10 และ 5555)", centerX, centerY, native.systemFont, 28)
    warningMsg:setFillColor(0.9, 0.9, 0.9)
    warningMsg.align = "center"

    local closeBtn = widget.newButton({
        x = centerX,
        y = centerY + 110,
        label = "ตกลง",
        font = native.systemFontBold,
        fontSize = 28,
        shape = "roundedRect",
        width = 240, height = 64,
        cornerRadius = 32,
        fillColor = { default={0.8, 0.2, 0.2, 1}, over={0.6, 0.1, 0.1, 1} },
        labelColor = { default={1,1,1}, over={0.9,0.9,0.9} },
        onEvent = function(e)
            if e.phase == "ended" then
                closeWarningPopup()
            end
        end
    })
    warningGroup:insert(closeBtn)
end
buildWarningPopup()

local function connectToServer(event)
    if event.phase == "ended" then
        server_ip = ipField.text
        server_port = tonumber(portField.text)

        if not server_ip or server_ip == "" or server_ip == "[IP_ADDRESS]" or not server_port then
            showWarningPopup()
            return
        end

        -- Initialize UDP
        udp = socket.udp()
        udp:settimeout(0)
        local success, err = udp:setpeername(server_ip, server_port)
        
        if not success then
            showWarningPopup()
            udp:close()
            udp = nil
            return
        end

        -- Send JOIN message
        local msg = json.encode({
            type = "JOIN",
            minX = display.screenOriginX,
            maxX = display.contentWidth - display.screenOriginX
        })
        udp:send(msg)

        STATE = "CONNECTING"

        -- Hide inputs and button, show loading
        ipField.isVisible = false
        portField.isVisible = false
        ipLabelText.isVisible = false
        portLabelText.isVisible = false
        if ipBg then ipBg.isVisible = false end
        if portBg then portBg.isVisible = false end
        statusText.isVisible = false

        -- Find and hide connect button
        event.target.isVisible = false

        showLoadingAnimation()
    end
end

local connectBtn = widget.newButton(
    {
        x = W/2,
        y = H*0.72,
        id = "connect",
        label = "CONNECT",
        font = native.systemFontBold,
        fontSize = 26,
        onEvent = connectToServer,
        shape = "roundedRect",
        width = 240, height = 64,
        cornerRadius = 32,
        fillColor = { 
            default={ type="gradient", color1={1, 0.6, 0.2, 1}, color2={1, 0.3, 0.1, 1}, direction="down" }, 
            over={ type="gradient", color1={0.8, 0.4, 0.1, 1}, color2={0.8, 0.2, 0.05, 1}, direction="down" } 
        },
        labelColor = { default={1,1,1}, over={0.9,0.9,0.9} },
        strokeColor = { default={1, 0.8, 0.4, 1}, over={0.8, 0.6, 0.2, 1}},
        strokeWidth = 2
    }
)
menuGroup:insert(connectBtn)
transition.to(connectBtn, { time=1500, xScale=1.05, yScale=1.05, transition=easing.continuousLoop, iterations=-1 })

-- ================= PAUSE MENU =================

local function closePauseMenu()
    pauseMenuGroup.isVisible = false
    pauseMenuVisible = false
end

local function openPauseMenu()
    pauseMenuGroup.isVisible = true
    pauseMenuVisible = true
end

local function buildPauseMenu()
    -- Dark transparent overlay
    local overlay = display.newRect(pauseMenuGroup, centerX, centerY, actualW, actualH)
    overlay:setFillColor(0, 0, 0, 0.7)

    -- Menu panel
    local panel = display.newRoundedRect(pauseMenuGroup, centerX, centerY, 460, 360, 20)
    panel:setFillColor(0.1, 0.13, 0.2, 0.97)
    panel.strokeWidth = 3
    panel:setStrokeColor(0.3, 0.5, 0.9)

    -- Title
    local pauseTitle = display.newText(pauseMenuGroup, "⏸  PAUSED", centerX, centerY - 130, native.systemFontBold, 36)
    pauseTitle:setFillColor(1, 0.85, 0.2)

    -- Separator line
    local sep = display.newRect(pauseMenuGroup, centerX, centerY - 90, 400, 3)
    sep:setFillColor(0.3, 0.5, 0.9, 0.5)

    -- Button: หยุดเกมชั่วคราว
    local reqPauseBtn = widget.newButton({
        x = centerX,
        y = centerY - 35,
        label = "⏸  ขอหยุดเกมชั่วคราว",
        font = native.systemFontBold,
        fontSize = 26,
        shape = "roundedRect",
        width = 380, height = 64,
        cornerRadius = 12,
        fillColor = { default={0.15, 0.45, 0.85, 1}, over={0.1, 0.3, 0.65, 1} },
        labelColor = { default={1,1,1}, over={0.8,0.8,0.8} },
        onEvent = function(e)
            if e.phase == "ended" then
                if udp then
                    udp:send(json.encode({type = "PAUSE_REQUEST"}))
                end
                closePauseMenu()
            end
        end
    })
    pauseMenuGroup:insert(reqPauseBtn)

    -- Button: กลับเข้าเกม
    local resumeBtn = widget.newButton({
        x = centerX,
        y = centerY + 45,
        label = "▶  กลับเข้าเกม",
        font = native.systemFontBold,
        fontSize = 26,
        shape = "roundedRect",
        width = 380, height = 64,
        cornerRadius = 12,
        fillColor = { default={0.15, 0.65, 0.25, 1}, over={0.1, 0.45, 0.15, 1} },
        labelColor = { default={1,1,1}, over={0.8,0.8,0.8} },
        onEvent = function(e)
            if e.phase == "ended" then
                if udp and STATE == "PAUSED" then
                    udp:send(json.encode({type = "RESUME"}))
                end
                closePauseMenu()
            end
        end
    })
    pauseMenuGroup:insert(resumeBtn)

    -- Button: ออกจากเกม
    local quitBtn = widget.newButton({
        x = centerX,
        y = centerY + 125,
        label = "✕  ออกจากเกม",
        font = native.systemFontBold,
        fontSize = 26,
        shape = "roundedRect",
        width = 380, height = 64,
        cornerRadius = 12,
        fillColor = { default={0.65, 0.15, 0.15, 1}, over={0.45, 0.1, 0.1, 1} },
        labelColor = { default={1,1,1}, over={0.8,0.8,0.8} },
        onEvent = function(e)
            if e.phase == "ended" then
                closePauseMenu()
                -- Reset and go back to menu
                STATE = "MENU"
                isPaused = false
                if udp then udp:close(); udp = nil end
                audio.stop(1)
                Groupbg.isVisible = false
                gameGroup.isVisible = false
                hudGroup.isVisible = false
                menuGroup.isVisible = true
                -- Re-show menu elements
                ipField.isVisible = true
                portField.isVisible = true
                ipLabelText.isVisible = true
                portLabelText.isVisible = true
                if ipBg then ipBg.isVisible = true end
                if portBg then portBg.isVisible = true end
                statusText.isVisible = true
                statusText.text = "Enter server details to connect"
                statusText:setFillColor(0.8, 0.8, 0.8)
                connectBtn.isVisible = true
                hideLoadingAnimation()
                player_id = 0
                player_vy = 0
            end
        end
    })
    pauseMenuGroup:insert(quitBtn)
end

buildPauseMenu()

-- ================= PAUSE REQUEST POPUP =================

local function buildPauseRequestPopup()
    -- Centered, larger panel
    local panel = display.newRoundedRect(pauseRequestGroup, centerX, 120, 500, 160, 16)
    panel:setFillColor(0.08, 0.1, 0.18, 0.96)
    panel.strokeWidth = 3
    panel:setStrokeColor(1, 0.7, 0.1)

    local reqText = display.newText(pauseRequestGroup, "ผู้เล่นอีกคนขอหยุดเกมชั่วคราว", centerX, 70, native.systemFontBold, 26)
    reqText:setFillColor(1, 0.9, 0.3)

    local subText = display.newText(pauseRequestGroup, "ตกลงมั้ย?", centerX, 110, native.systemFont, 22)
    subText:setFillColor(0.9, 0.9, 0.9)

    -- YES button image
    local yesBtn = display.newImageRect(pauseRequestGroup, "button_yes.png", 150, 63)
    yesBtn.x = centerX - 100
    yesBtn.y = 160
    yesBtn:addEventListener("tap", function()
        if udp then
            udp:send(json.encode({type = "PAUSE_RESPONSE", accept = true}))
        end
        pauseRequestGroup.isVisible = false
    end)

    -- NO button image
    local noBtn = display.newImageRect(pauseRequestGroup, "button_no.png", 150, 63)
    noBtn.x = centerX + 100
    noBtn.y = 160
    noBtn:addEventListener("tap", function()
        if udp then
            udp:send(json.encode({type = "PAUSE_RESPONSE", accept = false}))
        end
        pauseRequestGroup.isVisible = false
    end)
end

buildPauseRequestPopup()

-- ================= GAME STATE =================

-- Network Download Images and BGM
local function downloadImages(bgNum, bgmNum)
    local bgStr = "BG" .. tostring(bgNum) .. ".jpg"
    local bgUrl = "https://raw.githubusercontent.com/meowinwza06/project_game_Test/main/" .. bgStr
    local p1Url = "https://raw.githubusercontent.com/meowinwza06/project_game_Test/main/CHA12.png"
    local p2Url = "https://raw.githubusercontent.com/meowinwza06/project_game_Test/main/CHA2.png"

    local bgmStr = tostring(bgmNum) .. ".mp3"
    local bgmUrl = "https://raw.githubusercontent.com/meowinwza06/project_game_Test/main/" .. bgmStr

    local imgDir = system.TemporaryDirectory

    local function bgmListener(event)
        if not event.isError and STATE == "PLAYING" then
            timer.performWithDelay(2000, function()
                if STATE == "PLAYING" then
                    audio.setVolume(0.1, { channel=1 })
                    local bgMusic = audio.loadStream(bgmStr, imgDir)
                    if bgMusic then
                        audio.play(bgMusic, { channel=1, loops=-1, fadein=1000 })
                    end
                end
            end)
        end
    end
    audio.stop(1)
    network.download(bgmUrl, "GET", bgmListener, bgmStr, imgDir)

    local function bgListener(event)
        if event.phase == "ended" and not event.isError then
            if STATE == "PLAYING" or STATE == "PAUSED" then
                if bgImage then bgImage:removeSelf() end
                bgImage = display.newImage(Groupbg, event.response.filename, event.response.baseDirectory)
                if bgImage then
                    bgImage.x = display.contentCenterX
                    bgImage.y = display.contentCenterY
                    local scaleRatio = math.max(display.actualContentWidth / bgImage.width, display.actualContentHeight / bgImage.height)
                    bgImage.xScale = scaleRatio
                    bgImage.yScale = scaleRatio
                    bgImage:toBack()
                end
            end
        end
    end
    network.download(bgUrl, "GET", bgListener, bgStr, imgDir)

    local function p1Listener(event)
        if event.phase == "ended" and not event.isError then
            if STATE == "PLAYING" or STATE == "PAUSED" then
                display.remove(p1Obj)
                p1Obj = display.newImageRect(gameGroup, "CHA1.png", imgDir, 240, 300)
                if p1Obj then
                    p1Obj.x, p1Obj.y = W * 0.15, FLOOR_Y - 150
                end
            end
        end
    end
    network.download(p1Url, "GET", p1Listener, "CHA1.png", imgDir)

    local function p2Listener(event)
        if event.phase == "ended" and not event.isError then
            if STATE == "PLAYING" or STATE == "PAUSED" then
                display.remove(p2Obj)
                p2Obj = display.newImageRect(gameGroup, "CHA2.png", imgDir, 240, 300)
                if p2Obj then
                    p2Obj.x, p2Obj.y = W * 0.85, FLOOR_Y - 150
                end
            end
        end
    end
    network.download(p2Url, "GET", p2Listener, "CHA2.png", imgDir)

    local txUrl = "https://raw.githubusercontent.com/meowinwza06/project_game_Test/main/Tx.png"
    local function txListener(event)
        if event.phase == "ended" and not event.isError then
            if STATE == "PLAYING" or STATE == "PAUSED" then
                -- Remove the placeholder / previous net
                if netObj then display.remove(netObj); netObj = nil end
                -- Create properly-sized image
                local img = display.newImageRect(gameGroup, "Tx.png", imgDir, 80, 340)
                if img then
                    img.anchorX = 0.5
                    img.anchorY = 1
                    img.x = W / 2
                    img.y = FLOOR_Y
                    netObj = img
                end
            end
        end
    end
    network.download(txUrl, "GET", txListener, "Tx.png", imgDir)
end

local function initGameUI(bgNum, bgmNum)
    -- Background placeholder explicitly scaled to fill letterbox
    bgImage = display.newRect(Groupbg, centerX, centerY, actualW + 200, actualH + 200)
    bgImage:setFillColor(0.2, 0.45, 0.7)

    -- Net placeholder rect (replaced by Tx.png once downloaded)
    local netPlaceholder = display.newRect(gameGroup, W/2, FLOOR_Y, 80, 340)
    netPlaceholder.anchorY = 1
    netPlaceholder:setFillColor(0.9, 0.9, 0.9, 0.3)
    netPlaceholder.strokeWidth = 0
    netObj = netPlaceholder  -- so txListener can reference & remove it

    -- Floor line
    local floor = display.newRect(gameGroup, centerX, FLOOR_Y + 2, 2000, 4)
    floor:setFillColor(0.5, 0.4, 0.3, 0.8)

    p1Obj = display.newRect(gameGroup, W * 0.15, FLOOR_Y - 150, 240, 300)
    p1Obj:setFillColor(1, 0.5, 0.5)

    p2Obj = display.newRect(gameGroup, W * 0.85, FLOOR_Y - 150, 240, 300)
    p2Obj:setFillColor(0.5, 0.5, 1)

    -- Ball
    ballObj = display.newCircle(gameGroup, W/2, H * 0.1, 70)
    ballObj:setFillColor(1, 0.95, 0)
    ballObj.strokeWidth = 3
    ballObj:setStrokeColor(0.8, 0.5, 0)

    -- UI texts (score/time on hudGroup so they don't move with gameGroup)
    scoreText, scoreShadow = createTextWithShadow(hudGroup, "0 - 0", W/2, display.screenOriginY + 65, native.systemFontBold, 64, {1, 1, 1})
    timeText, timeShadow = createTextWithShadow(hudGroup, "Time: 90", W/2, display.screenOriginY + 135, native.systemFontBold, 36, {1, 1, 1})

    gameoverText, gameoverShadow = createTextWithShadow(hudGroup, "", W/2, display.contentCenterY, native.systemFontBold, 64, {1, 0.2, 0.2})
    gameoverText.isVisible = false
    gameoverShadow.isVisible = false

    -- Push gameGroup down so FLOOR_Y aligns with the actual device screen bottom
    gameGroup.y = (display.actualContentHeight + display.screenOriginY) - FLOOR_Y

    -- Pause button (top-right corner)
    pauseBtn = display.newImageRect(hudGroup, "pause_button.png", 56, 56)
    pauseBtn.x = actualW/2 - 36
    pauseBtn.y = -actualH/2 + 36
    pauseBtn:addEventListener("tap", function()
        if STATE == "PAUSED" then
            if udp then udp:send(json.encode({type = "RESUME"})) end
        elseif STATE == "PLAYING" and not pauseMenuVisible then
            openPauseMenu()
        elseif pauseMenuVisible then
            closePauseMenu()
        end
    end)

    downloadImages(bgNum, bgmNum)
end

local function startGame(bgNum, bgmNum)
    STATE = "PLAYING"
    isPaused = false
    menuGroup.isVisible = false
    Groupbg.isVisible = true
    gameGroup.isVisible = true
    hudGroup.isVisible = true
    hideLoadingAnimation()
    initGameUI(bgNum, bgmNum)
end

-- Keyboard handling
local function onKeyEvent( event )
    local keyName = event.keyName
    if event.phase == "down" then
        keys[keyName] = true
        
        if keyName == "p" and STATE == "CONNECTING" then
            if udp then
                udp:send(json.encode({
                    type = "FORCE_START",
                    minX = display.screenOriginX,
                    maxX = display.contentWidth - display.screenOriginX
                }))
            end
        end

        -- ESC toggles pause menu
        if keyName == "escape" and (STATE == "PLAYING" or STATE == "PAUSED") then
            if pauseMenuVisible then
                closePauseMenu()
            else
                openPauseMenu()
            end
        end
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
    if pauseMenuVisible then return true end

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
            if target.y >= FLOOR_Y - 150 then
                player_vy = -32
                swipe_triggered = true
            end
        end
        if event.y > swipe_yStart then
            swipe_yStart = event.y
            swipe_triggered = false
        end

        -- Clamp X strictly to screen bounds
        local minX = display.screenOriginX
        local maxX = display.contentWidth - display.screenOriginX
        if player_id == 1 then
            if target.x < minX + 60 then target.x = minX + 60 end
            if target.x > W/2 - 78 then target.x = W/2 - 78 end
        else
            if target.x < W/2 + 78 then target.x = W/2 + 78 end
            if target.x > maxX - 60 then target.x = maxX - 60 end
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
    if STATE == "PLAYING" and not isPaused and player_id > 0 then
        local target = (player_id == 1) and p1Obj or p2Obj
        if target then

            -- Horizontal WASD movement
            if not isDragging then
                local speed = 14
                local dx = 0
                if keys.a or keys.left then dx = -speed end
                if keys.d or keys.right then dx = speed end
                target.x = target.x + dx

                local minX = display.screenOriginX
                local maxX = display.contentWidth - display.screenOriginX
                local halfPlayer = 60  -- half of player width 120
                local halfNet = 8     -- half of NET_WIDTH 16
                if player_id == 1 then
                    if target.x < minX + halfPlayer then target.x = minX + halfPlayer end
                    if target.x > W/2 - halfNet - halfPlayer then target.x = W/2 - halfNet - halfPlayer end
                else
                    if target.x < W/2 + halfNet + halfPlayer then target.x = W/2 + halfNet + halfPlayer end
                    if target.x > maxX - halfPlayer then target.x = maxX - halfPlayer end
                end
            end

            -- Gravity & Jump physics
            local isGrounded = (target.y >= FLOOR_Y - 150)

            if not isGrounded then
                player_vy = player_vy + 2.0
            else
                player_vy = 0
                target.y = FLOOR_Y - 150
            end

            if (keys.w or keys.up) and isGrounded then
                player_vy = -32
            end

            target.y = target.y + player_vy

            if target.y > FLOOR_Y - 150 then
                target.y = FLOOR_Y - 150
                player_vy = 0
            end

            local msg = json.encode({ type = "MOVE", x = target.x, y = target.y })
            udp:send(msg)
        end
    end

    -- Ball physics (only P1 runs this)
    if STATE == "PLAYING" and player_id == 1 and not isPaused and udp then
        local now_t = system.getTimer()
        local dt    = (now_t - ball_last_t) / 1000  -- convert ms to seconds
        if dt > 0.05 then dt = 0.05 end  -- cap to avoid tunneling on lag
        ball_last_t = now_t

        local minX = display.screenOriginX
        local maxX = display.contentWidth - display.screenOriginX

        -- Gravity
        ball_vy = ball_vy + 900 * dt

        local prev_bx = ball_x
        local prev_by = ball_y
        ball_x = ball_x + ball_vx * dt
        ball_y = ball_y + ball_vy * dt

        -- Left/Right walls
        if ball_x - BALL_R < minX then
            ball_x = minX + BALL_R
            ball_vx = math.abs(ball_vx) * 0.85
        elseif ball_x + BALL_R > maxX then
            ball_x = maxX - BALL_R
            ball_vx = -math.abs(ball_vx) * 0.85
        end

        -- Net collision (CCD)
        local net_cx = W / 2
        local net_L  = net_cx - NET_W / 2
        local net_R  = net_cx + NET_W / 2
        local net_top = FLOOR_Y - NET_H

        -- From left
        if prev_bx + BALL_R <= net_L and ball_x + BALL_R > net_L then
            if ball_y + BALL_R > net_top and ball_y - BALL_R < FLOOR_Y then
                ball_x = net_L - BALL_R
                ball_vx = -math.abs(ball_vx) * 0.85
            end
        -- From right
        elseif prev_bx - BALL_R >= net_R and ball_x - BALL_R < net_R then
            if ball_y + BALL_R > net_top and ball_y - BALL_R < FLOOR_Y then
                ball_x = net_R + BALL_R
                ball_vx = math.abs(ball_vx) * 0.85
            end
        -- Hit top of net
        elseif ball_x > net_L and ball_x < net_R then
            if prev_by - BALL_R >= net_top and ball_y - BALL_R < net_top then
                ball_y = net_top - BALL_R
                ball_vy = -math.abs(ball_vy) * 0.75
            end
        end

        -- Player 1 collision (self)
        if p1Obj then
            local pdx = ball_x - p1Obj.x
            local pdy = ball_y - p1Obj.y
            local hw, hh = 60, 150
            if math.abs(pdx) < hw + BALL_R and math.abs(pdy) < hh + BALL_R then
                ball_vy = -math.abs(ball_vy + 300)
                ball_vx = pdx * 6
                if sfx and sfx.pop then audio.play(sfx.pop) end
            end
        end

        -- Player 2 collision (received position from server)
        if p2Obj then
            local pdx = ball_x - p2Obj.x
            local pdy = ball_y - p2Obj.y
            local hw, hh = 60, 150
            if math.abs(pdx) < hw + BALL_R and math.abs(pdy) < hh + BALL_R then
                ball_vy = -math.abs(ball_vy + 300)
                ball_vx = pdx * 6
                if sfx and sfx.pop then audio.play(sfx.pop) end
            end
        end

        -- Floor / Scoring
        if ball_y + BALL_R >= FLOOR_Y then
            if not ball_scored then
                ball_scored = true
                local scorer = (ball_x < W / 2) and 2 or 1  -- who scored
                udp:send(json.encode({ type = "SCORE", scorer = scorer }))
                -- Delay reset so both clients see the landing
                timer.performWithDelay(1200, function()
                    ball_x = W / 2
                    ball_y = 80
                    ball_vx = (math.random(0,1) == 0) and 350 or -350
                    ball_vy = -100
                    ball_scored = false
                end)
            end
            -- Bounce on floor softly while waiting for reset
            if ball_y + BALL_R > FLOOR_Y then
                ball_y = FLOOR_Y - BALL_R
                ball_vy = -math.abs(ball_vy) * 0.5
            end
        end

        -- Update visual
        if ballObj then
            ballObj.x = ball_x
            ballObj.y = ball_y
        end

        -- Send ball position to server (relayed to P2)
        udp:send(json.encode({ type = "BALL_POS", x = ball_x, y = ball_y }))
    end

    if udp then
        while true do
            local data, err = udp:receive()
            if not data then break end

            local msg = json.decode(data)
            if msg then
                if STATE == "CONNECTING" then
                    if msg.type == "ACCEPTED" then
                        player_id = msg.player_id
                    elseif msg.type == "START" then
                        local bgNum = msg.bg_num or 2
                        local bgmNum = msg.bgm_num or 1
                        startGame(bgNum, bgmNum)
                    end

                elseif STATE == "PLAYING" or STATE == "PAUSED" then
                    if msg.type == "STATE" and STATE == "PLAYING" then
                        -- Ball position: P2 reads from server relay; P1 ignores (runs local physics)
                        if ballObj and player_id ~= 1 then
                            ballObj.x = msg.ball.x
                            ballObj.y = msg.ball.y
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

                    elseif msg.type == "SCORE_UPDATE" then
                        -- Server confirmed score; update display
                        scoreText.text = msg.p1_score .. " - " .. msg.p2_score
                        scoreShadow.text = scoreText.text
                        if sfx and sfx.pop then audio.play(sfx.pop) end

                    elseif msg.type == "HIT" then
                        if sfx.pop then audio.play(sfx.pop) end

                    elseif msg.type == "PAUSE_REQUEST" then
                        -- Show pause request popup
                        pauseRequestGroup.isVisible = true

                    elseif msg.type == "PAUSED" then
                        STATE = "PAUSED"
                        isPaused = true
                        -- Show "game paused" notice
                        if gameoverText then
                            gameoverText.text = "⏸ เกมหยุดชั่วคราว\n(กดปุ่มหยุดเกมอีกครั้งเพื่อเริ่มเกมใหม่)"
                            gameoverShadow.text = gameoverText.text
                            gameoverText.size = 50
                            gameoverShadow.size = 50
                            gameoverText.xScale = 1; gameoverText.yScale = 1
                            gameoverShadow.xScale = 1; gameoverShadow.yScale = 1
                            gameoverText:setFillColor(1, 0.9, 0.2)
                            gameoverText.isVisible = true
                            gameoverShadow.isVisible = true
                        end

                    elseif msg.type == "RESUME_COUNTDOWN" then
                        if gameoverText then
                            gameoverText.text = tostring(msg.count)
                            gameoverShadow.text = gameoverText.text
                            gameoverText.size = 120
                            gameoverShadow.size = 120
                            gameoverText:setFillColor(1, 1, 1)
                            gameoverText.isVisible = true
                            gameoverShadow.isVisible = true
                            
                            -- Animate
                            gameoverText.xScale = 1.6; gameoverText.yScale = 1.6
                            gameoverShadow.xScale = 1.6; gameoverShadow.yScale = 1.6
                            transition.to(gameoverText, {time=200, xScale=1.0, yScale=1.0, transition=easing.outElastic})
                            transition.to(gameoverShadow, {time=200, xScale=1.0, yScale=1.0, transition=easing.outElastic})
                        end

                    elseif msg.type == "RESUMED" then
                        STATE = "PLAYING"
                        isPaused = false
                        if gameoverText then
                            gameoverText.isVisible = false
                            gameoverShadow.isVisible = false
                            gameoverText.size = 64
                            gameoverShadow.size = 64
                        end

                    elseif msg.type == "PAUSE_DENIED" then
                        -- The other player rejected our pause request
                        if gameoverText then
                            gameoverText.text = "คำขอถูกปฏิเสธ"
                            gameoverShadow.text = gameoverText.text
                            gameoverText:setFillColor(1, 0.3, 0.3)
                            gameoverText.isVisible = true
                            gameoverShadow.isVisible = true
                        end
                        -- Hide the notice after 2s
                        timer.performWithDelay(2000, function()
                            if gameoverText and STATE == "PLAYING" then 
                                gameoverText.isVisible = false 
                                gameoverShadow.isVisible = false
                            end
                        end)

                    elseif msg.type == "GAMEOVER" then
                        STATE = "GAMEOVER"
                        audio.stop(1)
                        timeText.text = "Time: 0"
                        timeShadow.text = "Time: 0"

                        local winStr = ""
                        if msg.winner == 0 then
                            winStr = "DRAW!"
                        else
                            winStr = "PLAYER " .. msg.winner .. " WINS!"
                            if msg.winner == player_id then
                                if sfx.win then audio.play(sfx.win) end
                            else
                                if sfx.lose then audio.play(sfx.lose) end
                            end
                        end

                        gameoverText.text = winStr
                        gameoverText:setFillColor(1, 0.2, 0.2)
                        gameoverText.isVisible = true
                        gameoverShadow.isVisible = true

                        -- Show Return-to-Menu button after 1.5 s
                        timer.performWithDelay(1500, function()
                            if STATE ~= "GAMEOVER" then return end
                            local returnBtn = widget.newButton({
                                x = W / 2,
                                y = display.contentCenterY + 80,
                                label = "\226\134\169 กลับเมนู",
                                font = native.systemFontBold,
                                fontSize = 28,
                                shape = "roundedRect",
                                width = 280, height = 60,
                                cornerRadius = 12,
                                fillColor = { default={0.15,0.6,1,1}, over={0.05,0.4,0.8,1} },
                                labelColor = { default={1,1,1}, over={0.9,0.9,0.9} },
                                onEvent = function(e)
                                    if e.phase == "ended" then
                                        -- disconnect
                                        if udp then udp:close(); udp = nil end
                                        audio.stop(1)
                                        -- reset groups
                                        STATE = "MENU"
                                        player_id = 0
                                        ball_x, ball_y = W/2, 80
                                        ball_vx, ball_vy = 300, -50
                                        ball_scored = false
                                        -- hide game, show menu
                                        Groupbg.isVisible = false
                                        gameGroup.isVisible = false
                                        hudGroup.isVisible = false
                                        menuGroup.isVisible = true
                                        ipField.isVisible = true
                                        portField.isVisible = true
                                        ipLabelText.isVisible = true
                                        portLabelText.isVisible = true
                                        statusText.isVisible = true
                                        statusText.text = "Enter server details to connect"
                                        statusText:setFillColor(0.8, 0.8, 0.8)
                                        connectBtn.isVisible = true
                                        hideLoadingAnimation()
                                        -- remove this button
                                        display.remove(returnBtn)
                                    end
                                end
                            })
                            hudGroup:insert(returnBtn)
                        end)
                    end
                end
            end
        end
    end
end

Runtime:addEventListener("enterFrame", update)