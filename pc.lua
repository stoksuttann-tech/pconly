local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local Camera = workspace.CurrentCamera
local LocalPlayer = Players.LocalPlayer
local mouse = LocalPlayer:GetMouse()
local UIS = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local HttpService = game:GetService("HttpService")

-- ================= PROTECT GUI SYSTEM =================
local ProtectedFolder = Instance.new("Folder")
ProtectedFolder.Parent = cloneref(CoreGui)
ProtectedFolder.Name = "RobloxGui"

local function Protect(inst)
    local HiddenUI = gethui or gethiddenui or get_hidden_ui or get_hui or get_h_ui
    if inst and inst:IsA("GuiObject") then
        inst.Parent = HiddenUI and HiddenUI() or cloneref(ProtectedFolder)
        inst.Name = HttpService:GenerateGUID(false)
    elseif inst then
        inst.Parent = cloneref(ProtectedFolder)
        inst.Name = HttpService:GenerateGUID(false)
    end
end

-- ================= STATE =================
local AIM_ENABLED = false
local AIM_SPEED = 0.35
local FOV_RADIUS = 220
local HEIGHT_OFFSET = 1.5
local STICKY_LOCK = false
local target = nil

-- ================= RMB PAUSE =================
local RMB_HOLD = false
local AIM_PAUSED = false

-- ================= PREDICTION =================
local PREDICTION_ENABLED = false
local PREDICTION_MULT = 0.12   -- strength prediction (stable value)
local lastPos = {}
local lastTime = {}

-- ================= MAGNET CONTROL =================
local INNER_FOV_MULTIPLIER = 1.6
local OUTSIDE_FOV_LIMIT = 1.3

-- ================= DISTANCE HEIGHT FIX =================
local DIST_HEIGHT_MULT = 0.015
local DIST_HEIGHT_MAX  = 3.5

-- ================= FOV OFFSET FIX =================
local FOV_Y_OFFSET = 12
local RADIUS_OFFSET = 0

-- ================= OFFSET LOCK =================
local LOCKED_OFFSET = nil

-- ================= GUI =================
local gui = Instance.new("ScreenGui")
gui.ResetOnSpawn = false
gui.DisplayOrder = 999999
Protect(gui) -- << PROTECT GUI AKTIF

local frame = Instance.new("Frame", gui)
frame.Size = UDim2.new(0,260,0,355) -- + space for prediction
frame.Position = UDim2.new(0.02,0,0.32,0)
frame.BackgroundColor3 = Color3.fromRGB(25,25,25)
frame.Active = true
frame.Draggable = true
Instance.new("UICorner", frame).CornerRadius = UDim.new(0,12)

local title = Instance.new("TextLabel", frame)
title.Size = UDim2.new(1,0,0,35)
title.Text = "CURSOR AIMLOCK"
title.TextColor3 = Color3.new(1,1,1)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold
title.TextSize = 14

local toggle = Instance.new("TextButton", frame)
toggle.Size = UDim2.new(0.9,0,0,35)
toggle.Position = UDim2.new(0.05,0,0,45)
toggle.Text = "AIM : OFF"
toggle.Font = Enum.Font.GothamBold
toggle.TextSize = 13
toggle.TextColor3 = Color3.new(1,1,1)
toggle.BackgroundColor3 = Color3.fromRGB(140,0,0)
Instance.new("UICorner", toggle).CornerRadius = UDim.new(0,10)

-- Prediction toggle
local predToggle = Instance.new("TextButton", frame)
predToggle.Size = UDim2.new(0.9,0,0,28)
predToggle.Position = UDim2.new(0.05,0,0,85)
predToggle.Text = "PREDICTION : OFF"
predToggle.Font = Enum.Font.GothamBold
predToggle.TextSize = 12
predToggle.TextColor3 = Color3.new(1,1,1)
predToggle.BackgroundColor3 = Color3.fromRGB(80,0,0)
Instance.new("UICorner", predToggle).CornerRadius = UDim.new(0,8)

