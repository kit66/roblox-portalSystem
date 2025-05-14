-- running system for player. Smooth acceleration 

local Players = game:GetService("Players")
local player = Players.LocalPlayer

local inputService = game:GetService("UserInputService")

local run_key = Enum.KeyCode.LeftShift
local f = false

-- speed+
local function raiseSpeed(character)	
	while character.Humanoid.WalkSpeed <40 do
		if not f then 
			break
		end
		character.Humanoid.WalkSpeed = character.Humanoid.WalkSpeed+1
		task.wait(0.01)
	end
end


local function run(input, _gameProcessed)
	local pressed_button = inputService:IsKeyDown(run_key)
	if pressed_button then
		local character = player.Character
		f = true
		raiseSpeed(character)
	end

end

-- speed-
local function downSpeed(character) 
	while character.Humanoid.WalkSpeed >12 do
		if f then 
			break
		end
		character.Humanoid.WalkSpeed = character.Humanoid.WalkSpeed-1
		task.wait(0.01)
	end
end

local function runoff (input, _gameProcessed)
	local pressed_button = inputService:IsKeyDown(run_key)
	if f and not pressed_button then
		local character = player.Character
		f = false
		downSpeed(character)
	end
end


inputService.InputBegan:Connect(run)
inputService.InputEnded:Connect(runoff)







--local Players = game:GetService("Players")
--local player = Players.LocalPlayer

--local inputService = game:GetService("UserInputService")

--local run_key = Enum.KeyCode.LeftShift
--local flag = false

--local function run(input, _gameProcessed)
--	local character = player.Character
--	local pressed_button = inputService:IsKeyDown(run_key)
--	if pressed_button then
--		if flag then
--			character.Humanoid.WalkSpeed = 12
--			flag = false
--			print("off")
--		else
--			character.Humanoid.WalkSpeed = 250
--			flag = true
--			print("on")
--		end
--	end
	
--end

--inputService.InputBegan:Connect(run)



