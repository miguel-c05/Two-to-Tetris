TTTT - TAKES TWO TO TETRIS
Digital Games 2026/27 - Modding a Classic Game

Group
  Joao Pedro Nunes Rocha                        202306599
  Miguel Martins Ferreira Camocho de Carvalho   202305229

Repository: https://github.com/miguel-c05/Two-to-Tetris


ABOUT
A local co-op mod of modern (Guideline) Tetris. Two players share one
16-column well and play at the same time, each with their own falling piece.
They share the Next queue, a single Hold slot, the score and the game over.
Falling pieces are solid to each other, and a drop can push the partner's
piece down with yours. Two pieces locking together can clear more than four
lines at once.


START MENU
The game opens on a start screen where you pick the starting level (1 to 15).
Higher levels start with faster gravity; the level still goes up every 10 lines.

  <- -> or A D   change the starting level
  Enter / Space  start (or click START)

When the game is over you can restart at the same level (R) or go back to the
start menu (Esc) to pick another one.


CONTROLS
                Move    Soft drop   Rotate   Hard drop   Hold
  Player 1      <- ->   Down        Up       K           J
  Player 2      A  D    S           W        G           F

  Esc  pause (on the game over screen: back to the start menu)
  R    restart at the same level


DELIVERY CONTENTS
  1_Poster/TTTT_poster_A2.pdf      A2 poster
  2_Video/TTTT_gameplay.mp4        Gameplay video (H.264, about 2 min)
  2_Video/VIDEO_LINK.txt           Link to the same video on YouTube
  3_Executable_Web/GAME_LINK.txt   Link to the playable web version on itch.io
  4_Godot_Project/                 Godot source project


PLAYING THE GAME (WEB)
We could not get the exported HTML5 files to work reliably when run from a
folder, so instead of including them we published the web build on itch.io,
where it runs directly in the browser with nothing to install:

  https://miguel-c05.itch.io/takes-two-to-tetris

Use Chrome or Firefox on a computer. Both players share the same keyboard.
Click the game once so it gets keyboard focus.


GAMEPLAY VIDEO
The video is included in 2_Video. The same video is also on YouTube:

  https://www.youtube.com/watch?v=cC1sQapefLA


OPENING THE SOURCE PROJECT
Requires Godot 4.7. Open Godot, choose Import, select
4_Godot_Project/project.godot and press F5 to run.

Scripts/
  game.gd            shared rules: board, queue, hold, gravity, collisions, pushing
  player.gd          one per player: input, movement timing, soft drop, lock delay
  board.gd           the grid and its rendering
  scoring.gd         points, combos, back-to-back, levels
  piece.gd           a falling piece (type, rotation, position)
  piece_data.gd      shapes and SRS wall kick tables
  bag_randomizer.gd  7-bag piece randomizer
  hud.gd             interface (hold, next, score, pause, game over)
  start_menu.gd      start screen where the starting level is chosen
  piece_preview.gd   draws a piece in the Hold/Next boxes
  grid_lines.gd      board grid
