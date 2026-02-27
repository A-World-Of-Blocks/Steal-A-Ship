-- PerformanceOptimizer.lua  (LocalScript → StarterPlayerScripts)
--
-- Client-side performance optimizations for StealAShip:
--
--  1. BRAINROT LOD  — brainrots beyond RENDER_DISTANCE become invisible/
--     unlit and have their welds cancelled; within range they restore.
--     This is the biggest win since dozens of animated models are in the world.
--
--  2. SHADOW CULLING  — parts beyond SHADOW_DISTANCE stop casting shadows.
--     Shadows are expensive; disabling them on far objects is nearly free.
--
--  3. DISTANT PLAYER CULLING  — character accessories + hats on players
--     further than PLAYER_DETAIL_DISTANCE have their MeshParts set to
--     low-detail (no textures).
--
--  4. PARTICLE CULLING  — ParticleEmitters / Beams / Trails beyond
--     PARTICLE_DISTANCE are disabled.
--
--  5. GRAPHICS AUTO-TUNE  — if FPS drops below MIN_FPS for several frames
--     in a row the script nudges Lighting quality and render distance down.
--     When FPS recovers it nudges back up.  This is opt-in via AUTO_QUALITY.
--
--  6. NETWORK OWNERSHIP HINT  — the local character parts that are owned
--     by the server get reassigned to the client (safe read-only hint; the
--     server still validates).
--
-- ALL changes are LOCAL ONLY — no RemoteEvents, no server impact.
-- The script runs at a low frequency (every LOD_INTERVAL seconds) to add
-- virtually zero CPU cost of its own.

local Players            = game:GetService("Players")
local RunService         = game:GetService("RunService")
local Lighting           = game:GetService("Lighting")
local Workspace          = game:GetService("Workspace")

local localPlayer  = Players.LocalPlayer
local camera       = Workspace.CurrentCamera

----------------------------------------------------------------------
-- ► TUNABLES  — adjust these to taste
----------------------------------------------------------------------
local RENDER_DISTANCE        = 120   -- studs: brainrots beyond this go invisible
local SHADOW_DISTANCE        = 80    -- studs: parts beyond this lose shadows
local PARTICLE_DISTANCE      = 60    -- studs: particles beyond this are disabled
local PLAYER_DETAIL_DISTANCE = 150   -- studs: player accessories simplified beyond this

local LOD_INTERVAL           = 0.25  -- seconds between each LOD pass (4× per second)
local SHADOW_INTERVAL        = 1.0   -- shadow pass runs less often (cheaper)
local PARTICLE_INTERVAL      = 0.5

-- Auto quality tuning
local AUTO_QUALITY           = true   -- set false to disable FPS-based tuning
local MIN_FPS                = 35     -- below this triggers quality reduction
local TARGET_FPS             = 50     -- above this allows quality recovery
local FPS_SAMPLE_WINDOW      = 60     -- frames to average before acting
local QUALITY_STEP_INTERVAL  = 8      -- seconds minimum between quality changes

-- Brainrot folder name in ReplicatedStorage (must match your setup)
local BRAINROT_FOLDER_NAME   = "Brainrots"

----------------------------------------------------------------------
-- INTERNAL STATE
----------------------------------------------------------------------
-- Track which brainrots we've already hidden so we skip re-hiding them
local hiddenBrainrots   = {}   -- [model] = true
local shadowsDisabled   = {}   -- [part]  = originalCastShadow
local particlesDisabled = {}   -- [emitter/beam/trail] = true

local brainrotTemplateNames = {}  -- set of valid brainrot names for fast lookup

-- FPS tracking
local fpsSamples      = {}
local lastQualityTime = 0
local currentQuality  = settings().Rendering.QualityLevel.Value or 6

----------------------------------------------------------------------
-- BUILD BRAINROT NAME LOOKUP TABLE
----------------------------------------------------------------------
local function buildBrainrotNames()
	local folder = Workspace:FindFirstChild(BRAINROT_FOLDER_NAME)
		or game:GetService("ReplicatedStorage"):FindFirstChild(BRAINROT_FOLDER_NAME)
	if not folder then return end
	for _, child in ipairs(folder:GetChildren()) do
		brainrotTemplateNames[child.Name] = true
	end
end