local function makeLabel(text,y)
	local l = Instance.new("TextLabel", frame)
	l.Size = UDim2.new(0.9,0,0,18)
	l.Position = UDim2.new(0.05,0,0,y)
	l.Text = text
	l.TextColor3 = Color3.new(1,1,1)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.Gotham
	l.TextSize = 12
	l.TextXAlignment = Enum.TextXAlignment.Left
	return l
end

local fovLabel    = makeLabel("FOV : 220", 125)
local speedLabel  = makeLabel("SPEED : 0.35", 175)
local heightLabel = makeLabel("HEIGHT : 1.5", 225)
local offsetLabel = makeLabel("FOV OFFSET : 12", 275)

local function makeSlider(y)
	local bg = Instance.new("Frame", frame)
	bg.Size = UDim2.new(0.9,0,0,6)
	bg.Position = UDim2.new(0.05,0,0,y)
	bg.BackgroundColor3 = Color3.fromRGB(60,60,60)
	Instance.new("UICorner", bg).CornerRadius = UDim.new(1,0)

	local bar = Instance.new("Frame", bg)
	bar.Size = UDim2.new(0.5,0,1,0)
	bar.BackgroundColor3 = Color3.fromRGB(0,170,0)
	Instance.new("UICorner", bar).CornerRadius = UDim.new(1,0)

	return bg,bar
end

local fovBG,fovBar = makeSlider(150)
local spdBG,spdBar = makeSlider(200)
local hBG,hBar     = makeSlider(250)
local offBG,offBar = makeSlider(300)

-- ================= FOV CIRCLE =================
local FOVCircle = Instance.new("Frame", gui)
FOVCircle.BackgroundTransparency = 1
FOVCircle.ZIndex = 999999
local stroke = Instance.new("UIStroke", FOVCircle)
stroke.Thickness = 2
stroke.Color = Color3.fromRGB(0,255,0)
stroke.Transparency = 0.2
local corner = Instance.new("UICorner", FOVCircle)
corner.CornerRadius = UDim.new(1,0)

-- ================= TARGET =================
local function getTarget()
	local best, dist = nil, math.huge
	for _,p in pairs(Players:GetPlayers()) do
		if p~=LocalPlayer and p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
			local hrp = p.Character.HumanoidRootPart
			local hum = p.Character:FindFirstChildWhichIsA("Humanoid")
			if hum and hum.Health > 0 then
				local camDist = (Camera.CFrame.Position - hrp.Position).Magnitude
				local dynHeight = math.clamp(camDist * DIST_HEIGHT_MULT, 0, DIST_HEIGHT_MAX)

				local pos = hrp.Position + Vector3.new(0, HEIGHT_OFFSET + dynHeight, 0)
				local s,on = Camera:WorldToViewportPoint(pos)
				if on then
					local d = (Vector2.new(s.X,s.Y) - Vector2.new(mouse.X, mouse.Y + FOV_Y_OFFSET)).Magnitude
					if d < (FOV_RADIUS+RADIUS_OFFSET) and d < dist then
						dist = d
						best = hrp
					end
				end
			end
		end
	end
	return best
end

