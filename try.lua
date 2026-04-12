local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local debris = game:GetService("Debris")

local GetCameraDirectionFunction = RS:WaitForChild("getCameraDirection")
local castFunction = RS:WaitForChild("cast")

--------
local Abilities = {}
Abilities.__index = Abilities

type AbilitiesType = typeof(setmetatable( {} :: AbilityData, Abilities))

type AbilityData = {
	config: { 
		damage: number,
		cooldown: number?,
		allowCastStates: { StateName }?,
	},
	onActivate: ((self: AbilityData, player: Player) -> ())?,
}

function Abilities.new(cfg: AbilityData)
	local self = setmetatable({}, Abilities)
	self.config = cfg
	self.lastUsed  = -math.huge
	self.onActivate = cfg.onActivate
	return self
end

function Abilities:isReady(): boolean
	return (tick() - self.lastUsed) >= self.config.cooldown
end

function Abilities:use(player: Player)	
	self.lastUsed = tick()
	self:onActivate(player)
end

function Abilities:refresh()
	self.lastUsed = -math.huge
end

--------
local States = {}
States.__index = States

type StateName = "Idle" | "Silenced"

type StatesType = typeof(setmetatable( {} :: { current: StateName, SilenceFunc: thread?}, States))

type PlayerStateData = {
	state: StatesType,
	abilities: {[string]: AbilitiesType},
}		

function States.new(): StatesType
	return setmetatable({current = "Idle"}, States)
end

function States:setState(newState: StateName)
	self.current = newState
end

function States:CancelSilence()
	if self.SilenceFunc then
		task.cancel(self.SilenceFunc)
	end
	self.current = "Idle"
	self.SilenceFunc = nil
end

function States:setSilence(duration: number)
	if self.SilenceFunc then
		task.cancel(self.SilenceFunc)
	end

	self.current = "Silenced"
	
	
	self.SilenceFunc = task.delay(duration, function()
		--prevent check for the same thread
		self.SilenceFunc = nil  
		self:CancelSilence()
	end)
end

--------
local playersRegister: {[number]: PlayerStateData} = {}


local function refreshPlayer(player)
	local humanoid = player.Character:FindFirstChild("Humanoid")
	humanoid.Health = humanoid.MaxHealth

	for _, ability in pairs(playersRegister[player.UserId].abilities) do
		ability:refresh()
	end
end

