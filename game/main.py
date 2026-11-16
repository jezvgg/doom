import pygame

from doom import export as ext


SCALE = 4
FPS = 60


def step(player, engine, keys):
    changed = False

    for forward, action in (
        (pygame.K_w, "move_forward"),
        (pygame.K_UP, "move_forward"),
        (pygame.K_s, "move_backward"),
        (pygame.K_DOWN, "move_backward"),
    ):
        if keys[forward]:
            candidate = getattr(player, action)()
            if not engine.check_collision(candidate):
                player = candidate
                changed = True
            break

    for turn, action in (
        (pygame.K_a, "rotate_left"),
        (pygame.K_LEFT, "rotate_left"),
        (pygame.K_d, "rotate_right"),
        (pygame.K_RIGHT, "rotate_right"),
    ):
        if keys[turn]:
            player = getattr(player, action)()
            changed = True
            break

    return player, changed


def draw(display, renderer, player):
    """Renderer (Mojo) -> hex-RGB строка -> pygame.Surface 128x128 -> окно."""
    width, height = ext.Renderer.width(), ext.Renderer.height()
    image = pygame.image.frombytes(
        bytes.fromhex(renderer.render(player)), (width, height), "RGB"
    )
    display.blit(pygame.transform.scale(image, display.get_size()), (0, 0))
    pygame.display.flip()


def main():
    level = ext.Map()
    player = ext.Player(4.5, 4.5, 0.0)
    level.add_entity(player)  # заготовка под спрайты: себя тоже видно

    engine = ext.Engine(level)
    renderer = ext.Renderer(level)

    pygame.init()
    size = (ext.Renderer.width() * SCALE, ext.Renderer.height() * SCALE)
    display = pygame.display.set_mode(size)
    pygame.display.set_caption("doom.mojo — WASD / стрелки, Esc — выход")
    clock = pygame.time.Clock()

    draw(display, renderer, player)

    running = True
    while running:
        for event in pygame.event.get():
            if event.type == pygame.QUIT:
                running = False
            elif event.type == pygame.KEYDOWN and event.key == pygame.K_ESCAPE:
                running = False

        player, changed = step(player, engine, pygame.key.get_pressed())
        if changed:
            draw(display, renderer, player)

        clock.tick(FPS)

    pygame.quit()


if __name__ == "__main__":
    main()
