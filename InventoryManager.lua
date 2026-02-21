-- inventory + hotbar drag & drop
-- DISCLAIMER: Normally i would ALWAYS use the server for data but because im only allowed for one script i made the data Local
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local plr = Players.LocalPlayer
local plrGui = plr:WaitForChild("PlayerGui")

local invGui = script.Parent
local hotbarGui = plrGui:WaitForChild("Hotbar")

local invFrame = invGui.Canvas.MainFrame:WaitForChild("InventoryFrame")
local invMain = invFrame:WaitForChild("InventoryMainFrame")
local searchBox = invMain.SearchFrame:WaitForChild("TextBox")
local scrollFrame = invMain.Container:WaitForChild("MainScrollingFrame")
local grid = scrollFrame:WaitForChild("UIGridLayout")
local cardTemplate = invGui.Canvas.MainFrame:WaitForChild("InventoryTemplate")

local hotbarMain = hotbarGui.Canvas:WaitForChild("MainFrame")
local bpButton = hotbarMain.BackPackHotBar:WaitForChild("BackPackIconButton")

local STAR_FAV = "rbxassetid://125580573336944"
local STAR_DEFAULT = cardTemplate:WaitForChild("Star").Image

-- preload stars so they dont flash white on first toggle
task.spawn(function()
	local tmp1 = Instance.new("ImageLabel"); tmp1.Image = STAR_FAV
	local tmp2 = Instance.new("ImageLabel"); tmp2.Image = STAR_DEFAULT
	game:GetService("ContentProvider"):PreloadAsync({tmp1, tmp2})
	tmp1:Destroy(); tmp2:Destroy()
end)

-- Placeholder data this would be replaced with data from the server via remotes
local items = {
	{ id = "wood_log", name = "Wood Log", amount = 14, weight = 7.5, img = "rbxassetid://116246568302827", fav = false },
	{ id = "iron_ingot", name = "Iron Ingot", amount = 8, weight = 4.2, img = "rbxassetid://116246568302827", fav = false },
	{ id = "gold_nugget", name = "Gold Nugget", amount = 21, weight = 1.4, img = "rbxassetid://116246568302827", fav = false },
	{ id = "healing_potion", name = "Healing Potion", amount = 5, weight = 0.9, img = "rbxassetid://116246568302827", fav = false },
	{ id = "mana_potion", name = "Mana Potion", amount = 6, weight = 0.9, img = "rbxassetid://116246568302827", fav = false },
	{ id = "torch", name = "Torch", amount = 12, weight = 0.5, img = "rbxassetid://116246568302827", fav = false },
	{ id = "rope", name = "Rope", amount = 2, weight = 3.0, img = "rbxassetid://116246568302827", fav = false },
	{ id = "diamond", name = "Diamond", amount = 3, weight = 0.2, img = "rbxassetid://116246568302827", fav = false },
	{ id = "apple", name = "Apple", amount = 16, weight = 0.3, img = "rbxassetid://116246568302827", fav = false },
	{ id = "hammer", name = "Hammer", amount = 1, weight = 5.5, img = "rbxassetid://116246568302827", fav = false },
	{ id = "map", name = "Treasure Map", amount = 1, weight = 0.1, img = "rbxassetid://116246568302827", fav = false },
	{ id = "crystal", name = "Energy Crystal", amount = 4, weight = 0.7, img = "rbxassetid://116246568302827", fav = false },
}

-- lookup table so i dont have to loop every time to get an item via id 
local itemById = {}
for _, v in items do itemById[v.id] = v end

local slots = {}
local hotbar = {} 
local invOpen = true
local firstRender = true


-- keeps track of which cards exist in the scrollframe right now

local activeCards = {}

-- Here are all drag related stuff so i can reset them with ease
local dragActive = false
local dragItem = nil
local dragGhost = nil
local dragHover = nil
local dragConn = nil
local dragFrom = nil     -- "inv" or "hotbar"
local dragFromSlot = nil

