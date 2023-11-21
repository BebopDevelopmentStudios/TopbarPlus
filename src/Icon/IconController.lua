-- LOCAL
local starterGui = game:GetService("StarterGui")
local guiService = game:GetService("GuiService")
local hapticService = game:GetService("HapticService")
local runService = game:GetService("RunService")
local userInputService = game:GetService("UserInputService")
local tweenService = game:GetService("TweenService")
local players = game:GetService("Players")
local VRService = game:GetService("VRService")
local localizationService = game:GetService("LocalizationService")
local iconModule = script.Parent
local TopbarPlusReference = require(iconModule.TopbarPlusReference)
local referenceObject = TopbarPlusReference.getObject()
local leadPackage = referenceObject and referenceObject.Value
if leadPackage and leadPackage.IconController ~= script then
	return require(leadPackage.IconController)
end
if not referenceObject then
    TopbarPlusReference.addToReplicatedStorage()
end
local IconController = {}
local Signal = require(iconModule.Signal)
local TopbarPlusGui = require(iconModule.TopbarPlusGui)
local topbarIcons = {}
local forceTopbarDisabled = false
local menuOpen
local topbarUpdating = false
local cameraConnection
local controllerMenuOverride
local isStudio = runService:IsStudio()
local localPlayer = players.LocalPlayer
local disableControllerOption = false
local STUPID_CONTROLLER_OFFSET = 32



-- LOCAL FUNCTIONS
local function checkTopbarEnabled()
	local success, bool = xpcall(function()
		return starterGui:GetCore("TopbarEnabled")
	end,function(err)
		--has not been registered yet, but default is that is enabled
		return true
	end)
	return (success and bool)
end

local function checkTopbarEnabledAccountingForMimic()
	local topbarEnabledAccountingForMimic = (checkTopbarEnabled() or not IconController.mimicCoreGui)
	return topbarEnabledAccountingForMimic
end

-- Add icons to an overflow if they overlap the screen bounds or other icons
local function bindCamera()
	if not workspace.CurrentCamera then return end
	if cameraConnection and cameraConnection.Connected then
		cameraConnection:Disconnect()
	end
	cameraConnection = workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(IconController.updateTopbar)
end

--[=[
	Gets the offset for the topbar inset.
	The topbar on mobile devices is 52px tall, whereas on desktop it's 58px tall, and this difference also applies to spacing and padding.
]=]
local function getOffsetForTopbarInset(): number
	if not IconController.accountForMobile then
		return 0
	end

	return guiService.TopbarInset.Max.Y - 52
end

-- Handles changing of the top bar inset
local function bindTopBarInsetChanged()
	guiService:GetPropertyChangedSignal("TopbarInset"):Connect(IconController.updateTopbar)
end

-- OFFSET HANDLERS
local alignmentDetails = {}
alignmentDetails["left"] = {
	startScale = 0,
	getOffset = function()
		local offset = IconController.leftOffset + getOffsetForTopbarInset()
		return offset
	end,
	getStartOffset = function()
		local alignmentGap = IconController["leftGap"]
		local startOffset = alignmentDetails.left.getOffset() + alignmentGap
		return startOffset
	end,
	records = {}
}
alignmentDetails["mid"] = {
	startScale = 0.5,
	getOffset = function()
		return 0
	end,
	getStartOffset = function(totalIconX)
		local alignmentGap = IconController["midGap"]
		return -totalIconX/2 + (alignmentGap/2)
	end,
	records = {}
}
alignmentDetails["right"] = {
	startScale = 1,
	getOffset = function()
		local offset = IconController.rightOffset --+ getOffsetForTopbarInset()
		return offset
	end,
	getStartOffset = function(totalIconX)
		local startOffset = -totalIconX - alignmentDetails.right.getOffset()
		return startOffset
	end,
	records = {}
	--reverseSort = true
}


-- PROPERTIES
IconController.topbarEnabled = true
IconController.controllerModeEnabled = false
IconController.previousTopbarEnabled = checkTopbarEnabled()
IconController.accountForMobile = true
IconController.leftGap = 6
IconController.midGap = 6
IconController.rightGap = 6
IconController.leftOffset = 0
IconController.rightOffset = 0
IconController.mimicCoreGui = true
IconController.healthbarDisabled = false
IconController.activeButtonBCallbacks = 0
IconController.disableButtonB = false
IconController.translator = localizationService:GetTranslatorForPlayer(localPlayer)

local function getAlignmentGap(alignment)
	local alignmentGap = IconController[alignment.."Gap"]
	return alignmentGap + getOffsetForTopbarInset()
end

-- EVENTS
IconController.iconAdded = Signal.new()
IconController.iconRemoved = Signal.new()
IconController.controllerModeStarted = Signal.new()
IconController.controllerModeEnded = Signal.new()
IconController.healthbarDisabledSignal = Signal.new()



-- CONNECTIONS
local iconCreationCount = 0
IconController.iconAdded:Connect(function(icon)
	topbarIcons[icon] = true
	if IconController.gameTheme then
		icon:setTheme(IconController.gameTheme)
	end
	icon.updated:Connect(function()
		IconController.updateTopbar()
	end)
	-- When this icon is selected, deselect other icons if necessary
	icon.selected:Connect(function()
		local allIcons = IconController.getIcons()
		for _, otherIcon in pairs(allIcons) do
			if icon.deselectWhenOtherIconSelected and otherIcon ~= icon and otherIcon.deselectWhenOtherIconSelected and otherIcon:getToggleState() == "selected" then
				otherIcon:deselect(icon)
			end
		end
	end)
	-- Order by creation if no order specified
	iconCreationCount = iconCreationCount + 1
	icon:setOrder(iconCreationCount)
	-- Apply controller view if enabled
	if IconController.controllerModeEnabled then
		IconController._enableControllerModeForIcon(icon, true)
	end
	IconController:_updateSelectionGroup()
	IconController.updateTopbar()
end)

