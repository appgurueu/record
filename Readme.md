# Record

A mod for Luanti that lets you record and replay in-game events.

**Important**: This mod is currently WIP. APIs, file formats, etc. may change without notice.

## Motivation

* Recording suspected cheaters
* Cutscenes
* Recording competitive matches (e.g. CTF)
* Recording build process for a timelapse

Installing mods like `character_anim` or `visible_wielditem` is recommended.

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

The following classes classes are exported under the `record` namespace:

### `Recording`

* `self = Recording.new(box, out_file)` creates a new recording.
* `self:start()` starts the recording.
  * Resuming recordings is not yet possible.
* `self:stop()` stops the recording.

### `Replay`

* `self = Replay.new(pos, in_file)` creates a new replay.
  * `pos` is the min pos of the cuboid.
* `self:start()` starts (or resumes) the replay.
* `self:stop()` stops the replay.

## Limitations

* Nodes may need to be substituted.
* Observers are ignored for now.
* Metadata is currently ignored.

## Design notes

### File format overview

Recordings are sequences of chunks. All binary data uses little endian.
A chunk is a u32 length followed by a body of the given length.
Chunk contents are serialized, subsequently zstd-compressed Lua values.
Currently, modlib's binary lua serialization format (bluon) is used for this
as it handles strings being used as byte buffers better than text-based formats.

The first chunk in the file is always a small "meta" chunk, currently containing recording extents.
The next chunk is an "init" chunk: A snapshot of the world to establish the initial state of the recording area.
Subsequent chunks are "event" chunks. Event chunks always have a timestamp, plus:

* Sparse node update events: Map from hashed node position to node to place.
* Dense node update events: Cuboid range, linearized 3d array of the node data to overwrite the range with.
* Object update events: Table mapping IDs to (diffs of) new object "attributes", e.g. position, properties, and bone overrides.
  Attachments are also preserved. It is expected that parent objects occur in the same update event as their children.

### Planned features

* More efficient seeking by aggregating events. This yields a segment tree kind of data structure of log n streams.
  We will probably want to use multiple files for this.
* Reverse replay by writing a second stream with everything, well, reversed:
  Every diff is new -> old rather than old -> new.
  Again more files is the simple way to go, otherwise we have to bother with reallocations within a file.
* Do something proper about meta by scrubbing meta before replays,
  and perhaps preserving some meta such as `infotext` in recordings.
* Particles & particlespawners
* Make recordings resumable.