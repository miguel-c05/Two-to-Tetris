# Plano de implementação — Clone de Tetris moderno (Godot 4.7)

Objetivo: um Tetris "Guideline" (moderno) com **hold**, **next queue**, **ghost piece**, **7-bag**, **SRS com wall kicks**, **lock delay**, **DAS/ARR** e pontuação moderna. A arquitetura separa *tabuleiro* de *controlador do jogador*, para facilitar depois o mod cooperativo (TTTT).

---

## 1. Regras a implementar

| Mecânica | Valor / comportamento |
|---|---|
| Tabuleiro | 10 colunas × 20 visíveis + 2 linhas escondidas no topo (22 no total) |
| Randomizer | 7-bag: baralha as 7 peças, distribui todas, volta a baralhar |
| Next queue | Mostrar 5 peças seguintes |
| Hold | Guarda a peça atual; se já houver uma, troca. **Só 1 vez por peça** (reativa ao bloquear a peça seguinte). A peça que sai do hold volta à rotação 0 e à posição de spawn |
| Rotação | SRS: CW, CCW (e 180 opcional), com tabelas de kicks (secção 6) |
| Ghost | Projeção da peça na posição de hard drop, semitransparente |
| Gravidade | Intervalo por linha (s) = `(0.8 - (nível-1)*0.007) ^ (nível-1)` |
| Soft drop | Gravidade ×20; +1 ponto por célula |
| Hard drop | Cai e bloqueia de imediato; +2 pontos por célula |
| Lock delay | 0,5 s no chão; mover/rodar com sucesso reinicia o temporizador, até 15 resets (reset do contador ao descer a uma linha nova mais baixa) |
| DAS / ARR | DAS ≈ 0,167 s, ARR ≈ 0,033 s (implementado à mão, não com eco do teclado) |
| Pontuação | Single 100, Double 300, Triple 500, Tetris 800 (× nível). Back-to-back (Tetris/T-spin seguidos) ×1,5. Combo: +50 × combo × nível |
| Nível | Sobe a cada 10 linhas |
| Game over | *Block out*: a peça nova colide ao nascer. *Lock out*: a peça bloqueia inteiramente nas linhas escondidas |

Spawn: caixa da peça na coluna 3 (O na coluna 4), linha 0 (escondida). Logo após o spawn tenta descer 1 linha.

---

## 2. Estrutura de pastas

```
res://
├─ Assets/
│  ├─ blocks.png              # 8 quadrados 32×32 numa linha (7 cores + cinzento)
│  └─ blocks_tileset.tres     # TileSet partilhado
├─ Scenes/
│  ├─ main.tscn               # (já existe) cena principal
│  ├─ board.tscn
│  └─ piece_preview.tscn
└─ Scripts/
   ├─ piece_data.gd           # constantes: formas, cores, kicks
   ├─ bag_randomizer.gd
   ├─ piece.gd
   ├─ board.gd
   ├─ game.gd                 # controlador do jogador + regras
   ├─ hud.gd
   └─ piece_preview.gd
```

---

## 3. Árvore de cenas

### `main.tscn`
```
Main (Node2D)                      ← game.gd
├─ Board (instância de board.tscn)
└─ HUD (CanvasLayer)               ← hud.gd
   ├─ HoldPanel (PanelContainer)
   │  └─ VBox → Label "HOLD" + HoldPreview (piece_preview.tscn)
   ├─ NextPanel (PanelContainer)
   │  └─ VBox → Label "NEXT" + Next0..Next4 (piece_preview.tscn ×5)
   ├─ Stats (VBoxContainer)
   │  └─ ScoreLabel, LevelLabel, LinesLabel (Label)
   ├─ PausePanel (Panel, visible = false)
   └─ GameOverPanel (Panel, visible = false)
      └─ Label "GAME OVER" + RestartButton (Button)
```