--------
local abilitiesConfig = {
	["Fireball"] = {
		damage = 10,
		cooldown = 1,
		travelTime = 2,
		speed = 20,
		
		allowCastStates = {"Idle"},

		onActivate = function (self, player)
			local lookDirection = GetCameraDirectionFunction:InvokeClient(player)

			-- Spawn projectile slightly in front of the character in camera direction
			local proj = RS:WaitForChild("fireball"):Clone()
			proj.Position = player.character:WaitForChild("HumanoidRootPart").Position + lookDirection * 2 + Vector3.new(0, 1, 0)
			proj.Parent = workspace:WaitForChild("Projectiles")

			local velocity = Instance.new("BodyVelocity")
			velocity.Velocity = lookDirection.Unit * self.config.speed
			velocity.MaxForce = Vector3.new(1e5, 1e5, 1e5)
			velocity.Parent = proj

			debris:AddItem(proj, self.config.travelTime)
			
			local damaged = {}

			proj.Touched:Connect(function(otherPart: BasePart)
				-- do not destroy if collided with a projectile (projecties folder)
				if otherPart.Parent == proj.Parent then return end
				
				-- do not destroy and do not deal damage if collided with a author of the projectile
				-- nesting unavoidable, cant return
				local character = otherPart:FindFirstAncestorWhichIsA("Model")
				if character then 
					local targetPlayer = Players:GetPlayerFromCharacter(character)
					if targetPlayer and targetPlayer == player then return end	
					
					local humanoid = character:FindFirstChild("Humanoid")
					if humanoid then
						-- do not damage same humanoid twice
						if not damaged[humanoid] then
							damaged[humanoid] = true

							local oldHealth = humanoid.Health
							humanoid:TakeDamage(self.config.damage)

							-- bonus on kill - only for fireball
							if oldHealth > 0 and humanoid.Health <= 0 then
								refreshPlayer(player)
								-- update cooldown timer on client
								castFunction:InvokeClient(player)
							end
						end
					end
				end 
				
				proj:Destroy()
			end)
		end
		
	},
	["iceConus"] = {
		damage = 4,
		cooldown = 3,
		stayTime = 5,
		
		allowCastStates = {"Idle"},

		onActivate = function (self, player)
			local lookDirection = GetCameraDirectionFunction:InvokeClient(player)
			
			-- position under player
			local position = player.Character:WaitForChild("HumanoidRootPart").Position - Vector3.new(0, 3, 0)

			-- ignore vertical camera direction
			local flatDirection = Vector3.new(lookDirection.X, 0, lookDirection.Z)

			local conus = RS:WaitForChild("conus"):Clone()
			conus:PivotTo(CFrame.lookAt(position, position + flatDirection.Unit))
			conus.Parent = workspace:WaitForChild("Projectiles")
			

			debris:AddItem(conus, self.config.stayTime)

			-- damage until exists
			task.spawn(function()
				while conus.Parent do
					local damaged = {}
					local parts = workspace:GetPartsInPart(conus.conus)
					
					for _, part in pairs(parts) do
						local character = part:FindFirstAncestorWhichIsA("Model")
						if not character then continue end
						
						local targetPlayer = Players:GetPlayerFromCharacter(character)
						if  targetPlayer and targetPlayer == player then continue end
						
						local humanoid = character:FindFirstChild("Humanoid")
						if not humanoid then continue end
						
						-- do not damage same humanoid twice
						if damaged[humanoid] then continue end
						damaged[humanoid] = true
	
						humanoid:TakeDamage(self.config.damage)
					end
					task.wait(0.5)
				end	
			end)
		end,
	},
	["silenceRing"] = {
		damage = 10,
		cooldown = 4,
		stayTime = 0.3,
		SilenceDuration = 5,
		
		allowCastStates = {"Idle"},

		onActivate = function (self, player)
			local position = player.Character:WaitForChild("HumanoidRootPart").Position 
			
			local ring = RS:WaitForChild("ring"):Clone()
			ring:PivotTo(CFrame.new(position))
			ring.Parent = workspace:WaitForChild("Projectiles")
			
			debris:AddItem(ring, self.config.stayTime)

			local damaged = {}
			local parts = workspace:GetPartsInPart(ring.ring)

			for _, part in pairs(parts) do
				local character = part:FindFirstAncestorWhichIsA("Model")
				if not character then continue end

				local targetPlayer = Players:GetPlayerFromCharacter(character)
				if targetPlayer and targetPlayer == player then continue end

				local humanoid = character:FindFirstChild("Humanoid")
				if not humanoid then continue end

				-- do not damage same humanoid twice
				if damaged[humanoid] then continue end
				damaged[humanoid] = true

				if targetPlayer then
					playersRegister[targetPlayer.UserId].state:setSilence(self.config.SilenceDuration)
				end
				humanoid:TakeDamage(self.config.damage)
			end
		end,
	},
	["cleanse"] = {
		cooldown = 10,
		
		allowCastStates = {"Silenced"},
		
		onActivate = function (self, player)
			playersRegister[player.UserId].state:CancelSilence()
		end,
	}
}

--------
local function boostAbilityIfInGroup(player: Player, abilityConfig: AbilityData) : AbilityData
	if not player:IsInGroupAsync(12345678) then return abilityConfig end

	local newAbilityConfig = table.clone(abilityConfig)
	newAbilityConfig.damage += newAbilityConfig.damage

	return newAbilityConfig
end

local function castSpellRequest(player: Player, abilityName: string)
	local playerState = playersRegister[player.UserId]
	if not playerState then return false end	

	local ability = playerState.abilities[abilityName]
	if not ability  then return false end

	if not table.find(ability.config.allowCastStates, playerState.state.current) then return end

	if not ability:isReady() then return false end

	task.spawn(function()
		ability:use(player)
	end)

	return true, ability.config.cooldown
end

local function onPlayerRemoved(player: Player)
	-- GC automatically cleanup metatables inside
	playersRegister[player.UserId] = nil
end

local function onPlayerAdded(player: Player)
	playersRegister[player.UserId] = {
		state = States.new(),
		abilities = {
			Fireball   = Abilities.new(boostAbilityIfInGroup(player, abilitiesConfig.Fireball)),
			iceConus   = Abilities.new(boostAbilityIfInGroup(player, abilitiesConfig.iceConus)),
			silenceRing = Abilities.new(boostAbilityIfInGroup(player, abilitiesConfig.silenceRing)),
			cleanse = Abilities.new(abilitiesConfig.cleanse),
		},
	}
end

castFunction.OnServerInvoke = castSpellRequest
Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoved)