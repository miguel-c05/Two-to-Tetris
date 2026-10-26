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


CONTROLS
                Move    Soft drop   Rotate   Hard drop   Hold
  Player 1      <- ->   Down        Up       K           J
  Player 2      A  D    S           W        G           F

  Esc  pause
  R    restart


DELIVERY CONTENTS
  1_Poster/TTTT_poster_A2.pdf      A2 poster
  2_Video/TTTT_gameplay.mp4        Gameplay video (H.264, about 2 min)
  3_Executable_Web/                Web/HTML5 build
  4_Godot_Project/                 Godot source project


RUNNING THE WEB BUILD
Browsers block games opened straight from disk (file://), so double-clicking
index.html will not work. Serve the folder with any local web server, e.g.:

  cd 3_Executable_Web
  python -m http.server 8000

and open http://localhost:8000 in a browser (Chrome or Firefox).
Both players use the same keyboard.


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
  piece_preview.gd   draws a piece in the Hold/Next boxes
  grid_lines.gd      board grid