-- ================= AIM LOOP =================
RunService.RenderStepped:Connect(function(dt)
	FOVCircle.Size = UDim2.new(0,(FOV_RADIUS+RADIUS_OFFSET)*2,0,(FOV_RADIUS+RADIUS_OFFSET)*2)
	FOVCircle.Position = UDim2.new(
		0, mouse.X - (FOV_RADIUS + RADIUS_OFFSET),
		0, (mouse.Y - (FOV_RADIUS + RADIUS_OFFSET)) + FOV_Y_OFFSET
	)

	if not AIM_ENABLED or AIM_PAUSED then
		FOVCircle.Visible = false
		return
	end

	FOVCircle.Visible = true

	if not target or not STICKY_LOCK then
		target = getTarget()
		LOCKED_OFFSET = FOV_Y_OFFSET
	end

	if target then
		local camDist = (Camera.CFrame.Position - target.Position).Magnitude
		local dynHeight = math.clamp(camDist * DIST_HEIGHT_MULT, 0, DIST_HEIGHT_MAX)

		local basePos = target.Position + Vector3.new(0, HEIGHT_OFFSET + dynHeight, 0)

		-- ================= PREDICTION LOGIC =================
		if PREDICTION_ENABLED then
			local t = tick()
			if not lastPos[target] then
				lastPos[target] = target.Position
				lastTime[target] = t
			end

			local dtp = t - (lastTime[target] or t)
			if dtp > 0 then
				local velocity = (target.Position - lastPos[target]) / dtp
				basePos = basePos + (velocity * PREDICTION_MULT)
				lastPos[target] = target.Position
				lastTime[target] = t
			end
		end
		-- ====================================================

		local s,on = Camera:WorldToViewportPoint(basePos)
		if on then
			local dist = (Vector2.new(s.X,s.Y) - Vector2.new(mouse.X, mouse.Y + LOCKED_OFFSET)).Magnitude
			if dist > ((FOV_RADIUS+RADIUS_OFFSET) * OUTSIDE_FOV_LIMIT) then return end

			local magnet = AIM_SPEED
			if dist <= (FOV_RADIUS+RADIUS_OFFSET) then
				magnet = AIM_SPEED * INNER_FOV_MULTIPLIER
			end

			local dx = (s.X - mouse.X) * magnet
			local dy = (s.Y - (mouse.Y + LOCKED_OFFSET)) * magnet

			pcall(function()
				if mousemoverel then
					mousemoverel(dx,dy)
				elseif syn and syn.mouse_move then
					syn.mouse_move(dx,dy)
				else
					VirtualInputManager:SendMouseMoveEvent(mouse.X+dx, mouse.Y+dy, 0)
				end
			end)
		end
	end
end)

-- ================= GUI TOGGLE =================
toggle.MouseButton1Click:Connect(function()
	AIM_ENABLED = not AIM_ENABLED
	if AIM_ENABLED then
		toggle.Text = "AIM : ON"
		toggle.BackgroundColor3 = Color3.fromRGB(0,170,0)
	else
		toggle.Text = "AIM : OFF"
		toggle.BackgroundColor3 = Color3.fromRGB(140,0,0)
	end
end)

-- Prediction toggle
predToggle.MouseButton1Click:Connect(function()
	PREDICTION_ENABLED = not PREDICTION_ENABLED
	if PREDICTION_ENABLED then
		predToggle.Text = "PREDICTION : ON"
		predToggle.BackgroundColor3 = Color3.fromRGB(0,120,0)
	else
		predToggle.Text = "PREDICTION : OFF"
		predToggle.BackgroundColor3 = Color3.fromRGB(80,0,0)
	end
end)

-- ================= KEY TOGGLE (Q) =================
UIS.InputBegan:Connect(function(i,gp)
	if gp then return end

	if i.KeyCode == Enum.KeyCode.Q then
		AIM_ENABLED = not AIM_ENABLED
		if AIM_ENABLED then
			toggle.Text = "AIM : ON"
			toggle.BackgroundColor3 = Color3.fromRGB(0,170,0)
		else
			toggle.Text = "AIM : OFF"
			toggle.BackgroundColor3 = Color3.fromRGB(140,0,0)
		end
	end

	-- RMB HOLD = PAUSE AIM
	if i.UserInputType == Enum.UserInputType.MouseButton2 then
		RMB_HOLD = true
		AIM_PAUSED = true
	end
end)

UIS.InputEnded:Connect(function(i)
	if i.UserInputType == Enum.UserInputType.MouseButton2 then
		RMB_HOLD = false
		AIM_PAUSED = false
	end
end)