### `board.tscn`
```
Board (Node2D)                     ← board.gd
├─ Frame (ColorRect)               # fundo/moldura 320×640, z_index -1
├─ BoardLayer (TileMapLayer)       # células bloqueadas
├─ GhostLayer (TileMapLayer)       # ghost, modulate.a = 0.3
└─ PieceLayer (TileMapLayer)       # peça ativa
```
As três TileMapLayer usam o mesmo `blocks_tileset.tres`.

### `piece_preview.tscn`
```
PiecePreview (Control, custom_minimum_size 100×60)   ← piece_preview.gd
```
Desenha a peça com `_draw()` (não precisa de TileMap).

---

## 4. Passos no editor

1. **Project Settings → Display → Window**: Viewport 1280×720. O stretch já está em `canvas_items`.
   Se usares pixel art: *Rendering → Textures → Default Texture Filter = Nearest*.
2. **Project Settings → Input Map** — criar as ações:

   | Ação | Tecla |
   |---|---|
   | `p1_move_left` | ← |
   | `p1_move_right` | → |
   | `p1_soft_drop` | ↓ |
   | `p1_rotate_cw` | ↑ |
   | `p1_hard_drop` | K |
   | `p1_hold` | J |
   | `pause` | Esc |
   | `restart` | R |

   As ações do jogador têm prefixo `p1_` (o 2.º jogador terá `p2_…`); `pause` e `restart` são globais.

3. **Textura dos blocos**: criar `Assets/blocks.png` (256×32, 8 tiles de 32×32) pela ordem I, O, T, S, Z, J, L, cinzento.
   Cores: I ciano `#00F0F0`, O amarelo `#F0F000`, T roxo `#A000F0`, S verde `#00F000`, Z vermelho `#F00000`, J azul `#0000F0`, L laranja `#F0A000`.
4. **TileSet**: selecionar `BoardLayer` → Inspector → *Tile Set → New TileSet*; *Tile Size* = 32×32. No painel inferior **TileSet**, arrastar `blocks.png` → aceitar "criar tiles automaticamente". Fica com `source_id = 0`, atlas coords `(0..7, 0)`.
   No Inspector, clicar na seta do TileSet → **Save As** `Assets/blocks_tileset.tres`. Atribuir esse ficheiro a `GhostLayer` e `PieceLayer`.
5. **Board**: `Frame` com tamanho 320×640 (10×20 células), cor escura. `GhostLayer.modulate = (1,1,1,0.3)`. Posicionar `Board` no centro do ecrã (ex.: x=480, y=40).
6. **HUD**: posicionar HoldPanel à esquerda do tabuleiro e NextPanel + Stats à direita (anchors ou posições absolutas). `PausePanel` e `GameOverPanel` com *Full Rect* e `visible = false`.
   Em `PausePanel` e `HUD`: *Process → Mode = Always* (para o menu responder em pausa).
7. **Scripts**: criar os ficheiros da secção 5 e atribuí-los aos nós indicados.
8. **Sinais** (podem ser ligados por código no `hud.gd`, ou pelo separador *Node → Signals*): `RestartButton.pressed` → `Main.new_game`.
9. Confirmar que `Scenes/main.tscn` é a *Main Scene* (Project Settings → Application → Run).

---

## 5. Scripts e funções