IconController.iconRemoved:Connect(function(icon)
	topbarIcons[icon] = nil
	icon:setEnabled(false)
	icon:deselect()
	icon.updated:Fire()
	IconController:_updateSelectionGroup()
end)

workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCamera)


-- METHODS
function IconController.setGameTheme(theme)
	IconController.gameTheme = theme
	local icons = IconController.getIcons()
	for _, icon in pairs(icons) do
		icon:setTheme(theme)
	end
end

function IconController.setDisplayOrder(value)
	value = tonumber(value) or TopbarPlusGui.DisplayOrder
	TopbarPlusGui.DisplayOrder = value
end
IconController.setDisplayOrder(10)

function IconController.getIcons()
	local allIcons = {}
	for otherIcon, _ in pairs(topbarIcons) do
		table.insert(allIcons, otherIcon)
	end
	return allIcons
end

function IconController.getIcon(name)
	for otherIcon, _ in pairs(topbarIcons) do
		if otherIcon.name == name then
			return otherIcon
		end
	end
	return false
end

function IconController.disableHealthbar(bool)
	local finalBool = (bool == nil or bool)
	IconController.healthbarDisabled = finalBool
	IconController.healthbarDisabledSignal:Fire(finalBool)
end

function IconController.disableControllerOption(bool)
	local finalBool = (bool == nil or bool)
	disableControllerOption = finalBool
	if IconController.getIcon("_TopbarControllerOption") then
		IconController._determineControllerDisplay()
	end
end

function IconController.canShowIconOnTopbar(icon)
	if (icon.enabled == true or icon.accountForWhenDisabled) and icon.presentOnTopbar then
		return true
	end
	return false
end

function IconController.getMenuOffset(icon)
	local alignment = icon:get("alignment")
	local alignmentGap = getAlignmentGap(alignment)
	local extendLeft = 0
	local extendRight = 0
	local additionalRight = 0
	if icon.menuOpen then
		local menuSize = icon:get("menuSize")
		local menuSizeXOffset = menuSize.X.Offset
		local direction = icon:_getMenuDirection()
		if direction == "right" then
			extendRight += menuSizeXOffset + alignmentGap/6--2
		elseif direction == "left" then
			extendLeft = menuSizeXOffset + 4
			extendRight += alignmentGap/3--4
			additionalRight = menuSizeXOffset
		end
	end
	return extendLeft, extendRight, additionalRight
end