-- ================= SLIDER =================
local draggingF, draggingS, draggingH, draggingO = false,false,false,false

fovBG.InputBegan:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 then draggingF=true end end)
spdBG.InputBegan:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 then draggingS=true end end)
hBG.InputBegan:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 then draggingH=true end end)
offBG.InputBegan:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 then draggingO=true end end)

UIS.InputEnded:Connect(function(i)
	if i.UserInputType==Enum.UserInputType.MouseButton1 then
		draggingF=false draggingS=false draggingH=false draggingO=false
	end
end)

RunService.RenderStepped:Connect(function()
	if draggingF then
		local x = math.clamp((mouse.X - fovBG.AbsolutePosition.X)/fovBG.AbsoluteSize.X,0,1)
		fovBar.Size = UDim2.new(x,0,1,0)
		FOV_RADIUS = math.floor(80 + (x*420))
		fovLabel.Text = "FOV : "..FOV_RADIUS
	end
	if draggingS then
		local x = math.clamp((mouse.X - spdBG.AbsolutePosition.X)/spdBG.AbsoluteSize.X,0,1)
		spdBar.Size = UDim2.new(x,0,1,0)
		AIM_SPEED = tonumber(string.format("%.2f",0.05 + (x*0.9)))
		speedLabel.Text = "SPEED : "..AIM_SPEED
	end
	if draggingH then
		local x = math.clamp((mouse.X - hBG.AbsolutePosition.X)/hBG.AbsoluteSize.X,0,1)
		hBar.Size = UDim2.new(x,0,1,0)
		HEIGHT_OFFSET = tonumber(string.format("%.2f",-2 + (x*8)))
		heightLabel.Text = "HEIGHT : "..HEIGHT_OFFSET
	end
	if draggingO then
		local x = math.clamp((mouse.X - offBG.AbsolutePosition.X)/offBG.AbsoluteSize.X,0,1)
		offBar.Size = UDim2.new(x,0,1,0)
		FOV_Y_OFFSET = math.floor(-60 + (x*120))
		offsetLabel.Text = "FOV OFFSET : "..FOV_Y_OFFSET
	end
end)

print("🔥 CURSOR AIMLOCK FINAL FULL SYSTEM LOADED (Q TOGGLE + RMB AUTO PAUSE + PREDICTION SYSTEM)")

-- ================= SAVE / LOAD + VISIBILITY SYSTEM =================
local SAVE_FILE = "cursor_aimlock_settings.json"

-- STATE EXTRA
local FOV_VISIBLE = true
local GUI_VISIBLE = true

-- ================= EXTRA GUI BUTTON =================
local fovToggleBtn = Instance.new("TextButton", frame)
fovToggleBtn.Size = UDim2.new(0.9,0,0,28)
fovToggleBtn.Position = UDim2.new(0.05,0,0,330)
fovToggleBtn.Text = "FOV : ON"
fovToggleBtn.Font = Enum.Font.GothamBold
fovToggleBtn.TextSize = 12
fovToggleBtn.TextColor3 = Color3.new(1,1,1)
fovToggleBtn.BackgroundColor3 = Color3.fromRGB(0,120,0)
Instance.new("UICorner", fovToggleBtn).CornerRadius = UDim.new(0,8)

-- ================= SETTINGS TABLE =================
local Settings = {
	AIM_ENABLED = AIM_ENABLED,
	FOV_RADIUS = FOV_RADIUS,
	AIM_SPEED = AIM_SPEED,
	HEIGHT_OFFSET = HEIGHT_OFFSET,
	FOV_Y_OFFSET = FOV_Y_OFFSET,
	PREDICTION_ENABLED = PREDICTION_ENABLED,
	FOV_VISIBLE = true,
	GUI_VISIBLE = true
}

