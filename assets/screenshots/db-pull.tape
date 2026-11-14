# Records the README GIF: a production database pulled into development with
# `trellis ops db-pull`, from inside a Trellis project. Run from this directory:
#
#   vhs db-pull.tape
#   ./mp4-to-gif.sh --detect db-pull.mp4   # list the idle stretches
#   ./mp4-to-gif.sh db-pull.mp4 db-pull.gif "0:13:1 13:42.2:6 42.2:83.4:20 83.4:92:4 92::1"
#
# The segments are start:end:speed in seconds, read off --detect: here the
# download (13-42s) runs at 6x, the import (42-83s) at 20x and search-replace
# (83-92s) at 4x. A new recording has different timings, so re-run --detect.
# Delete db-pull.mp4 afterwards; only the GIF is committed.
#
# It pulls a real database: the development copy is replaced (db-pull keeps a
# dump of it). Check the local site has no work that isn't on production first.
#
# trellis-cli runs the trellis-ops on PATH from the Homebrew cask even if
# another build comes first, so recording an unreleased build needs a shell
# function that sends `trellis ops` to it.

Output "db-pull.mp4"

Set Shell "bash"
Set FontSize 15
Set Width 1200
Set Height 720
Set Padding 20
Set Theme "Catppuccin Mocha"
Set TypingSpeed 45ms
Set Framerate 10

Hide
Type "export PS1='$ ' && unset TRELLIS_DIR && cd $HOME/code/imagewize.com && clear"
Enter
Show

Type "# Production database into development, from the Trellis project"
Enter
Sleep 600ms
Type "trellis ops db-pull demo.imagewize.com production --multisite --yes"
Sleep 500ms
Enter
# Wait+Screen only reads the first screenful and never sees scrolled output,
# so wait for the prompt to return on the cursor line instead.
Wait+Line@10m /^\$$/
Sleep 3s
