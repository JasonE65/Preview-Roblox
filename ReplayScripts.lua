--[[

Replay System
Author: Jason

An replay system that that allows players to go back in "time"
Features:
- Records Pos of Player every 0.1 seconds.
- Stores last 10 seconds in an Buffer
- Ghost visualization showing old positions
- Trails to sw path of player
- Smooth timeline with lerp

Structure: 
- Config : ReplicatdStorage/ReplaySystem/Config
- ReplayBuffer : ReplicatdStorage/ReplaySystem/ReplayBuffer
- GhostController : ReplicatdStorage/ReplaySystem/GhostController
- TrailRenderer : ReplicatedStorage/ReplaySystem/TrailRenderer
- Server script for recording and tps : ServerScriptService/ReplaySystem
- Client script for UI and ghost handeling : StarterPlayer/StarterPlayerScripts/ReplayClient
]]

-- CONFIG MODULE -- 

--[[
Config Module
This holds all settings for my Replay System
So I dont have to edit my other scripts again

]]

local Config = {}

-- Recording Settings
Config.RECORD_RATE = 10
Config.MAX_DURATION = 10
Config.MAX_FRAMES = Config.RECORD_RATE * Config.MAX_DURATION

-- Ghost Settings
Config.GHOST_TRANSPARENCY = 0.5
Config.GHOST_COLOR = Color3.fromRGB(0, 150, 255)
Config.GHOST_MATERIAL = Enum.Material.Neon
Config.LERP_SPEED = 0.3

-- Body Part Sizes if the clone fails
Config.BODY_PARTS = {
	HumanoidRootPart = {Size = Vector3.new(2, 2, 1), Offset = CFrame.new(0, 0, 0)},
	Head = {Size = Vector3.new(1.2, 1.2, 1.2), Offset = CFrame.new(0, 1.6, 0), Shape = Enum.PartType.Ball},
	LeftArm = {Size = Vector3.new(0.5, 1.5, 0.5), Offset = CFrame.new(-1.25, 0, 0)},
	RightArm = {Size = Vector3.new(0.5, 1.5, 0.5), Offset = CFrame.new(1.25, 0, 0)},
	LeftLeg = {Size = Vector3.new(0.5, 1.5, 0.5), Offset = CFrame.new(-0.5, -1.75, 0)},
	RightLeg = {Size = Vector3.new(0.5, 1.5, 0.5), Offset = CFrame.new(0.5, -1.75, 0)},
}

return Config

-- REPLAY BUFFER -- 

--[[
ReplayBuffer Module
Stores the position of a player in an buffer
the buffer overwrites old data if full
So we dont have too much seconds saved

]]
local Config = require(script.Parent.Config)

local ReplayBuffer = {}
ReplayBuffer.__index = ReplayBuffer

-- Creates a new ReplayBuffer
function ReplayBuffer.new()
	local self = setmetatable({}, ReplayBuffer)
	self.frames = {} -- Stores the data of the frames like position
	self.index = 1 -- Current position in the Buffer
	return self
end


-- Adds a new frame to the buffer
function ReplayBuffer:addFrame(frameData)
	self.frames[self.index] = frameData
	self.index = self.index + 1
	if self.index > Config.MAX_FRAMES then
		self.index = 1
	end
end

-- Returns the frames in the correct order
-- Its needed because the buffer overwrites it out of order
function ReplayBuffer:getOrderedFrames()
	local ordered = {}
	for _, frame in pairs(self.frames) do
		table.insert(ordered, frame)
	end
	table.sort(ordered, function(a, b)
		return a.timestamp < b.timestamp
	end)
	return ordered
end

return ReplayBuffer

-- GHOST CONTROLLER -- 

--[[
GhostController Module
Creates and controls the ghost of the Player
The Ghost is a clone of the player with low transparency
It shows where the player was at a specific frame

]]

local Players = game:GetService("Players")
local Config = require(script.Parent.Config)

local GhostController = {}
GhostController.__index = GhostController

-- Creates a new GhostController at that position
function GhostController.new(rootCFrame)
	local self = setmetatable({}, GhostController)

	self.model = nil
	self.rootPart = nil
	self.targetCFrame = rootCFrame

	self:_createModel(rootCFrame)

	return self