local renderInv
local renderHotbar

-- tween helper
local function tw(obj, info, goal)
	local t = TweenService:Create(obj, info, goal)
	t:Play()
	return t
end

-- Creates UIScale on any gui object so we can animate scale
-- without destroying the actual size property
local function getScale(obj)
	local s = obj:FindFirstChild("_uiscale")
	if not s then
		s = Instance.new("UIScale"); s.Name = "_uiscale"; s.Parent = obj
	end
	return s
end

-- Clones the card template into a hotbar slot frame
-- and it creates an invisible sensor frame on top for hover detection
local function ensureSlotUI(slotFrame)
	local folder = slotFrame:FindFirstChild("_runtime")
	if not folder then
		folder = Instance.new("Folder"); folder.Name = "_runtime"; folder.Parent = slotFrame
	end

	local card = folder:FindFirstChild("Card")
	if not card then
		card = cardTemplate:Clone()
		card.Name = "Card"
		card.Visible = false
		card.AutoButtonColor = false
		card.AnchorPoint = Vector2.new(.5, .5)
		card.Position = UDim2.fromScale(.5, .5)
		card.Size = UDim2.fromScale(.98, .98)
		card.ZIndex = 6
		card.NameOfTheObject.TextScaled = true
		card.AmountOfTheObject.TextScaled = true
		card.WeightOfTheObject.TextScaled = true
		card.WeightOfTheObject.Visible = true
		card.Parent = folder
	end

	-- sensor sits on top and is always there even when card is hidden
	local sensor = folder:FindFirstChild("_sensor")
	if not sensor then
		sensor = Instance.new("TextButton")
		sensor.Name = "_sensor"
		sensor.Text = ""
		sensor.AutoButtonColor = false
		sensor.BackgroundTransparency = 1
		sensor.Size = UDim2.fromScale(1, 1)
		sensor.ZIndex = 30
		sensor.Parent = folder
	end

	return card, sensor
end

-- stroke helpers for hotbar highlightg
local function tweenStroke(s, info, goal)
	if not s.stroke or not s.stroke.Parent then return end
	if s._tw then s._tw:Cancel() end
	s._tw = TweenService:Create(s.stroke, info, goal)
	s._tw:Play()
end

-- put stroke back to original color and thickness
local function resetStroke(s)
	tweenStroke(s, TweenInfo.new(0.08), { Thickness = s.defaultThickness, Color = s.defaultColor })
end

local function setHover(frame) -- keeps track about which hotbaar slot the cursor is hovering
	-- skip if slot didnt changed
	if dragHover == frame then return end

	-- remove old highlight if there is one
	if dragHover then
		for _, s in slots do
			if s.frame == dragHover then resetStroke(s) break end
		end
	end

	dragHover = frame

	-- highlights the new slot with a bluestroke via the helper function
	if not frame then return end
	for _, s in slots do
		if s.frame ~= frame then continue end
		tweenStroke(s, TweenInfo.new(0.08), {
			Thickness = s.defaultThickness + 2,
			Color = Color3.fromRGB(117, 212, 255)
		})
		break
	end
end

-- returns the hotbar slot frame under the given point as an fallback
-- implented ths because i had problems when i moved to fast with the mouse
local function slotAtPos(pt)
	for _, hit in plrGui:GetGuiObjectsAtPosition(pt.X, pt.Y) do
		for _, s in slots do
			if hit == s.frame or hit:IsDescendantOf(s.frame) then return s end
		end
	end
	return nil
end

-- star toggle animation used from both inventory and hotbar
local function animateStar(star, isFav)
	star.Image = isFav and STAR_FAV or STAR_DEFAULT
	local sc = getScale(star)
	sc.Scale = 0.75
	tw(sc, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1.08 })
	task.delay(0.12, function()
		if sc.Parent then tw(sc, TweenInfo.new(0.12), { Scale = 1 }) end
	end)
	star.Rotation = -15
	tw(star, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Rotation = 0 })
