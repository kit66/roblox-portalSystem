-- services
local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Debris = game:GetService("Debris")

-- get player current camera direction (cframe.LookVector) 
local GetCameraDirectionFunction = RS:WaitForChild("getCameraDirection")
-- remote ability cast request
local castFunction = RS:WaitForChild("cast")

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

-- init new ability by config
function Abilities.new(cfg: AbilityData)
	local self = setmetatable({}, Abilities)
	self.config = cfg
	self.lastUsed  = -math.huge
	self.onActivate = cfg.onActivate
	return self
end

-- check if ability has cooldown
function Abilities:isReady(): boolean
	return (tick() - self.lastUsed) >= self.config.cooldown
end

-- activate ability and set cooldown
function Abilities:use(player: Player)	
	self.lastUsed = tick()
	self:onActivate(player)
end

-- refresh ability cooldown
function Abilities:refresh()
	self.lastUsed = -math.huge
end


-- states - use to control player state
local States = {}
States.__index = States

type StateName = "Idle" | "Silenced"

type StatesType = typeof(setmetatable( {} :: { current: StateName, SilenceFunc: thread?}, States))

type PlayerStateData = {
	state: StatesType,
	abilities: {[string]: AbilitiesType},
}		

-- init new state object
function States.new(): StatesType
	return setmetatable({current = "Idle"}, States)
end

-- set player state
function States:setState(newState: StateName)
	self.current = newState
end

-- remove silence state and cancel silence thread
function States:CancelSilence()
	-- cancel any current cancelling silence thread
	if self.SilenceFunc then
		task.cancel(self.SilenceFunc)
	end
	-- set default state
	self.current = "Idle"
	self.SilenceFunc = nil
end

-- set silence state and start silence thread
function States:setSilence(duration: number)
	-- cancel any current cancelling silence to prevent from stacking silence
	if self.SilenceFunc then
		task.cancel(self.SilenceFunc)
	end

	self.current = "Silenced"

	-- remove silence in thread after duration
	self.SilenceFunc = task.delay(duration, function()
		--prevent check for the same thread
		self.SilenceFunc = nil  
		self:CancelSilence()
	end)
end



local playersRegister: {[number]: PlayerStateData} = {}

-- heal player and reset cooldown on every ability
local function refreshPlayer(player)
	local humanoid = player.Character:FindFirstChild("Humanoid")
	humanoid.Health = humanoid.MaxHealth

	for _, ability in pairs(playersRegister[player.UserId].abilities) do
		ability:refresh()
	end
end