### `piece_data.gd` — dados estáticos
```gdscript
class_name PieceData

enum { I, O, T, S, Z, J, L }

# Estado de spawn (rotação 0), coordenadas y para baixo, dentro da caixa.
const SHAPES := {
    I: [Vector2i(0,1), Vector2i(1,1), Vector2i(2,1), Vector2i(3,1)],
    O: [Vector2i(0,0), Vector2i(1,0), Vector2i(0,1), Vector2i(1,1)],
    T: [Vector2i(1,0), Vector2i(0,1), Vector2i(1,1), Vector2i(2,1)],
    S: [Vector2i(1,0), Vector2i(2,0), Vector2i(0,1), Vector2i(1,1)],
    Z: [Vector2i(0,0), Vector2i(1,0), Vector2i(1,1), Vector2i(2,1)],
    J: [Vector2i(0,0), Vector2i(0,1), Vector2i(1,1), Vector2i(2,1)],
    L: [Vector2i(2,0), Vector2i(0,1), Vector2i(1,1), Vector2i(2,1)],
}
const BOX_SIZE := { I: 4, O: 2, T: 3, S: 3, Z: 3, J: 3, L: 3 }
const COLORS := [Color("00f0f0"), Color("f0f000"), Color("a000f0"),
                 Color("00f000"), Color("f00000"), Color("0000f0"), Color("f0a000")]

static var rotations := {}   # rotations[type][rot] -> Array[Vector2i]

static func _static_init() -> void:
    for t in SHAPES:
        var states := [SHAPES[t]]
        for r in 3:
            states.append(rotate_cw(states[-1], BOX_SIZE[t]))
        rotations[t] = states

# Rotação de 90º horária numa caixa n×n (y para baixo): (x, y) -> (n-1-y, x)
static func rotate_cw(cells: Array, n: int) -> Array: ...
static func get_cells(type: int, rot: int) -> Array: ...
static func get_kicks(type: int, from: int, to: int) -> Array: ...   # ver secção 6
```

### `bag_randomizer.gd`
```gdscript
class_name BagRandomizer extends RefCounted
var _queue: Array[int] = []

func _refill() -> void        # adiciona [0..6] baralhado (shuffle) ao fim da fila
func next() -> int            # garante ≥ 7 na fila, remove e devolve a 1.ª
func peek(n: int) -> Array    # garante ≥ n, devolve as n seguintes sem remover
func reset() -> void
```
Manter sempre pelo menos 7 peças na fila para o `peek(5)` nunca falhar.

### `piece.gd`
```gdscript
class_name Piece extends RefCounted
var type: int
var rotation: int = 0
var position: Vector2i          # canto superior esquerdo da caixa, em células

func _init(t: int, spawn_pos: Vector2i)
func get_cells(rot := rotation, pos := position) -> Array[Vector2i]
    # PieceData.get_cells(type, rot) + pos
```

### `board.gd` — só dados e desenho (sem input)
```gdscript
class_name Board extends Node2D
const COLS := 10
const ROWS := 22
const HIDDEN := 2
const EMPTY := -1

var grid: Array[PackedInt32Array]    # grid[y][x] = tipo ou EMPTY

func reset() -> void
func is_inside(c: Vector2i) -> bool        # 0 ≤ x < COLS e y < ROWS (y < 0 permitido)
func is_free(c: Vector2i) -> bool          # dentro e vazio
func is_valid(cells: Array) -> bool        # todas as células livres
func lock(cells: Array, type: int) -> bool # escreve no grid; devolve true se ficou toda em y < HIDDEN (lock out)
func clear_full_lines() -> int             # remove linhas cheias, desce as de cima, devolve quantas
func render_board() -> void                # BoardLayer: clear + set_cell para cada célula ocupada
func render_active(cells: Array, ghost: Array, type: int) -> void   # PieceLayer + GhostLayer
func _to_layer(c: Vector2i) -> Vector2i    # (x, y - HIDDEN): linha 0 visível fica no topo do Frame
```
API do TileMapLayer: `set_cell(coords, 0, Vector2i(type, 0))`, `erase_cell(coords)`, `clear()`.
`render_board()` só é chamado depois de um lock; `render_active()` a cada frame (são 8 células, é barato).

Para `clear_full_lines()`: percorrer de baixo para cima, guardar as linhas não cheias, reconstruir o grid acrescentando linhas vazias no topo.

### `game.gd` — regras e controlo (nó `Main`)
```gdscript
extends Node2D

signal stats_changed(score: int, level: int, lines: int)
signal hold_changed(type: int, can_hold: bool)
signal next_changed(types: Array)
signal game_over
signal paused_changed(paused: bool)

const DAS := 0.167
const ARR := 0.033
const SOFT_DROP_FACTOR := 20.0
const LOCK_DELAY := 0.5
const MAX_LOCK_RESETS := 15
const NEXT_COUNT := 5

enum State { PLAYING, PAUSED, GAME_OVER }

@onready var board: Board = $Board
var bag := BagRandomizer.new()
var current: Piece
var hold_type := -1
var can_hold := true
var score := 0; var level := 1; var lines := 0
var combo := -1; var back_to_back := false
# temporizadores
var _gravity_t := 0.0; var _lock_t := 0.0; var _lock_resets := 0; var _lowest_y := 0
var _das_dir := 0; var _das_t := 0.0; var _arr_t := 0.0
var _last_move_was_rotation := false
```

