# Record

A mod for Luanti that lets you record and replay in-game events.

## Usage

Record registers the `record` priv needed to start recordings and replays.

Recordings are saved under `<world path>/recordings/<player name>/<recording name>`.

* Recording:
  * `/record pos 1|2`: Set pos 1 / 2 to your current position.
    * Once both pos 1 and pos 2 are set, the box will be visualized.
  * `/record pos clear`: Clear pos 1 and pos 2, hiding the box.
  * `/record start <name>`: Start a recording for the given box.
  * `/record stop [name]`: Stop a recording.
    * You only need to specify the name if you have more than one running recording.
* Replaying:
  * `/replay box <name>`: Visualize the box of a replay before playing it.
  * `/replay start <name>`: Start a replay at your position.
  * `/replay speed <factor> [name]`: Set the speed for a running replay or all running replays.
  * `/replay seek <time> [name]`: Seek to a timestamp; jump forward or backward:
    * You only need to specify the name if you have more than one running replay.
    * `/replay seek +42` jumps 42 seconds forward;
    * `/replay seek -42` jumps 42 seconds backward;
    * `/replay seek 42` jumps to second 42 in the recording.
    * The default unit is seconds, but you can suffix numbers with
      * `d` for days,
      * `h` for hours,
      * `m` for minutes,
      * `s` for seconds.
  * `/replay stop [name]`: Stop a replay.
    * You only need to specify the name if you have more than one running replay.

If in doubt, use `/help`.

## API

Two classes are exported under the `record` namespace:

### `Recording`

### `Replay`

## Limitations

* Nodes may need to be substituted.
* Observers are ignored for now.
* Metadata is currently ignored.