end

-- updates the text/image on an existing card without recreating it
local function updateCard(card, item)
	card.NameOfTheObject.Text = item.name
	card.AmountOfTheObject.Text = item.amount .. "x"
	card.WeightOfTheObject.Text = string.format("%.1f KG", item.weight)
	card.ItemLabel.Image = item.img
	card.Star.Image = item.fav and STAR_FAV or STAR_DEFAULT
end

-- creates a new card for an item and hooks up all the events
local function createInvCard(item)
	local card = cardTemplate:Clone()
	card.Name = "Item_" .. item.id
	card.Visible = true
	card.Parent = scrollFrame
	updateCard(card, item)

	local sc = getScale(card)
	local conns = {}

	
	table.insert(conns, card.MouseEnter:Connect(function()
		tw(sc, TweenInfo.new(0.13, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1.04 })
	end))

	table.insert(conns, card.MouseLeave:Connect(function()
		if not dragActive then tw(sc, TweenInfo.new(0.12, Enum.EasingStyle.Quad), { Scale = 1 }) end
	end))

	table.insert(conns, card.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			item.fav = not item.fav
			local star = card:FindFirstChild("Star")
			if star then animateStar(star, item.fav) end
			renderHotbar()
		elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
			beginDrag(item, card, "inv", nil)
		end
	end))

	return card, conns
end

-- removes a card and disconnects its events
local function removeCard(id)
	local entry = activeCards[id]
	if not entry then return end
	for _, c in entry.conns do c:Disconnect() end
	entry.card:Destroy()
	activeCards[id] = nil
end

-- updates all hotbar slots it takes the data drom the Hotbar table
renderHotbar = function()
	for _, s in slots do
		-- tries to find the item thats in this slot empty string if the Helper Function fails
		local item = itemById[hotbar[s.index] or ""]
		local card = ensureSlotUI(s.frame)

		if not item then
			-- empty slots are invisble
			-- sensor stays visible 
			card.Visible = false
			continue
		end

		card.Visible = true
		card.NameOfTheObject.Text = item.name
		card.AmountOfTheObject.Text = item.amount .. "x"
		card.WeightOfTheObject.Text = string.format("%.1f KG", item.weight)
		card.ItemLabel.Image = item.img
		card.Star.Image = item.fav and STAR_FAV or STAR_DEFAULT
	end
end