end

-- Private Function creates the ghost
function GhostController:_createModel(rootCFrame)
	local character = Players.LocalPlayer.Character
	if not character then return end


	local wasArchivable = character.Archivable
	character.Archivable = true

	self.model = character:Clone()
	
	
	character.Archivable = wasArchivable

	if not self.model then return end

	self.model.Name = "ReplayGhost"

	-- Remove all scripts to prevent unexpected behavior
	for _, desc in pairs(self.model:GetDescendants()) do
		if desc:IsA("Script") or desc:IsA("LocalScript") then
			desc:Destroy()
		end
	end

	-- Find the HRP returns if it doesnt find it
	self.rootPart = self.model:FindFirstChild("HumanoidRootPart")
	if not self.rootPart then 
		self.model:Destroy()
		self.model = nil
		return 
	end

	-- Makes all parts transparent and removes collisions
	for _, part in pairs(self.model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Transparency = Config.GHOST_TRANSPARENCY
			part.CanCollide = false
		end
	end
	
	-- Disable animations
	local humanoid = self.model:FindFirstChild("Humanoid")
	if humanoid then
		humanoid.PlatformStand = true
	end


	self.rootPart.Anchored = true

	self.model.Parent = workspace
end

-- Sets the target pos 
function GhostController:setTarget(cframe)
	if not cframe then return end
	self.targetCFrame = cframe
end

-- Updates the pos with lerp so its smooth
function GhostController:update()
	if not self.model then return end
	if not self.rootPart then return end
	if not self.targetCFrame then return end

	local currentCFrame = self.rootPart.CFrame
	local newCFrame = currentCFrame:Lerp(self.targetCFrame, Config.LERP_SPEED)

	self.rootPart.CFrame = newCFrame
end

-- Deletes the ghost and cleans up
function GhostController:destroy()
	if self.model then
		self.model:Destroy()
		self.model = nil
		self.rootPart = nil
	end
end

return GhostController

-- TRAIL RENDERER --

--[[
TrailRenderer Module
This modules shows where the player walked and visualizes it with lines

]]

local Config = require(script.Parent.Config)

local TrailRenderer = {}
TrailRenderer.__index = TrailRenderer


-- Creates an new TrairlRenderer
function TrailRenderer.new()
	local self = setmetatable({}, TrailRenderer)

	self.points = {}      -- Thats gonna Save all Points
	self.folder = nil     -- Folder for organization

	self:_createFolder()

	return self
end

-- Private function creates the Folder for all Trail parts
function TrailRenderer:_createFolder()
	self.folder = Instance.new("Folder")
	self.folder.Name = "ReplayTrail"
	self.folder.Parent = workspace
end

-- Shows the entire path of the player with the frames
function TrailRenderer:renderPath(frames)
	if not frames then return end
	if #frames < 2 then return end

	-- Generates an ball for every Frame
	for i, frame in ipairs(frames) do
		if not frame.cframe then continue end
		
		local point = Instance.new("Part")
		point.Name = "TrailPoint_" .. i
		point.Size = Vector3.new(0.5, 0.5, 0.5)
		point.Shape = Enum.PartType.Ball
		point.CFrame = frame.cframe
		point.Anchored = true
		point.CanCollide = false
		point.Material = Enum.Material.Neon
		point.Transparency = 0.5 
		point.Color = Config.GHOST_COLOR
		point.Parent = self.folder

		table.insert(self.points, point)
	end
	
	-- Connects all Points with Lines
	self:_connectPoints()
end

    -- Private Function Creates lines between all Points
function TrailRenderer:_connectPoints()
	for i = 1, #self.points - 1 do
		local pointA = self.points[i]
		local pointB = self.points[i + 1]
		-- Calculates the distance between and the Middlepoint of 2 Points
		local distance = (pointA.Position - pointB.Position).Magnitude
		local midPoint = (pointA.Position + pointB.Position) / 2
		-- Creates an Line between the Points
		local line = Instance.new("Part")
		line.Name = "TrailLine_" .. i
		line.Size = Vector3.new(0.2, 0.2, distance)  
		line.CFrame = CFrame.lookAt(midPoint, pointB.Position) -- Rotates the Line to the next point.
		line.Anchored = true
		line.CanCollide = false
		line.Material = Enum.Material.Neon
		line.Transparency = 0.5
		line.Color = Config.GHOST_COLOR
		line.Parent = self.folder
	end
end
-- Deletes the Trail
function TrailRenderer:destroy()
	if self.folder then
		self.folder:Destroy()
		self.folder = nil
	end
	self.points = {}
end

return TrailRenderer

-- REPLAY SYSTEM -- 

--[[ 
ReplaySystem Script
This script handles the recording and replaying of player movements
It uses the ReplayBuffer to store the data
]]



local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")


-- Load Modules
local ReplaySystem = ReplicatedStorage:WaitForChild("ReplaySystem")
local Config = require(ReplaySystem:WaitForChild("Config"))
local ReplayBuffer = require(ReplaySystem:WaitForChild("ReplayBuffer"))

-- Load remotes
local ReplayRemotes = ReplicatedStorage:WaitForChild("ReplayRemotes")
local RequestReplay = ReplayRemotes:WaitForChild("RequestReplay")
local ConfirmRewind = ReplayRemotes:WaitForChild("ConfirmRewind")
local SendFrameData = ReplayRemotes:WaitForChild("SendFrameData")


-- Player data
local playerBuffers = {} -- ReplayBuffer for each player
local lastRecordTime = {} -- Last time a players frame got recorded
local isInReplayMode = {} -- Checks if the player is in replay mode


-- Records a frame
local function recordFrame(player)
	local buffer = playerBuffers[player]
	if not buffer then return end

	local character = player.Character
	if not character then return end

	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then return end
	
	-- Create frameData with time, position and rotation + velocity
	local frameData = {
		timestamp = tick(),
		cframe = humanoidRootPart.CFrame,
		velocity = humanoidRootPart.AssemblyLinearVelocity,
	}

	buffer:addFrame(frameData)
end


-- Starts replay mode for the player
local function startReplay(player)
	local buffer = playerBuffers[player]
	if not buffer then return end

	local frames = buffer:getOrderedFrames()
	
	-- Needs atleast 2 frames for replay
	if #frames < 2 then return end
	
	-- Stops recording
	isInReplayMode[player] = true
	-- Sends data
	SendFrameData:FireClient(player, frames)
end

-- Teleports player to the frame they choose
local function confirmRewind(player, frameIndex)
	local buffer = playerBuffers[player]
	if not buffer then return end

	local frames = buffer:getOrderedFrames()

	if not frames[frameIndex] then return end

	local character = player.Character
	if not character then return end

	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then return end

	local frame = frames[frameIndex]
	
	-- Stops movement before teleporting
	humanoidRootPart.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
	humanoidRootPart.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
	
	-- Teleports character
	character:PivotTo(frame.cframe)
	
	-- Applies velocity
	humanoidRootPart.AssemblyLinearVelocity = frame.velocity
	
	-- Exit replay mode and creates new buffer
	isInReplayMode[player] = false
	playerBuffers[player] = ReplayBuffer.new()
end

-- Creates a buffer for the player on join 
Players.PlayerAdded:Connect(function(player)
	playerBuffers[player] = ReplayBuffer.new()
	isInReplayMode[player] = false
end)

-- Cleanup
Players.PlayerRemoving:Connect(function(player)
	playerBuffers[player] = nil
	lastRecordTime[player] = nil
	isInReplayMode[player] = nil
end)

-- Main loop for recording frames
RunService.Heartbeat:Connect(function()
	for _, player in pairs(Players:GetPlayers()) do
		-- Skip if in Replaymode
		if isInReplayMode[player] then
			continue
		end
		-- Only records at the configured time
		if lastRecordTime[player] then
			if tick() - lastRecordTime[player] < 1 / Config.RECORD_RATE then
				continue
			end
		end

		recordFrame(player)
		lastRecordTime[player] = tick()
	end
end)


-- Handles client request
RequestReplay.OnServerEvent:Connect(startReplay)

ConfirmRewind.OnServerEvent:Connect(function(player, frameIndex)
	if not frameIndex then return end
	confirmRewind(player, frameIndex)
end)

-- REPLAY CLIENT -- 

--[[
ReplaySystem 
Handles the replay UI, ghosts, and trails.
Allows the playet to rewind and replay their movement.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Load Modules
local ReplaySystem = ReplicatedStorage:WaitForChild("ReplaySystem")
local Config = require(ReplaySystem:WaitForChild("Config"))
local GhostController = require(ReplaySystem:WaitForChild("GhostController"))
local TrailRenderer = require(ReplaySystem:WaitForChild("TrailRenderer"))

-- Load remote events 
local ReplayRemotes = ReplicatedStorage:WaitForChild("ReplayRemotes")
local RequestReplay = ReplayRemotes:WaitForChild("RequestReplay")
local ConfirmRewind = ReplayRemotes:WaitForChild("ConfirmRewind")
local SendFrameData = ReplayRemotes:WaitForChild("SendFrameData")

-- UI 
local ReplayUI = playerGui:WaitForChild("ReplayUI")
local MainFrame = ReplayUI:WaitForChild("MainFrame")
local Frame = MainFrame:WaitForChild("Frame")
local DoneButton = MainFrame:WaitForChild("DoneButton")
local SliderHandle = Frame:WaitForChild("TextButton")
local Button = playerGui:WaitForChild("ScreenButtons"):WaitForChild("TextButton")

-- State
local frames = {}
local currentFrameIndex = 1
local isInReplayMode = false
local ghost = nil
local trail = nil


-- Update the slider based on current frame
local function updateSlider()
	if #frames == 0 then return end
	local progress = currentFrameIndex / #frames
	SliderHandle.Position = UDim2.new(progress, -10, 0, 0)
end

-- Update loop for smooth movement
RunService.RenderStepped:Connect(function()
	if not isInReplayMode then return end
	if not ghost then return end

	ghost:update()
end)

-- Dragging state
local isDragging = false

-- Starts dragging on mouse pressed
SliderHandle.MouseButton1Down:Connect(function()
	isDragging = true
end)

-- Stop dragging when mouse released
UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		isDragging = false
	end
end)

-- Handles Slider
UserInputService.InputChanged:Connect(function(input)
	if not isDragging then return end
	if not isInReplayMode then return end
	if input.UserInputType ~= Enum.UserInputType.MouseMovement then return end

	local mouseX = input.Position.X
	local barStart = Frame.AbsolutePosition.X
	local barWidth = Frame.AbsoluteSize.X

	local progress = (mouseX - barStart) / barWidth
	progress = math.clamp(progress, 0, 1)

	currentFrameIndex = math.floor(progress * #frames) + 1
	currentFrameIndex = math.clamp(currentFrameIndex, 1, #frames)

	if ghost and frames[currentFrameIndex] then
		ghost:setTarget(frames[currentFrameIndex].cframe)
	end

	updateSlider()
end)


-- Ends replay and tps player 
local function endReplay()
	ConfirmRewind:FireServer(currentFrameIndex) 
	ReplayUI.Enabled = false
	isInReplayMode = false

	if ghost then
		ghost:destroy()
		ghost = nil
	end

	if trail then
		trail:destroy()
		trail = nil
	end

	frames = {}
end

-- Done button ends the replay
DoneButton.MouseButton1Click:Connect(endReplay)


-- Handles receiving frames
SendFrameData.OnClientEvent:Connect(function(receivedFrames)
	frames = receivedFrames
	currentFrameIndex = #receivedFrames
	isInReplayMode = true
	ReplayUI.Enabled = true
	
	-- create ghost at position of player
	local character = player.Character
	if character then
		local hrp = character:FindFirstChild("HumanoidRootPart")
		if hrp then
			ghost = GhostController.new(hrp.CFrame)

			if frames[currentFrameIndex] then
				ghost:setTarget(frames[currentFrameIndex].cframe)
			end
		end
	end
	
	-- creates trail
	trail = TrailRenderer.new()
	trail:renderPath(frames)

	updateSlider()
end)

Button.MouseButton1Click:Connect(function()
	if isInReplayMode then return end
	RequestReplay:FireServer()
end)
