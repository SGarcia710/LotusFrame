# LotusFrames

Marcos de jugador y objetivo estilizados para **WoW Classic Era** (1.15.x), inspirados en ElvUI.

- Modelo 3D sobre la barra de vida, con vida y poder siempre visibles.
- Clase al lado del nombre de los jugadores, en su color; en tu marco también tu especialización (el árbol de talentos con más puntos). Classic Era no deja ver los talentos de otros jugadores, así que de ellos solo sale la clase.
- Puntos de combo y porcentaje de vida del objetivo (en rojo bajo 20 %, zona de Ejecutar).
- Auras del objetivo y del jugador (beneficios y perjuicios), encima de cada marco, en dos estilos: íconos con contador y animación de reloj, o barras que se vacían.
- Alerta de poca vida: tu marco late con un borde rojo cuando tu vida baja del porcentaje que elijas (con sonido opcional).
- Se mueven con el Modo edición de Blizzard o con Shift + arrastrar.
- Panel de ajustes en Opciones > AddOns > LotusFrames.

## Instalación

Copia o clona el repositorio en `Interface/AddOns` **con el nombre de carpeta `LotusFrames`** (WoW exige que la carpeta se llame igual que el `.toc`):

```sh
cd "/Applications/World of Warcraft/_classic_era_/Interface/AddOns"
git clone https://github.com/SGarcia710/LotusFrame.git LotusFrames
```

## Comandos

| Comando | Qué hace |
| --- | --- |
| `/lotus opciones` | Abre el panel de ajustes |
| `/lotus scale N` | Cambia la escala de los marcos |
| `/lotus reset` | Devuelve los marcos a su posición inicial |
| `/lotus auras` | Lista en el chat las auras del objetivo (diagnóstico) |

## Créditos

La fuente PT Sans Narrow es de ParaType y se distribuye bajo la SIL Open Font License 1.1 (`Media/PT Sans License.txt`).