-- config
local abilitiesConfig = {
	["Fireball"] = {
		damage = 40,
		cooldown = 1,
		travelTime = 2,
		speed = 20,

		allowCastStates = {"Idle"},

		onActivate = function (self, player)
			local lookDirection = GetCameraDirectionFunction:InvokeClient(player)

			-- Spawn projectile slightly in front of the character in camera direction
			local fireball = RS:WaitForChild("fireball"):Clone()
			fireball.Position = player.Character:WaitForChild("HumanoidRootPart").Position + lookDirection * 2 + Vector3.new(0, 1, 0)
			fireball.Parent = workspace:WaitForChild("Projectiles")
			
			-- apply velocity with speed
			local velocity = Instance.new("BodyVelocity")
			velocity.Velocity = lookDirection.Unit * self.config.speed
			velocity.MaxForce = Vector3.new(1e5, 1e5, 1e5)
			velocity.Parent = fireball
			
			-- destroy projectile after travel time if not collided with anyting
			Debris:AddItem(fireball, self.config.travelTime)

			local damaged = {}

			fireball.Touched:Connect(function(otherPart: BasePart)
				-- do not destroy if collided with any other projectile (projecties folder)
				if otherPart:FindFirstAncestorWhichIsA("Folder") == fireball.Parent then return end

				local character = otherPart:FindFirstAncestorWhichIsA("Model")
				if character then 
					-- do not destroy and do not deal damage if collided with a owner of the projectile
					local targetPlayer = Players:GetPlayerFromCharacter(character)
					if targetPlayer and targetPlayer == player then return end	

					-- collided with another player 
					fireball:Destroy()
					
					local humanoid = character:FindFirstChild("Humanoid")
					if not humanoid then return end 
					
					-- do not damage same humanoid twice
					if damaged[humanoid] then return end
					damaged[humanoid] = true

					local oldHealth = humanoid.Health
					
					humanoid:TakeDamage(self.config.damage)

					-- bonus on kill - only for fireball
					if oldHealth > 0 and humanoid.Health <= 0 then
						refreshPlayer(player)
						-- update cooldown timer on client
						castFunction:InvokeClient(player)
					end
				else
					-- collided with something else
					fireball:Destroy()
				end
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
			
			-- spawn cone in camera direction without vertical component
			local conus = RS:WaitForChild("conus"):Clone()
			conus:PivotTo(CFrame.lookAt(position, position + flatDirection.Unit))
			conus.Parent = workspace:WaitForChild("Projectiles")

			-- destroy cone after stayTime
			Debris:AddItem(conus, self.config.stayTime)

			-- damage until exists
			task.spawn(function()
				while conus.Parent do
					local damaged = {}
					local parts = workspace:GetPartsInPart(conus.conus)
					
					-- damage multiple players
					for _, part in pairs(parts) do
						local character = part:FindFirstAncestorWhichIsA("Model")
						if not character then continue end
						
						-- do not damage projectile owner
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
		damage = 20,
		cooldown = 4,
		stayTime = 0.3,
		SilenceDuration = 5,

		allowCastStates = {"Idle"},

		onActivate = function (self, player)
			-- ring around player
			local position = player.Character:WaitForChild("HumanoidRootPart").Position 
			
			-- spawn ring in player
			local ring = RS:WaitForChild("ring"):Clone()
			ring:PivotTo(CFrame.new(position))
			ring.Parent = workspace:WaitForChild("Projectiles")
			
			-- destroy ring after stayTime
			Debris:AddItem(ring, self.config.stayTime)


			-- deal damage and apply status one time to all players that collided
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

				-- silence only players, NPC does not have register
				if targetPlayer then
					playersRegister[targetPlayer.UserId].state:setSilence(self.config.SilenceDuration)
				end
				
				humanoid:TakeDamage(self.config.damage)
			end
		end,
	},
	["cleanse"] = {
		cooldown = 10,

		-- could be activated only when silenced () by 'ring' ability
		allowCastStates = {"Silenced"},

		onActivate = function (self, player)
			playersRegister[player.UserId].state:CancelSilence()
		end,
	}
}

-- boost ability config if players has premium
local function boostAbilityIfPremium(player: Player, abilityConfig: AbilityData) : AbilityData
	-- return without boost
	if player.MembershipType ~= Enum.MembershipType.Premium then return abilityConfig end
	
	-- new boosted config
	local newAbilityConfig = table.clone(abilityConfig)
	newAbilityConfig.damage *= 2

	return newAbilityConfig
end

-- handle remote cast spell request
local function castSpellRequest(player: Player, abilityName: string)
	-- player must have registered ability on server
	local playerState = playersRegister[player.UserId]
	if not playerState then return false end	

	local ability = playerState.abilities[abilityName]
	if not ability  then return false end

	-- player have right state for skill
	if not table.find(ability.config.allowCastStates, playerState.state.current) then return end

	if not ability:isReady() then return false end

	task.spawn(function()
		ability:use(player)
	end)
	
	-- send cooldown time to client
	return true, ability.config.cooldown
end

local function onPlayerAdded(player: Player)
	-- register every skill for player and state
	playersRegister[player.UserId] = {
		state = States.new(),
		-- could be skills from dataStore that player have (buyed or obtained), but for now - fixed list of skills
		abilities = {
			Fireball   = Abilities.new(boostAbilityIfPremium(player, abilitiesConfig.Fireball)),
			iceConus   = Abilities.new(boostAbilityIfPremium(player, abilitiesConfig.iceConus)),
			silenceRing = Abilities.new(boostAbilityIfPremium(player, abilitiesConfig.silenceRing)),
			cleanse = Abilities.new(abilitiesConfig.cleanse),
		},
	}
end

local function onPlayerRemoved(player: Player)
	-- GC automatically cleanup metatables inside
	playersRegister[player.UserId] = nil
end

castFunction.OnServerInvoke = castSpellRequest
Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoved)