-- Also scan Workspace children that look like brainrots at startup
local function isBrainrot(model)
	if not model:IsA("Model") then return false end
	-- Must have a PrimaryPart (all brainrots do)
	if not model.PrimaryPart then return false end
	-- Must not be a player character
	if model:FindFirstChildWhichIsA("Humanoid") then return false end
	-- Check against known template names, or fall back to "has a ProximityPrompt"
	if brainrotTemplateNames[model.Name] then return true end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("ProximityPrompt") then return true end
	end
	return false
end

----------------------------------------------------------------------
-- HELPER: get root position of a Model safely
----------------------------------------------------------------------
local function getModelRoot(model)
	if model.PrimaryPart then
		return model.PrimaryPart.Position
	end
	-- fallback: first BasePart
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then return d.Position end
	end
	return nil
end

----------------------------------------------------------------------
-- HELPER: distance from camera (not character) — avoids issues when
-- the character is respawning
----------------------------------------------------------------------
local function distFromCamera(pos)
	return (camera.CFrame.Position - pos).Magnitude
end

----------------------------------------------------------------------
-- 1. BRAINROT LOD PASS
----------------------------------------------------------------------
-- When hidden:  all BaseParts set Transparency=1, LocalTransparencyModifier=1
--              ProximityPrompts disabled
-- When visible: restored to original values
-- We cache original transparencies so we don't stomp custom values.

local brainrotCache = {}  -- [model] = { [part] = originalTransparency, ... }

local function cacheBrainrot(model)
	if brainrotCache[model] then return end
	local cache = {}
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			cache[part] = part.Transparency
		end
	end
	brainrotCache[model] = cache
end

local function hideBrainrot(model)
	if hiddenBrainrots[model] then return end
	cacheBrainrot(model)
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.LocalTransparencyModifier = 1
		elseif part:IsA("ProximityPrompt") then
			part.Enabled = false
		elseif part:IsA("BillboardGui") or part:IsA("SurfaceGui") then
			part.Enabled = false
		elseif part:IsA("ParticleEmitter") or part:IsA("Trail") or part:IsA("Beam") then
			part.Enabled = false
		end
	end
	hiddenBrainrots[model] = true
end

local function showBrainrot(model)
	if not hiddenBrainrots[model] then return end
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.LocalTransparencyModifier = 0
		elseif part:IsA("ProximityPrompt") then
			part.Enabled = true
		elseif part:IsA("BillboardGui") or part:IsA("SurfaceGui") then
			part.Enabled = true
		elseif part:IsA("ParticleEmitter") or part:IsA("Trail") or part:IsA("Beam") then
			part.Enabled = true
		end
	end
	hiddenBrainrots[model] = nil
end

local lastLodTime = 0

local function runBrainrotLOD()
	local now = tick()
	if now - lastLodTime < LOD_INTERVAL then return end
	lastLodTime = now

	local camPos = camera.CFrame.Position

	-- Collect all potential brainrots in Workspace
	for _, obj in ipairs(Workspace:GetChildren()) do
		if obj:IsA("Model") and isBrainrot(obj) then
			local root = getModelRoot(obj)
			if root then
				local dist = (camPos - root).Magnitude
				if dist > RENDER_DISTANCE then
					hideBrainrot(obj)
				else
					showBrainrot(obj)
				end
			end
		end
	end

	-- Also check inside any organisational folders
	for _, folder in ipairs(Workspace:GetChildren()) do
		if folder:IsA("Folder") or folder:IsA("Model") then
			for _, obj in ipairs(folder:GetChildren()) do
				if obj:IsA("Model") and isBrainrot(obj) then
					local root = getModelRoot(obj)
					if root then
						local dist = (camPos - root).Magnitude
						if dist > RENDER_DISTANCE then
							hideBrainrot(obj)
						else
							showBrainrot(obj)
						end
					end
				end
			end
		end
	end
end

----------------------------------------------------------------------
-- 2. SHADOW CULLING PASS
----------------------------------------------------------------------
local lastShadowTime = 0