| Função | O que faz |
|---|---|
| `_ready()` | `new_game()` |
| `new_game()` | Reset de board, bag, hold, stats; esconde painéis; `spawn_next()`; emite sinais |
| `_unhandled_input(event)` | Ações "one-shot": `hard_drop`, `rotate_cw/ccw/180`, `hold`, `pause` (usar `event.is_action_pressed(...)` sem eco) |
| `_process(delta)` | Se `PLAYING`: `_handle_horizontal(delta)`, `_apply_gravity(delta)`, `_update_lock(delta)`, `_render()` |
| `spawn_piece(type)` | Cria `Piece` no spawn; se `!board.is_valid` → `_game_over()`; reset de timers de lock/gravidade; tenta descer 1 linha |
| `spawn_next()` | `spawn_piece(bag.next())`; emite `next_changed(bag.peek(NEXT_COUNT))` |
| `try_move(dx, dy) -> bool` | Testa `current.get_cells(rot, pos + d)`; aplica se válido; chama `_on_manipulated()` |
| `try_rotate(dir) -> bool` | SRS com kicks (secção 6); O não roda |
| `hard_drop()` | Desce enquanto puder, soma 2×células, `lock_piece()` |
| `hold_piece()` | Se `!can_hold` sai. Guarda `current.type`; se `hold_type == -1` → `spawn_next()`, senão `spawn_piece(antigo)`. `can_hold = false`; emite `hold_changed` |
| `lock_piece()` | `board.lock()` (lock out → game over); deteta T-spin; `cleared = board.clear_full_lines()`; `_add_score(cleared, tspin)`; `board.render_board()`; `can_hold = true`; `spawn_next()` |
| `get_ghost_cells() -> Array` | Desce uma cópia da posição até colidir |
| `is_grounded() -> bool` | `!board.is_valid(current.get_cells(rot, pos + (0,1)))` |
| `gravity_interval() -> float` | Fórmula da secção 1 |
| `_handle_horizontal(delta)` | DAS/ARR (abaixo) |
| `_apply_gravity(delta)` | Acumulador; com soft drop divide o intervalo por 20 e dá +1 ponto/célula |
| `_update_lock(delta)` | Se no chão: soma `_lock_t`; ao passar `LOCK_DELAY` ou `MAX_LOCK_RESETS` → `lock_piece()`. Se não: `_lock_t = 0` |
| `_on_manipulated()` | Se no chão e `_lock_resets < MAX`: `_lock_t = 0`, `_lock_resets += 1`. Se `pos.y > _lowest_y`: atualiza e zera `_lock_resets` |
| `_add_score(cleared, tspin)` | Tabela + B2B + combo; atualiza linhas/nível; emite `stats_changed` |
| `_detect_tspin() -> bool` | (Opcional) T, último movimento foi rotação, ≥3 dos 4 cantos da caixa 3×3 ocupados |
| `toggle_pause()` | `PLAYING ↔ PAUSED`; emite `paused_changed` |
| `_game_over()` | `state = GAME_OVER`; emite `game_over` |
| `_render()` | `board.render_active(current.get_cells(), get_ghost_cells(), current.type)` |

DAS/ARR:
```gdscript
func _handle_horizontal(delta: float) -> void:
    var dir := int(Input.is_action_pressed("move_right")) - int(Input.is_action_pressed("move_left"))
    if dir != _das_dir:
        _das_dir = dir; _das_t = 0.0; _arr_t = 0.0
        if dir != 0: try_move(dir, 0)
        return
    if dir == 0: return
    _das_t += delta
    if _das_t < DAS: return
    _arr_t += delta
    while _arr_t >= ARR:
        _arr_t -= ARR
        if not try_move(dir, 0): break
```