-- ================= SAVE =================
local function SaveSettings()
	Settings.AIM_ENABLED = AIM_ENABLED
	Settings.FOV_RADIUS = FOV_RADIUS
	Settings.AIM_SPEED = AIM_SPEED
	Settings.HEIGHT_OFFSET = HEIGHT_OFFSET
	Settings.FOV_Y_OFFSET = FOV_Y_OFFSET
	Settings.PREDICTION_ENABLED = PREDICTION_ENABLED
	Settings.FOV_VISIBLE = FOV_VISIBLE
	Settings.GUI_VISIBLE = GUI_VISIBLE

	local data = HttpService:JSONEncode(Settings)
	pcall(function()
		writefile(SAVE_FILE, data)
	end)
end

-- ================= LOAD =================
local function LoadSettings()
	if isfile and isfile(SAVE_FILE) then
		local raw = readfile(SAVE_FILE)
		local data = HttpService:JSONDecode(raw)

		AIM_ENABLED = data.AIM_ENABLED
		FOV_RADIUS = data.FOV_RADIUS
		AIM_SPEED = data.AIM_SPEED
		HEIGHT_OFFSET = data.HEIGHT_OFFSET
		FOV_Y_OFFSET = data.FOV_Y_OFFSET
		PREDICTION_ENABLED = data.PREDICTION_ENABLED
		FOV_VISIBLE = data.FOV_VISIBLE
		GUI_VISIBLE = data.GUI_VISIBLE

		-- apply visuals
		gui.Enabled = GUI_VISIBLE
		FOVCircle.Visible = FOV_VISIBLE

		-- update buttons
		toggle.Text = AIM_ENABLED and "AIM : ON" or "AIM : OFF"
		toggle.BackgroundColor3 = AIM_ENABLED and Color3.fromRGB(0,170,0) or Color3.fromRGB(140,0,0)

		predToggle.Text = PREDICTION_ENABLED and "PREDICTION : ON" or "PREDICTION : OFF"
		predToggle.BackgroundColor3 = PREDICTION_ENABLED and Color3.fromRGB(0,120,0) or Color3.fromRGB(80,0,0)

		fovToggleBtn.Text = FOV_VISIBLE and "FOV : ON" or "FOV : OFF"
		fovToggleBtn.BackgroundColor3 = FOV_VISIBLE and Color3.fromRGB(0,120,0) or Color3.fromRGB(120,0,0)

		fovLabel.Text = "FOV : "..FOV_RADIUS
		speedLabel.Text = "SPEED : "..AIM_SPEED
		heightLabel.Text = "HEIGHT : "..HEIGHT_OFFSET
		offsetLabel.Text = "FOV OFFSET : "..FOV_Y_OFFSET
	end
end

LoadSettings()

-- ================= AUTO SAVE LOOP =================
task.spawn(function()
	while true do
		task.wait(2)
		SaveSettings()
	end
end)

-- ================= FOV TOGGLE (GUI) =================
fovToggleBtn.MouseButton1Click:Connect(function()
	FOV_VISIBLE = not FOV_VISIBLE
	FOVCircle.Visible = FOV_VISIBLE

	if FOV_VISIBLE then
		fovToggleBtn.Text = "FOV : ON"
		fovToggleBtn.BackgroundColor3 = Color3.fromRGB(0,120,0)
	else
		fovToggleBtn.Text = "FOV : OFF"
		fovToggleBtn.BackgroundColor3 = Color3.fromRGB(120,0,0)
	end
end)

-- ================= HIDE MENU KEY (Z) =================
UIS.InputBegan:Connect(function(i,gp)
	if gp then return end

	if i.KeyCode == Enum.KeyCode.Z then
		GUI_VISIBLE = not GUI_VISIBLE
		gui.Enabled = GUI_VISIBLE
	end
end)

print("💾 AUTO SAVE SETTINGS ACTIVE")
print("📂 AUTO LOAD SETTINGS ACTIVE")
print("👁️ FOV TOGGLE VIA GUI BUTTON")
print("🧩 Z = HIDE/SHOW MENU")
