# 2.5D Graphics on Mojo (+ Python/pygame)

![Screenshot of gameplay](./gameplay_screenshot.png)

```python
from doom import export as ext

level    = ext.Map()
player   = ext.Player(4.5, 4.5, 0.0)   # x, y, угол
level.add_entity(player)               # спрайты уровня
engine   = ext.Engine(level)
renderer = ext.Renderer(level)

candidate = player.move_forward()      # Player — value-тип: вернулся НОВЫЙ
if not engine.check_collision(candidate):
    player = candidate

hex_rgb = renderer.render(player)      # 128*128*6 символов
ext.Renderer.width(), ext.Renderer.height()
```

## Сборка и запуск
```bash
uv sync # Установка mojo и pygame
mojo build src/doom/export.mojo --emit shared-lib -o src/doom/export.so -I src/doom
uv run -m game.main
```

## Если сборка падает

* `unable to find suitable c compiler for linking` — для `--emit shared-lib`
  нужен C-компилятор: `sudo apt install clang`.
* `module 'export' has no attribute 'PyInit_export'` — .so собран не из
  `src/doom/export.mojo` или лежит не в `src/doom/`.
* Функции, зарегистрированные в `PythonModuleBuilder`, обязаны быть
  `@staticmethod` структур-адаптеров (`PyMap`, `PyPlayer`, `PyEngine`,
  `PyRenderer`) и принимать `self_ptr: Pointer[mut=True, T, MutUnsafeAnyOrigin]`;
  модульные `def` туда не подходят.