-- updates the inventory display
renderInv = function(doIntro)
	local q = string.lower(searchBox.Text or "")

	-- checks which items should be visible rn 
	local shouldShow = {}
	local order = {}
	for _, item in items do
		-- check if its already on the hotbar
		local onBar = false
		for _, v in hotbar do if v == item.id then onBar = true break end end

		if not onBar and (q == "" or string.find(string.lower(item.name), q, 1, true)) then
			shouldShow[item.id] = item
			table.insert(order, item)
		end
	end

	-- favs first
	table.sort(order, function(a, b)
		if a.fav ~= b.fav then return a.fav end
		return a.name < b.name
	end)

	-- remove cards that shouldnt be there anymore

	for id in activeCards do
		if not shouldShow[id] then removeCard(id) end
	end

	-- add new cards or update existing ones
	local shouldAnimate = doIntro and firstRender
	for i, item in ipairs(order) do
		local existing = activeCards[item.id]
		if existing then
			-- updating because it already exists
	
			updateCard(existing.card, item)
			
			existing.card.LayoutOrder = i
		else
			-- new card needed
			local card, conns = createInvCard(item)
			card.LayoutOrder = i
			activeCards[item.id] = { card = card, conns = conns }

			if shouldAnimate then
				local sc = getScale(card)
				sc.Scale = 0.85
				task.delay((i - 1) * 0.03, function()
					if card.Parent then
						tw(sc, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
					end
				end)
			end
		end
	end

	if shouldAnimate then firstRender = false end
end


-- starts dragging an item, clones the slot as a ghost 
-- that follows the curosor until release
function beginDrag(item, srcCard, from, fromSlot)
	if dragActive then
		-- shouldnt happen but just in case
		-- seen it trigger when clicking very fast
		if dragGhost then dragGhost:Destroy() end
		if dragConn then dragConn:Disconnect() end
	end

	dragActive = true
	dragItem = item
	dragFrom = from
	dragFromSlot = fromSlot

	-- clones the card so it havas an visual copy
	local ghost = srcCard:Clone()
	ghost.Name = "Ghost"
	ghost.AnchorPoint = Vector2.new(.5, .5)
	-- high zindex so it shows above everything
	ghost.ZIndex = 2000
	ghost.Visible = true
	-- active false so it doesnt take mouse events
	ghost.Active = false
	ghost.AutoButtonColor = false
	ghost.Rotation = 3
	ghost.Size = UDim2.fromOffset(srcCard.AbsoluteSize.X, srcCard.AbsoluteSize.Y)
	ghost.Parent = invGui

	--  small animation when picking up 
	local gsc = getScale(ghost)
	gsc.Scale = 0.95
	tw(gsc, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1.04 })

	local mPos = UIS:GetMouseLocation()
	ghost.Position = UDim2.fromOffset(mPos.X, mPos.Y)
	dragGhost = ghost

	local lastPt = Vector2.new(mPos.X, mPos.Y)
	local tilt = 0

	-- update ghost every frame so it follows the cursor smooth
	-- also makes an  tilt based on the direction the cursor moves
	dragConn = RunService.RenderStepped:Connect(function()
		if not dragActive then return end
		local m = UIS:GetMouseLocation()
		local pt = Vector2.new(m.X, m.Y)
		ghost.Position = UDim2.fromOffset(pt.X, pt.Y)
		-- clamp so it doesnt tilt too much
		local dx = pt - lastPt
		local target = math.clamp(dx.X * 0.65 + dx.Y * 0.08, -18, 18)
		tilt = tilt + (target - tilt) * 0.35
		ghost.Rotation = tilt
		lastPt = pt
	end)
end

-- called when the mouse button release it checke where it drops and updates the Inventory/Hotbar 
local function endDrag()
	if not dragActive then return end

	local m = UIS:GetMouseLocation()
	local pt = Vector2.new(m.X, m.Y)

	-- figure out where we dropped
	local target = nil
	if dragHover then
		for _, s in slots do
			if s.frame == dragHover then target = s break end
		end
	end
	if not target then
		local fallback = slotAtPos(pt)
		if fallback then target = fallback end
	end

	if target and dragItem then
		if dragFrom == "hotbar" and dragFromSlot and dragFromSlot ~= target.index then
			-- Swap hotbar slots if dragging between hotbar
			hotbar[dragFromSlot] = hotbar[target.index] 
		elseif dragFrom == "inv" then
			-- dragging from inv to hotbar 
			for i = 1, #slots do
				if i ~= target.index and hotbar[i] == dragItem.id then hotbar[i] = nil end
			end
		end

		-- assign the item to the targeted slot
		hotbar[target.index] = dragItem.id
		renderHotbar()
		renderInv()
	else
		-- didnt dropped on the hotbar checks if its an hotbar item
		if dragFrom == "hotbar" and dragFromSlot then
			local fp = invFrame.AbsolutePosition
			local fs = invFrame.AbsoluteSize
			local inside = pt.X >= fp.X and pt.X <= fp.X + fs.X and pt.Y >= fp.Y and pt.Y <= fp.Y + fs.Y
			if inside then
				hotbar[dragFromSlot] = nil
				renderHotbar()
				renderInv()
			end
		end
	end

	-- cleanup everything 
	setHover(nil)
	for _, s in slots do resetStroke(s) end

	-- disconnects the RenderStepped 
	if dragConn then dragConn:Disconnect() end

	if dragGhost then dragGhost:Destroy() end
	dragActive = false
	dragItem = nil
	dragGhost = nil
	dragConn = nil
	dragFrom = nil
	dragFromSlot = nil
