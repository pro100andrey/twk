# The walkthrough's tally (tally.dart), recorded by `twk tape`: from
# packages/twk_dev,
#
#   dart run twk_dev:twk tape example/tally.tape
#
# writes build/tally.cast (asciicast v2, for `twk play`), build/tally.svg
# (the session, animated) and build/tally-counted.svg (a still).
Output build/tally.cast
Output build/tally.svg

Set Width 44
Set Height 7
Set Theme dark
Set FontSize 16
Set TypingSpeed 250ms

Run dart example/tally.dart

# the app compiles and draws its first frame meanwhile, not recorded
Hide
Wait /q quit/
Show
Sleep 800ms

Type "++"
Down
Type "+++"
Down
Type "+"
Sleep 1s
Screenshot build/tally-counted.svg

Up
Type "-"
Sleep 2s
