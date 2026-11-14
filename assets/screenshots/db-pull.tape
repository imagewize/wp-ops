# Records the README GIF: a production database pulled into development with
# `trellis ops db-pull`, from inside a Trellis project. Run from this directory:
#
#   vhs db-pull.tape
#   mp4-to-gif.sh --detect db-pull.mp4          # find the idle stretches
#   mp4-to-gif.sh db-pull.mp4 db-pull.gif "..."  # speed them up
#
# mp4-to-gif.sh lives in ~/code/seo-strategy/scripts. It pulls a real
# database: the development copy is replaced (db-pull keeps a dump of it).

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
