
-- predator-kb:begin
-- Predator RGB keyboard (https://github.com/luccas-santos01/predator-kb)
--
-- Omarchy's stock media bindings drive /sys/class/leds/*kbd_backlight*, which
-- Predator laptops don't expose - the keys just error out. Take them over.
hl.unbind("XF86KbdBrightnessUp")
hl.unbind("XF86KbdBrightnessDown")
hl.unbind("XF86KbdLightOnOff")

o.bind("XF86KbdBrightnessUp", "Keyboard backlight +", "predator-kb up")
o.bind("XF86KbdBrightnessDown", "Keyboard backlight -", "predator-kb down")
o.bind("XF86KbdLightOnOff", "Keyboard backlight toggle", "predator-kb toggle")
o.bind("SUPER + SHIFT + K", "Keyboard RGB", "omarchy menu summon keyboard")
-- predator-kb:end