-- This is responsible for positioning the topbar icons
local requestedTopbarUpdate = false
function IconController.updateTopbar()
	local function getIncrement(otherIcon, alignment)
		local iconSize = otherIcon:get("iconSize", otherIcon:getIconState()) or UDim2.new(0, 32, 0, 32)
		local sizeX = iconSize.X.Offset
		local alignmentGap = getAlignmentGap(alignment)
		local iconWidthAndGap = (sizeX + alignmentGap)
		local increment = iconWidthAndGap
		local preOffset = 0
		if otherIcon._parentIcon == nil then
			local extendLeft, extendRight, additionalRight = IconController.getMenuOffset(otherIcon)
			preOffset += extendLeft
			increment += extendRight + additionalRight
		end
		return increment, preOffset
	end
	if topbarUpdating then -- This prevents the topbar updating and shifting icons more than it needs to
		requestedTopbarUpdate = true
		return false
	end
	task.defer(function()
		topbarUpdating = true
		runService.Heartbeat:Wait()
		topbarUpdating = false

		for _, alignmentInfo in alignmentDetails do
			alignmentInfo.records = {}
		end

		for otherIcon, _ in topbarIcons do
			if IconController.canShowIconOnTopbar(otherIcon) then
				local alignment = otherIcon:get("alignment")
				table.insert(alignmentDetails[alignment].records, otherIcon)
			end
		end
		local viewportSize = workspace.CurrentCamera.ViewportSize
		local topbarStart = guiService.TopbarInset.Min.X
		local topbarSize = viewportSize.X - (topbarStart)

		for alignment, alignmentInfo in alignmentDetails do
			local records = alignmentInfo.records
			if #records > 1 then
				if alignmentInfo.reverseSort then
					table.sort(records, function(a, b)
						return a:get("order") > b:get("order")
					end)
				else
					table.sort(records, function(a, b)
						return a:get("order") < b:get("order")
					end)
				end
			end
			local totalIconX = 0
			for _, otherIcon in records do
				local increment = getIncrement(otherIcon, alignment)
				totalIconX = totalIconX + increment
			end
			local offsetX = alignmentInfo.getStartOffset(totalIconX, alignment)
			for _, otherIcon in records do
				local container = otherIcon.instances.iconContainer
				local increment, preOffset = getIncrement(otherIcon, alignment)
				local topPadding = otherIcon.topPadding
				local newPositon = UDim2.new(alignmentInfo.startScale, offsetX+preOffset, topPadding.Scale, topPadding.Offset + getOffsetForTopbarInset())
				local repositionInfo = otherIcon:get("repositionInfo")
				if repositionInfo then
					tweenService:Create(container, repositionInfo, {Position = newPositon}):Play()
				else
					container.Position = newPositon
				end
				offsetX = offsetX + increment
				otherIcon.targetPosition = UDim2.new(0, (newPositon.X.Scale*topbarSize) + newPositon.X.Offset, 0, (newPositon.Y.Scale*viewportSize.Y) + newPositon.Y.Offset)
				-- print(otherIcon.name, otherIcon.targetPosition.X.Offset)
			end
		end

		-- OVERFLOW HANDLER
		--------
		local START_LEEWAY = 10 -- The additional offset where the end icon will be converted to ... without an apparant change in position
		-- Gets the boundary X position of the icon, accounting for the provided side.
		local function getAbsoluteBoundaryX(iconToCheck, side, gap)
			local additionalGap = gap or 0
			local currentSize = iconToCheck:get("iconSize", iconToCheck:getIconState())
			local sizeX = currentSize.X.Offset
			local extendLeft, extendRight = IconController.getMenuOffset(iconToCheck)
			local boundaryXOffset = (side == "left" and (-additionalGap - extendLeft)) or (side == "right" and sizeX + additionalGap + extendRight)
			local boundaryX = iconToCheck.targetPosition.X.Offset + boundaryXOffset + (topbarStart)
			return boundaryX
		end

		local function handleAlignment(alignment, alignmentInfo)
			local oppositeAlignment = alignment == "left" and "right" or "left"
			local overflowIcon = alignmentInfo.overflowIcon
			local alignmentGap = getAlignmentGap(alignment)

			if not overflowIcon then
				return
			end

			local exceededCriticalBoundary = false

			local overflowIconBoundaryX = getAbsoluteBoundaryX(overflowIcon, alignment)

			if overflowIcon.enabled then
				overflowIconBoundaryX = getAbsoluteBoundaryX(overflowIcon, oppositeAlignment, alignmentGap)
			end

			local function checkExceeds(boundary)
				return (alignment == "left" and boundary < overflowIconBoundaryX)
					or (alignment == "right" and overflowIconBoundaryX < boundary)
			end

			-- TODO: what about middle?
			local boundaryX = alignment == "left" and topbarStart + topbarSize or topbarStart
			exceededCriticalBoundary = checkExceeds(boundaryX)

			-- Checks whether there's an overlap between the current alignment and the other provided side.
			local function checkOverlapWithOtherSide(icons)
				local iconCount = #icons
				for i = 1, iconCount do
					local endIcon = icons[iconCount + 1 - i]
					if not IconController.canShowIconOnTopbar(endIcon) then
						continue
					end

					local isAnOverflowIcon = string.match(endIcon.name, "_overflowIcon-")
					if isAnOverflowIcon and iconCount == 1 then
						return
					elseif isAnOverflowIcon and not endIcon.enabled then
						continue
					end
					local additionalMyX = 0
					if not overflowIcon.enabled then
						additionalMyX = START_LEEWAY
					end
					local endIconBoundaryX = getAbsoluteBoundaryX(endIcon, alignment, additionalMyX)
					-- local isNowClosest = (alignment == "left" and endIconBoundaryX < boundaryX) or (alignment == "right" and endIconBoundaryX > boundaryX)
					local isNowClosest = (alignment == "left" and endIconBoundaryX < boundaryX) or (alignment == "right" and boundaryX < endIconBoundaryX)

					if not isNowClosest then
						continue
					end
					-- boundaryX = endIconBoundaryX
					boundaryX = endIconBoundaryX
					if checkExceeds(endIconBoundaryX) then
						exceededCriticalBoundary = true
					end
				end
			end
			checkOverlapWithOtherSide(alignmentDetails[oppositeAlignment].records)
			checkOverlapWithOtherSide(alignmentDetails["mid"].records)

			-- This determines which icons to give to the overflow if an overlap is present
			if exceededCriticalBoundary then
				local recordToCheck = alignmentInfo.records
				local totalIcons = #recordToCheck
				for i = 1, totalIcons do
					local endIcon = (alignment == "left" and recordToCheck[totalIcons+1 - i]) or (alignment == "right" and recordToCheck[i])
					if endIcon == overflowIcon or not IconController.canShowIconOnTopbar(endIcon) then
						continue
					end

					local additionalGap = alignmentGap
					if overflowIcon.enabled then
						local overflowIconSizeX = overflowIcon:get("iconSize", overflowIcon:getIconState()).X.Offset
						additionalGap += alignmentGap + overflowIconSizeX
					end
					local endIconBoundaryX = getAbsoluteBoundaryX(endIcon, oppositeAlignment, additionalGap)
					local exceeds = (alignment == "left" and boundaryX >= endIconBoundaryX) or (alignment == "right" and endIconBoundaryX >= boundaryX)
					if not exceeds then
						continue
					end

					if not overflowIcon.enabled then
						local overflowContainer = overflowIcon.instances.iconContainer
						local yPos = overflowContainer.Position.Y
						local appearXAdditional = (alignment == "left" and -overflowContainer.Size.X.Offset) or 0
						local appearX = getAbsoluteBoundaryX(endIcon, oppositeAlignment, appearXAdditional)
						overflowContainer.Position = UDim2.new(0, appearX, yPos.Scale, yPos.Offset)
						overflowIcon:setEnabled(true)
					end
					if #endIcon.dropdownIcons > 0 then
						endIcon._overflowConvertedToMenu = true
						local wasSelected = endIcon.isSelected
						endIcon:deselect()
						local iconsToConvert = {}
						for _, dIcon in pairs(endIcon.dropdownIcons) do
							table.insert(iconsToConvert, dIcon)
						end
						for _, dIcon in pairs(endIcon.dropdownIcons) do
							dIcon:leave()
						end
						endIcon:setMenu(iconsToConvert)
						if wasSelected and overflowIcon.isSelected then
							endIcon:select()
						end
					end
					if endIcon.hovering then
						endIcon.wasHoveringBeforeOverflow = true
					end
					endIcon:join(overflowIcon, "dropdown")
					if #endIcon.menuIcons > 0 and endIcon.menuOpen then
						endIcon:deselect()
						endIcon:select()
						overflowIcon:select()
					end

					break
				end
			else
				-- if not workspace.handleOverflow.Value then return end
				--Gets the width of the icon, accounting for its left/right offset.
				local function getSizeX(iconToCheck, usePrevious)
					local currentSize, previousSize = iconToCheck:get("iconSize", iconToCheck:getIconState(), "beforeDropdown")
					local hoveringSize = iconToCheck:get("iconSize", "hovering")
					if iconToCheck.wasHoveringBeforeOverflow and previousSize and hoveringSize and hoveringSize.X.Offset > previousSize.X.Offset then
						-- This prevents hovering icons flicking back and forth, demonstrated at thread/1017485/191.
						previousSize = hoveringSize
					end
					local newSize = (usePrevious and previousSize) or currentSize
					local extendLeft, extendRight = IconController.getMenuOffset(iconToCheck)
					local sizeX = newSize.X.Offset + extendLeft + extendRight
					return sizeX
				end

				local oppositeAlignmentInfo = alignmentDetails[oppositeAlignment]
				local oppositeOverflowIcon = IconController.getIcon("_overflowIcon-"..oppositeAlignment)

				-- This checks to see if the lowest/highest (depending on left/right) ordered overlapping icon is no longer overlapping, removes from the dropdown, and repeats if valid
				if not (not (oppositeOverflowIcon and oppositeOverflowIcon.enabled and #alignmentInfo.records == 1 and #oppositeAlignmentInfo.records ~= 1)) then
					return
				end

				local winningOrder, winningOverlappedIcon
				for _, overlappedIcon in pairs(overflowIcon.dropdownIcons) do
					local iconOrder = overlappedIcon:get("order")
					if winningOverlappedIcon == nil or (alignment == "left" and iconOrder < winningOrder) or (alignment == "right" and iconOrder > winningOrder) then
						winningOrder = iconOrder
						winningOverlappedIcon = overlappedIcon
					end
				end

				if not winningOverlappedIcon then
					-- print(alignment, "no winning overlapped icon")
					return
				end



				local newOverflowIconBoundaryX = getAbsoluteBoundaryX(overflowIcon, oppositeAlignment)
				local availableSpace = math.abs(boundaryX - newOverflowIconBoundaryX) - (alignmentGap * 2)

				local winningOverlappedIconSizeX = getSizeX(winningOverlappedIcon, true)

				-- if winningOverlappedIconSizeX < 1 then
				-- 	-- print(alignment, "winningOverlappedIconSizeX == 0")
				-- 	return
				-- end

				-- print(winningOverlappedIcon.name, winningOverlappedIconSizeX, availableSpace)
				local noLongerExceeds = winningOverlappedIconSizeX < availableSpace
				if not noLongerExceeds then
					return
				end

				if #overflowIcon.dropdownIcons == 1 then
					overflowIcon:setEnabled(false)
				end
				local overflowContainer = overflowIcon.instances.iconContainer
				local yPos = overflowContainer.Position.Y
				overflowContainer.Position = UDim2.new(0, newOverflowIconBoundaryX - topbarStart, yPos.Scale, yPos.Offset)
				winningOverlappedIcon:leave()
				winningOverlappedIcon.wasHoveringBeforeOverflow = nil

				-- print(winningOverlappedIcon.name, winningOverlappedIcon._overflowConvertedToMenu)
				if winningOverlappedIcon._overflowConvertedToMenu then
					winningOverlappedIcon._overflowConvertedToMenu = nil
					local iconsToConvert = {}
					for _, dIcon in pairs(winningOverlappedIcon.menuIcons) do
						table.insert(iconsToConvert, dIcon)
					end
					for _, dIcon in pairs(winningOverlappedIcon.menuIcons) do
						dIcon:leave()
					end
					winningOverlappedIcon:setDropdown(iconsToConvert)
				end
				--
			end
		end

		for alignment, alignmentInfo in alignmentDetails do
			handleAlignment(alignment, alignmentInfo)
		end
		--------
		if requestedTopbarUpdate then
			requestedTopbarUpdate = false
			IconController.updateTopbar()
		end
		return true
	end)
	return true
end

function IconController.setTopbarEnabled(bool, forceBool)
	if forceBool == nil then
		forceBool = true
	end
	local indicator = TopbarPlusGui.Indicator
	if forceBool and not bool then
		forceTopbarDisabled = true
	elseif forceBool and bool then
		forceTopbarDisabled = false
	end
	local topbarEnabledAccountingForMimic = checkTopbarEnabledAccountingForMimic()
	if IconController.controllerModeEnabled then
		if bool then
			if TopbarPlusGui.TopbarContainer.Visible or forceTopbarDisabled or menuOpen or not topbarEnabledAccountingForMimic then return end
			if forceBool then
				indicator.Visible = topbarEnabledAccountingForMimic
			else
				indicator.Active = false
				if controllerMenuOverride and controllerMenuOverride.Connected then
					controllerMenuOverride:Disconnect()
				end

				if hapticService:IsVibrationSupported(Enum.UserInputType.Gamepad1) and hapticService:IsMotorSupported(Enum.UserInputType.Gamepad1,Enum.VibrationMotor.Small) then
					hapticService:SetMotor(Enum.UserInputType.Gamepad1,Enum.VibrationMotor.Small,1)
					delay(0.2,function()
						pcall(function()
							hapticService:SetMotor(Enum.UserInputType.Gamepad1,Enum.VibrationMotor.Small,0)
						end)
					end)
				end
				TopbarPlusGui.TopbarContainer.Visible = true
				TopbarPlusGui.TopbarContainer:TweenPosition(
					UDim2.new(0,0,0,5 + STUPID_CONTROLLER_OFFSET),
					Enum.EasingDirection.Out,
					Enum.EasingStyle.Quad,
					0.1,
					true
				)


				local selectIcon
				local targetOffset = 0
				IconController:_updateSelectionGroup()
				runService.Heartbeat:Wait()
				local indicatorSizeTrip = 50 --indicator.AbsoluteSize.Y * 2
				for otherIcon, _ in pairs(topbarIcons) do
					if IconController.canShowIconOnTopbar(otherIcon) and (selectIcon == nil or otherIcon:get("order") < selectIcon:get("order")) and otherIcon.enabled then
						selectIcon = otherIcon
					end
					local container = otherIcon.instances.iconContainer
					local newTargetOffset = -27 + container.AbsoluteSize.Y + indicatorSizeTrip
					if newTargetOffset > targetOffset then
						targetOffset = newTargetOffset
					end
				end
				if guiService:GetEmotesMenuOpen() then
					guiService:SetEmotesMenuOpen(false)
				end
				if guiService:GetInspectMenuEnabled() then
					guiService:CloseInspectMenu()
				end
				local newSelectedObject = IconController._previousSelectedObject or selectIcon.instances.iconButton
				IconController._setControllerSelectedObject(newSelectedObject)
				indicator.Image = "rbxassetid://5278151071"
				indicator:TweenPosition(
					UDim2.new(0.5,0,0,targetOffset + STUPID_CONTROLLER_OFFSET),
					Enum.EasingDirection.Out,
					Enum.EasingStyle.Quad,
					0.1,
					true
				)
			end
		else
			if forceBool then
				indicator.Visible = false
			elseif topbarEnabledAccountingForMimic then
				indicator.Visible = true
				indicator.Active = true
				controllerMenuOverride = indicator.InputBegan:Connect(function(input)
					if input.UserInputType == Enum.UserInputType.MouseButton1 then
						IconController.setTopbarEnabled(true,false)
					end
				end)
			else
				indicator.Visible = false
			end
			if not TopbarPlusGui.TopbarContainer.Visible then return end
			guiService.AutoSelectGuiEnabled = true
			IconController:_updateSelectionGroup(true)
			TopbarPlusGui.TopbarContainer:TweenPosition(
				UDim2.new(0,0,0,-TopbarPlusGui.TopbarContainer.Size.Y.Offset + STUPID_CONTROLLER_OFFSET),
				Enum.EasingDirection.Out,
				Enum.EasingStyle.Quad,
				0.1,
				true,
				function()
					TopbarPlusGui.TopbarContainer.Visible = false
				end
			)
			indicator.Image = "rbxassetid://5278151556"
			indicator:TweenPosition(
				UDim2.new(0.5,0,0,5),
				Enum.EasingDirection.Out,
				Enum.EasingStyle.Quad,
				0.1,
				true
			)
		end
	else
		local topbarContainer = TopbarPlusGui.TopbarContainer
		if topbarEnabledAccountingForMimic then
			topbarContainer.Visible = bool
		else
			topbarContainer.Visible = false
		end
	end
end

function IconController.setGap(value, alignment)
	local newValue = tonumber(value) or 6
	local newAlignment = tostring(alignment):lower()
	if newAlignment == "left" or newAlignment == "mid" or newAlignment == "right" then
		IconController[newAlignment.."Gap"] = newValue
		IconController.updateTopbar()
		return
	end
	IconController.leftGap = newValue
	IconController.midGap = newValue
	IconController.rightGap = newValue
	IconController.updateTopbar()
end

function IconController.setLeftOffset(value)
	IconController.leftOffset = tonumber(value) or 0
	IconController.updateTopbar()
end

function IconController.setRightOffset(value)
	IconController.rightOffset = tonumber(value) or 0
	IconController.updateTopbar()
end

local iconsToClearOnSpawn = {}
localPlayer.CharacterAdded:Connect(function()
	for _, icon in pairs(iconsToClearOnSpawn) do
		icon:destroy()
	end
	iconsToClearOnSpawn = {}
end)
function IconController.clearIconOnSpawn(icon)
	coroutine.wrap(function()
		local char = localPlayer.Character or localPlayer.CharacterAdded:Wait()
		table.insert(iconsToClearOnSpawn, icon)
	end)()
end



-- PRIVATE METHODS
function IconController:_updateSelectionGroup(clearAll)
	if IconController._navigationEnabled then
		guiService:RemoveSelectionGroup("TopbarPlusIcons")
	end
	if clearAll then
		guiService.CoreGuiNavigationEnabled = IconController._originalCoreGuiNavigationEnabled
		guiService.GuiNavigationEnabled = IconController._originalGuiNavigationEnabled
		IconController._navigationEnabled = nil
	elseif IconController.controllerModeEnabled then
		local icons = IconController.getIcons()
		local iconContainers = {}
		for i, otherIcon in pairs(icons) do
			local featureName = otherIcon.joinedFeatureName
			if not featureName or otherIcon._parentIcon[otherIcon.joinedFeatureName.."Open"] == true then
				table.insert(iconContainers, otherIcon.instances.iconButton)
			end
		end
		guiService:AddSelectionTuple("TopbarPlusIcons", table.unpack(iconContainers))
		if not IconController._navigationEnabled then
			IconController._originalCoreGuiNavigationEnabled = guiService.CoreGuiNavigationEnabled
			IconController._originalGuiNavigationEnabled = guiService.GuiNavigationEnabled
			guiService.CoreGuiNavigationEnabled = false
			guiService.GuiNavigationEnabled = true
			IconController._navigationEnabled = true
		end
	end
end

local function getScaleMultiplier()
	if guiService:IsTenFootInterface() then
		return 3
	else
		return 1.3
	end
end

function IconController._setControllerSelectedObject(object)
	local startId = (IconController._controllerSetCount and IconController._controllerSetCount + 1) or 0
	IconController._controllerSetCount = startId
	guiService.SelectedObject = object
	task.delay(0.1, function()
		local finalId = IconController._controllerSetCountS
		if startId == finalId then
			guiService.SelectedObject = object
		end
	end)
end

function IconController._enableControllerMode(bool)
	local indicator = TopbarPlusGui.Indicator
	local controllerOptionIcon = IconController.getIcon("_TopbarControllerOption")
	if IconController.controllerModeEnabled == bool then
		return
	end
	IconController.controllerModeEnabled = bool
	if bool then
		TopbarPlusGui.TopbarContainer.Position = UDim2.new(0,0,0,5)
		TopbarPlusGui.TopbarContainer.Visible = false
		local scaleMultiplier = getScaleMultiplier()
		indicator.Position = UDim2.new(0.5,0,0,5)
		indicator.Size = UDim2.new(0, 18*scaleMultiplier, 0, 18*scaleMultiplier)
		indicator.Image = "rbxassetid://5278151556"
		indicator.Visible = checkTopbarEnabledAccountingForMimic()
		indicator.Position = UDim2.new(0.5,0,0,5)
		indicator.Active = true
		controllerMenuOverride = indicator.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				IconController.setTopbarEnabled(true,false)
			end
		end)
	else
		TopbarPlusGui.TopbarContainer.Position = UDim2.new(0,0,0,0)
		TopbarPlusGui.TopbarContainer.Visible = checkTopbarEnabledAccountingForMimic()
		indicator.Visible = false
		IconController._setControllerSelectedObject(nil)
	end
	for icon, _ in pairs(topbarIcons) do
		IconController._enableControllerModeForIcon(icon, bool)
	end
end

function IconController._enableControllerModeForIcon(icon, bool)
	local parentIcon = icon._parentIcon
	local featureName = icon.joinedFeatureName
	if parentIcon then
		icon:leave()
	end
	if bool then
		local scaleMultiplier = getScaleMultiplier()
		local currentSizeDeselected = icon:get("iconSize", "deselected")
		local currentSizeSelected = icon:get("iconSize", "selected")
		local currentSizeHovering = icon:getHovering("iconSize")
		icon:set("iconSize", UDim2.new(0, currentSizeDeselected.X.Offset*scaleMultiplier, 0, currentSizeDeselected.Y.Offset*scaleMultiplier), "deselected", "controllerMode")
		icon:set("iconSize", UDim2.new(0, currentSizeSelected.X.Offset*scaleMultiplier, 0, currentSizeSelected.Y.Offset*scaleMultiplier), "selected", "controllerMode")
		if currentSizeHovering then
			icon:set("iconSize", UDim2.new(0, currentSizeSelected.X.Offset*scaleMultiplier, 0, currentSizeSelected.Y.Offset*scaleMultiplier), "hovering", "controllerMode")
		end
		icon:set("alignment", "mid", "deselected", "controllerMode")
		icon:set("alignment", "mid", "selected", "controllerMode")
	else
		local states = {"deselected", "selected", "hovering"}
		for _, iconState in pairs(states) do
			local _, previousAlignment = icon:get("alignment", iconState, "controllerMode")
			if previousAlignment then
				icon:set("alignment", previousAlignment, iconState)
			end
			local currentSize, previousSize = icon:get("iconSize", iconState, "controllerMode")
			if previousSize then
				icon:set("iconSize", previousSize, iconState)
			end
		end
	end
	if parentIcon then
		icon:join(parentIcon, featureName)
	end
end

local createdFakeHealthbarIcon = false
function IconController.setupHealthbar()

	if createdFakeHealthbarIcon then
		return
	end
	createdFakeHealthbarIcon = true

	-- Create a fake healthbar icon to mimic the core health gui
	task.defer(function()
		runService.Heartbeat:Wait()
		local Icon = require(iconModule)

		Icon.new()
			:setProperty("internalIcon", true)
			:setName("_FakeHealthbar")
			:setRight()
			:setOrder(-420)
			:setSize(80, 32)
			:lock()
			:set("iconBackgroundTransparency", 1)
			:give(function(icon)

				local healthContainer = Instance.new("Frame")
				healthContainer.Name = "HealthContainer"
				healthContainer.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
				healthContainer.BorderSizePixel = 0
				healthContainer.AnchorPoint = Vector2.new(0, 0.5)
				healthContainer.Position = UDim2.new(0, 0, 0.5, 0)
				healthContainer.Size = UDim2.new(1, 0, 0.2, 0)
				healthContainer.Visible = true
				healthContainer.ZIndex = 11
				healthContainer.Parent = icon.instances.iconButton

				local corner = Instance.new("UICorner")
				corner.CornerRadius = UDim.new(1, 0)
				corner.Parent = healthContainer

				local healthFrame = healthContainer:Clone()
				healthFrame.Name = "HealthFrame"
				healthFrame.BackgroundColor3 = Color3.fromRGB(167, 167, 167)
				healthFrame.BorderSizePixel = 0
				healthFrame.AnchorPoint = Vector2.new(0.5, 0.5)
				healthFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
				healthFrame.Size = UDim2.new(1, -2, 1, -2)
				healthFrame.Visible = true
				healthFrame.ZIndex = 12
				healthFrame.Parent = healthContainer

				local healthBar = healthFrame:Clone()
				healthBar.Name = "HealthBar"
				healthBar.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
				healthBar.BorderSizePixel = 0
				healthBar.AnchorPoint = Vector2.new(0, 0.5)
				healthBar.Position = UDim2.new(0, 0, 0.5, 0)
				healthBar.Size = UDim2.new(0.5, 0, 1, 0)
				healthBar.Visible = true
				healthBar.ZIndex = 13
				healthBar.Parent = healthFrame

				local START_HEALTHBAR_COLOR = Color3.fromRGB(27, 252, 107)
				local MID_HEALTHBAR_COLOR = Color3.fromRGB(250, 235, 0)
				local END_HEALTHBAR_COLOR = Color3.fromRGB(255, 28, 0)

				local function powColor3(color, pow)
					return Color3.new(
						math.pow(color.R, pow),
						math.pow(color.G, pow),
						math.pow(color.B, pow)
					)
				end

				local function lerpColor(colorA, colorB, frac, gamma)
					gamma = gamma or 2.0
					local CA = powColor3(colorA, gamma)
					local CB = powColor3(colorB, gamma)
					return powColor3(CA:Lerp(CB, frac), 1/gamma)
				end

				local firstTimeEnabling = true
				local function listenToHealth(character)
					if not character then
						return
					end
					local humanoid = character:WaitForChild("Humanoid", 10)
					if not humanoid then
						return
					end

					local function updateHealthBar()
						local realHealthbarEnabled = starterGui:GetCoreGuiEnabled(Enum.CoreGuiType.Health)
						local healthInterval = humanoid.Health / humanoid.MaxHealth
						if healthInterval == 1 or IconController.healthbarDisabled or (firstTimeEnabling and realHealthbarEnabled == false) then
							if icon.enabled then
								icon:setEnabled(false)
							end
							return
						elseif healthInterval < 1 then
							if not icon.enabled then
								icon:setEnabled(true)
							end
							firstTimeEnabling = false
							if realHealthbarEnabled then
								starterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
							end
						end
						local startInterval = 0.9
						local endInterval = 0.1
						local m = 1/(startInterval - endInterval)
						local c = -m*endInterval
						local colorIntervalAbsolute = (m*healthInterval) + c
						local colorInterval = (colorIntervalAbsolute > 1 and 1) or (colorIntervalAbsolute < 0 and 0) or colorIntervalAbsolute
						local firstColor = (healthInterval > 0.5 and START_HEALTHBAR_COLOR) or MID_HEALTHBAR_COLOR
						local lastColor = (healthInterval > 0.5 and MID_HEALTHBAR_COLOR) or END_HEALTHBAR_COLOR
						local doubleSubtractor = (1-colorInterval)*2
						local modifiedColorInterval = (healthInterval > 0.5 and (1-doubleSubtractor)) or (2-doubleSubtractor)
						local newHealthFillColor = lerpColor(lastColor, firstColor, modifiedColorInterval)
						local newHealthFillSize = UDim2.new(healthInterval, 0, 1, 0)
						healthBar.BackgroundColor3 = newHealthFillColor
						healthBar.Size = newHealthFillSize
					end

					humanoid.HealthChanged:Connect(updateHealthBar)
					IconController.healthbarDisabledSignal:Connect(updateHealthBar)
					updateHealthBar()
				end
				localPlayer.CharacterAdded:Connect(function(character)
					listenToHealth(character)
				end)
				task.spawn(listenToHealth, localPlayer.Character)
			end)
	end)
end

function IconController._determineControllerDisplay()
	local mouseEnabled = userInputService.MouseEnabled
	local controllerEnabled = userInputService.GamepadEnabled
	local controllerOptionIcon = IconController.getIcon("_TopbarControllerOption")
	if mouseEnabled and controllerEnabled then
		-- Show icon (if option not disabled else hide)
		if not disableControllerOption then
			controllerOptionIcon:setEnabled(true)
		else
			controllerOptionIcon:setEnabled(false)
		end
	elseif mouseEnabled and not controllerEnabled then
		-- Hide icon, disableControllerMode
		controllerOptionIcon:setEnabled(false)
		IconController._enableControllerMode(false)
		controllerOptionIcon:deselect()
	elseif not mouseEnabled and controllerEnabled then
		-- Hide icon, _enableControllerMode
		controllerOptionIcon:setEnabled(false)
		IconController._enableControllerMode(true)
	end
end



-- BEHAVIOUR
--Controller support
coroutine.wrap(function()

	-- Create PC 'Enter Controller Mode' Icon
	runService.Heartbeat:Wait() -- This is required to prevent an infinite recursion
	local Icon = require(iconModule)
	local controllerOptionIcon = Icon.new()
		:setProperty("internalIcon", true)
		:setName("_TopbarControllerOption")
		:setOrder(100)
		:setImage(11162828670)
		:setRight()
		:setEnabled(false)
		:setTip("Controller mode")
		:setProperty("deselectWhenOtherIconSelected", false)

	-- This decides what controller widgets and displays to show based upon their connected inputs
	-- For example, if on PC with a controller, give the player the option to enable controller mode with a toggle
	-- While if using a console (no mouse, but controller) then bypass the toggle and automatically enable controller mode
	userInputService:GetPropertyChangedSignal("MouseEnabled"):Connect(IconController._determineControllerDisplay)
	userInputService.GamepadConnected:Connect(IconController._determineControllerDisplay)
	userInputService.GamepadDisconnected:Connect(IconController._determineControllerDisplay)
	IconController._determineControllerDisplay()

	-- Enable/Disable Controller Mode when icon clicked
	local function iconClicked()
		local isSelected = controllerOptionIcon.isSelected
		local iconTip = (isSelected and "Normal mode") or "Controller mode"
		controllerOptionIcon:setTip(iconTip)
		IconController._enableControllerMode(isSelected)
	end
	controllerOptionIcon.selected:Connect(iconClicked)
	controllerOptionIcon.deselected:Connect(iconClicked)

	-- Hide/show topbar when indicator action selected in controller mode
	userInputService.InputBegan:Connect(function(input,gpe)
		if not IconController.controllerModeEnabled then return end
		if input.KeyCode == Enum.KeyCode.DPadDown then
			if not guiService.SelectedObject and checkTopbarEnabledAccountingForMimic() then
				IconController.setTopbarEnabled(true,false)
			end
		elseif input.KeyCode == Enum.KeyCode.ButtonB and not IconController.disableButtonB then
			if IconController.activeButtonBCallbacks == 1 and TopbarPlusGui.Indicator.Image == "rbxassetid://5278151556" then
				IconController.activeButtonBCallbacks = 0
				guiService.SelectedObject = nil
			end
			if IconController.activeButtonBCallbacks == 0 then
				IconController._previousSelectedObject = guiService.SelectedObject
				IconController._setControllerSelectedObject(nil)
				IconController.setTopbarEnabled(false,false)
			end
		end
		input:Destroy()
	end)

	-- Setup overflow icons
	for alignment, detail in pairs(alignmentDetails) do
		if alignment ~= "mid" then
			local overflowName = "_overflowIcon-"..alignment
			local overflowIcon = Icon.new()
				:setProperty("internalIcon", true)
				:setImage(6069276526)
				:setName(overflowName)
				:setEnabled(false)
			detail.overflowIcon = overflowIcon
			overflowIcon.accountForWhenDisabled = true
			if alignment == "left" then
				overflowIcon:setOrder(math.huge)
				overflowIcon:setLeft()
				overflowIcon:set("dropdownAlignment", "right")
			elseif alignment == "right" then
				overflowIcon:setOrder(-math.huge)
				overflowIcon:setRight()
				overflowIcon:set("dropdownAlignment", "left")
			end
			overflowIcon.lockedSettings = {
				["iconImage"] = true,
				["order"] = true,
				["alignment"] = true,
			}
		end
	end

	if not isStudio then
		local ownerId = game.CreatorId
		local groupService = game:GetService("GroupService")
		if game.CreatorType == Enum.CreatorType.Group then
			local success, ownerInfo = pcall(function() return groupService:GetGroupInfoAsync(game.CreatorId).Owner end)
			if success then
				ownerId = ownerInfo.Id
			end
		end
		local version = require(iconModule.VERSION)
		if localPlayer.UserId ~= ownerId then
			local marketplaceService = game:GetService("MarketplaceService")
			local success, placeInfo = pcall(function() return marketplaceService:GetProductInfo(game.PlaceId) end)
			if success and placeInfo then
				-- Required attrbute for using TopbarPlus
				-- This is not printed within stuido and to the game owner to prevent mixing with debug prints
				local gameName = placeInfo.Name
				print(("\n\n\n⚽ %s uses TopbarPlus %s\n🍍 TopbarPlus was developed by ForeverHD and the Nanoblox Team, and forked by Bebop Development Studios\n🚀 You can learn more and take a free copy by searching for 'TopbarPlus' on the DevForum\n\n"):format(gameName, version))
			end
		end
	end

end)()

-- Mimic the enabling of the topbar when StarterGui:SetCore("TopbarEnabled", state) is called
coroutine.wrap(function()
	local chatScript = players.LocalPlayer.PlayerScripts:WaitForChild("ChatScript", 4) or game:GetService("Chat"):WaitForChild("ChatScript", 4)
	if not chatScript then return end
	local chatMain = chatScript:FindFirstChild("ChatMain")
	if not chatMain then return end
	local ChatMain = require(chatMain)
	ChatMain.CoreGuiEnabled:connect(function()
		local topbarEnabled = checkTopbarEnabled()
		if topbarEnabled == IconController.previousTopbarEnabled then
			IconController.updateTopbar()
			return "SetCoreGuiEnabled was called instead of SetCore"
		end
		if IconController.mimicCoreGui then
			IconController.previousTopbarEnabled = topbarEnabled
			if IconController.controllerModeEnabled then
				IconController.setTopbarEnabled(false,false)
			else
				IconController.setTopbarEnabled(topbarEnabled,false)
			end
		end
		IconController.updateTopbar()
	end)
	local makeVisible = checkTopbarEnabled()
	if not makeVisible and not IconController.mimicCoreGui then
		makeVisible = true
	end
	IconController.setTopbarEnabled(makeVisible, false)
end)()

-- Mimic roblox menu when opened and closed
guiService.MenuClosed:Connect(function()
	if VRService.VREnabled then
		return
	end
	menuOpen = false
	if not IconController.controllerModeEnabled then
		IconController.setTopbarEnabled(IconController.topbarEnabled,false)
	end
end)
guiService.MenuOpened:Connect(function()
	if VRService.VREnabled then
		return
	end
	menuOpen = true
	IconController.setTopbarEnabled(false,false)
end)

bindCamera()
bindTopBarInsetChanged()

-- It's important we update all icons when a players language changes to account for changes in the width of text, etc
task.spawn(function()
	local success, translator = pcall(function() return localizationService:GetTranslatorForPlayerAsync(localPlayer) end)
	local function updateAllIcons()
		local icons = IconController.getIcons()
		for _, icon in pairs(icons) do
			icon:_updateAll()
		end
	end
	if success then
		IconController.translator = translator
		translator:GetPropertyChangedSignal("LocaleId"):Connect(updateAllIcons)
		task.spawn(updateAllIcons)
		task.delay(1, updateAllIcons)
		task.delay(10, updateAllIcons)
	end
end)


return IconController
