
Don't make any excuse anymore to not use the [Pomodoro Technique](https://en.wikipedia.org/wiki/Pomodoro_Technique)!


###Info

Boilerplate implementation of the pomodoro technique in bash script.

It works with a client/server architecture.

Implemented with FSM (Finite State Machine), some mutex (flock) and really simple.

The typical workflow is start the daemon with login (systemd,openbox autostart ...) and 
then using shortkeys or a very simple trayicon app work with it.

Just a hack day.

###Dependencies

1. flock
2. inotify-tools (great toolset)
3. zenity/notify/gpicview/xscreensaver/whatever you want to show a msg/image/lock...

###Why yet another pomodoro app?

Emmm...for fun? :o:

###TODO

- [ ] Unit testing (bats)
- [ ] Make the gtk trayicon app
