local replicated = game:GetService("ReplicatedStorage")
local events = replicated.events
local players = game:GetService("Players")

local weapon = script.Parent
local sound = weapon.WeaponSystem.Assets.Sound
WeaponManager = require(weapon.WeaponSystem.Libraries.Shoot)
CoinsManager = require(weapon.WeaponSystem.Libraries.CoinsManager)

local canFire = true

-- update cooldown by event
local function cooldownEnd(name)
	if weapon.Name == name then 
		canFire = true
		end
end

-- fire weapon on shoot and check hitObject is owned luckyBlock
local function gunActivated()
	if canFire then 
		canFire = false
		events.cooldown:FireServer(weapon.Name,weapon.Configuration.ReloadTime.Value)
		local HitObject, direction = WeaponManager.fireWeapon()
		sound:Play()

		if HitObject then
			if HitObject:IsA("BasePart") then
				if HitObject.Name  == "LuckyBlock" and HitObject.Parent.owner.Value == weapon.Parent.Name then
					local DAMAGE = weapon.Configuration.Damage.Value
					replicated.events.anima:FireServer(HitObject,direction)
					replicated.events.blockDamaged:FireServer(DAMAGE,HitObject,direction)
					CoinsManager.spawncoin(DAMAGE,HitObject)
					
				end
			end
		end
	end
end

weapon.Equipped:Connect(gunEquipped)
weapon.Activated:Connect(gunActivated)
weapon.Unequipped:Connect(gunUnEquipped)
events.cooldown.OnClientEvent:Connect(cooldownEnd)