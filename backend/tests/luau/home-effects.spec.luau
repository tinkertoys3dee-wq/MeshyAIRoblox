local checks = 0
local function check(value, message)
	checks += 1
	assert(value, message)
end
local function equal(actual, expected, message)
	check(actual == expected, message .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end
local function near(actual, expected, message)
	check(math.abs(actual - expected) < 0.00001, message)
end
local function settle()
	while #delayed > 0 do table.remove(delayed, 1)() end
end
local Motion, Factory, Effects = require("Motion"), require("Factory"), require("HomeEffects")
local parent = Instance.new("Frame")
local accent = Color3.fromRGB(189, 75, 255)
local button = Factory.New("TextButton", {
	Parent = parent, AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(0.25, 30, 0.4, 20), Size = UDim2.new(0.4, -8, 0, 56),
})
local size = button.Size
Effects.Button(button, accent)
local pop = button:FindFirstChild("PopScale")
check(pop and pop.Scale == 1, "Button starts at its authored scale")
equal(button.Size, size, "Opt-in pops preserve the authored button size")
near(button.Position.X.Scale, 0.05, "Centering the pivot preserves scaled horizontal bounds")
equal(button.Position.X.Offset, 34, "Centering the pivot preserves offset horizontal bounds")
equal(button.Position.Y.Offset, 48, "Centering the pivot preserves vertical bounds")
local centered, children = button.Position, #button:GetChildren()
Effects.Button(button, accent)
equal(button.Position, centered, "Repeated binding does not move the pivot again")
equal(#button:GetChildren(), children, "Repeated binding does not duplicate a scale or listeners")
button.MouseEnter:Fire()
near(pop.Scale, 1.035, "Hover enlarges the Home button")
equal(button:FindFirstChild("InteractionOutline").Color, accent, "Hover outline matches the card accent")
for _, input in {
	{ UserInputType = Enum.UserInputType.MouseButton1, KeyCode = Enum.KeyCode.Unknown },
	{ UserInputType = Enum.UserInputType.Touch, KeyCode = Enum.KeyCode.Unknown },
	{ UserInputType = Enum.UserInputType.Gamepad1, KeyCode = Enum.KeyCode.ButtonA },
	{ UserInputType = Enum.UserInputType.Keyboard, KeyCode = Enum.KeyCode.Return },
	{ UserInputType = Enum.UserInputType.Keyboard, KeyCode = Enum.KeyCode.Space },
} do
	button.InputBegan:Fire(input)
	near(pop.Scale, 0.95, input.UserInputType.Name .. " compresses while held")
	button.InputEnded:Fire(input)
	check(pop.Scale > 1.035, input.UserInputType.Name .. " rebounds on release")
	settle()
	near(pop.Scale, 1.035, "Release settles back to the hover scale")
end
local mouse = { UserInputType = Enum.UserInputType.MouseButton1, KeyCode = Enum.KeyCode.Unknown }
button.InputBegan:Fire(mouse)
button.InputEnded:Fire({ UserInputType = Enum.UserInputType.MouseMovement, KeyCode = Enum.KeyCode.Unknown })
near(pop.Scale, 0.95, "Unrelated input release does not interrupt a held press")
button.InputEnded:Fire(mouse)
button.Activated:Fire()
local before = tweenCount
table.remove(delayed, 1)()
equal(tweenCount, before, "An older release cannot overwrite a newer rebound")
button.MouseLeave:Fire()
settle()
near(pop.Scale, 1, "Leaving the button cancels queued rebound recovery")
button.SelectionGained:Fire()
near(pop.Scale, 1.035, "Keyboard/gamepad focus gets the same pop as hover")
button.Active = false
near(pop.Scale, 1, "A disabled button returns to its resting scale")
button.InputBegan:Fire(mouse)
button.Activated:Fire()
near(pop.Scale, 1, "Disabled controls cannot pop on activation")
button.Active = true
button.SelectionLost:Fire()
button.Activated:Fire()
button:Destroy()
before = tweenCount
settle()
equal(tweenCount, before, "Destroyed buttons do not start delayed tweens")

local card = Factory.New("Frame", { Parent = parent, Position = UDim2.fromOffset(20, 80) })
local action = Factory.New("TextButton", { Parent = card })
Effects.Card(card, action, accent, 0.07)
equal(card.Position.Y.Offset, 102, "Card waits below its resting position for its entrance")
card.MouseEnter:Fire()
equal(card.Position.Y.Offset, 74, "Hover interrupts the entrance and lifts the card")
check(card:FindFirstChild("CardGlow").Transparency < 0.2, "Hover reveals a colored card glow")
settle()
equal(card.Position.Y.Offset, 74, "Delayed entrance never overwrites a hovered card")
card.MouseLeave:Fire()
equal(card.Position.Y.Offset, 80, "Leaving the card restores its original position")
action.SelectionGained:Fire()
equal(card.Position.Y.Offset, 74, "Focusing the CTA emphasizes its whole card")
action.SelectionLost:Fire()
equal(card.Position.Y.Offset, 80, "Removing CTA focus restores the card")
local waitingCard = Factory.New("Frame", { Parent = parent, Position = UDim2.fromOffset(10, 25) })
Effects.Card(waitingCard, Factory.New("TextButton", { Parent = waitingCard }), accent, 0.14)
waitingCard:Destroy()
before = tweenCount
settle()
equal(tweenCount, before, "Destroyed cards cancel their staggered entrance")

local shortcut = Factory.New("TextButton", { Parent = parent, Position = UDim2.fromOffset(10, 200) })
Effects.Rise(shortcut, 0.2, 14)
equal(shortcut.Position.Y.Offset, 214, "Shortcut starts below its final position")
settle()
equal(shortcut.Position.Y.Offset, 200, "Shortcut entrance restores its authored position")
Effects.Rise(shortcut, 0.2, 14)
shortcut:Destroy()
before = tweenCount
settle()
equal(tweenCount, before, "Destroyed shortcuts cancel delayed entrances")

Motion.Configure(function() return true end)
local reducedButton = Factory.New("TextButton", { Parent = parent, Position = UDim2.fromOffset(5, 10), Size = UDim2.fromOffset(120, 48) })
Effects.Button(reducedButton, accent)
local reducedPop = reducedButton:FindFirstChild("PopScale")
before = tweenCount
reducedButton.MouseEnter:Fire()
reducedButton.InputBegan:Fire(mouse)
reducedButton.InputEnded:Fire(mouse)
reducedButton.Activated:Fire()
settle()
equal(tweenCount, before, "Reduce Motion skips every button tween")
equal(reducedPop.Scale, 1, "Reduce Motion never compresses or enlarges the button")
check(reducedButton:FindFirstChild("InteractionOutline").Transparency < 1, "Reduce Motion retains visible interaction feedback")
local reducedCard = Factory.New("Frame", { Parent = parent, Position = UDim2.fromOffset(0, 40) })
Effects.Card(reducedCard, reducedButton, accent, 0.2)
Effects.Rise(reducedCard, 0.2, 20)
equal(#delayed, 0, "Reduce Motion skips delayed entrances")
reducedCard.MouseEnter:Fire()
equal(reducedCard.Position.Y.Offset, 40, "Reduce Motion keeps a hovered card stationary")
check(reducedCard:FindFirstChild("CardGlow").Transparency < 1, "Reduce Motion retains a static card glow")
equal(tweenCount, before, "Reduce Motion skips card glow and lift tweens")
return checks