Gravidade:
```gdscript
func _apply_gravity(delta: float) -> void:
    var soft := Input.is_action_pressed("soft_drop")
    var interval := gravity_interval() / (SOFT_DROP_FACTOR if soft else 1.0)
    _gravity_t += delta
    while _gravity_t >= interval:
        _gravity_t -= interval
        if try_move(0, 1):
            if soft: score += 1
        else:
            _gravity_t = 0.0
            break
```

### `piece_preview.gd`
```gdscript
extends Control
const CELL := 20
var type := -1

func set_piece(t: int) -> void      # guarda e queue_redraw()
func _draw() -> void                # centra a forma (bounding box) e draw_rect por célula com PieceData.COLORS
```
Para o hold bloqueado: `modulate = Color(1,1,1,0.4)` quando `can_hold == false`.

### `hud.gd`
```gdscript
extends CanvasLayer
func _ready()                                   # liga os sinais de get_parent() (Main)
func _on_stats_changed(score, level, lines)     # atualiza Labels
func _on_hold_changed(type, can_hold)           # HoldPreview.set_piece + modulate
func _on_next_changed(types)                    # Next0..Next4.set_piece
func _on_game_over()                            # mostra GameOverPanel
func _on_paused_changed(p)                      # mostra/esconde PausePanel
```

---

## 6. Tabelas SRS (já em coordenadas Godot, y para baixo)

Guardar apenas os kicks **horários**; o anti-horário de `a → b` é o horário de `b → a` com sinal trocado.

```gdscript
const KICKS_JLSTZ := {   # from -> from+1 (CW)
    0: [Vector2i(0,0), Vector2i(-1,0), Vector2i(-1,-1), Vector2i(0,2),  Vector2i(-1,2)],
    1: [Vector2i(0,0), Vector2i(1,0),  Vector2i(1,1),   Vector2i(0,-2), Vector2i(1,-2)],
    2: [Vector2i(0,0), Vector2i(1,0),  Vector2i(1,-1),  Vector2i(0,2),  Vector2i(1,2)],
    3: [Vector2i(0,0), Vector2i(-1,0), Vector2i(-1,1),  Vector2i(0,-2), Vector2i(-1,-2)],
}
const KICKS_I := {
    0: [Vector2i(0,0), Vector2i(-2,0), Vector2i(1,0),  Vector2i(-2,1),  Vector2i(1,-2)],
    1: [Vector2i(0,0), Vector2i(-1,0), Vector2i(2,0),  Vector2i(-1,-2), Vector2i(2,1)],
    2: [Vector2i(0,0), Vector2i(2,0),  Vector2i(-1,0), Vector2i(2,-1),  Vector2i(-1,2)],
    3: [Vector2i(0,0), Vector2i(1,0),  Vector2i(-2,0), Vector2i(1,2),   Vector2i(-2,-1)],
}

static func get_kicks(type: int, from: int, to: int) -> Array:
    var table := KICKS_I if type == I else KICKS_JLSTZ
    if to == posmod(from + 1, 4):
        return table[from]
    return table[to].map(func(k): return -k)   # CCW
```

Rotação com kicks:
```gdscript
func try_rotate(dir: int) -> bool:
    if current.type == PieceData.O: return false
    var to := posmod(current.rotation + dir, 4)
    for k in PieceData.get_kicks(current.type, current.rotation, to):
        var p := current.position + k
        if board.is_valid(current.get_cells(to, p)):
            current.rotation = to
            current.position = p
            _last_move_was_rotation = true
            _on_manipulated()
            return true
    return false
```
Rotação 180 (opcional): testar só o offset `(0,0)` e `(0,-1)`; não existe tabela oficial.

---

## 7. Ordem de implementação (marcos testáveis)