end

-- open/close inv 
local function setInvOpen(open)
	-- return if alr in the correct state
	if invOpen == open then return end
	invOpen = open

	local fsc = getScale(invFrame)
	local bsc = getScale(bpButton)

	if open then
		-- make it visible before animation
		invFrame.Visible = true
		-- starts scaled down
		fsc.Scale = 0.85
		invFrame.BackgroundTransparency = 1
		-- scale up with bounce
		tw(fsc, TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
		-- animate background
		tw(invFrame, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 0.5 })
		-- animate backpack icon
		tw(bsc, TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1.08 })
		task.delay(0.15, function()
			if bsc.Parent then tw(bsc, TweenInfo.new(0.1), { Scale = 1 }) end
		end)
	else
		-- animate away with shrink and fade
		tw(fsc, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0.9 })
		local t = tw(invFrame, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { BackgroundTransparency = 1 })
		-- only set invis after animation 
		-- so you see the fade out
		t.Completed:Connect(function()
			if not invOpen then invFrame.Visible = false end
		end)
	end
end

-- hotbar slot init
-- loop througs all children of the hotbar and setup all that match the naming pattern Slot1, Slot2, etc
for _, child in hotbarMain:GetChildren() do
	local n = tonumber(child.Name:match("^Slot(%d+)$"))
	if not n then continue end
	if not child:IsA("Frame") then continue end

	-- grab the UIStroke for animations
	local stroke = child:FindFirstChildOfClass("UIStroke")

	local s = {
		index = n,
		frame = child,
		stroke = stroke,
		defaultThickness = stroke and stroke.Thickness or 1,
		defaultColor = stroke and stroke.Color or Color3.new(1, 1, 1),
	}
	table.insert(slots, s)

	child.Active = true
	local card, sensor = ensureSlotUI(child)

	-- hover/drop detection goes on the sensor not the card
	sensor.MouseEnter:Connect(function()
		if dragActive then setHover(child) end
	end)
	sensor.MouseLeave:Connect(function()
		if dragActive and dragHover == child then setHover(nil) end
	end)

	-- clicks go through the sensor too since its on top
	sensor.InputBegan:Connect(function(input)
		local slotItem = itemById[hotbar[s.index] or ""]
		if not slotItem then return end

		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			slotItem.fav = not slotItem.fav
			renderHotbar()
			renderInv()
			local star = card:FindFirstChild("Star")
			if star then animateStar(star, slotItem.fav) end
		elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
			if not invOpen then return end -- cant rearrange while closed
			beginDrag(slotItem, card, "hotbar", s.index)
		end
	end)
end

table.sort(slots, function(a, b) return a.index < b.index end)

-- event connections
searchBox.PlaceholderText = "Search item..."
-- renders the inv new when the text changes for filter
searchBox:GetPropertyChangedSignal("Text"):Connect(function() renderInv() end)

bpButton.MouseButton1Click:Connect(function() setInvOpen(not invOpen) end)

UIS.InputBegan:Connect(function(input, gpe)
	if gpe then return end
	if input.KeyCode == Enum.KeyCode.Tab or input.KeyCode == Enum.KeyCode.E then
		setInvOpen(not invOpen)
	end
end)

-- auto resize the scroll canvas twhen the content changes so the scrollbar works
grid:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
	scrollFrame.CanvasSize = UDim2.fromOffset(0, grid.AbsoluteContentSize.Y + 14)
end)

-- releasing the mouse end any active drag

UIS.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		endDrag()
		for _, s in slots do resetStroke(s) end
	end
end)

-- cancel drag when changing windows or alt + tab
UIS.WindowFocusReleased:Connect(function()
	if dragActive then endDrag() end
end)

-- hide the template
cardTemplate.Visible = false

-- int render
renderHotbar()
renderInv(true)
setInvOpen(true)
