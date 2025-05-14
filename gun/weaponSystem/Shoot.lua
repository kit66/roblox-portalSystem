local UIS = game:GetService("UserInputService")
local replicated = game:GetService("ReplicatedStorage")

local weapon = script.Parent.Parent.Parent
local player = weapon.Parent.Parent.Name
local character = workspace:WaitForChild(player)

local param = RaycastParams.new()

local maxMouseDistance = 1000
local maxGunRange = 100

-- Set up an array of wall objects to exclude from collision when shooting
local array = {
	weapon.Handle,
	Vector3,
	character}

for _,plot in ipairs(workspace.plots:GetChildren()) do 
	table.insert(array,plot.wal.wal1)
	table.insert(array,plot.wal.wal2)
	table.insert(array,plot.wal.wal3)
	table.insert(array,plot.wal.wal4)
end

param.FilterDescendantsInstances = array

local shoot = {}
-- get mouse position
local function getWorldMousePosition()
	local mousePosition = UIS:GetMouseLocation()
	local Screentoworldray = workspace.CurrentCamera:ViewportPointToRay(mousePosition.x,mousePosition.y)
	local DirectionVector = Screentoworldray.Direction * maxMouseDistance

	local raycastResult = workspace:Raycast(Screentoworldray.Origin,DirectionVector,param)
	if raycastResult then
		return raycastResult.Position
	end

end

-- create vecrtor from gun to mouse and return hitted object
function shoot.fireWeapon()
	local mouseLocation = getWorldMousePosition()
	if mouseLocation then
		local targetDirection = (mouseLocation - weapon.Handle.Position).Unit
		local DirectionVector = targetDirection * maxGunRange

		local raycastResult = workspace:Raycast(weapon.Handle.Position, DirectionVector, param)
		if raycastResult then
			local HitObject = raycastResult.Instance
			return HitObject,targetDirection
		end
	end
end
return shoot