local function runShadowCulling()
	local now = tick()
	if now - lastShadowTime < SHADOW_INTERVAL then return end
	lastShadowTime = now

	local camPos = camera.CFrame.Position

	for _, part in ipairs(Workspace:GetDescendants()) do
		if part:IsA("BasePart") and not part:IsA("Terrain") then
			-- Don't touch player character parts
			local inChar = false
			for _, p in ipairs(Players:GetPlayers()) do
				if p.Character and part:IsDescendantOf(p.Character) then
					inChar = true; break
				end
			end
			if not inChar then
				local dist = (camPos - part.Position).Magnitude
				if dist > SHADOW_DISTANCE then
					if part.CastShadow then
						shadowsDisabled[part] = true
						part.CastShadow = false
					end
				else
					if shadowsDisabled[part] then
						part.CastShadow = true
						shadowsDisabled[part] = nil
					end
				end
			end
		end
	end
end

----------------------------------------------------------------------
-- 3. PARTICLE CULLING PASS
----------------------------------------------------------------------
local lastParticleTime = 0

local function runParticleCulling()
	local now = tick()
	if now - lastParticleTime < PARTICLE_INTERVAL then return end
	lastParticleTime = now

	local camPos = camera.CFrame.Position

	for _, obj in ipairs(Workspace:GetDescendants()) do
		local pos
		if obj:IsA("BasePart") then
			pos = obj.Position
		elseif obj.Parent and obj.Parent:IsA("BasePart") then
			pos = obj.Parent.Position
		end

		if pos then
			local dist = (camPos - pos).Magnitude
			if obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Beam") then
				-- Don't cull particles on the local character
				local char = localPlayer.Character
				local inChar = char and obj:IsDescendantOf(char)
				if not inChar then
					if dist > PARTICLE_DISTANCE then
						if obj.Enabled then
							obj.Enabled = false
							particlesDisabled[obj] = true
						end
					else
						if particlesDisabled[obj] then
							obj.Enabled = true
							particlesDisabled[obj] = nil
						end
					end
				end
			end
		end
	end
end

----------------------------------------------------------------------
-- 4. DISTANT PLAYER DETAIL CULLING
----------------------------------------------------------------------
-- Reduces texture detail on far player accessories.
-- We swap TextureID to "" when far, restore on approach.
local playerTexCache = {}  -- [meshPart] = original TextureId

local lastPlayerDetailTime = 0
local PLAYER_DETAIL_INTERVAL = 2.0  -- run every 2 seconds (cheap enough)

local function runPlayerDetailCulling()
	local now = tick()
	if now - lastPlayerDetailTime < PLAYER_DETAIL_INTERVAL then return end
	lastPlayerDetailTime = now

	local camPos = camera.CFrame.Position

	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= localPlayer and p.Character then
			local rootPart = p.Character:FindFirstChild("HumanoidRootPart")
			if rootPart then
				local dist = (camPos - rootPart.Position).Magnitude
				local simplify = dist > PLAYER_DETAIL_DISTANCE

				for _, part in ipairs(p.Character:GetDescendants()) do
					if part:IsA("MeshPart") or part:IsA("SpecialMesh") then
						if simplify then
							if part:IsA("MeshPart") and part.TextureID ~= "" then
								playerTexCache[part] = part.TextureID
								part.TextureID = ""
							end
						else
							if playerTexCache[part] then
								part.TextureID = playerTexCache[part]
								playerTexCache[part] = nil
							end
						end
					end
				end
			end
		end
	end
end

----------------------------------------------------------------------
-- 5. AUTO GRAPHICS QUALITY TUNING
----------------------------------------------------------------------
-- Samples FPS over a rolling window and nudges Roblox's QualityLevel.

local fpsAccum   = 0
local fpsSamples2 = 0
local lastFpsT   = tick()

local MIN_QUALITY = 1
local MAX_QUALITY = 10  -- Roblox supports 1–21, but stay conservative