1. **Dados + tabuleiro**: `piece_data.gd`, `board.gd`, TileSet. Teste: preencher células à mão e ver se desenham no sítio certo.
2. **Peça ativa**: spawn, mover esquerda/direita, gravidade fixa, colisão com paredes e fundo.
3. **Lock + limpeza de linhas**: lock imediato no chão primeiro, depois lock delay.
4. **Rotação SRS**: rotação simples, depois kicks. Teste: rodar I e T encostadas às paredes.
5. **7-bag + next queue + PiecePreview**.
6. **Hold** (incluindo a regra "uma vez por peça").
7. **Ghost + hard drop + soft drop**.
8. **DAS/ARR** (substituir o movimento simples do passo 2).
9. **Pontuação, níveis, velocidade**.
10. **Game over, pausa, restart**.
11. **Polimento**: T-spin, sons (`AudioStreamPlayer` em lock/clear/hold), animação de linha a limpar (flash com `Tween` antes de remover), shake no hard drop.

---

## 8. Checklist de testes

- [ ] Em cada 7 peças seguidas aparecem as 7 diferentes
- [ ] Hold vazio → peça vai para o hold e entra a próxima da fila
- [ ] Hold duas vezes na mesma peça não faz nada
- [ ] Peça que sai do hold aparece no spawn, rotação 0
- [ ] I na vertical encostada à parede consegue rodar (kick)
- [ ] Ghost coincide com a posição final do hard drop
- [ ] Mover no chão adia o lock, mas não para sempre (15 resets)
- [ ] Limpar 4 linhas dá 800 × nível; dois Tetris seguidos ativam B2B
- [ ] Peça nova a colidir no spawn → game over
- [ ] Pausa congela gravidade e input de jogo

---

## 9. Notas para o mod cooperativo (TTTT)

Já que o objetivo final é cooperativo, vale a pena desde já:

- **`Board` não conhece jogadores**: só dados, validação e desenho. Toda a lógica de peça fica no controlador (`game.gd`). Mais tarde, extrair a parte de jogador para um nó `PlayerController` e instanciar dois sobre o mesmo `Board` (tabuleiro mais largo, ex.: 16–20 colunas).
- **Ações com prefixo**: em vez de `move_left`, usar uma variável `@export var prefix := "p1_"` e `Input.is_action_pressed(prefix + "move_left")`. Assim o 2.º jogador é só outro mapa de teclas.
- **Colisão entre peças ativas**: `is_valid(cells, ignore_player)` deve poder considerar também as células da peça ativa do outro jogador.
- **Bag partilhada ou separada** e **hold partilhado ou individual** são decisões de design do mod — manter `BagRandomizer` e o hold como objetos independentes facilita testar as duas opções.

---

## 10. Modo cooperativo (implementado)

Estrutura: `Main` (`game.gd`) guarda o que é partilhado; cada jogador é um nó `Player` (`player.gd`) filho de `Main`.

| Regra | Onde |
|---|---|
| Tabuleiro de 16 colunas; P2 nasce na metade esquerda (coluna 4), P1 na direita (coluna 12) | `Board.cols`, `Player.spawn_center` |
| Fila de peças partilhada: quem pousa recebe a próxima | `Game.lock_pieces()` |
| Hold com um só slot e um só cooldown; reativa quando qualquer jogador pousa | `Game.hold()` |
| Peças ativas colidem entre si (mover, rodar, spawn) | `Game.can_occupy()` |
| Hard drop com o companheiro no caminho: empurra-o e pousa as duas de imediato | `Game.hard_drop()` / `_simulate_drop()` |
| Soft drop com o companheiro por baixo: empurra-o à velocidade de soft drop | `Game.push_down()` |
| Peça em cima de outra que ainda cai não bloqueia; só bloqueia se a de baixo estiver assente | `Game.is_supported()` |
| Gravidade comum, aplicada de baixo para cima (peças empilhadas caem juntas) | `Game._apply_gravity()` |
| Spawn ocupado pelo companheiro: o jogador espera até ficar livre | `Player.try_spawn_waiting()` |

Controlos: P1 ← → ↓ ↑ K (hard drop) J (hold); P2 A D S W G (hard drop) F (hold); Esc pausa, R recomeça.

