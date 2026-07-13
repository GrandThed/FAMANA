-- Feedback for the LOCAL player getting hit by an enemy: a quick red screen
-- vignette, a small camera shake, a distinct "hurt" sound (see Sfx.lua), and
-- gamepad rumble if a controller is connected. All driven off the local
-- Humanoid's own Health property dropping — no new remote needed, Health
-- already replicates to its owning client.
--
-- Mobile/touch has no public Roblox API for device vibration (HapticService
-- only drives gamepad rumble motors), so on phone this reduces to the flash
-- + sound, same as keyboard/mouse.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local HapticService = game:GetService("HapticService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Sfx = require(script.Parent.Sfx)

local player = Players.LocalPlayer

local PlayerHurtFeedbackUI = {}

local FLASH_IN_TIME = 0.05
local FLASH_OUT_TIME = 0.35
local FLASH_PEAK_TRANSPARENCY = 0.72 -- lower = more intense flash
local SHAKE_TIME = 0.18
local SHAKE_MAGNITUDE = 0.15 -- studs of camera offset at the start of the shake
local RUMBLE_TIME = 0.15
local RUMBLE_STRENGTH = 0.6
local MIN_SFX_GAP = 0.15 -- avoid a sound-spam wall on multi-hit ticks

local function buildVignette()
	local gui = Instance.new("ScreenGui")
	gui.Name = "HurtVignette"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")

	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(1, 0, 1, 0)
	frame.BackgroundColor3 = Color3.fromRGB(180, 20, 20)
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Parent = gui
	return frame
end

local flashTween
local function flash(frame)
	if flashTween then
		flashTween:Cancel()
	end
	frame.BackgroundTransparency = 1
	local flashIn = TweenService:Create(frame, TweenInfo.new(FLASH_IN_TIME, Enum.EasingStyle.Quad), {
		BackgroundTransparency = FLASH_PEAK_TRANSPARENCY,
	})
	flashTween = flashIn
	flashIn:Play()
	flashIn.Completed:Once(function()
		local flashOut = TweenService:Create(frame, TweenInfo.new(FLASH_OUT_TIME, Enum.EasingStyle.Quad), {
			BackgroundTransparency = 1,
		})
		flashTween = flashOut
		flashOut:Play()
	end)
end

-- Brief random camera-offset shake, additive on top of whatever the camera's
-- CFrame already is that frame, self-cleaning after SHAKE_TIME. A `token`
-- guards against two shakes overlapping and fighting each other.
local shakeToken = 0
local function shakeCamera()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	shakeToken += 1
	local myToken = shakeToken
	local startTime = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		if myToken ~= shakeToken then
			connection:Disconnect()
			return
		end
		local elapsed = os.clock() - startTime
		if elapsed >= SHAKE_TIME then
			connection:Disconnect()
			return
		end
		local falloff = 1 - (elapsed / SHAKE_TIME)
		local offset = Vector3.new(
			(math.random() - 0.5) * SHAKE_MAGNITUDE * falloff,
			(math.random() - 0.5) * SHAKE_MAGNITUDE * falloff,
			0
		)
		camera.CFrame *= CFrame.new(offset)
	end)
end

-- Gamepad rumble, if a controller is connected — silently does nothing on
-- keyboard/mouse or touch (mobile has no equivalent to fall back to).
local function rumble()
	for _, gamepad in ipairs(UserInputService:GetConnectedGamepads()) do
		if HapticService:IsMotorSupported(gamepad, Enum.VibrationMotor.Large) then
			HapticService:SetMotor(gamepad, Enum.VibrationMotor.Large, RUMBLE_STRENGTH)
			task.delay(RUMBLE_TIME, function()
				HapticService:SetMotor(gamepad, Enum.VibrationMotor.Large, 0)
			end)
		end
	end
end

function PlayerHurtFeedbackUI.start()
	local vignette = buildVignette()

	local function onCharacterAdded(character)
		local humanoid = character:WaitForChild("Humanoid")
		local lastHealth = humanoid.Health

		humanoid.HealthChanged:Connect(function(newHealth)
			if newHealth < lastHealth then
				flash(vignette)
				shakeCamera()
				Sfx.playThrottled("hurt", MIN_SFX_GAP)
				rumble()
			end
			lastHealth = newHealth
		end)
	end

	if player.Character then
		onCharacterAdded(player.Character)
	end
	player.CharacterAdded:Connect(onCharacterAdded)
end

return PlayerHurtFeedbackUI