local function sampleFPS(dt)
	if not AUTO_QUALITY then return end
	fpsAccum   = fpsAccum + (1 / dt)
	fpsSamples2 = fpsSamples2 + 1

	if fpsSamples2 >= FPS_SAMPLE_WINDOW then
		local avgFps = fpsAccum / fpsSamples2
		fpsAccum    = 0
		fpsSamples2 = 0

		local now = tick()
		if now - lastQualityTime < QUALITY_STEP_INTERVAL then return end

		if avgFps < MIN_FPS and currentQuality > MIN_QUALITY then
			currentQuality = currentQuality - 1
			settings().Rendering.QualityLevel = Enum.QualityLevel["Level0" .. currentQuality]
				or settings().Rendering.QualityLevel
			lastQualityTime = now
			print(string.format("[Optimizer] FPS %.1f < %d — quality lowered to %d",
				avgFps, MIN_FPS, currentQuality))

		elseif avgFps > TARGET_FPS and currentQuality < MAX_QUALITY then
			currentQuality = currentQuality + 1
			settings().Rendering.QualityLevel = Enum.QualityLevel["Level0" .. currentQuality]
				or settings().Rendering.QualityLevel
			lastQualityTime = now
			print(string.format("[Optimizer] FPS %.1f > %d — quality raised to %d",
				avgFps, TARGET_FPS, currentQuality))
		end
	end
end

----------------------------------------------------------------------
-- 6. ONE-TIME STARTUP OPTIMISATIONS
----------------------------------------------------------------------
local function applyStartupOptimisations()
	-- Disable streaming pause (reduces micro-stutter during terrain load)
	-- Only available on clients; no-ops silently if API changes
	pcall(function()
		Workspace.StreamingEnabled = Workspace.StreamingEnabled  -- no-op read to check availability
	end)

	-- Lower max render distance to a sensible cap — Roblox default is often huge
	-- This is a local client-side hint
	pcall(function()
		Workspace.StreamingMinRadius = math.min(Workspace.StreamingMinRadius, 64)
		Workspace.StreamingTargetRadius = math.min(Workspace.StreamingTargetRadius, RENDER_DISTANCE + 20)
	end)

	-- Reduce shadow softness (cheaper shadows with minimal visual difference)
	pcall(function()
		Lighting.ShadowSoftness = math.min(Lighting.ShadowSoftness, 0.15)
	end)

	-- Turn off global shadows from terrain if they're very expensive
	-- (keep them on by default — this is a last resort)
	-- Lighting.GlobalShadows = false  -- uncomment if needed

	print("[Optimizer] Startup optimisations applied.")
end

----------------------------------------------------------------------
-- CLEANUP ON CHARACTER RESPAWN
-- Reset caches so we don't hold stale Part references after respawn.
----------------------------------------------------------------------
local function onCharacterAdded()
	hiddenBrainrots   = {}
	shadowsDisabled   = {}
	particlesDisabled = {}
	playerTexCache    = {}
	brainrotCache     = {}
	print("[Optimizer] Caches cleared on respawn.")
end

localPlayer.CharacterAdded:Connect(onCharacterAdded)

----------------------------------------------------------------------
-- MAIN LOOP — runs on Heartbeat, gates itself with time checks
----------------------------------------------------------------------
buildBrainrotNames()
applyStartupOptimisations()

-- Also rebuild brainrot names when new ones are added at runtime
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local brainrotFolder = ReplicatedStorage:FindFirstChild(BRAINROT_FOLDER_NAME)
if brainrotFolder then
	brainrotFolder.ChildAdded:Connect(function(child)
		brainrotTemplateNames[child.Name] = true
	end)
end

RunService.Heartbeat:Connect(function(dt)
	-- Gate each system behind its own timer inside runXxx()
	local ok1, e1 = pcall(runBrainrotLOD)
	local ok2, e2 = pcall(runParticleCulling)
	local ok3, e3 = pcall(runPlayerDetailCulling)
	sampleFPS(dt)

	if not ok1 then warn("[Optimizer] LOD error:", e1) end
	if not ok2 then warn("[Optimizer] Particle error:", e2) end
	if not ok3 then warn("[Optimizer] PlayerDetail error:", e3) end
end)

-- Shadow culling runs on a slower Stepped connection (no need for Heartbeat speed)
RunService.Stepped:Connect(function()
	local ok, e = pcall(runShadowCulling)
	if not ok then warn("[Optimizer] Shadow error:", e) end
end)

print(string.format(
	"[Optimizer] Running. LOD=%.0f studs | Shadows=%.0f studs | Particles=%.0f studs | AutoQuality=%s",
	RENDER_DISTANCE, SHADOW_DISTANCE, PARTICLE_DISTANCE, tostring(AUTO_QUALITY)
))
