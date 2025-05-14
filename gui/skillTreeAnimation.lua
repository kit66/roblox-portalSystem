-- animation for skill Tree gui (tree icon on right) 
local TS = game:GetService("TweenService")
local flag = true

local tweenInfo = TweenInfo.new(3,Enum.EasingStyle.Bounce)
local tweenInfoBack = TweenInfo.new(1.5,Enum.EasingStyle.Exponential)

local anim = TS:Create(script.Parent.Frame,tweenInfo,{Position = UDim2.fromScale(0,-1.5)})
local anim2 = TS:Create(script.Parent.ImageButton,tweenInfo,{Position = UDim2.fromScale(0.747,-1.5)})

local animback = TS:Create(script.Parent.Frame,tweenInfoBack,{Position = UDim2.fromScale(0,0)})
local animback2 = TS:Create(script.Parent.ImageButton,tweenInfoBack,{Position = UDim2.fromScale(0.747,0.268)})

local function open()
	animback:Play()
	animback2:Play()
end

local function close()
	anim:Play()
	anim2:Play()
end

script.Parent.ImageButton.Activated:Connect(function()
	close()
	flag = false
end)

script.Parent.Parent.scorebar.buttons.PerkTree.Activated:Connect(function()
	if flag then
		close()
		flag = false
	else
		open()
		flag = true
	end
end)

